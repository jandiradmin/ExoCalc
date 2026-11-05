import Foundation

public struct CalcZone: Equatable {
    public let id: String
    public let label: String
}

/// Date/time helpers. Keep in sync with windows/src/datetime.js.
enum DT {
    private static func fdiv(_ a: Int, _ b: Int) -> Int { Int((Double(a) / Double(b)).rounded(.down)) }

    /// Days since 1970-01-01 (H. Hinnant's algorithm).
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = y0 - (m <= 2 ? 1 : 0)
        let era = fdiv(y, 400)
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719468
        let era = fdiv(z, 146097)
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    static func daysInMonth(_ y: Int, _ m: Int) -> Int {
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        return [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
    }

    static func valid(_ y: Int, _ m: Int, _ d: Int) -> Bool {
        y >= 1 && y <= 9999 && m >= 1 && m <= 12 && d >= 1 && d <= daysInMonth(y, m)
    }

    /// Calendar month addition: 31 Jan + 1 month = 28/29 Feb.
    static func addMonths(_ days: Int, _ n: Int) -> Int {
        let (y, m, d) = civilFromDays(days)
        let total = y * 12 + (m - 1) + n
        let ny = fdiv(total, 12)
        let nm = total - ny * 12 + 1
        return daysFromCivil(ny, nm, min(d, daysInMonth(ny, nm)))
    }

    /// 0 = Sunday … 6 = Saturday.
    static func weekday(_ days: Int) -> Int { ((days + 4) % 7 + 7) % 7 }

    static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4, "may": 5,
        "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9,
        "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12,
        "январь": 1, "января": 1, "янв": 1, "февраль": 2, "февраля": 2, "фев": 2, "март": 3, "марта": 3,
        "апрель": 4, "апреля": 4, "апр": 4, "май": 5, "мая": 5, "июнь": 6, "июня": 6, "июн": 6,
        "июль": 7, "июля": 7, "июл": 7, "август": 8, "августа": 8, "авг": 8, "сентябрь": 9, "сентября": 9, "сен": 9,
        "октябрь": 10, "октября": 10, "окт": 10, "ноябрь": 11, "ноября": 11, "ноя": 11, "декабрь": 12, "декабря": 12, "дек": 12,
        "січень": 1, "січня": 1, "лютий": 2, "лютого": 2, "березень": 3, "березня": 3, "квітень": 4, "квітня": 4,
        "травень": 5, "травня": 5, "червень": 6, "червня": 6, "липень": 7, "липня": 7, "серпень": 8, "серпня": 8,
        "вересень": 9, "вересня": 9, "жовтень": 10, "жовтня": 10, "листопад": 11, "листопада": 11, "грудень": 12, "грудня": 12,
    ]

    static let dayWords: [String: Int] = [
        "today": 0, "сегодня": 0, "сьогодні": 0,
        "tomorrow": 1, "завтра": 1,
        "yesterday": -1, "вчера": -1, "вчора": -1,
    ]
    static let nowWords: Set<String> = ["now", "сейчас", "зараз"]
    static let untilWords: Set<String> = ["until", "till", "до"]

    static let zones: [String: CalcZone] = {
        var z: [String: CalcZone] = [:]
        func add(_ id: String, _ label: String, _ aliases: [String]) {
            for a in aliases { z[a] = CalcZone(id: id, label: label) }
        }
        add("Europe/Kyiv", "Kyiv", ["kyiv", "kiev", "киев", "київ", "киеве", "києві",  "ukraine", "украина", "україна", "kherson", "херсон", "odesa", "odessa", "одесса", "одеса", "lviv", "львов", "львів", "kharkiv", "харьков", "харків", "dnipro", "днепр", "дніпро"])
        add("America/Los_Angeles", "LA", ["la", "los angeles", "лос анджелес", "лос-анджелес", "pst", "pdt", "pacific", "sf", "san francisco", "сан франциско", "seattle", "сиэтл", "las vegas", "лас вегас"])
        add("America/New_York", "New York", ["ny", "nyc", "new york", "нью йорк", "нью-йорк", "нью йорке", "нью-йорке", "нью-йорку", "est", "edt", "eastern", "miami", "майами", "washington", "вашингтон", "boston"])
        add("America/Chicago", "Chicago", ["chicago", "чикаго", "cdt", "central"])
        add("America/Denver", "Denver", ["denver", "денвер", "mst", "mdt", "mountain"])
        add("America/Toronto", "Toronto", ["toronto", "торонто"])
        add("UTC", "UTC", ["utc", "gmt", "zulu"])
        add("Europe/London", "London", ["london", "лондон", "лондоне", "лондоні", "uk time", "bst"])
        add("Europe/Warsaw", "Warsaw", ["warsaw", "варшава", "варшаве", "варшаві", "poland", "польша", "польща"])
        add("Europe/Berlin", "Berlin", ["berlin", "берлин", "берлін", "берлине", "берліні", "germany", "германия", "німеччина", "cet", "cest"])
        add("Europe/Paris", "Paris", ["paris", "париж", "париже", "парижі"])
        add("Europe/Madrid", "Madrid", ["madrid", "мадрид"])
        add("Europe/Rome", "Rome", ["rome", "рим"])
        add("Europe/Prague", "Prague", ["prague", "прага"])
        add("Europe/Vienna", "Vienna", ["vienna", "вена", "відень"])
        add("Europe/Bucharest", "Bucharest", ["bucharest", "бухарест"])
        add("Europe/Chisinau", "Chisinau", ["chisinau", "кишинев", "кишинів"])
        add("Europe/Istanbul", "Istanbul", ["istanbul", "стамбул", "turkey", "турция", "туреччина"])
        add("Asia/Tbilisi", "Tbilisi", ["tbilisi", "тбилиси", "тбілісі"])
        add("Asia/Jerusalem", "Tel Aviv", ["tel aviv", "тель авив", "israel", "израиль", "ізраїль"])
        add("Asia/Dubai", "Dubai", ["dubai", "дубай", "uae", "оаэ"])
        add("Asia/Kolkata", "India", ["india", "индия", "індія", "delhi", "mumbai"])
        add("Asia/Shanghai", "Beijing", ["beijing", "shanghai", "пекин", "пекін", "шанхай", "china", "китай"])
        add("Asia/Tokyo", "Tokyo", ["tokyo", "токио", "токіо", "japan", "япония", "японія"])
        add("Australia/Sydney", "Sydney", ["sydney", "сидней", "сідней"])
        return z
    }()

    /// Seconds east of UTC for a zone at a moment.
    static func offset(_ zoneID: String, at date: Date) -> Int {
        (TimeZone(identifier: zoneID) ?? TimeZone(secondsFromGMT: 0)!).secondsFromGMT(for: date)
    }
}
