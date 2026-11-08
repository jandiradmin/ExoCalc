import Foundation

public enum UnitDim: String {
    case length, area, volume, mass, time, temperature, data, speed, angle, energy, power, pressure, frequency, fuel, flow, currency
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
    d("mm", .length, 0.001, ["millimeter", "millimeters", "millimetre", "millimetres", "мм", "миллиметр", "миллиметров", "миллиметра", "міліметр", "міліметрів"]),
    d("cm", .length, 0.01, ["centimeter", "centimeters", "centimetre", "centimetres", "см", "сантиметр", "сантиметров", "сантиметра"]),
    d("dm", .length, 0.1, ["decimeter", "decimeters", "дм"]),
    d("m", .length, 1, ["meter", "meters", "metre", "metres", "м", "метр", "метров", "метра", "метры", "метрів"]),
    d("km", .length, 1000, ["kilometer", "kilometers", "kilometre", "kilometres", "км", "километр", "километров", "километра", "кілометр", "кілометрів", "кілометри"]),
    d("µm", .length, 1e-6, ["um", "micrometer", "micrometers", "micron", "microns", "мкм"]),
    d("nm", .length, 1e-9, ["nanometer", "nanometers", "нм"]),
    d("in", .length, 0.0254, ["inch", "inches", "дюйм", "дюймов", "дюйма"]),
    d("ft", .length, 0.3048, ["foot", "feet", "фут", "футов", "фута"]),
    d("yd", .length, 0.9144, ["yard", "yards", "ярд", "ярдов", "ярда"]),
    d("mi", .length, 1609.344, ["mile", "miles", "миля", "миль", "мили", "милях", "миля"]),
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
    d("l", .volume, 1e-3, ["L", "liter", "liters", "litre", "litres", "л", "литр", "литров", "литра", "литры", "літр", "літрів", "літри"]),
    d("m³", .volume, 1, ["m3", "m^3", "cubic meter", "cubic meters", "cubic metre", "м³", "м3", "куб", "кубов", "куба", "кубометр", "кубометров"]),
    d("cm³", .volume, 1e-6, ["cm3", "cm^3", "cc", "см³", "см3"]),
    d("gal", .volume, 0.003785411784, ["gallon", "gallons", "галлон", "галлонов", "галлона", "галон", "галонів", "галони"]),
    d("qt", .volume, 0.000946352946, ["quart", "quarts"]),
    d("pt", .volume, 0.000473176473, ["pint", "pints"]),
    d("cup", .volume, 0.0002365882365, ["cups", "стакан", "стакана", "стаканов"]),
    d("fl oz", .volume, 2.95735295625e-5, ["floz", "fluid ounce", "fluid ounces"]),
    d("tbsp", .volume, 1.478676478125e-5, ["tablespoon", "tablespoons"]),
    d("tsp", .volume, 4.92892159375e-6, ["teaspoon", "teaspoons"]),
    d("bbl", .volume, 0.158987294928, ["barrel", "barrels", "баррель", "баррелей", "барреля"]),

    // Mass — base kg
    d("mg", .mass, 1e-6, ["milligram", "milligrams", "мг", "миллиграмм"]),
    d("g", .mass, 1e-3, ["gram", "grams", "gramme", "gr", "г", "гр", "грамм", "граммов", "грамма", "грам", "грамів"]),
    d("kg", .mass, 1, ["kilogram", "kilograms", "kilo", "kilos", "кг", "килограмм", "килограммов", "килограмма", "кило", "кілограм", "кілограмів"]),
    d("t", .mass, 1000, ["ton", "tons", "tonne", "tonnes", "т", "тонна", "тонн", "тонны", "тонну"]),
    d("lb", .mass, 0.45359237, ["lbs", "pound", "pounds", "фунт", "фунтов", "фунта"]),
    d("oz", .mass, 0.028349523125, ["ounce", "ounces", "унция", "унций", "унции"]),
    d("st", .mass, 6.35029318, ["stone", "stones"]),
    d("ct", .mass, 0.0002, ["carat", "carats", "карат", "карата"]),

    // Time — base second
    d("ms", .time, 0.001, ["millisecond", "milliseconds", "мс"]),
    d("s", .time, 1, ["sec", "secs", "second", "seconds", "с", "сек", "секунда", "секунд", "секунды", "секунду", "секунди"]),
    d("min", .time, 60, ["mins", "minute", "minutes", "мин", "минута", "минут", "минуты", "минуту", "хв", "хвилина", "хвилин", "хвилини"]),
    d("h", .time, 3600, ["hr", "hrs", "hour", "hours", "ч", "час", "часа", "часов", "година", "годин", "години"]),
    d("day", .time, 86400, ["days", "d", "день", "дня", "дней", "дн", "сутки", "суток", "днів", "дні", "доба", "діб"]),
    d("week", .time, 604800, ["weeks", "wk", "неделя", "недели", "недель", "нед", "неделю", "тиждень", "тижні", "тижнів"]),
    d("month", .time, 2629746, ["months", "мес", "месяц", "месяца", "месяцев", "місяць", "місяці", "місяців"]),
    d("year", .time, 31556952, ["years", "yr", "yrs", "год", "года", "лет", "рік", "роки", "років"]),

    // Temperature — base kelvin
    d("°C", .temperature, 1, ["C", "℃", "°С", "celsius", "цельсий", "цельсия", "цельсію", "цельсіях", "градус цельсия", "градусов цельсия", "градус цельсія", "градусів цельсія", "degree celsius", "degrees celsius"], off: 273.15),
    d("°F", .temperature, 5.0 / 9.0, ["F", "℉", "fahrenheit", "фаренгейт", "фаренгейта", "фаренгейтах", "градус фаренгейта", "градусов фаренгейта", "градусів фаренгейта", "degree fahrenheit", "degrees fahrenheit"], off: 459.67 * 5.0 / 9.0),
    d("K", .temperature, 1, ["kelvin", "kelvins", "кельвин", "кельвина", "кельвін", "кельвіна"]),

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
    d("m/s", .speed, 1, ["mps", "м/с", "m/sec", "meters per second", "metres per second", "м/сек", "метров в секунду", "метрів на секунду"]),
    d("km/h", .speed, 1.0 / 3.6, ["kmh", "kph", "kmph", "км/ч", "кмч", "km/hr", "km/hour", "kilometers per hour", "км/год", "км/час", "километров в час", "кілометрів на годину"]),
    d("km/s", .speed, 1000, ["km/sec", "км/с", "км/сек"]),
    d("km/min", .speed, 16.666666666666668, ["km/minute", "km/mn", "км/мин", "км/хв"]),
    d("m/min", .speed, 0.016666666666666666, ["m/minute", "м/мин", "м/хв"]),
    d("mph", .speed, 0.44704, ["mi/h", "миль/ч"]),
    d("kn", .speed, 0.5144444444444445, ["knot", "knots", "узел", "узлов", "узла"]),
    d("ft/s", .speed, 0.3048, ["fps"]),

    // Angle — base radian
    d("rad", .angle, 1, ["radian", "radians", "рад"]),
    d("°", .angle, Double.pi / 180, ["deg", "degree", "degrees", "градус", "градуса", "градусов", "градусів"]),

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
    d("kW", .power, 1000, ["kilowatt", "kilowatts", "кВт", "квт", "кіловат"]),
    d("MW", .power, 1e6, ["megawatt", "megawatts", "МВт"]),
    d("hp", .power, 745.69987158227, ["horsepower", "лс", "лошадиных сил", "кінських сил"]),

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

    // Flow rate — base m³/s
    d("m³/s", .flow, 1, ["m3/s", "m^3/s", "m3/sec", "m³/sec", "cumec", "м3/с", "м³/с", "м3/сек", "кубов в секунду", "кубометров в секунду"]),
    d("m³/min", .flow, 0.016666666666666666, ["m3/min", "m^3/min", "м3/мин", "м³/мин", "м3/хв", "м³/хв"]),
    d("m³/h", .flow, 0.0002777777777777778, ["m3/h", "m^3/h", "m3/hr", "m³/hr", "m3/hour", "cubic meters per hour", "cubic metres per hour", "м3/ч", "м³/ч", "м3/час", "м3/год", "м³/год", "кубов в час", "куб/ч", "кубометров в час", "кубів на годину"]),
    d("m³/day", .flow, 1.1574074074074073e-05, ["m3/day", "m3/d", "m^3/day", "м3/сут", "м³/сут", "м3/добу", "кубов в сутки"]),
    d("l/s", .flow, 0.001, ["L/s", "lps", "l/sec", "л/с", "л/сек", "литров в секунду", "літрів на секунду"]),
    d("l/min", .flow, 1.6666666666666667e-05, ["L/min", "lpm", "л/мин", "л/хв", "литров в минуту", "літрів на хвилину"]),
    d("l/h", .flow, 2.7777777777777776e-07, ["L/h", "л/ч", "л/час", "л/год", "литров в час", "літрів на годину"]),
    d("gpm", .flow, 6.30901964e-05, ["gal/min", "US gpm", "gallons per minute", "галлонов в минуту"]),
    d("cfm", .flow, 0.0004719474432, ["ft3/min", "ft³/min", "cubic feet per minute"]),

    // Fuel economy — base km/l; a negative factor means an inverse unit (l/100km = 100 / km/l)
    d("km/l", .fuel, 1, ["kmpl", "km per liter", "km per litre", "км/л", "км на литр", "км на літр"]),
    d("l/100km", .fuel, -100, ["l/100 km", "L/100km", "L/100 km", "l per 100 km", "liters per 100 km", "litres per 100 km", "liter per 100 km", "л/100км", "л/100 км", "л на 100 км", "литров на 100 км", "литра на 100 км", "литр на 100 км", "літрів на 100 км", "літра на 100 км", "літр на 100 км"]),
    d("l/km", .fuel, -1, ["L/km", "л/км"]),
    d("mpg", .fuel, 0.425143707430272, ["mpg us", "us mpg", "miles per gallon", "mile per gallon", "миль на галлон", "миль на галон", "миля на галлон"]),
    d("mpg uk", .fuel, 0.3540061899346471, ["mpg imp", "uk mpg", "imperial mpg", "miles per imperial gallon"]),
]

private let currencyAliases: [(String, [String])] = [
    ("USD", ["$", "usd", "dollar", "dollars", "buck", "bucks", "доллар", "доллара", "долларов", "доллары", "долларах", "долл", "бакс", "бакса", "баксов", "долар", "долари", "доларів", "доларах"]),
    ("EUR", ["€", "eur", "euro", "euros", "евро", "євро"]),
    ("UAH", ["₴", "uah", "hryvnia", "hryvnias", "hryvna", "грн", "гривна", "гривны", "гривен", "гривну", "гривнах", "гривень", "гривня", "гривні", "гривнях"]),
    ("GBP", ["£", "gbp", "sterling", "фунтов стерлингов", "фунт стерлингов", "фунтів стерлінгів"]),
    ("JPY", ["¥", "yen", "иена", "иен", "йена"]),
    ("CNY", ["yuan", "юань", "юаней", "юаня"]),
    ("PLN", ["zloty", "zł", "злотый", "злотых"]),
    ("CHF", ["franc", "francs", "франк", "франков"]),
    ("TRY", ["lira", "лира", "лир"]),
    ("BTC", ["₿", "bitcoin", "bitcoins", "биткоин", "биткоина", "биткоинов", "биток", "біткоїн", "біткоін"]),
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
    private var stemUnit: [String: CalcUnit] = [:]
    private var stemCur: [String: String] = [:]
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
                if UnitRegistry.hasCyrillic(a) {
                    let st = UnitRegistry.stem(a)
                    if stemUnit[st] == nil { stemUnit[st] = u }
                }
                words.insert(a)
            }
        }
        for (code, aliases) in currencyAliases {
            words.insert(code)
            for a in aliases {
                if curExact[a] == nil { curExact[a] = code }
                let l = a.lowercased()
                if curLower[l] == nil { curLower[l] = code }
                if UnitRegistry.hasCyrillic(a) {
                    let st = UnitRegistry.stem(a)
                    if stemCur[st] == nil { stemCur[st] = code }
                }
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
        // Russian/Ukrainian word forms: "фаренгейтах", "гривнях", "долларов", "милях"
        if UnitRegistry.hasCyrillic(s) {
            let st = UnitRegistry.stem(s)
            if let u = stemUnit[st] { return u }
            if let c = stemCur[st] { return currency(c) }
        }
        return nil
    }

    static func hasCyrillic(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.value >= 0x400 && $0.value <= 0x4FF }
    }

    private static let endings: [String] = [
        "ами", "ями", "ією", "ах", "ях", "ов", "ев", "ей", "ів", "їв", "ам", "ям", "ом", "ем", "ою", "ею",
        "ий", "ій", "ия", "ія", "ию", "ію", "ые", "ых", "и", "ы", "і", "а", "я", "у", "ю", "е", "є", "о", "ь", "й",
    ]

    /// Crude stemmer: strips a common case/plural ending from each word (keeps ≥3 letters).
    static func stem(_ s: String) -> String {
        s.lowercased().split(separator: " ").map { part -> String in
            let w = String(part)
            guard w.count >= 4, hasCyrillic(w) else { return w }
            for e in endings where w.hasSuffix(e) && w.count - e.count >= 3 {
                return String(w.dropLast(e.count))
            }
            return w
        }.joined(separator: " ")
    }

    static func isCodeLike(_ s: String) -> Bool {
        let n = s.unicodeScalars.count
        guard n >= 3 && n <= 5 else { return false }
        return s.unicodeScalars.allSatisfy { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }
    }

    public func convert(_ v: Double, _ from: CalcUnit, _ to: CalcUnit) throws -> Double {
        if from == to { return v }
        guard from.dim == to.dim else { throw CalcError(tr("cantConvert", from.id, to.id)) }
        if from.dim == .currency {
            guard let a = rates.perUSD[from.id], let b = rates.perUSD[to.id], a > 0 else {
                if rates.perUSD.count <= 1 { throw CalcError(tr("noRates")) }
                let missing = rates.perUSD[from.id] == nil ? from.id : to.id
                throw CalcError(tr("noRate", missing))
            }
            return v / a * b
        }
        // Inverse units (l/100km): base = |factor| / value
        if from.factor < 0 || to.factor < 0 {
            if v == 0 { throw CalcError(tr("divZero")) }
            let base = from.factor < 0 ? -from.factor / v : v * from.factor + from.offset
            if to.factor < 0 { return -to.factor / base }
            return (base - to.offset) / to.factor
        }
        let base = v * from.factor + from.offset
        return (base - to.offset) / to.factor
    }
}
