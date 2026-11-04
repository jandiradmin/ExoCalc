import Foundation

public enum UnitDim: String {
    case length, area, volume, mass, time, temperature, data, speed, angle, energy, power, pressure, frequency, currency
}

/// A unit. Conversion to the base unit of its dimension: base = value * factor + offset.
public struct CalcUnit: Equatable {
    public let id: String
    public let dim: UnitDim
    public let factor: Double
    public let offset: Double
    public let isCrypto: Bool

    public init(_ id: String, _ dim: UnitDim, _ factor: Double, offset: Double = 0, isCrypto: Bool = false) {
        self.id = id
        self.dim = dim
        self.factor = factor
        self.offset = offset
        self.isCrypto = isCrypto
    }

    public static func == (a: CalcUnit, b: CalcUnit) -> Bool { a.id == b.id && a.dim == b.dim }
}

private struct Def {
    let id: String
    let dim: UnitDim
    let f: Double
    let off: Double
    let a: [String]
}

private func d(_ id: String, _ dim: UnitDim, _ f: Double, _ a: [String], off: Double = 0) -> Def {
    Def(id: id, dim: dim, f: f, off: off, a: a)
}

private let unitDefs: [Def] = [
    // Length — base metre
    d("mm", .length, 0.001, ["millimeter", "millimeters", "millimetre", "millimetres", "мм", "миллиметр", "миллиметров", "миллиметра"]),
    d("cm", .length, 0.01, ["centimeter", "centimeters", "centimetre", "centimetres", "см", "сантиметр", "сантиметров", "сантиметра"]),
    d("dm", .length, 0.1, ["decimeter", "decimeters", "дм"]),
    d("m", .length, 1, ["meter", "meters", "metre", "metres", "м", "метр", "метров", "метра", "метры"]),
    d("km", .length, 1000, ["kilometer", "kilometers", "kilometre", "kilometres", "км", "километр", "километров", "километра"]),
    d("µm", .length, 1e-6, ["um", "micrometer", "micrometers", "micron", "microns", "мкм"]),
    d("nm", .length, 1e-9, ["nanometer", "nanometers", "нм"]),
    d("in", .length, 0.0254, ["inch", "inches", "дюйм", "дюймов", "дюйма"]),
    d("ft", .length, 0.3048, ["foot", "feet", "фут", "футов", "фута"]),
    d("yd", .length, 0.9144, ["yard", "yards", "ярд", "ярдов", "ярда"]),
    d("mi", .length, 1609.344, ["mile", "miles", "миля", "миль", "мили", "милях"]),
    d("nmi", .length, 1852, ["nautical mile", "nautical miles", "морская миля", "морских миль"]),

    // Area — base m²
    d("mm²", .area, 1e-6, ["mm2", "mm^2", "sq mm", "мм²", "мм2"]),
    d("cm²", .area, 1e-4, ["cm2", "cm^2", "sq cm", "см²", "см2"]),
    d("m²", .area, 1, ["m2", "m^2", "sq m", "sqm", "square meter", "square meters", "square metre", "м²", "м2", "кв м", "квм"]),
    d("km²", .area, 1e6, ["km2", "km^2", "sq km", "square kilometer", "square kilometers", "км²", "км2", "кв км"]),
    d("ha", .area, 1e4, ["hectare", "hectares", "га", "гектар", "гектаров", "гектара"]),
    d("сотка", .area, 100, ["сотки", "соток", "ar", "are", "ares"]),
    d("ft²", .area, 0.09290304, ["ft2", "ft^2", "sq ft", "sqft", "square foot", "square feet"]),
    d("in²", .area, 0.00064516, ["in2", "in^2", "sq in", "square inch", "square inches"]),
    d("yd²", .area, 0.83612736, ["yd2", "sq yd", "square yard", "square yards"]),
    d("acre", .area, 4046.8564224, ["acres", "ac", "акр", "акров", "акра"]),
    d("mi²", .area, 2589988.110336, ["mi2", "sq mi", "square mile", "square miles"]),

    // Volume — base m³
    d("ml", .volume, 1e-6, ["mL", "milliliter", "milliliters", "millilitre", "мл", "миллилитр", "миллилитров"]),
    d("cl", .volume, 1e-5, ["centiliter", "centiliters"]),
    d("l", .volume, 1e-3, ["L", "liter", "liters", "litre", "litres", "л", "литр", "литров", "литра", "литры"]),
    d("m³", .volume, 1, ["m3", "m^3", "cubic meter", "cubic meters", "cubic metre", "м³", "м3", "куб", "кубов", "куба", "кубометр", "кубометров"]),
    d("cm³", .volume, 1e-6, ["cm3", "cm^3", "cc", "см³", "см3"]),
    d("gal", .volume, 0.003785411784, ["gallon", "gallons", "галлон", "галлонов", "галлона"]),
    d("qt", .volume, 0.000946352946, ["quart", "quarts"]),
    d("pt", .volume, 0.000473176473, ["pint", "pints"]),
    d("cup", .volume, 0.0002365882365, ["cups", "стакан", "стакана", "стаканов"]),
    d("fl oz", .volume, 2.95735295625e-5, ["floz", "fluid ounce", "fluid ounces"]),
    d("tbsp", .volume, 1.478676478125e-5, ["tablespoon", "tablespoons"]),
    d("tsp", .volume, 4.92892159375e-6, ["teaspoon", "teaspoons"]),
    d("bbl", .volume, 0.158987294928, ["barrel", "barrels", "баррель", "баррелей", "барреля"]),

    // Mass — base kg
    d("mg", .mass, 1e-6, ["milligram", "milligrams", "мг", "миллиграмм"]),
    d("g", .mass, 1e-3, ["gram", "grams", "gramme", "gr", "г", "гр", "грамм", "граммов", "грамма"]),
    d("kg", .mass, 1, ["kilogram", "kilograms", "kilo", "kilos", "кг", "килограмм", "килограммов", "килограмма", "кило"]),
    d("t", .mass, 1000, ["ton", "tons", "tonne", "tonnes", "т", "тонна", "тонн", "тонны", "тонну"]),
    d("lb", .mass, 0.45359237, ["lbs", "pound", "pounds", "фунт", "фунтов", "фунта"]),
    d("oz", .mass, 0.028349523125, ["ounce", "ounces", "унция", "унций", "унции"]),
    d("st", .mass, 6.35029318, ["stone", "stones"]),
    d("ct", .mass, 0.0002, ["carat", "carats", "карат", "карата"]),

    // Time — base second
    d("ms", .time, 0.001, ["millisecond", "milliseconds", "мс"]),
    d("s", .time, 1, ["sec", "secs", "second", "seconds", "с", "сек", "секунда", "секунд", "секунды", "секунду"]),
    d("min", .time, 60, ["mins", "minute", "minutes", "мин", "минута", "минут", "минуты", "минуту"]),
    d("h", .time, 3600, ["hr", "hrs", "hour", "hours", "ч", "час", "часа", "часов"]),
    d("day", .time, 86400, ["days", "d", "день", "дня", "дней", "дн", "сутки", "суток"]),
    d("week", .time, 604800, ["weeks", "wk", "неделя", "недели", "недель", "нед", "неделю"]),
    d("month", .time, 2629746, ["months", "мес", "месяц", "месяца", "месяцев"]),
    d("year", .time, 31556952, ["years", "yr", "yrs", "год", "года", "лет"]),

    // Temperature — base kelvin
    d("°C", .temperature, 1, ["C", "℃", "°С", "celsius", "цельсий", "цельсия"], off: 273.15),
    d("°F", .temperature, 5.0 / 9.0, ["F", "℉", "fahrenheit", "фаренгейт", "фаренгейта"], off: 459.67 * 5.0 / 9.0),
    d("K", .temperature, 1, ["kelvin", "kelvins", "кельвин", "кельвина"]),

    // Data — base byte
    d("bit", .data, 0.125, ["bits", "бит", "бита", "битов"]),
    d("B", .data, 1, ["byte", "bytes", "байт", "байта", "байтов", "Б"]),
    d("KB", .data, 1e3, ["kB", "kilobyte", "kilobytes", "КБ", "Кб", "кб"]),
    d("MB", .data, 1e6, ["megabyte", "megabytes", "МБ", "Мб", "мб"]),
    d("GB", .data, 1e9, ["gigabyte", "gigabytes", "ГБ", "Гб", "гб"]),
    d("TB", .data, 1e12, ["terabyte", "terabytes", "ТБ", "Тб", "тб"]),
    d("PB", .data, 1e15, ["petabyte", "petabytes"]),
    d("KiB", .data, 1024, ["kibibyte", "kibibytes"]),
    d("MiB", .data, 1048576, ["mebibyte", "mebibytes"]),
    d("GiB", .data, 1073741824, ["gibibyte", "gibibytes"]),
    d("TiB", .data, 1099511627776, ["tebibyte", "tebibytes"]),
    d("Kb", .data, 125, ["kbit", "kilobit", "kilobits"]),
    d("Mb", .data, 125000, ["Mbit", "megabit", "megabits", "Мбит", "мбит"]),
    d("Gb", .data, 1.25e8, ["Gbit", "gigabit", "gigabits", "Гбит", "гбит"]),

    // Speed — base m/s
    d("m/s", .speed, 1, ["mps", "м/с"]),
    d("km/h", .speed, 1.0 / 3.6, ["kmh", "kph", "kmph", "км/ч", "кмч"]),
    d("mph", .speed, 0.44704, ["mi/h", "миль/ч"]),
    d("kn", .speed, 0.5144444444444445, ["knot", "knots", "узел", "узлов", "узла"]),
    d("ft/s", .speed, 0.3048, ["fps"]),

    // Angle — base radian
    d("rad", .angle, 1, ["radian", "radians", "рад"]),
    d("°", .angle, Double.pi / 180, ["deg", "degree", "degrees", "градус", "градуса", "градусов"]),

    // Energy — base joule
    d("J", .energy, 1, ["joule", "joules", "Дж", "дж"]),
    d("kJ", .energy, 1000, ["kilojoule", "kilojoules", "кДж"]),
    d("cal", .energy, 4.184, ["calorie", "calories", "кал"]),
    d("kcal", .energy, 4184, ["kilocalorie", "kilocalories", "ккал"]),
    d("Wh", .energy, 3600, ["watt hour", "watt hours", "Втч"]),
    d("kWh", .energy, 3.6e6, ["kilowatt hour", "kilowatt hours", "кВтч", "квтч"]),
    d("BTU", .energy, 1055.05585262, ["btu"]),

    // Power — base watt
    d("W", .power, 1, ["watt", "watts", "Вт", "вт"]),
    d("kW", .power, 1000, ["kilowatt", "kilowatts", "кВт", "квт"]),
    d("MW", .power, 1e6, ["megawatt", "megawatts", "МВт"]),
    d("hp", .power, 745.69987158227, ["horsepower", "лс", "лошадиных сил"]),

    // Pressure — base pascal
    d("Pa", .pressure, 1, ["pascal", "pascals", "Па"]),
    d("kPa", .pressure, 1000, ["kilopascal", "kilopascals", "кПа"]),
    d("MPa", .pressure, 1e6, ["megapascal", "megapascals", "МПа"]),
    d("bar", .pressure, 1e5, ["bars", "бар"]),
    d("atm", .pressure, 101325, ["atmosphere", "atmospheres", "атм"]),
    d("psi", .pressure, 6894.757293168, []),
    d("mmHg", .pressure, 133.322387415, ["torr"]),

    // Frequency — base hertz
    d("Hz", .frequency, 1, ["hertz", "Гц"]),
    d("kHz", .frequency, 1e3, ["кГц"]),
    d("MHz", .frequency, 1e6, ["МГц"]),
    d("GHz", .frequency, 1e9, ["ГГц"]),
]

private let currencyAliases: [(String, [String])] = [
    ("USD", ["$", "usd", "dollar", "dollars", "buck", "bucks", "доллар", "доллара", "долларов", "доллары", "долларах", "долл", "бакс", "бакса", "баксов"]),
    ("EUR", ["€", "eur", "euro", "euros", "евро"]),
    ("UAH", ["₴", "uah", "hryvnia", "hryvnias", "hryvna", "грн", "гривна", "гривны", "гривен", "гривну", "гривнах", "гривень"]),
    ("GBP", ["£", "gbp", "sterling", "фунтов стерлингов"]),
    ("JPY", ["¥", "yen", "иена", "иен", "йена"]),
    ("CNY", ["yuan", "юань", "юаней", "юаня"]),
    ("PLN", ["zloty", "zł", "злотый", "злотых"]),
    ("CHF", ["franc", "francs", "франк", "франков"]),
    ("TRY", ["lira", "лира", "лир"]),
    ("BTC", ["₿", "bitcoin", "bitcoins", "биткоин", "биткоина", "биткоинов", "биток"]),
    ("ETH", ["ether", "ethereum", "эфир", "эфира"]),
    ("USDT", ["tether"]),
    ("SOL", ["solana"]),
    ("DOGE", ["dogecoin"]),
    ("TON", ["toncoin"]),
]

public final class UnitRegistry {
    private var exact: [String: CalcUnit] = [:]
    private var lower: [String: CalcUnit] = [:]
    private var curExact: [String: String] = [:]
    private var curLower: [String: String] = [:]
    public let rates: RateStore
    public private(set) var completionWords: [String] = []

    public init(rates: RateStore) {
        self.rates = rates
        var words = Set<String>()
        for def in unitDefs {
            let u = CalcUnit(def.id, def.dim, def.f, offset: def.off)
            for a in [def.id] + def.a {
                if exact[a] == nil { exact[a] = u }
                let l = a.lowercased()
                if lower[l] == nil { lower[l] = u }
                words.insert(a)
            }
        }
        for (code, aliases) in currencyAliases {
            words.insert(code)
            for a in aliases {
                if curExact[a] == nil { curExact[a] = code }
                let l = a.lowercased()
                if curLower[l] == nil { curLower[l] = code }
                words.insert(a)
            }
        }
        for c in RateStore.commonCodes { words.insert(c) }
        completionWords = words.filter { w in
            guard let f = w.unicodeScalars.first else { return false }
            return CharacterSet.letters.contains(f)
        }.sorted()
    }

    public func currency(_ code: String) -> CalcUnit {
        CalcUnit(code, .currency, 1, isCrypto: RateStore.cryptoIDs[code] != nil)
    }

    /// Order: exact-case unit → exact currency alias/code → case-insensitive unit → case-insensitive currency.
    public func lookup(_ s: String) -> CalcUnit? {
        if let u = exact[s] { return u }
        if let c = curExact[s] { return currency(c) }
        let codeLike = UnitRegistry.isCodeLike(s)
        if codeLike, s == s.uppercased(), rates.knows(s) { return currency(s) }
        let l = s.lowercased()
        if let u = lower[l] { return u }
        if let c = curLower[l] { return currency(c) }
        let up = s.uppercased()
        if codeLike, rates.knows(up) { return currency(up) }
        return nil
    }

    static func isCodeLike(_ s: String) -> Bool {
        let n = s.unicodeScalars.count
        guard n >= 3 && n <= 5 else { return false }
        return s.unicodeScalars.allSatisfy { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }
    }

    public func convert(_ v: Double, _ from: CalcUnit, _ to: CalcUnit) throws -> Double {
        if from == to { return v }
        guard from.dim == to.dim else { throw CalcError("нельзя перевести \(from.id) в \(to.id)") }
        if from.dim == .currency {
            guard let a = rates.perUSD[from.id], let b = rates.perUSD[to.id], a > 0 else {
                if rates.perUSD.count <= 1 { throw CalcError("курсы ещё не загружены") }
                let missing = rates.perUSD[from.id] == nil ? from.id : to.id
                throw CalcError("нет курса для \(missing)")
            }
            return v / a * b
        }
        let base = v * from.factor + from.offset
        return (base - to.offset) / to.factor
    }
}
