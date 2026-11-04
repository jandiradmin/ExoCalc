import Foundation

public enum NumFormat {
    case dec, hex, bin, oct, sci
}

/// Result of an expression: a number, optionally with a unit, or a percentage.
public struct Value {
    public var num: Double
    public var unit: CalcUnit?
    public var isPercent: Bool
    public var format: NumFormat

    public init(_ num: Double, unit: CalcUnit? = nil, percent: Bool = false, format: NumFormat = .dec) {
        self.num = num
        self.unit = unit
        self.isPercent = percent
        self.format = format
    }
}

public struct CalcError: Error {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public struct CalcSettings: Equatable {
    public var decimalSeparator: Character = "."
    public var groupingSeparator: String = ","
    public var decimals: Int = 2
    public var trimZeros: Bool = true
    public init() {}
}

public enum HKind {
    case number, unit, keyword, function, variable, comment, label
}

/// Syntax highlight span; offsets are UTF-16 positions inside the line.
public struct Highlight {
    public let start: Int
    public let end: Int
    public let kind: HKind
}

public struct LineResult {
    public var value: Value?
    public var display: String?
    public var error: String?
    public var highlights: [Highlight] = []
    public init() {}
}
