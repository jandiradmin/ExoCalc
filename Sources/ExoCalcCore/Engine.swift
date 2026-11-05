import Foundation

public final class Engine {
    public var settings = CalcSettings()
    public let rates: RateStore
    public let registry: UnitRegistry
    public private(set) var lastVariables: [String] = []
    /// Overridable in tests.
    public var now: () -> Date = { Date() }
    /// nil = system time zone.
    public var timeZone: TimeZone?

    public init(rates: RateStore) {
        self.rates = rates
        self.registry = UnitRegistry(rates: rates)
    }

    /// Evaluates a whole sheet. Lines share variables, `prev` and `sum`.
    public func evaluate(lines: [String], recordVariables: Bool = false) -> [LineResult] {
        let ctx = Context()
        let date = now()
        let tz = timeZone ?? TimeZone.current
        ctx.now = date
        ctx.localTZ = tz.identifier
        let t = Int(date.timeIntervalSince1970.rounded(.down)) + tz.secondsFromGMT(for: date)
        ctx.today = Int((Double(t) / 86400).rounded(.down))
        ctx.nowSec = Double(((t % 86400) + 86400) % 86400 / 60 * 60)
        let res = lines.map { evalLine($0, ctx) }
        if recordVariables { lastVariables = Array(ctx.vars.keys) }
        return res
    }

    public func evaluate(_ expression: String) -> LineResult {
        evaluate(lines: [expression])[0]
    }

    func evalLine(_ line: String, _ ctx: Context) -> LineResult {
        var res = LineResult()
        let u = Array(line.utf16)
        var startIdx = 0
        while startIdx < u.count && (u[startIdx] == 32 || u[startIdx] == 9) { startIdx += 1 }
        if startIdx == u.count {
            ctx.block = []
            return res
        }
        // "# heading" or "// comment"
        if u[startIdx] == 35 || (u[startIdx] == 47 && startIdx + 1 < u.count && u[startIdx + 1] == 47) {
            res.highlights.append(Highlight(start: startIdx, end: u.count, kind: .comment))
            ctx.block = []
            return res
        }
        // Inline "// comment"
        var end = u.count
        var k = startIdx
        while k + 1 < u.count {
            if u[k] == 47 && u[k + 1] == 47 {
                end = k
                res.highlights.append(Highlight(start: k, end: u.count, kind: .comment))
                break
            }
            k += 1
        }
        // "Label: expression"
        var colonIdx = u[startIdx..<end].firstIndex(of: 58)
        // "15:00" is a time, not a label
        while let c = colonIdx, c > startIdx, c + 1 < end, Lexer.isDigit(u[c - 1]), Lexer.isDigit(u[c + 1]) {
            colonIdx = u[(c + 1)..<end].firstIndex(of: 58)
        }
        if let colon = colonIdx {
            let pre = u[startIdx..<colon]
            let hasLetter = pre.contains { Lexer.isLetter($0) }
            let hasBad = pre.contains { $0 == 61 || $0 == 40 }
            if hasLetter && !hasBad {
                res.highlights.append(Highlight(start: startIdx, end: colon + 1, kind: .label))
                startIdx = colon + 1
            }
        }

        let body = String(decoding: u[startIdx..<end], as: UTF16.self)
        var parser: Parser? = nil
        do {
            let toks = try Lexer(body, base: startIdx, settings: settings).tokenize()
            for tk in toks where tk.kind == .num || tk.kind == .clock || tk.kind == .date {
                res.highlights.append(Highlight(start: tk.start, end: tk.end, kind: .number))
            }
            let p = Parser(toks, reg: registry, ctx: ctx)
            p.decimals = settings.decimals
            p.fmt = { [unowned self] x in self.number(x, decimals: self.settings.decimals) }
            p.fmtValue = { [unowned self] v in (try? self.format(v)) ?? String(v.num) }
            parser = p
            if let v = try p.parseLine() {
                res.value = v
                res.display = try format(v)
                ctx.prev = v
                ctx.block.append(v)
            }
            res.highlights += p.marks
            res.warning = p.warnings.first
        } catch let e as CalcError {
            res.error = e.message
            res.value = nil
            res.display = nil
            if let p = parser { res.highlights += p.marks }
        } catch {
            res.error = "\(error)"
        }
        return res
    }

    // MARK: - Formatting

    public func format(_ v: Value) throws -> String {
        switch v.kind {
        case .clock: return formatClock(v)
        case .date: return formatDate(Int(v.num))
        case .plain: break
        }
        if v.format == .hms { return formatDuration(v.num) }
        guard v.num.isFinite else {
            throw CalcError(v.num.isNaN ? tr("noResult") : tr("tooBig"))
        }
        switch v.format {
        case .hex, .bin, .oct:
            guard v.num == v.num.rounded(), Swift.abs(v.num) < 9.0e15 else {
                throw CalcError(tr("intOnly"))
            }
            let iv = Int64(v.num)
            let radix = v.format == .hex ? 16 : (v.format == .bin ? 2 : 8)
            let prefix = v.format == .hex ? "0x" : (v.format == .bin ? "0b" : "0o")
            let body = String(iv.magnitude, radix: radix, uppercase: true)
            return (iv < 0 ? "-" : "") + prefix + body + unitSuffix(v)
        case .hms:
            return formatDuration(v.num)
        case .sci:
            return sci(v.num, digits: max(settings.decimals, 3)) + unitSuffix(v)
        case .dec:
            let dec = (v.unit?.isCrypto ?? false) ? max(settings.decimals, 8) : settings.decimals
            var s = number(v.num, decimals: dec)
            if v.isPercent { s += "%" }
            if let u = v.unit, ["day", "week", "month", "year"].contains(u.id), Swift.abs(v.num) != 1 {
                return s + unitSuffix(v) + "s"
            }
            return s + unitSuffix(v)
        }
    }

    private func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    func formatClock(_ v: Value) -> String {
        let total = Int(v.num.rounded())
        let dayOff = Int((Double(total) / 86400).rounded(.down))
        let sec = total - dayOff * 86400
        var s = "\(two(sec / 3600)):\(two(sec % 3600 / 60))"
        if sec % 60 != 0 { s += ":" + two(sec % 60) }
        if let z = v.tz { s += " " + z.label }
        if dayOff != 0 { s += " " + tr("dayOff", (dayOff > 0 ? "+" : "−") + String(Swift.abs(dayOff))) }
        return s
    }

    func formatDate(_ days: Int) -> String {
        let (y, m, d) = DT.civilFromDays(days)
        let s: String
        switch settings.dateFormat {
        case "mdy": s = "\(two(m))/\(two(d))/\(y)"
        case "ymd": s = "\(y)-\(two(m))-\(two(d))"
        default: s = "\(two(d)).\(two(m)).\(y)"
        }
        return s + ", " + tr("wd\(DT.weekday(days))")
    }

    func formatDuration(_ secs: Double) -> String {
        let sign = secs < 0 ? "-" : ""
        let t = Int(Swift.abs(secs).rounded())
        let h = t / 3600, m = t % 3600 / 60, s = t % 60
        var parts: [String] = []
        if h != 0 { parts.append("\(h) h") }
        if m != 0 || (h == 0 && s == 0) { parts.append("\(m) min") }
        if s != 0 { parts.append("\(s) s") }
        return sign + parts.joined(separator: " ")
    }

    private func unitSuffix(_ v: Value) -> String {
        guard let u = v.unit else { return "" }
        return u.id == "°" ? "°" : " " + u.id
    }

    private var groupSep: String {
        let g = settings.groupingSeparator
        if g == String(settings.decimalSeparator) { return settings.decimalSeparator == "," ? " " : "," }
        return g
    }

    /// Formats a plain number according to the settings (separators, decimals, trimming).
    public func number(_ x: Double, decimals: Int) -> String {
        guard x.isFinite else { return x.isNaN ? "—" : (x > 0 ? "∞" : "-∞") }
        let ax = Swift.abs(x)
        if ax >= 1e15 { return sci(x, digits: 6) }
        var d = max(0, min(decimals, 12))
        var trim = settings.trimZeros
        let threshold = pow(10.0, Double(-d)) / 2
        if ax != 0 && ax < threshold {
            if ax < 1e-9 { return sci(x, digits: 4) }
            d = Int((-log10(ax)).rounded(.down)) + 4   // show ~4 significant digits
            trim = true
        }
        let s = String(format: "%.\(d)f", ax)
        var intPart = s
        var frac = ""
        if let dot = s.firstIndex(of: ".") {
            intPart = String(s[..<dot])
            frac = String(s[s.index(after: dot)...])
        }
        if trim {
            while frac.hasSuffix("0") { frac.removeLast() }
        }
        let g = groupSep
        if !g.isEmpty && intPart.count > 3 {
            var out = ""
            let n = intPart.count
            for (idx, ch) in intPart.enumerated() {
                if idx > 0 && (n - idx) % 3 == 0 { out += g }
                out.append(ch)
            }
            intPart = out
        }
        var res = intPart
        if !frac.isEmpty { res += String(settings.decimalSeparator) + frac }
        if x < 0 && (Double(s) ?? 0) != 0 { res = "-" + res }
        return res
    }

    private func sci(_ x: Double, digits: Int) -> String {
        let s = String(format: "%.\(digits)e", x)
        let parts = s.split(separator: "e")
        guard parts.count == 2 else { return s }
        var mant = String(parts[0])
        if mant.contains(".") {
            while mant.hasSuffix("0") { mant.removeLast() }
            if mant.hasSuffix(".") { mant.removeLast() }
        }
        let exp = Int(parts[1]) ?? 0
        mant = mant.replacingOccurrences(of: ".", with: String(settings.decimalSeparator))
        return "\(mant)e\(exp)"
    }

    // MARK: - Completion

    public func completions(for prefix: String) -> [String] {
        let p = prefix.lowercased()
        guard !p.isEmpty else { return [] }
        var words = Set(registry.completionWords)
        words.formUnion(Parser.funcAliases.keys)
        words.formUnion(["in", "to", "sum", "prev", "avg", "hex", "bin", "oct", "sci", "pi", "mod", "of", "off", "итого"])
        words.formUnion(lastVariables)
        return words
            .filter { $0.lowercased().hasPrefix(p) && $0.count > prefix.count }
            .sorted { ($0.count, $0) < ($1.count, $1) }
    }
}
