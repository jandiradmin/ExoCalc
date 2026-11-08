import Foundation

/// Example sheets and help examples shared by the Mac and iPhone/iPad apps.
public enum Examples {
    public static func helpSections() -> [(String, [String])] {
        let ru = L10n.lang == .ru, uk = L10n.lang == .uk
        let conv = ru ? "в" : (uk ? "у" : "in")
        return [
            (tr("hArith"), ["2 + 3 * 4", "(2 + 3) * 4", "2^10", "10 mod 3", "5!", "800 * 12", "800x12", "1/3"]),
            (tr("hNumbers"), ["300,000.00 * 2", "300 000,00 * 2", "30000,00 * 8", "1.5 + 1,5", "19,480.00 + 2150"]),
            (tr("hPercent"), ["100 + 15%", "250 - 20%",
                              ru ? "15% от 800" : (uk ? "15% від 800" : "15% of 800"),
                              "20% off 1500", "5% on 200"]),
            (tr("hFunc"), ["sqrt(144)", "sqrt 2", "sin(30 deg)", "cos(pi)", "log(1000)", "ln(e)",
                           "round(3.14159; 1)", "max(3; 9; 4)", "avg(10; 20; 60)", "2 pi"]),
            (tr("hCurrency"), ru ? ["600 usd в uah", "600 долларов в гривнах", "$20 + €15", "100 евро в грн",
                                    "1000 грн в долларах", "0.05 btc в usd", "1 eth в гривнах"]
                            : uk ? ["600 usd у uah", "600 доларів у гривнях", "$20 + €15", "100 євро у грн",
                                    "1000 грн у доларах", "0.05 btc у usd", "1 eth у гривнях"]
                                 : ["600 usd in uah", "$20 + €15", "100 eur in uah", "1000 uah in usd",
                                    "0.05 btc in usd", "1 eth in uah"]),
            (tr("hUnits"), ru ? ["18 цельсия в фаренгейтах", "100 км в милях", "5 футов в см", "70 кг в фунтах",
                                 "1.5 часа в минутах", "1 GB \(conv) MB", "100 км/ч в m/s", "3 m * 4 m",
                                 "120 км / 1.5 ч", "10 соток в м2", "1 км + 300 м", "9 л/100км в mpg", "30 mpg в л/100км", "100 км/ч в м/сек", "1500 м3/ч в л/с", "1500 м3/ч в м/с при 500 мм"]
                         : uk ? ["18 цельсія у фаренгейтах", "100 км у милях", "5 футів у см", "70 кг у фунтах",
                                 "1.5 години у хвилинах", "1 GB \(conv) MB", "100 км/ч у m/s", "3 m * 4 m",
                                 "120 км / 1.5 години", "1 км + 300 м", "9 л/100км у mpg", "30 mpg у л/100км", "100 км/год у м/сек", "1500 м3/год у л/с", "1500 м3/год у м/с при 500 мм"]
                              : ["18 celsius in fahrenheit", "100 km in miles", "5 ft in cm", "70 kg in lb",
                                 "1.5 hours in minutes", "1 GB in MB", "100 km/h in m/s", "3 m * 4 m",
                                 "120 km / 1.5 h", "1 km + 300 m", "9 l/100km in mpg", "30 mpg in l/100km", "100 km/h in m/sec", "1500 m3/h in l/s", "1500 m3/h in m/s at 500 mm"]),
            (tr("hTime"), ru ? ["12:30 + 1 h 15 min", "23:30 + 2 h", "18:15 - 9:40", "8 h 35 min в мин", "3pm + 30 min", "сейчас", "сейчас в Киеве", "15:00 Киев в LA"]
                        : uk ? ["12:30 + 1 h 15 min", "23:30 + 2 h", "18:15 - 9:40", "8 h 35 min у хв", "3pm + 30 min", "зараз", "зараз у Києві", "15:00 Київ у LA"]
                             : ["12:30 + 1 h 15 min", "23:30 + 2 h", "18:15 - 9:40", "8 h 35 min in min", "3pm + 30 min", "now", "now in Kyiv", "15:00 Kyiv in LA"]),
            (tr("hDates"), ru ? ["сегодня + 30 дней", "12.12.2026 + 2 недели", "31.01.2027 + 1 месяц", "31.12.2026 - сегодня", "до 31.12", "до 31.12 в неделях", "12 декабря 2026"]
                         : uk ? ["сьогодні + 30 днів", "12.12.2026 + 2 тижні", "31.01.2027 + 1 місяць", "31.12.2026 - сьогодні", "до 31.12", "до 31.12 у тижнях", "12 грудня 2026"]
                              : ["today + 30 days", "12/12/2026 + 2 weeks", "01/31/2027 + 1 month", "12/31/2026 - today", "12/31/2026 - today in weeks", "December 12, 2026"]),
            (tr("hBases"), ["255 \(conv) hex", "0xFF + 1", "10 \(conv) bin", ru ? "5k + 2.5 млн" : (uk ? "5k + 2.5 мільйон" : "5k + 2.5 million"), "1234567 \(conv) sci"]),
            (tr("hVars"), ru ? ["цена = 1250", "кол = 3", "цена * кол", "пред + 100"]
                        : uk ? ["ціна = 1250", "кількість = 3", "ціна * кількість", "попер + 100"]
                             : ["price = 1250", "qty = 3", "price * qty", "prev + 100"]),
            (tr("hTotals"), ru ? ["Аренда: 2000", "Свет: 150", "Интернет: 30", "итого"]
                          : uk ? ["Оренда: 2000", "Світло: 150", "Інтернет: 30", "разом"]
                               : ["Rent: 2000", "Power: 150", "Internet: 30", "total"]),
        ]
    }

    /// First-run sheet. `hotkey` nil → touch version (iPhone/iPad).
    public static func welcomeLines(hotkey: String?) -> [String] {
        switch L10n.lang {
        case .ru: return [
            "# Добро пожаловать в ExoCalc! Пишите выражение — ответ появится справа.",
            hotkey.map { "# F1 — справка · Esc — спрятать · \($0) — вызвать из любого приложения" } ?? "# Нажмите на зелёный результат — скопировать, удерживайте — «выражение = результат»",
            "14*5", "500*4", "(2+2)*4", "2^10", "1/3", "",
            "# Проценты", "20% от 1500", "1500 - 20%", "",
            "# Валюты (курсы обновляются сами)", "600 долларов в гривнах", "100 евро в грн", "0.01 btc в usd", "",
            "# Единицы измерения", "18 цельсия в фаренгейтах", "100 км в милях", "1 галлон в литрах", "70 кг в фунтах", "",
            "# Время и даты", "18:15 - 9:40", "23:30 + 2 h", "15:00 Киев в LA", "сегодня + 30 дней", "31.12.2026 - сегодня", "",
            "# Числа в любом формате", "300 000,00 * 2", "300,000.00 * 2", "",
            "# Переменные и итоги", "цена = 1250", "цена * 3", "",
            "Аренда: 2000", "Свет: 150", "итого",
        ]
        case .uk: return [
            "# Ласкаво просимо до ExoCalc! Пишіть вираз — відповідь з’явиться праворуч.",
            hotkey.map { "# F1 — довідка · Esc — сховати · \($0) — викликати з будь-якої програми" } ?? "# Натисніть на зелений результат — скопіювати, утримуйте — «вираз = результат»",
            "14*5", "500*4", "(2+2)*4", "2^10", "1/3", "",
            "# Відсотки", "20% від 1500", "1500 - 20%", "",
            "# Валюти (курси оновлюються самі)", "600 доларів у гривнях", "100 євро у грн", "0.01 btc у usd", "",
            "# Одиниці виміру", "18 цельсія у фаренгейтах", "100 км у милях", "1 галон у літрах", "70 кг у фунтах", "",
            "# Час і дати", "18:15 - 9:40", "23:30 + 2 h", "15:00 Київ у LA", "сьогодні + 30 днів", "31.12.2026 - сьогодні", "",
            "# Числа в будь-якому форматі", "300 000,00 * 2", "300,000.00 * 2", "",
            "# Змінні та підсумки", "ціна = 1250", "ціна * 3", "",
            "Оренда: 2000", "Світло: 150", "разом",
        ]
        case .en: return [
            "# Welcome to ExoCalc! Type an expression — the answer appears on the right.",
            hotkey.map { "# F1 — help · Esc — hide · \($0) — open from any app" } ?? "# Tap a green result to copy it, hold to copy “expression = result”",
            "14*5", "500*4", "(2+2)*4", "2^10", "1/3", "",
            "# Percentages", "20% of 1500", "1500 - 20%", "",
            "# Currencies (rates update automatically)", "600 usd in uah", "100 eur in usd", "0.01 btc in usd", "",
            "# Units", "18 celsius in fahrenheit", "100 km in miles", "1 gallon in liters", "70 kg in lb", "",
            "# Time and dates", "18:15 - 9:40", "23:30 + 2 h", "15:00 Kyiv in LA", "today + 30 days", "12/31/2026 - today", "",
            "# Numbers in any format", "300 000,00 * 2", "300,000.00 * 2", "",
            "# Variables and totals", "price = 1250", "price * 3", "",
            "Rent: 2000", "Power: 150", "total",
        ]
        }
    }

    /// Example sheet; each line shows its answer after "=", like a worked example.
    public static func welcomeText(engine: Engine, hotkey: String?) -> String {
        let lines = welcomeLines(hotkey: hotkey)
        let res = engine.evaluate(lines: lines)
        return zip(lines, res).map { line, r in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") || t.contains("=") || t.allSatisfy({ $0.isLetter }) { return line }
            // Lines that depend on today/now are not frozen with "= answer" (it would go stale).
            if t.range(of: "(today|now|сегодня|сейчас|сьогодні|зараз|завтра|tomorrow|вчера|вчора|yesterday|\\bдо\\b|until|kyiv|київ|киев|\\bla\\b)",
                       options: [.regularExpression, .caseInsensitive]) != nil { return line }
            guard let d = r.display else { return line }
            return "\(line) = \(d)"
        }.joined(separator: "\n")
    }

    /// The expression part of a sheet line: without "// comment" and a trailing "= answer".
    public static func expression(ofLine line: String) -> String {
        var expr = line
        if let cut = expr.range(of: "//") { expr = String(expr[..<cut.lowerBound]) }
        if let eq = expr.range(of: "=", options: .backwards) {
            let before = String(expr[..<eq.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !before.isEmpty { expr = before }
        }
        return expr.trimmingCharacters(in: .whitespaces)
    }
}
