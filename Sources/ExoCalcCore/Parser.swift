import Foundation

final class Context {
    var vars: [String: Value] = [:]
    var prev: Value?
    var block: [Value] = []
    var now = Date()
    var localTZ = TimeZone.current.identifier
    var today = 0
    var nowSec = 0.0
}

/// Recursive-descent parser that evaluates while parsing.
final class Parser {
    private let t: [Token]
    private var i = 0
    private let reg: UnitRegistry
    private let ctx: Context
    var marks: [Highlight] = []
    var warnings: [String] = []
    /// Marks applied after all others (they win over the unit colour).
    var lateMarks: [Highlight] = []
    /// Formats a number for messages; set by the engine.
    var fmt: (Double) -> String = { String($0) }
    var fmtValue: (Value) -> String = { String($0.num) }
    /// Decimal places shown to the user (for comparing typed numbers).
    var decimals = 2
    private var override: (index: Int, value: Double)?

    static let convWords: Set<String> = ["in", "to", "as", "into", "в", "во", "у"]

    static let formatWords: [String: NumFormat] = [
        "hex": .hex, "bin": .bin, "binary": .bin, "oct": .oct, "octal": .oct,
        "sci": .sci, "scientific": .sci, "dec": .dec, "decimal": .dec,
    ]

    static let scales: [String: Double] = [
        "k": 1e3, "тис": 1e3, "тисяч": 1e3, "тисячі": 1e3, "мільйон": 1e6, "мільйонів": 1e6, "мільярд": 1e9, "мільярдів": 1e9, "thousand": 1e3, "thousands": 1e3, "тыс": 1e3, "тысяча": 1e3, "тысячи": 1e3, "тысяч": 1e3,
        "M": 1e6, "mln": 1e6, "million": 1e6, "millions": 1e6, "млн": 1e6, "миллион": 1e6, "миллиона": 1e6, "миллионов": 1e6,
        "bn": 1e9, "billion": 1e9, "billions": 1e9, "млрд": 1e9, "миллиард": 1e9, "миллиарда": 1e9, "миллиардов": 1e9,
    ]

    static let constants: [String: Double] = [
        "pi": Double.pi, "π": Double.pi, "e": exp(1.0), "tau": 2 * Double.pi,
    ]

    static let funcAliases: [String: String] = [
        "sqrt": "sqrt", "√": "sqrt", "корень": "sqrt", "корінь": "sqrt", "cbrt": "cbrt",
        "abs": "abs", "модуль": "abs", "round": "round", "floor": "floor", "ceil": "ceil", "trunc": "trunc",
        "sin": "sin", "cos": "cos", "tan": "tan", "tg": "tan",
        "asin": "asin", "acos": "acos", "atan": "atan", "arcsin": "asin", "arccos": "acos", "arctan": "atan",
        "sinh": "sinh", "cosh": "cosh", "tanh": "tanh",
        "ln": "ln", "log": "log", "lg": "log", "log10": "log", "log2": "log2", "exp": "exp",
        "min": "min", "max": "max", "avg": "avg", "average": "avg", "sum": "sum",
        "fact": "fact", "root": "root",
    ]

    /// Functions that may be written without parentheses: `sqrt 16`, `sin 30°`.
    static let prefixFuncs: Set<String> = [
        "sqrt", "cbrt", "abs", "sin", "cos", "tan", "asin", "acos", "atan",
        "sinh", "cosh", "tanh", "ln", "log", "log2", "exp", "fact",
    ]

    static let prevWords: Set<String> = ["prev", "ans", "пред", "попер"]
    static let sumWords: Set<String> = ["sum", "total", "итого", "сумма", "всего", "разом", "підсумок", "усього", "всього"]
    static let avgWords: Set<String> = ["avg", "average", "среднее", "середнє"]

    init(_ tokens: [Token], reg: UnitRegistry, ctx: Context) {
        t = tokens
        self.reg = reg
        self.ctx = ctx
    }

    // MARK: - Helpers

    private var cur: Token { t[i] }
    private func at(_ k: Int) -> Token { t[min(k, t.count - 1)] }
    private func isOp(_ tok: Token, _ s: String) -> Bool { tok.kind == .op && tok.text == s }
    private func mark(_ a: Int, _ b: Int, _ k: HKind) {
        guard a < t.count, b < t.count, a <= b else { return }
        marks.append(Highlight(start: t[a].start, end: t[b].end, kind: k))
    }

    private func isConvWord(_ tok: Token) -> Bool {
        (tok.kind == .ident && Parser.convWords.contains(tok.text.lowercased())) || isOp(tok, "->")
    }

    private func startsOperand(_ tok: Token) -> Bool {
        switch tok.kind {
        case .num, .lparen: return true
        case .ident: return !Parser.convWords.contains(tok.text.lowercased())
        default: return false
        }
    }

    private func isImplicitFactor(_ tok: Token) -> Bool {
        if tok.kind == .lparen { return true }
        guard tok.kind == .ident else { return false }
        let low = tok.text.lowercased()
        if ctx.vars[tok.text] != nil { return true }
        if Parser.constants[low] != nil { return true }
        if tok.text == "√" { return true }
        if Parser.funcAliases[low] != nil && at(i + 1).kind == .lparen { return true }
        return false
    }

    private func isVarName(_ s: String) -> Bool {
        guard let f = s.utf16.first, Lexer.isLetter(f), f != 0xB0 else { return false }
        return Parser.constants[s.lowercased()] == nil
    }

    /// Longest unit/currency that starts at token j: "km", "km/h", "fl oz", "m^2", "кв м".
    static let squareWords: Set<String> = ["sq", "square", "кв", "квадратных", "квадратный", "квадратного", "квадратних", "квадратний"]
    static let cubicWords: Set<String> = ["cu", "cubic", "куб", "кубических", "кубический", "кубических", "кубічних", "кубічний"]

    func matchUnit(at j: Int) -> (CalcUnit, Int)? {
        guard j < t.count, t[j].kind == .ident else { return nil }
        // "sq feet", "кв футов", "cubic inches": square/cubic word + any length unit
        let w = t[j].text.lowercased()
        if Parser.squareWords.contains(w) || Parser.cubicWords.contains(w), j + 1 < t.count,
           let (lu, n) = matchUnit(at: j + 1), lu.dim == .length {
            let sup = Parser.squareWords.contains(w) ? "²" : "³"
            if let u = reg.lookup(lu.id + sup) { return (u, n + 1) }
        }
        var cands: [(String, Int)] = []
        var acc = ""
        var k = j
        while k < t.count && k < j + 5 {
            let tk = t[k]
            var ok = false
            if k == j {
                ok = true
            } else if tk.kind == .ident {
                ok = true
            } else if tk.kind == .op && (tk.text == "/" || tk.text == "^") {
                ok = !tk.spaceBefore
            } else if tk.kind == .num {
                // "m^2", "l/100km", "литров на 100 км", "l per 100 km"
                let prev = t[k - 1]
                ok = ((isOp(prev, "^") || isOp(prev, "/")) && !tk.spaceBefore)
                    || (prev.kind == .ident && ["на", "per"].contains(prev.text.lowercased()))
            }
            if !ok { break }
            acc += (k > j && tk.spaceBefore ? " " : "") + tk.text
            if tk.kind == .ident || tk.kind == .num { cands.append((acc, k - j + 1)) }
            k += 1
        }
        for (s, n) in cands.reversed() {
            if let u = reg.lookup(s) {
                if let amb = reg.ambiguity(s), j + n - 1 < t.count {
                    let h = Highlight(start: t[j].start, end: t[j + n - 1].end, kind: .error)
                    if !lateMarks.contains(where: { $0.start == h.start }) {
                        lateMarks.append(h)
                        warnings.append(tr("ambUnit", s, amb.map { $0.id }.joined(separator: " / "), u.id))
                    }
                }
                return (u, n)
            }
        }
        return nil
    }

    // MARK: - Grammar

    func parseLine() throws -> Value? {
        if cur.kind == .eof { return nil }
        if cur.kind == .ident, isOp(at(i + 1), "="), at(i + 2).kind != .eof, isVarName(cur.text) {
            let name = cur.text
            mark(i, i, .variable)
            i += 2
            let v = try parseConversion()
            try finish()
            ctx.vars[name] = v
            return v
        }
        var v = try parseConversion()
        // Chains: "88+1=89+1=90+55+8=153" → answer of the last link.
        // A link that starts with an operator continues from the previous answer: "10=+5=*2".
        // A last link that is only a number (a note or an old answer) keeps the live answer.
        while isOp(cur, "=") {
            i += 1
            if cur.kind == .eof { break }
            var j = i
            while t[j].kind != .eof && !isOp(t[j], "=") { j += 1 }
            if j == i { continue }
            var isNote = t[j].kind == .eof && [.num, .clock, .date].contains(t[i].kind)
            if isNote {
                for k in i..<j {
                    let x = t[k]
                    let ok = [.num, .ident, .clock, .date, .sep, .lparen, .rparen].contains(x.kind)
                        || (x.kind == .op && (x.text == "+" || x.text == "-") && k > i && t[k - 1].kind == .lparen)
                    if !ok { isNote = false; break }
                }
            }
            if isNote {
                let first = t[i]
                let differs: Bool
                if first.kind == .num {
                    differs = v.kind == .plain && !v.isPercent && v.format != .hms && !matches(first.num, v.num)
                } else if first.kind == .clock && v.isHMS {
                    differs = Swift.abs(first.num - Swift.abs(v.num)) > 0.5
                } else if (first.kind == .clock && v.kind == .clock) || (first.kind == .date && v.kind == .date) {
                    differs = v.kind == .date ? first.num != v.num
                        : (Int(first.num.rounded()) - Int(v.num.rounded())) % 86400 != 0
                } else {
                    differs = true
                }
                if differs {
                    let text = t[i..<j].map { $0.text }.joined(separator: " ")
                    warnings.append(tr("noteFix", text, fmtValue(v)))
                    marks.append(Highlight(start: t[i].start, end: t[j - 1].end, kind: .error))
                }
                i = j
                break
            }
            if cur.kind == .op && ["+", "-", "*", "/", "^"].contains(cur.text) {
                v = try continueOps(v, allowPower: true)
            } else {
                // The link should start with the previous answer; if the typed number differs,
                // continue from the real answer and flag the number.
                // Always continue from the exact answer (the text may show it rounded).
                if cur.kind == .num && !v.isPercent && v.kind == .plain {
                    if !matches(cur.num, v.num) {
                        warnings.append(tr("chainFix", cur.text, fmt(v.num)))
                        marks.append(Highlight(start: cur.start, end: cur.end, kind: .error))
                    }
                    override = (i, v.num)
                }
                v = try parseConversion()
                override = nil
            }
        }
        try finish()
        return v
    }

    /// Typed number equals the answer within the precision it was written with.
    private func matches(_ typed: Double, _ actual: Double) -> Bool {
        var digits = 0
        let str = String(typed)
        if str.contains("e") {
            digits = 12
        } else if let dot = str.firstIndex(of: ".") {
            let frac = str[str.index(after: dot)...]
            digits = frac == "0" ? 0 : frac.count
        }
        let tol = 0.5 * pow(10.0, -Double(max(digits, decimals))) + 1e-9 * Swift.max(1, Swift.abs(actual))
        return Swift.abs(typed - actual) <= tol
    }

    private func finish() throws {
        guard cur.kind == .eof else { throw CalcError(tr("unclear", cur.text)) }
    }

    private func parseConversion() throws -> Value {
        try continueOps(try parseExpr(), allowPower: false)
    }

    /// Conversions and arithmetic applied to an already computed value.
    private func continueOps(_ start: Value, allowPower: Bool) throws -> Value {
        var v = start
        while true {
            if allowPower && isOp(cur, "^") {
                i += 1
                let e = try parseUnary()
                v = try power(v, e)
                continue
            }
            let tok = cur
            if isConvWord(tok) {
                let j = i + 1
                let nt = at(j)
                if nt.kind == .ident, let f = Parser.formatWords[nt.text.lowercased()] {
                    mark(i, j, .keyword)
                    i = j + 1
                    v.format = f
                    continue
                }
                if v.kind == .clock, let z = matchZone(at: j) {
                    mark(i, i, .keyword)
                    mark(j, j + z.1 - 1, .unit)
                    i = j + z.1
                    v = toZone(v, z.0)
                    continue
                }
                guard let m = matchUnit(at: j) else {
                    if nt.kind == .eof { throw CalcError(tr("convertTo")) }
                    throw CalcError(tr("unknownUnit", nt.text))
                }
                mark(i, i, .keyword)
                mark(j, j + m.1 - 1, .unit)
                i = j + m.1
                if let from = v.unit, (from.dim == .flow && m.0.dim == .speed) || (from.dim == .speed && m.0.dim == .flow) {
                    v = try pipeConvert(v, from, to: m.0)
                    continue
                }
                v = try convert(v, to: m.0)
                continue
            }
            // Arithmetic after a conversion: "$20 in eur - 5%"
            if tok.kind == .op && (tok.text == "+" || tok.text == "-") {
                i += 1
                let r = try parseTerm()
                v = try addSub(v, r, tok.text == "-")
                continue
            }
            if tok.kind == .op && (tok.text == "*" || tok.text == "/") {
                i += 1
                let r = try parseUnary()
                if tok.text == "*" { v = try mul(v, r) } else { v = try div(v, r) }
                continue
            }
            break
        }
        return v
    }

    private func parseExpr() throws -> Value {
        var l = try parseTerm()
        while cur.kind == .op && (cur.text == "+" || cur.text == "-") {
            let sub = cur.text == "-"
            i += 1
            let r = try parseTerm()
            l = try addSub(l, r, sub)
        }
        return l
    }

    private func parseTerm() throws -> Value {
        var l = try parseUnary()
        while true {
            let tok = cur
            if tok.kind == .op && (tok.text == "*" || tok.text == "/") {
                i += 1
                let r = try parseUnary()
                if tok.text == "*" { l = try mul(l, r) } else { l = try div(l, r) }
                continue
            }
            if tok.kind == .ident {
                let low = tok.text.lowercased()
                if (low == "x" || low == "х") && ctx.vars[tok.text] == nil && startsOperand(at(i + 1)) {
                    i += 1
                    let r = try parseUnary()
                    l = try mul(l, r)
                    continue
                }
                if low == "mod" {
                    mark(i, i, .keyword)
                    i += 1
                    let r = try parseUnary()
                    l = try modulo(l, r)
                    continue
                }
                if l.isPercent && (low == "of" || low == "от" || low == "від" || low == "off" || low == "on") {
                    mark(i, i, .keyword)
                    i += 1
                    let r = try parseUnary()
                    if r.isPercent { throw CalcError(tr("pctOfPct")) }
                    var res = r
                    let p = l.num / 100
                    switch low {
                    case "off": res.num = r.num * (1 - p)
                    case "on": res.num = r.num * (1 + p)
                    default: res.num = r.num * p
                    }
                    l = res
                    continue
                }
            }
            break
        }
        return l
    }

    private func parseUnary() throws -> Value {
        if isOp(cur, "-") {
            i += 1
            var v = try parseUnary()
            v.num = -v.num
            return v
        }
        if isOp(cur, "+") {
            i += 1
            return try parseUnary()
        }
        return try parsePower()
    }

    private func parsePower() throws -> Value {
        let b = try parsePostfix()
        if isOp(cur, "^") {
            i += 1
            let e = try parseUnary()
            return try power(b, e)
        }
        return b
    }

    private func parsePostfix() throws -> Value {
        var v = try parsePrimary()
        while true {
            if isOp(cur, "!") && !v.isPercent {
                i += 1
                v.num = try factorial(v.num)
                continue
            }
            if isOp(cur, "%") && !v.isPercent {
                i += 1
                v.isPercent = true
                continue
            }
            break
        }
        v = try dateTimePostfix(v)
        if v.kind == .plain && v.unit == nil && !v.isPercent {
            if cur.kind == .ident, let sc = Parser.scales[cur.text] {
                mark(i, i, .keyword)
                i += 1
                v.num *= sc
            }
            if let m = matchUnit(at: i) {
                let low = cur.text.lowercased()
                let isConv = m.1 == 1 && Parser.convWords.contains(low)
                let next = at(i + 1)
                let nextIsTarget = (matchUnit(at: i + 1) != nil || Parser.formatWords[next.text.lowercased()] != nil)
                    && !Parser.convWords.contains(next.text.lowercased())
                if !(isConv && nextIsTarget) {
                    mark(i, i + m.1 - 1, .unit)
                    i += m.1
                    v.unit = m.0
                    v = try compoundUnits(v)
                }
            }
        }
        // Implicit multiplication: 2 pi, 3(4+1), 2x
        if isImplicitFactor(cur) {
            let r = try parsePostfix()
            v = try mul(v, r)
        }
        return v
    }

    private func parsePrimary() throws -> Value {
        let tok = cur
        switch tok.kind {
        case .clock:
            i += 1
            let showSec = tok.text.filter { $0 == ":" }.count > 1
            // more than 24 hours can only be a duration: 36:30
            if tok.num > 24 * 3600 { return Value.duration(tok.num, showSec, unit: reg.lookup("s")) }
            var c = Value.clock(tok.num)
            c.showSec = showSec
            return c
        case .date:
            i += 1
            return Value.date(Int(tok.num))
        case .num:
            if let o = override, o.index == i {
                i += 1
                return Value(o.value)
            }
            i += 1
            return Value(tok.num)
        case .lparen:
            i += 1
            let v = try parseConversion()
            if cur.kind == .rparen {
                i += 1
            } else if cur.kind != .eof {
                throw CalcError(tr("expectedParen"))
            }
            return v
        case .ident:
            return try parseIdent()
        case .eof:
            throw CalcError(tr("incomplete"))
        default:
            throw CalcError(tr("unexpected", tok.text))
        }
    }

    private func parseIdent() throws -> Value {
        let tok = cur
        let name = tok.text
        let low = name.lowercased()

        if let v = ctx.vars[name] {
            mark(i, i, .variable)
            i += 1
            return v
        }
        if let off = DT.dayWords[low] {
            mark(i, i, .keyword)
            i += 1
            return Value.date(ctx.today + off)
        }
        if DT.nowWords.contains(low) {
            mark(i, i, .keyword)
            i += 1
            return Value.clock(ctx.nowSec)
        }
        if DT.untilWords.contains(low), at(i + 1).kind == .date || at(i + 1).kind == .num {
            mark(i, i, .keyword)
            i += 1
            let target = try upcomingDate()
            return Value(Double(target - ctx.today), unit: reg.lookup("day"))
        }
        if let month = DT.months[low], at(i + 1).kind == .num {
            // "December 12, 2026"
            mark(i, i, .unit)
            i += 1
            let day = cur.num
            i += 1
            if cur.kind == .sep { i += 1 }
            var year = DT.civilFromDays(ctx.today).0
            if cur.kind == .num, cur.num == cur.num.rounded(), cur.num >= 1000 { year = Int(cur.num); i += 1 }
            guard day == day.rounded(), DT.valid(year, month, Int(day)) else { throw CalcError(tr("badDate")) }
            return Value.date(DT.daysFromCivil(year, month, Int(day)))
        }

        if let f = Parser.funcAliases[low] {
            if at(i + 1).kind == .lparen {
                mark(i, i, .function)
                i += 2
                var args: [Value] = []
                if cur.kind == .rparen {
                    i += 1
                } else {
                    while true {
                        let a = try parseConversion()
                        args.append(a)
                        if cur.kind == .sep { i += 1; continue }
                        if cur.kind == .rparen { i += 1; break }
                        if cur.kind == .eof { break }
                        throw CalcError(tr("expectedParen"))
                    }
                }
                return try callFunc(f, args)
            }
            if Parser.prefixFuncs.contains(f), startsOperand(at(i + 1)) {
                mark(i, i, .function)
                i += 1
                let a = try parsePostfix()
                return try callFunc(f, [a])
            }
        }

        if let c = Parser.constants[low] {
            mark(i, i, .keyword)
            i += 1
            return Value(c)
        }

        if Parser.prevWords.contains(low) {
            mark(i, i, .keyword)
            i += 1
            guard let p = ctx.prev else { throw CalcError(tr("noPrev")) }
            return p
        }
        if Parser.sumWords.contains(low) {
            mark(i, i, .keyword)
            i += 1
            return blockAggregate().0
        }
        if Parser.avgWords.contains(low) {
            mark(i, i, .keyword)
            i += 1
            let (s, n) = blockAggregate()
            var r = s
            r.num = n > 0 ? s.num / Double(n) : 0
            return r
        }

        if let m = matchUnit(at: i) {
            mark(i, i + m.1 - 1, .unit)
            i += m.1
            // "$20", "usd 20", "€ 15"
            if m.0.dim == .currency && (cur.kind == .num || cur.kind == .lparen) {
                var v = try parsePostfix()
                if v.isPercent { throw CalcError(tr("curPct")) }
                if let u = v.unit { v.num = try reg.convert(v.num, u, m.0) }
                v.unit = m.0
                return v
            }
            return Value(1, unit: m.0)
        }

        throw CalcError(tr("unknown", name))
    }

    private func blockAggregate() -> (Value, Int) {
        var acc: Value? = nil
        var n = 0
        for v in ctx.block where !v.isPercent {
            if let a = acc {
                if let s = try? addSub(a, v, false) { acc = s; n += 1 }
            } else {
                acc = v
                n = 1
            }
        }
        return (acc ?? Value(0), n)
    }

    // MARK: - Arithmetic

    // MARK: - Dates and times

    private func dateTimePostfix(_ input: Value) throws -> Value {
        var v = input
        func low() -> String { cur.kind == .ident ? cur.text.lowercased() : "" }
        // "12 December 2026", "12 декабря"
        if v.isPlainNumber, v.num == v.num.rounded(), v.num >= 1, v.num <= 31, let month = DT.months[low()] {
            mark(i, i, .unit)
            i += 1
            var year = DT.civilFromDays(ctx.today).0
            if cur.kind == .num, cur.num == cur.num.rounded(), cur.num >= 1000, cur.num <= 9999 { year = Int(cur.num); i += 1 }
            guard DT.valid(year, month, Int(v.num)) else { throw CalcError(tr("badDate")) }
            return Value.date(DT.daysFromCivil(year, month, Int(v.num)))
        }
        // "3pm", "11 am"
        if v.isPlainNumber, v.num == v.num.rounded(), v.num >= 1, v.num <= 12, low() == "am" || low() == "pm" {
            v = Value.clock(v.num * 3600)
        }
        if v.kind == .clock {
            if low() == "am" || low() == "pm" {
                let h = Int(v.num / 3600)
                let rest = v.num - Double(h * 3600)
                let h24 = low() == "pm" ? h % 12 + 12 : h % 12
                mark(i, i, .unit)
                i += 1
                v = Value.clock(Double(h24 * 3600) + rest, v.tz)
            }
            if v.tz == nil && !isConvWord(cur), let z = matchZone(at: i) {
                mark(i, i + z.1 - 1, .unit)
                i += z.1
                v = Value.clock(v.num, z.0)
            }
        }
        return v
    }

    /// "8 h 35 min", "1 day 2 h": add following number+unit of the same kind.
    private func compoundUnits(_ input: Value) throws -> Value {
        var v = input
        while cur.kind == .num, let u = v.unit, [UnitDim.time, .length, .mass].contains(u.dim) {
            var mm = matchUnit(at: i + 1)
            // "1 h 30 m": after hours "m" means minutes
            if let x = mm, u.dim == .time, x.0.dim != .time, at(i + 1).text == "m", let minute = reg.lookup("min") { mm = (minute, 1) }
            guard let m = mm, m.0.dim == u.dim,
                  !Parser.convWords.contains(at(i + 1).text.lowercased()) else { break }
            let n = cur.num
            mark(i + 1, i + m.1, .unit)
            i += 1 + m.1
            v = try addSub(v, Value(n, unit: m.0), false)
        }
        return v
    }

    private func matchZone(at j: Int) -> (CalcZone, Int)? {
        guard at(j).kind == .ident else { return nil }
        for n in [2, 1] where j + n <= t.count {
            let toks = t[j..<(j + n)]
            if toks.contains(where: { $0.kind != .ident }) { continue }
            let key = toks.map { $0.text }.joined(separator: " ").lowercased()
            if let z = DT.zones[key] { return (z, n) }
        }
        return nil
    }

    private func zoneOffset(_ z: CalcZone?) -> Double {
        Double(DT.offset(z?.id ?? ctx.localTZ, at: ctx.now))
    }

    private func toZone(_ v: Value, _ z: CalcZone?) -> Value {
        Value.clock(v.num + zoneOffset(z) - zoneOffset(v.tz), z)
    }

    private func upcomingDate() throws -> Int {
        let tok = cur
        if tok.kind == .date { i += 1; return Int(tok.num) }
        let parts = tok.text.split(whereSeparator: { $0 == "." || $0 == "," })
        guard parts.count == 2, let d = Int(parts[0]), let m = Int(parts[1]) else { throw CalcError(tr("badDate")) }
        i += 1
        var y = DT.civilFromDays(ctx.today).0
        guard DT.valid(y, m, d) else { throw CalcError(tr("badDate")) }
        if DT.daysFromCivil(y, m, d) < ctx.today { y += 1 }
        return DT.daysFromCivil(y, m, d)
    }

    private func addSubDT(_ a: Value, _ b: Value, _ sub: Bool) throws -> Value {
        let sign: Double = sub ? -1 : 1
        if a.isPercent || b.isPercent { throw CalcError(tr("dateOp")) }
        guard let secUnit = reg.lookup("s"), let dayUnit = reg.lookup("day") else { throw CalcError(tr("dateOp")) }
        let showSec = a.showSec || b.showSec
        // time ± time → duration: 0:45+0:30, 18:45-9:30
        if a.kind == .clock && b.kind == .clock {
            let bn = sub && (a.tz != nil || b.tz != nil) ? toZone(b, a.tz).num : b.num
            return Value.duration(a.num + sign * bn, showSec, unit: secUnit)
        }
        if (a.kind == .clock && b.isHMS) || (a.isHMS && b.kind == .clock) {
            return Value.duration(a.num + sign * b.num, showSec, unit: secUnit)
        }
        // clock ± duration in units (h, min) → time of day
        if a.kind == .clock, b.isDuration, let bu = b.unit {
            var c = Value.clock(a.num + sign * (try reg.convert(b.num, bu, secUnit)), a.tz)
            c.showSec = showSec
            return c
        }
        if b.kind == .clock, a.isDuration, !sub, let au = a.unit {
            return Value.clock(b.num + (try reg.convert(a.num, au, secUnit)), b.tz)
        }
        if a.kind == .clock && b.isPlainNumber { throw CalcError(tr("timeNeedsUnit")) }
        if a.kind == .date, b.isDuration, let bu = b.unit {
            return Value.date(try shiftDate(Int(a.num), sign * b.num, bu))
        }
        if b.kind == .date, a.isDuration, !sub, let au = a.unit {
            return Value.date(try shiftDate(Int(b.num), a.num, au))
        }
        if a.kind == .date && b.kind == .date && sub {
            return Value(a.num - b.num, unit: dayUnit)
        }
        if a.kind == .date && b.isPlainNumber { throw CalcError(tr("dateNeedsUnit")) }
        throw CalcError(tr("dateOp"))
    }

    private func shiftDate(_ days: Int, _ n: Double, _ unit: CalcUnit) throws -> Int {
        if unit.id == "month" || unit.id == "year" {
            let months = n * (unit.id == "year" ? 12 : 1)
            guard Swift.abs(months - months.rounded()) < 1e-9 else { throw CalcError(tr("dateWholeDays")) }
            return DT.addMonths(days, Int(months.rounded()))
        }
        guard let dayUnit = reg.lookup("day") else { throw CalcError(tr("dateOp")) }
        let d = try reg.convert(n, unit, dayUnit)
        guard Swift.abs(d - d.rounded()) < 1e-9 else { throw CalcError(tr("dateWholeDays")) }
        return days + Int(d.rounded())
    }

    private func convert(_ v: Value, to u: CalcUnit) throws -> Value {
        if v.kind == .clock && u.dim == .time, let secUnit = reg.lookup("s") {
            return Value(try reg.convert(v.num, secUnit, u), unit: u)
        }
        if v.kind != .plain { throw CalcError(tr("dateOp")) }
        if v.isPercent { throw CalcError(tr("pctConvert", u.id)) }
        var r = v
        r.format = .dec
        if let from = v.unit {
            r.num = try reg.convert(v.num, from, u)
        }
        r.unit = u
        return r
    }

    private func addSub(_ a: Value, _ b: Value, _ sub: Bool) throws -> Value {
        if a.kind != .plain || b.kind != .plain { return try addSubDT(a, b, sub) }
        if (a.isHMS && b.isPlainNumber) || (b.isHMS && a.isPlainNumber) { throw CalcError(tr("timeNeedsUnit")) }
        let sign: Double = sub ? -1 : 1
        if b.isPercent && !a.isPercent {
            var r = a
            r.num = a.num * (1 + sign * b.num / 100)
            return r
        }
        if a.isPercent != b.isPercent { throw CalcError(tr("pctAdd")) }
        var r = a
        switch (a.unit, b.unit) {
        case (.some(let ua), .some(let ub)):
            let bv = try reg.convert(b.num, ub, ua)
            r.num = a.num + sign * bv
        case (nil, .some(let ub)):
            r.num = a.num + sign * b.num
            r.unit = ub
        default:
            r.num = a.num + sign * b.num
        }
        return r
    }

    private func asDuration(_ v: Value) -> Value {
        v.kind == .clock ? Value.duration(v.num, v.showSec, unit: reg.lookup("s")) : v
    }

    private func mul(_ a0: Value, _ b0: Value) throws -> Value {
        let a = asDuration(a0), b = asDuration(b0)
        if a.kind != .plain || b.kind != .plain { throw CalcError(tr("dateOp")) }
        // hours × rate: 8:30 * $25, 8 h * 25 usd
        func timeMoney(_ t: Value, _ m: Value) -> Bool {
            t.unit?.dim == .time && m.unit?.dim == .currency && !t.isPercent && !m.isPercent
        }
        if timeMoney(a, b), let tu = a.unit, let h = reg.lookup("h") { return Value(try reg.convert(a.num, tu, h) * b.num, unit: b.unit) }
        if timeMoney(b, a), let tu = b.unit, let h = reg.lookup("h") { return Value(try reg.convert(b.num, tu, h) * a.num, unit: a.unit) }
        if a.isPercent && b.isPercent { return Value(a.num * b.num / 100, percent: true) }
        if b.isPercent { var r = a; r.num = a.num * b.num / 100; return r }
        if a.isPercent { var r = b; r.num = b.num * a.num / 100; return r }
        switch (a.unit, b.unit) {
        case (.some(let ua), .some(let ub)):
            if (ua.dim == .flow && ub.dim == .time) || (ua.dim == .time && ub.dim == .flow),
               let m3s = reg.lookup("m³/s"), let s = reg.lookup("s"), let m3 = reg.lookup("m³") {
                let (q, t) = ua.dim == .flow ? (a, b) : (b, a)
                return Value(try reg.convert(q.num, q.unit!, m3s) * reg.convert(t.num, t.unit!, s), unit: m3)
            }
            // area × length → volume: 2 ft * 3 ft * 4 ft
            if (ua.dim == .area && ub.dim == .length) || (ua.dim == .length && ub.dim == .area),
               let m2 = reg.lookup("m²"), let m = reg.lookup("m"), let m3 = reg.lookup("m³") {
                let (ar, ln) = ua.dim == .area ? (a, b) : (b, a)
                let v = try reg.convert(ar.num, ar.unit!, m2) * reg.convert(ln.num, ln.unit!, m)
                if let cu = reg.lookup(ln.unit!.id + "³") { return Value(try reg.convert(v, m3, cu), unit: cu) }
                return Value(v, unit: m3)
            }
            if ua.dim == .length && ub.dim == .length {
                let bv = try reg.convert(b.num, ub, ua)
                if let area = reg.lookup(ua.id + "²") { return Value(a.num * bv, unit: area) }
            }
            throw CalcError(tr("mulUnits", ua.id, ub.id))
        case (nil, .some(let ub)):
            return Value(a.num * b.num, unit: ub)
        default:
            var r = a
            r.num = a.num * b.num
            return r
        }
    }

    private func div(_ a0: Value, _ b0: Value) throws -> Value {
        let a = asDuration(a0), b = asDuration(b0)
        if b.num == 0 { throw CalcError(tr("divZero")) }
        if a.kind != .plain || b.kind != .plain { throw CalcError(tr("dateOp")) }
        if a.isPercent && b.isPercent { return Value(a.num / b.num) }
        if b.isPercent { var r = a; r.num = a.num / (b.num / 100); return r }
        if a.isPercent { return Value(a.num / b.num, percent: true) }
        switch (a.unit, b.unit) {
        case (.some(let ua), .some(let ub)):
            if ua.dim == ub.dim {
                let bv = try reg.convert(b.num, ub, ua)
                if bv == 0 { throw CalcError(tr("divZero")) }
                return Value(a.num / bv)
            }
            if ua.dim == .volume && ub.dim == .time, let base = reg.lookup("m³/s") {
                let q = (a.num * ua.factor) / (b.num * ub.factor)
                let tu = reg.lookup(ua.id + "/" + ub.id).flatMap { $0.dim == .flow ? $0 : nil } ?? base
                return Value(try reg.convert(q, base, tu), unit: tu)
            }
            if ua.dim == .flow && ub.dim == .area, let m3s = reg.lookup("m³/s"), let m2 = reg.lookup("m²"), let ms = reg.lookup("m/s") {
                let area = try reg.convert(b.num, ub, m2)
                if area == 0 { throw CalcError(tr("divZero")) }
                return Value(try reg.convert(a.num, ua, m3s) / area, unit: ms)
            }
            if ua.dim == .length && ub.dim == .time, let direct = reg.lookup(ua.id + "/" + ub.id), direct.dim == .speed,
               let ms = reg.lookup("m/s") {
                let mps = (a.num * ua.factor) / (b.num * ub.factor)
                return Value(try reg.convert(mps, ms, direct), unit: direct)
            }
            if ua.dim == .length && ub.dim == .time {
                let mps = (a.num * ua.factor) / (b.num * ub.factor)
                var target = "m/s"
                if ub.id == "h" && ua.id == "km" { target = "km/h" }
                if ub.id == "h" && ua.id == "mi" { target = "mph" }
                guard let ms = reg.lookup("m/s"), let tu = reg.lookup(target) else { break }
                return Value(try reg.convert(mps, ms, tu), unit: tu)
            }
            throw CalcError(tr("divUnits", ua.id, ub.id))
        case (nil, .some(let ub)):
            throw CalcError(tr("divNumUnit", ub.id))
        default:
            var r = a
            r.num = a.num / b.num
            return r
        }
        throw CalcError(tr("divGeneric"))
    }

    static let atWords: Set<String> = ["at", "при", "для", "for", "d", "dn", "ø", "⌀"]

    /// Flow ↔ speed in a round pipe: "1500 m3/h in m/s at 500 mm".
    private func pipeConvert(_ v: Value, _ from: CalcUnit, to: CalcUnit) throws -> Value {
        guard cur.kind == .ident, Parser.atWords.contains(cur.text.lowercased()) else {
            throw CalcError(tr("needDiameter"))
        }
        mark(i, i, .keyword)
        i += 1
        // optional words: "при диаметре 500 мм", "at diameter 500 mm"
        while cur.kind == .ident, ["диаметре", "діаметрі", "diameter", "трубе", "трубі", "pipe", "dn", "d"].contains(cur.text.lowercased()) {
            mark(i, i, .keyword)
            i += 1
        }
        let d = try parseTerm()
        guard let du = d.unit, du.dim == .length, let m = reg.lookup("m"),
              let m3s = reg.lookup("m³/s"), let ms = reg.lookup("m/s") else {
            throw CalcError(tr("needDiameter"))
        }
        let dm = try reg.convert(d.num, du, m)
        guard dm > 0 else { throw CalcError(tr("divZero")) }
        let area = Double.pi * dm * dm / 4
        if from.dim == .flow {
            let q = try reg.convert(v.num, from, m3s)
            return Value(try reg.convert(q / area, ms, to), unit: to)
        }
        let s = try reg.convert(v.num, from, ms)
        return Value(try reg.convert(s * area, m3s, to), unit: to)
    }

    private func modulo(_ a: Value, _ b: Value) throws -> Value {
        var bv = b.num
        if let ua = a.unit, let ub = b.unit { bv = try reg.convert(b.num, ub, ua) }
        if bv == 0 { throw CalcError(tr("divZero")) }
        var r = a
        r.num = fmod(a.num, bv)
        return r
    }

    private func power(_ b: Value, _ e: Value) throws -> Value {
        if e.unit != nil || e.isPercent { throw CalcError(tr("powNum")) }
        if let u = b.unit {
            if u.dim == .length && (e.num == 2 || e.num == 3) {
                let suffix = e.num == 2 ? "²" : "³"
                if let nu = reg.lookup(u.id + suffix) { return Value(pow(b.num, e.num), unit: nu) }
            }
            throw CalcError(tr("powUnit", u.id))
        }
        let r = pow(b.num, e.num)
        if r.isNaN { throw CalcError(tr("noReal")) }
        return Value(r)
    }

    private func factorial(_ x: Double) throws -> Double {
        guard x >= 0, x == x.rounded(), x <= 170 else { throw CalcError(tr("factorial")) }
        return tgamma(x + 1).rounded()
    }

    private func callFunc(_ f: String, _ args: [Value]) throws -> Value {
        func one() throws -> Value {
            guard args.count == 1 else { throw CalcError(tr("oneArg", f)) }
            return args[0]
        }
        func plain(_ v: Value) throws -> Double {
            if v.unit != nil { throw CalcError(tr("plainArg", f)) }
            return v.isPercent ? v.num / 100 : v.num
        }
        func radians(_ v: Value) throws -> Double {
            if let u = v.unit {
                guard u.dim == .angle else { throw CalcError(tr("angleArg", f)) }
                return v.num * u.factor
            }
            return v.num
        }

        switch f {
        case "sqrt":
            let x = try plain(try one())
            guard x >= 0 else { throw CalcError(tr("sqrtNeg")) }
            return Value(x.squareRoot())
        case "cbrt":
            let x = try plain(try one())
            return Value(cbrt(x))
        case "root":
            guard args.count == 2 else { throw CalcError(tr("rootUsage")) }
            let x = try plain(args[0])
            let n = try plain(args[1])
            guard n != 0 else { throw CalcError(tr("rootZero")) }
            return Value(pow(x, 1 / n))
        case "abs", "round", "floor", "ceil", "trunc":
            guard args.count == 1 || args.count == 2 else { throw CalcError(tr("oneTwoArgs", f)) }
            var v = args[0]
            var digits = 0.0
            if args.count == 2 { digits = try plain(args[1]) }
            let m = pow(10.0, digits)
            switch f {
            case "abs": v.num = Swift.abs(v.num)
            case "round": v.num = (v.num * m).rounded(.toNearestOrAwayFromZero) / m
            case "floor": v.num = (v.num * m).rounded(.down) / m
            case "ceil": v.num = (v.num * m).rounded(.up) / m
            default: v.num = (v.num * m).rounded(.towardZero) / m
            }
            return v
        case "sin": return Value(sin(try radians(try one())))
        case "cos": return Value(cos(try radians(try one())))
        case "tan": return Value(tan(try radians(try one())))
        case "asin": return Value(asin(try plain(try one())))
        case "acos": return Value(acos(try plain(try one())))
        case "atan": return Value(atan(try plain(try one())))
        case "sinh": return Value(sinh(try plain(try one())))
        case "cosh": return Value(cosh(try plain(try one())))
        case "tanh": return Value(tanh(try plain(try one())))
        case "ln":
            let x = try plain(try one())
            guard x > 0 else { throw CalcError(tr("logPos")) }
            return Value(log(x))
        case "log":
            guard args.count == 1 || args.count == 2 else { throw CalcError(tr("logUsage")) }
            let x = try plain(args[0])
            guard x > 0 else { throw CalcError(tr("logPos")) }
            if args.count == 2 {
                let b = try plain(args[1])
                guard b > 0 && b != 1 else { throw CalcError(tr("badBase")) }
                return Value(log(x) / log(b))
            }
            return Value(log10(x))
        case "log2":
            let x = try plain(try one())
            guard x > 0 else { throw CalcError(tr("logPos")) }
            return Value(log2(x))
        case "exp":
            return Value(exp(try plain(try one())))
        case "fact":
            let x = try plain(try one())
            return Value(try factorial(x))
        case "min", "max", "avg", "sum":
            guard let first = args.first else { throw CalcError(tr("needArgs", f)) }
            var vals: [Double] = []
            for a in args {
                if let ua = first.unit, let ub = a.unit {
                    vals.append(try reg.convert(a.num, ub, ua))
                } else {
                    vals.append(a.num)
                }
            }
            var r = first
            switch f {
            case "min": r.num = vals.min() ?? 0
            case "max": r.num = vals.max() ?? 0
            case "sum": r.num = vals.reduce(0, +)
            default: r.num = vals.reduce(0, +) / Double(vals.count)
            }
            return r
        default:
            throw CalcError(tr("unknownFunc", f))
        }
    }
}
