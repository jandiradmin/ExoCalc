import Foundation

public enum NumFormat {
    case dec, hex, bin, oct, sci, hms
}

public enum ValueKind {
    /// Number, maybe with a unit or percent.
    case plain
    /// Clock time: seconds since midnight (may run past 24 h after arithmetic).
    case clock
    /// Calendar date: days since 1970-01-01.
    case date
}

/// Result of an expression: a number, optionally with a unit, or a percentage.
public struct Value {
    public var num: Double
    public var unit: CalcUnit?
    public var isPercent: Bool
    public var format: NumFormat
    public var kind: ValueKind = .plain
    public var tz: CalcZone?

    public init(_ num: Double, unit: CalcUnit? = nil, percent: Bool = false, format: NumFormat = .dec) {
        self.num = num
        self.unit = unit
        self.isPercent = percent
        self.format = format
    }

    static func clock(_ sec: Double, _ tz: CalcZone? = nil) -> Value {
        var v = Value(sec)
        v.kind = .clock
        v.tz = tz
        return v
    }

    static func date(_ days: Int) -> Value {
        var v = Value(Double(days))
        v.kind = .date
        return v
    }

    var isPlainNumber: Bool { kind == .plain && unit == nil && !isPercent }
    var isDuration: Bool { kind == .plain && unit?.dim == .time && !isPercent }
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
    /// "dmy" (31.12.2026), "mdy" (12/31/2026) or "ymd" (2026-12-31).
    public var dateFormat: String = "dmy"
    public init() {}
}

public enum HKind {
    case number, unit, keyword, function, variable, comment, label, error
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
    /// Non-fatal note, e.g. a wrong number inside a chain.
    public var warning: String?
    public var highlights: [Highlight] = []
    public init() {}
}
