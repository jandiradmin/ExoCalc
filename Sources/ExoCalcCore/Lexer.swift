import Foundation

struct Token {
    enum Kind { case num, ident, op, lparen, rparen, sep, eof }
    var kind: Kind
    var text: String
    var num: Double = 0
    var start: Int          // UTF-16 offset in the line
    var end: Int
    var spaceBefore: Bool
}

struct Lexer {
    private let s: [UInt16]
    private let base: Int
    private let decimal: UInt16
    private let groups: Set<UInt16>

    init(_ text: String, base: Int, settings: CalcSettings) {
        s = Array(text.utf16)
        self.base = base
        let dec: UInt16 = settings.decimalSeparator == "," ? 44 : 46
        decimal = dec
        // Thousands separators accepted in input.
        var g: Set<UInt16> = dec == 46 ? [44, 39] : [46, 32, 0xA0, 0x202F, 39]
        if let gs = settings.groupingSeparator.utf16.first { g.insert(gs) }
        g.remove(dec)
        groups = g
    }

    static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }

    static func isLetter(_ c: UInt16) -> Bool {
        if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 { return true }
        if c < 0xB0 { return false }
        if c == 0xB0 || c == 0xB5 { return true }                       // ° µ
        if c == 0xB2 || c == 0xB3 || c == 0xB7 || c == 0xD7 || c == 0xF7 { return false }
        guard let u = Unicode.Scalar(UInt32(c)) else { return false }
        return CharacterSet.letters.contains(u)
    }

    static func isIdentCont(_ c: UInt16) -> Bool {
        isLetter(c) || isDigit(c) || c == 0xB2 || c == 0xB3              // ² ³
    }

    private func str(_ a: Int, _ b: Int) -> String {
        String(decoding: s[a..<b], as: UTF16.self)
    }

    func tokenize() throws -> [Token] {
        var toks: [Token] = []
        var i = 0
        var space = false
        let n = s.count

        func push(_ k: Token.Kind, _ text: String, _ a: Int, _ b: Int, num: Double = 0) {
            toks.append(Token(kind: k, text: text, num: num, start: base + a, end: base + b, spaceBefore: space))
            space = false
        }

        while i < n {
            let c = s[i]
            if c == 32 || c == 9 || c == 0xA0 || c == 0x202F || c == 0x2009 {
                space = true
                i += 1
                continue
            }
            if Lexer.isDigit(c) || (c == decimal && i + 1 < n && Lexer.isDigit(s[i + 1])) {
                let (v, e) = try lexNumber(i)
                push(.num, str(i, e), i, e, num: v)
                i = e
                // 800x12 → 800 * 12
                if i + 1 < n, s[i] == 120 || s[i] == 88 || s[i] == 0x445, Lexer.isDigit(s[i + 1]) {
                    push(.op, "*", i, i + 1)
                    i += 1
                }
                continue
            }
            if Lexer.isLetter(c) {
                var j = i + 1
                while j < n && Lexer.isIdentCont(s[j]) { j += 1 }
                push(.ident, str(i, j), i, j)
                i = j
                continue
            }
            let ch = Character(Unicode.Scalar(UInt32(c)) ?? "?")
            switch ch {
            case "$", "€", "£", "₴", "¥", "₿", "√", "℃", "℉":
                push(.ident, String(ch), i, i + 1); i += 1
            case "(", "[":
                push(.lparen, "(", i, i + 1); i += 1
            case ")", "]":
                push(.rparen, ")", i, i + 1); i += 1
            case ";", ",":
                push(.sep, ",", i, i + 1); i += 1
            case "-", "−", "–":
                if i + 1 < n && s[i + 1] == 62 {
                    push(.op, "->", i, i + 2); i += 2
                } else {
                    push(.op, "-", i, i + 1); i += 1
                }
            case "*":
                if i + 1 < n && s[i + 1] == 42 {
                    push(.op, "^", i, i + 2); i += 2
                } else {
                    push(.op, "*", i, i + 1); i += 1
                }
            case "×", "·", "∙":
                push(.op, "*", i, i + 1); i += 1
            case "÷":
                push(.op, "/", i, i + 1); i += 1
            case "→":
                push(.op, "->", i, i + 1); i += 1
            case "+", "/", "^", "%", "!", "=":
                push(.op, String(ch), i, i + 1); i += 1
            default:
                throw CalcError(tr("unknownChar", String(ch)))
            }
        }
        toks.append(Token(kind: .eof, text: "", start: base + n, end: base + n, spaceBefore: space))
        return toks
    }

    private func digitValue(_ c: UInt16, _ radix: Int) -> Int? {
        var v = -1
        if c >= 48 && c <= 57 { v = Int(c) - 48 }
        else if c >= 97 && c <= 102 { v = Int(c) - 87 }
        else if c >= 65 && c <= 70 { v = Int(c) - 55 }
        return (v >= 0 && v < radix) ? v : nil
    }

    private func ascii(_ c: UInt16) -> Character {
        Character(Unicode.Scalar(UInt8(truncatingIfNeeded: c)))
    }

    private func lexNumber(_ start: Int) throws -> (Double, Int) {
        let n = s.count
        var i = start

        // 0xFF, 0b1010, 0o17
        if s[i] == 48 && i + 2 < n {
            let p = s[i + 1]
            var radix = 0
            if p == 120 || p == 88 { radix = 16 }
            else if p == 98 || p == 66 { radix = 2 }
            else if p == 111 || p == 79 { radix = 8 }
            if radix > 0 {
                var j = i + 2
                while j < n, digitValue(s[j], radix) != nil { j += 1 }
                if j > i + 2, let v = UInt64(str(i + 2, j), radix: radix) {
                    return (Double(v), j)
                }
            }
        }

        // Collect digit groups and the separators between them.
        // Understands 300,000.00 · 300 000,00 · 30000,00 · 1.234.567 · 1'000 regardless of settings.
        var groupsArr: [String] = []
        var seps: [UInt16] = []
        var ends: [Int] = []          // end index after each group
        func readDigits() -> String {
            var g = ""
            while i < n && Lexer.isDigit(s[i]) { g.append(ascii(s[i])); i += 1 }
            return g
        }
        groupsArr.append(readDigits())
        ends.append(i)
        while i + 1 < n {
            let c = s[i]
            let last = groupsArr[groupsArr.count - 1]
            if c == 44 || c == 46 || c == 39 {                      // , . '
                guard Lexer.isDigit(s[i + 1]) else { break }
                i += 1
                seps.append(c)
                groupsArr.append(readDigits())
                ends.append(i)
            } else if c == 32 || c == 0xA0 || c == 0x202F {          // space grouping: "300 000"
                guard i + 3 < n,
                      Lexer.isDigit(s[i + 1]), Lexer.isDigit(s[i + 2]), Lexer.isDigit(s[i + 3]),
                      i + 4 >= n || !Lexer.isDigit(s[i + 4]),
                      last.count >= 1 && last.count <= 3,
                      !seps.contains(where: { $0 == 44 || $0 == 46 }) || seps.allSatisfy({ $0 == 32 }) else { break }
                i += 1
                seps.append(32)
                groupsArr.append(readDigits())
                ends.append(i)
            } else {
                break
            }
        }

        // Interpret the longest valid prefix.
        var digits = ""
        var chosen = 0
        for k in stride(from: groupsArr.count, through: 1, by: -1) {
            if let d = interpretNumber(Array(groupsArr[0..<k]), Array(seps[0..<(k - 1)])) {
                digits = d
                chosen = k
                break
            }
        }
        guard chosen > 0 else { throw CalcError(tr("badNumber")) }
        i = ends[chosen - 1]

        // Exponent: 1e6, 2.5E-3
        if i < n, s[i] == 101 || s[i] == 69 {
            var j = i + 1
            if j < n, s[j] == 43 || s[j] == 45 { j += 1 }
            if j < n, Lexer.isDigit(s[j]) {
                var k = j
                while k < n && Lexer.isDigit(s[k]) { k += 1 }
                if k >= n || !Lexer.isLetter(s[k]) {
                    digits += "e" + str(i + 1, k)
                    i = k
                }
            }
        }

        guard let v = Double(digits) else { throw CalcError(tr("badNumber")) }
        return (v, i)
    }

    /// Turns groups/separators into a plain "1234.5" string, or nil if the combination is invalid.
    private func interpretNumber(_ g: [String], _ seps: [UInt16]) -> String? {
        if seps.isEmpty { return g[0].isEmpty ? nil : g[0] }
        let punct = seps.enumerated().filter { $0.element == 44 || $0.element == 46 }
        var decimalIndex: Int? = nil      // index into seps
        let kinds = Set(punct.map { $0.element })
        if kinds.count == 2 {
            guard let lastP = punct.last else { return nil }
            decimalIndex = lastP.offset
            if punct.filter({ $0.element == lastP.element }).count > 1 { return nil }
        } else if punct.count == 1 {
            let p = punct[0]
            let after = g[p.offset + 1]
            let before = g[p.offset]
            let couldGroup = after.count == 3 && before.count >= 1 && before.count <= 3
            if couldGroup && p.element != decimal && p.offset == seps.count - 1 {
                decimalIndex = nil        // 1,500 in "." mode → 1500
            } else {
                decimalIndex = p.offset   // 30000,00 / 1.5 / 1,500 in "," mode
            }
        }
        if let d = decimalIndex, d != seps.count - 1 { return nil }  // decimal must be last
        // Validate grouping: first group 1-3 digits, following groups exactly 3.
        let lastGroupIdx = decimalIndex ?? seps.count
        if lastGroupIdx > 0 {
            guard g[0].count >= 1 && g[0].count <= 3 else { return nil }
            for k in 1...lastGroupIdx where g[k].count != 3 { return nil }
        }
        var out = g[0...lastGroupIdx].joined()
        if let d = decimalIndex {
            if out.isEmpty { out = "0" }
            out += "." + g[d + 1]
        }
        return out.isEmpty ? nil : out
    }
}
