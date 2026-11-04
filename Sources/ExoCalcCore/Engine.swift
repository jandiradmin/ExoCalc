import Foundation

public final class Engine {
    public var settings = CalcSettings()
    public let rates: RateStore
    public let registry: UnitRegistry
    public private(set) var lastVariables: [String] = []

    public init(rates: RateStore) {
        self.rates = rates
        self.registry = UnitRegistry(rates: rates)
    }

    /// Evaluates a whole sheet. Lines share variables, `prev` and `sum`.
    public func evaluate(lines: [String], recordVariables: Bool = false) -> [LineResult] {
        let ctx = Context()
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
        if let colon = u[startIdx..<end].firstIndex(of: 58) {
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
            for tk in toks where tk.kind == .num {
                res.highlights.append(Highlight(start: tk.start, end: tk.end, kind: .number))
            }
            let p = Parser(toks, reg: registry, ctx: ctx)
            parser = p
            if let v = try p.parseLine() {
                res.value = v
                res.display = try format(v)
                ctx.prev = v
                ctx.block.append(v)
            }
            res.highlights += p.marks
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
        guard v.num.isFinite else {
            throw CalcError(v.num.isNaN ? "нет результата" : "слишком большое число")
        }
        switch v.format {
        case .hex, .bin, .oct:
            guard v.num == v.num.rounded(), Swift.abs(v.num) < 9.0e15 else {
                throw CalcError("hex/bin/oct — только для целых")
            }
            let iv = Int64(v.num)
            let radix = v.format == .hex ? 16 : (v.format == .bin ? 2 : 8)
            let prefix = v.format == .hex ? "0x" : (v.format == .bin ? "0b" : "0o")
            let body = String(iv.magnitude, radix: radix, uppercase: true)
            return (iv < 0 ? "-" : "") + prefix + body + unitSuffix(v)
        case .sci:
            return sci(v.num, digits: max(settings.decimals, 3)) + unitSuffix(v)
        case .dec:
            let dec = (v.unit?.isCrypto ?? false) ? max(settings.decimals, 8) : settings.decimals
            var s = number(v.num, decimals: dec)
            if v.isPercent { s += "%" }
            return s + unitSuffix(v)
        }
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
