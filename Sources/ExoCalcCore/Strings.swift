import Foundation

public enum Lang: String, CaseIterable {
    case ru, en, uk
}

public enum L10n {
    /// Current interface language (set by the app from settings).
    public static var lang: Lang = .ru

    /// Resolves "" (system) / "ru" / "en" / "uk".
    public static func resolve(_ code: String) -> Lang {
        if let l = Lang(rawValue: code) { return l }
        for pref in Locale.preferredLanguages {
            if pref.hasPrefix("uk") { return .uk }
            if pref.hasPrefix("ru") { return .ru }
            if pref.hasPrefix("en") { return .en }
        }
        return .en
    }
}

/// Translate a key; "{0}", "{1}" are replaced with args.
public func tr(_ key: String, _ args: String...) -> String {
    guard let row = strings[key] else { return key }
    var s: String
    switch L10n.lang {
    case .ru: s = row.0
    case .en: s = row.1
    case .uk: s = row.2
    }
    for (i, a) in args.enumerated() {
        s = s.replacingOccurrences(of: "{\(i)}", with: a)
    }
    return s
}

// (ru, en, uk)
private let strings: [String: (String, String, String)] = [
    // Engine errors
    "unknownChar": ("неизвестный символ «{0}»", "unknown character “{0}”", "невідомий символ «{0}»"),
    "badNumber": ("неверное число", "invalid number", "невірне число"),
    "unclear": ("непонятно: «{0}»", "unexpected: “{0}”", "незрозуміло: «{0}»"),
    "convertTo": ("во что перевести?", "convert to what?", "у що перевести?"),
    "unknownUnit": ("неизвестная единица «{0}»", "unknown unit “{0}”", "невідома одиниця «{0}»"),
    "pctOfPct": ("процент от процента", "percent of a percent", "відсоток від відсотка"),
    "expectedParen": ("ожидалась «)»", "expected “)”", "очікувалась «)»"),
    "incomplete": ("выражение не закончено", "incomplete expression", "вираз не закінчено"),
    "unexpected": ("неожиданное «{0}»", "unexpected “{0}”", "несподіване «{0}»"),
    "noPrev": ("нет предыдущего результата", "no previous result", "немає попереднього результату"),
    "curPct": ("валюта и процент вместе", "currency with a percent", "валюта разом із відсотком"),
    "unknown": ("неизвестно: «{0}»", "unknown: “{0}”", "невідомо: «{0}»"),
    "pctConvert": ("процент нельзя перевести в {0}", "can't convert a percent to {0}", "відсоток не можна перевести в {0}"),
    "pctAdd": ("нельзя сложить процент и число", "can't add a percent to a number", "не можна додати відсоток до числа"),
    "mulUnits": ("нельзя перемножить {0} и {1}", "can't multiply {0} by {1}", "не можна перемножити {0} і {1}"),
    "divZero": ("деление на ноль", "division by zero", "ділення на нуль"),
    "divUnits": ("нельзя разделить {0} на {1}", "can't divide {0} by {1}", "не можна поділити {0} на {1}"),
    "divNumUnit": ("нельзя разделить число на {0}", "can't divide a number by {0}", "не можна поділити число на {0}"),
    "divGeneric": ("нельзя разделить", "can't divide", "не можна поділити"),
    "powNum": ("степень должна быть числом", "exponent must be a plain number", "степінь має бути числом"),
    "powUnit": ("нельзя возвести {0} в степень", "can't raise {0} to a power", "не можна піднести {0} до степеня"),
    "noReal": ("нет действительного результата", "no real result", "немає дійсного результату"),
    "factorial": ("факториал — только целые 0…170", "factorial: integers 0…170 only", "факторіал — лише цілі 0…170"),
    "oneArg": ("{0}: нужен один аргумент", "{0}: needs one argument", "{0}: потрібен один аргумент"),
    "plainArg": ("{0}: нужно число без единиц", "{0}: needs a number without units", "{0}: потрібне число без одиниць"),
    "angleArg": ("{0}: нужен угол", "{0}: needs an angle", "{0}: потрібен кут"),
    "sqrtNeg": ("корень из отрицательного числа", "square root of a negative number", "корінь з від’ємного числа"),
    "rootUsage": ("root(x; n)", "root(x; n)", "root(x; n)"),
    "rootZero": ("корень нулевой степени", "zeroth root", "корінь нульового степеня"),
    "oneTwoArgs": ("{0}: 1 или 2 аргумента", "{0}: 1 or 2 arguments", "{0}: 1 або 2 аргументи"),
    "logPos": ("логарифм только для x > 0", "logarithm needs x > 0", "логарифм лише для x > 0"),
    "logUsage": ("log(x) или log(x; основание)", "log(x) or log(x; base)", "log(x) або log(x; основа)"),
    "badBase": ("неверное основание", "invalid base", "невірна основа"),
    "needArgs": ("{0}: нужны аргументы", "{0}: needs arguments", "{0}: потрібні аргументи"),
    "unknownFunc": ("неизвестная функция {0}", "unknown function {0}", "невідома функція {0}"),
    "cantConvert": ("нельзя перевести {0} в {1}", "can't convert {0} to {1}", "не можна перевести {0} у {1}"),
    "noRates": ("курсы ещё не загружены", "rates not loaded yet", "курси ще не завантажені"),
    "noRate": ("нет курса для {0}", "no rate for {0}", "немає курсу для {0}"),
    "noResult": ("нет результата", "no result", "немає результату"),
    "tooBig": ("слишком большое число", "number too large", "занадто велике число"),
    "intOnly": ("hex/bin/oct — только для целых", "hex/bin/oct: integers only", "hex/bin/oct — лише для цілих"),

    // Menus
    "about": ("О программе ExoCalc", "About ExoCalc", "Про ExoCalc"),
    "settings…": ("Настройки…", "Settings…", "Налаштування…"),
    "closeWindow": ("Закрыть окно", "Close Window", "Закрити вікно"),
    "quit": ("Выйти из ExoCalc", "Quit ExoCalc", "Вийти з ExoCalc"),
    "edit": ("Правка", "Edit", "Редагування"),
    "undo": ("Отменить", "Undo", "Скасувати"),
    "redo": ("Повторить", "Redo", "Повторити"),
    "cut": ("Вырезать", "Cut", "Вирізати"),
    "copy": ("Копировать", "Copy", "Копіювати"),
    "paste": ("Вставить", "Paste", "Вставити"),
    "selectAll": ("Выделить всё", "Select All", "Виділити все"),
    "copyLine": ("Копировать строку с результатом", "Copy Line with Result", "Копіювати рядок з результатом"),
    "copyResult": ("Копировать только результат", "Copy Result Only", "Копіювати лише результат"),
    "copyAll": ("Копировать весь лист с результатами", "Copy Whole Sheet with Results", "Копіювати весь аркуш з результатами"),
    "find…": ("Найти…", "Find…", "Знайти…"),
    "complete": ("Автодополнение", "Autocomplete", "Автодоповнення"),
    "sheet": ("Лист", "Sheet", "Аркуш"),
    "clearSheet": ("Очистить лист", "Clear Sheet", "Очистити аркуш"),
    "history": ("История", "History", "Історія"),
    "bigger": ("Крупнее", "Bigger", "Більше"),
    "smaller": ("Мельче", "Smaller", "Менше"),
    "actualSize": ("Обычный размер", "Actual Size", "Звичайний розмір"),
    "refreshRates": ("Обновить курсы", "Refresh Rates", "Оновити курси"),
    "help": ("Справка", "Help", "Довідка"),
    "helpItem": ("Справка ExoCalc", "ExoCalc Help", "Довідка ExoCalc"),
    "helpAlt": ("Справка (⌘/)", "Help (⌘/)", "Довідка (⌘/)"),
    "showHide": ("Показать / скрыть  ({0})", "Show / Hide  ({0})", "Показати / сховати  ({0})"),

    // Window titles
    "settingsTitle": ("Настройки ExoCalc", "ExoCalc Settings", "Налаштування ExoCalc"),
    "helpTitle": ("Справка ExoCalc", "ExoCalc Help", "Довідка ExoCalc"),
    "historyTitle": ("История ExoCalc", "ExoCalc History", "Історія ExoCalc"),

    // Status bar
    "stDefault": ("F1 — справка · {0} — показать/скрыть · ⌘, — настройки · курсы: {1}",
                  "F1 — help · {0} — show/hide · ⌘, — settings · rates: {1}",
                  "F1 — довідка · {0} — показати/сховати · ⌘, — налаштування · курси: {1}"),
    "stResult": ("Клик по результату — копировать · ⇧клик или ⇧⌘C — «выражение = результат» · ⌥⌘C — весь лист",
                 "Click a result to copy · ⇧-click or ⇧⌘C — “expression = result” · ⌥⌘C — whole sheet",
                 "Клік по результату — копіювати · ⇧клік або ⇧⌘C — «вираз = результат» · ⌥⌘C — весь аркуш"),
    "copied": ("Скопировано: {0}", "Copied: {0}", "Скопійовано: {0}"),
    "copiedAll": ("Скопирован весь лист с результатами", "Whole sheet copied with results", "Скопійовано весь аркуш з результатами"),
    "cleared": ("Лист очищен (⌘Z — вернуть, строки сохранены в истории)", "Sheet cleared (⌘Z to undo, lines saved to history)", "Аркуш очищено (⌘Z — повернути, рядки збережено в історії)"),
    "hotkeyBusy": ("Сочетание {0} занято — выберите другое в настройках", "{0} is taken — choose another in Settings", "Поєднання {0} зайняте — оберіть інше в налаштуваннях"),
    "ratesFailed": ("Не удалось обновить курсы — используется сохранённый кэш", "Couldn't refresh rates — using cached rates", "Не вдалося оновити курси — використовується кеш"),
    "never": ("нет", "never", "немає"),
    "ratesNotLoaded": ("Курсы ещё не загружены", "Rates not loaded yet", "Курси ще не завантажені"),
    "ratesUpdated": ("Обновлено: {0}", "Updated: {0}", "Оновлено: {0}"),
    "nbuOn": ("НБУ на {0}", "NBU as of {0}", "НБУ на {0}"),
    "updating": ("Обновление…", "Updating…", "Оновлення…"),

    // Settings
    "numbers": ("Числа", "Numbers", "Числа"),
    "decimalSep": ("Десятичный разделитель", "Decimal separator", "Десятковий роздільник"),
    "dot": ("Точка — 1.5", "Dot — 1.5", "Крапка — 1.5"),
    "comma": ("Запятая — 1,5", "Comma — 1,5", "Кома — 1,5"),
    "groupSep": ("Разделитель тысяч", "Thousands separator", "Роздільник тисяч"),
    "gNone": ("Нет — 1000000", "None — 1000000", "Немає — 1000000"),
    "gSpace": ("Пробел — 1 000 000", "Space — 1 000 000", "Пробіл — 1 000 000"),
    "gComma": ("Запятая — 1,000,000", "Comma — 1,000,000", "Кома — 1,000,000"),
    "gDot": ("Точка — 1.000.000", "Dot — 1.000.000", "Крапка — 1.000.000"),
    "gApos": ("Апостроф — 1'000'000", "Apostrophe — 1'000'000", "Апостроф — 1'000'000"),
    "decimals": ("Знаков после запятой: {0}", "Decimal places: {0}", "Знаків після коми: {0}"),
    "trimZeros": ("Убирать лишние нули (2.50 → 2.5)", "Trim trailing zeros (2.50 → 2.5)", "Прибирати зайві нулі (2.50 → 2.5)"),
    "inputNote": ("Ввод понимает любой формат: 300,000.00 · 300 000,00 · 30000,00", "Input accepts any format: 300,000.00 · 300 000,00 · 30000,00", "Введення розуміє будь-який формат: 300,000.00 · 300 000,00 · 30000,00"),
    "example": ("Пример", "Example", "Приклад"),
    "font": ("Шрифт", "Font", "Шрифт"),
    "systemMono": ("Системный моноширинный (SF Mono)", "System monospaced (SF Mono)", "Системний моноширинний (SF Mono)"),
    "fontSize": ("Размер: {0}  (⌘= / ⌘-)", "Size: {0}  (⌘= / ⌘-)", "Розмір: {0}  (⌘= / ⌘-)"),
    "behavior": ("Поведение", "Behavior", "Поведінка"),
    "language": ("Язык интерфейса", "Language", "Мова інтерфейсу"),
    "langSystem": ("Как в системе", "System", "Як у системі"),
    "hotkey": ("Горячая клавиша (глобальная)", "Global hotkey", "Гаряча клавіша (глобальна)"),
    "pressKeys": ("Нажмите сочетание… (Esc — отмена)", "Press keys… (Esc to cancel)", "Натисніть поєднання… (Esc — скасувати)"),
    "showDock": ("Значок в Dock", "Show in Dock", "Значок у Dock"),
    "showMenuBar": ("Значок в строке меню", "Show in menu bar", "Значок у рядку меню"),
    "hideOnDeactivate": ("Прятать окно при переходе в другое приложение", "Hide when switching to another app", "Ховати вікно при переході в іншу програму"),
    "alwaysOnTop": ("Поверх всех окон", "Always on top", "Поверх усіх вікон"),
    "showHints": ("Подсказки об ошибках в строках", "Show error hints", "Підказки про помилки в рядках"),
    "launchAtLogin": ("Запускать при входе в систему", "Launch at login", "Запускати під час входу"),
    "rates": ("Курсы валют", "Exchange rates", "Курси валют"),
    "useNBU": ("Гривна по официальному курсу НБУ", "Hryvnia at the official NBU rate", "Гривня за офіційним курсом НБУ"),
    "refreshNow": ("Обновить сейчас", "Refresh now", "Оновити зараз"),
    "ratesSources": ("Мировые курсы — open.er-api.com, крипта — CoinGecko, НБУ — bank.gov.ua. Обновляются каждые 4 часа и хранятся офлайн.",
                     "World rates — open.er-api.com, crypto — CoinGecko, NBU — bank.gov.ua. Refreshed every 4 hours and cached offline.",
                     "Світові курси — open.er-api.com, крипта — CoinGecko, НБУ — bank.gov.ua. Оновлюються кожні 4 години й зберігаються офлайн."),

    // History
    "searchHistory": ("Поиск по истории", "Search history", "Пошук в історії"),
    "clearAll": ("Очистить всё", "Clear All", "Очистити все"),
    "insertToSheet": ("Вставить в лист", "Insert into Sheet", "Вставити в аркуш"),
    "copyExprResult": ("Копировать «выражение = результат»", "Copy “expression = result”", "Копіювати «вираз = результат»"),
    "delete": ("Удалить", "Delete", "Видалити"),
    "historyCount": ("Записей: {0} · двойной клик — вставить в лист", "Entries: {0} · double-click to insert", "Записів: {0} · подвійний клік — вставити в аркуш"),

    // Help
    "helpHeader": ("ExoCalc — справка", "ExoCalc — Help", "ExoCalc — довідка"),
    "helpIntro": ("Пишите выражения обычными словами. Кликните по примеру — он добавится в лист.",
                  "Type expressions in plain words. Click an example to add it to the sheet.",
                  "Пишіть вирази звичайними словами. Клікніть по прикладу — він додасться в аркуш."),
    "hArith": ("Арифметика", "Arithmetic", "Арифметика"),
    "hNumbers": ("Числа в любом формате", "Numbers in any format", "Числа в будь-якому форматі"),
    "hPercent": ("Проценты", "Percentages", "Відсотки"),
    "hFunc": ("Функции и константы", "Functions and constants", "Функції та константи"),
    "hCurrency": ("Валюты (мир, НБУ, крипта)", "Currencies (world, NBU, crypto)", "Валюти (світ, НБУ, крипта)"),
    "hUnits": ("Единицы измерения", "Units", "Одиниці виміру"),
    "hBases": ("Системы счисления и масштаб", "Number bases and scale", "Системи числення та масштаб"),
    "hVars": ("Переменные", "Variables", "Змінні"),
    "hTotals": ("Итоги блока (до пустой строки)", "Block totals (up to an empty line)", "Підсумки блоку (до порожнього рядка)"),
    "hKeys": ("Клавиши и приёмы", "Keys and tips", "Клавіші та прийоми"),
    "tHotkey": ("показать / спрятать окно из любого приложения (меняется в настройках)", "show / hide from any app (change in Settings)", "показати / сховати вікно з будь-якої програми (змінюється в налаштуваннях)"),
    "tEsc": ("спрятать окно", "hide the window", "сховати вікно"),
    "tClickKey": ("клик по результату", "click a result", "клік по результату"),
    "tClick": ("скопировать результат", "copy the result", "скопіювати результат"),
    "tShiftClick": ("скопировать «выражение = результат»", "copy “expression = result”", "скопіювати «вираз = результат»"),
    "tCtrlC": ("скопировать только результат текущей строки", "copy the current line's result", "скопіювати лише результат поточного рядка"),
    "tAltC": ("скопировать весь лист с результатами", "copy the whole sheet with results", "скопіювати весь аркуш з результатами"),
    "tK": ("очистить лист (строки уходят в историю, ⌘Z — вернуть)", "clear the sheet (lines go to history, ⌘Z to undo)", "очистити аркуш (рядки йдуть в історію, ⌘Z — повернути)"),
    "tY": ("история вычислений", "calculation history", "історія обчислень"),
    "tF5": ("автодополнение единиц, валют, функций, переменных", "autocomplete units, currencies, functions, variables", "автодоповнення одиниць, валют, функцій, змінних"),
    "tFont": ("размер шрифта", "font size", "розмір шрифту"),
    "tR": ("обновить курсы", "refresh rates", "оновити курси"),
    "tComma": ("настройки: язык, разделители, знаки, шрифт, горячая клавиша", "settings: language, separators, decimals, font, hotkey", "налаштування: мова, роздільники, знаки, шрифт, гаряча клавіша"),
    "tConvKey": ("in, to, в, во, у, →", "in, to, as, →", "у, в, in, to, →"),
    "tConv": ("перевод в другую единицу или валюту", "convert to another unit or currency", "переведення в іншу одиницю чи валюту"),
    "tCommentKey": ("# или //", "# or //", "# або //"),
    "tComment": ("комментарий; «Текст: 100» — подпись перед числом", "comment; “Label: 100” adds a label", "коментар; «Текст: 100» — підпис перед числом"),
    "tTotalsKey": ("пред, итого, среднее", "prev, total, avg", "попер, разом, середнє"),
    "tTotals": ("предыдущий результат, сумма и среднее блока", "previous result, block sum and average", "попередній результат, сума та середнє блоку"),
    "tArgs": ("разделитель аргументов функций", "function argument separator", "роздільник аргументів функцій"),
]
