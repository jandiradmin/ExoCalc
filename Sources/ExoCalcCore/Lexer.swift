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
                throw CalcError("неизвестный символ «\(ch)»")
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

        var digits = ""
        var intLen = 0
        while i < n && Lexer.isDigit(s[i]) {
            digits.append(ascii(s[i]))
            i += 1
            intLen += 1
        }

        // Thousands groups: 19,480 / 1 000 000 / 1.000.000
        var grouped = false
        while i + 3 < n,
              groups.contains(s[i]),
              Lexer.isDigit(s[i + 1]), Lexer.isDigit(s[i + 2]), Lexer.isDigit(s[i + 3]),
              i + 4 >= n || !Lexer.isDigit(s[i + 4]),
              grouped || (intLen >= 1 && intLen <= 3) {
            for k in 1...3 { digits.append(ascii(s[i + k])) }
            i += 4
            grouped = true
        }

        // Fraction
        if i + 1 < n, Lexer.isDigit(s[i + 1]), s[i] == decimal || (decimal == 44 && s[i] == 46 && !grouped) {
            if digits.isEmpty { digits = "0" }
            digits.append(".")
            i += 1
            while i < n && Lexer.isDigit(s[i]) {
                digits.append(ascii(s[i]))
                i += 1
            }
        }

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

        guard let v = Double(digits) else { throw CalcError("неверное число") }
        return (v, i)
    }
}
