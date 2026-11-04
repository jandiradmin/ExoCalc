import AppKit
import SwiftUI
import ExoCalcCore

struct HelpView: View {
    private let engine: Engine
    private let onInsert: (String) -> Void

    init(engine: Engine, onInsert: @escaping (String) -> Void) {
        self.engine = engine
        self.onInsert = onInsert
    }

    private static func sections() -> [(String, [String])] {
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
                                 "120 км / 1.5 ч", "10 соток в м2", "1 км + 300 м"]
                         : uk ? ["18 цельсія у фаренгейтах", "100 км у милях", "5 футів у см", "70 кг у фунтах",
                                 "1.5 години у хвилинах", "1 GB \(conv) MB", "100 км/ч у m/s", "3 m * 4 m",
                                 "120 км / 1.5 години", "1 км + 300 м"]
                              : ["18 celsius in fahrenheit", "100 km in miles", "5 ft in cm", "70 kg in lb",
                                 "1.5 hours in minutes", "1 GB in MB", "100 km/h in m/s", "3 m * 4 m",
                                 "120 km / 1.5 h", "1 km + 300 m"]),
            (tr("hBases"), ["255 \(conv) hex", "0xFF + 1", "10 \(conv) bin", ru ? "5k + 2.5 млн" : (uk ? "5k + 2.5 мільйон" : "5k + 2.5 million"), "1234567 \(conv) sci"]),
            (tr("hVars"), ru ? ["цена = 1250", "кол = 3", "цена * кол", "пред + 100"]
                        : uk ? ["ціна = 1250", "кількість = 3", "ціна * кількість", "попер + 100"]
                             : ["price = 1250", "qty = 3", "price * qty", "prev + 100"]),
            (tr("hTotals"), ru ? ["Аренда: 2000", "Свет: 150", "Интернет: 30", "итого"]
                          : uk ? ["Оренда: 2000", "Світло: 150", "Інтернет: 30", "разом"]
                               : ["Rent: 2000", "Power: 150", "Internet: 30", "total"]),
        ]
    }

    private static func tips() -> [(String, String)] {
        [
            (HotKeyFormat.string(code: AppSettings.shared.hotKeyCode, mods: AppSettings.shared.hotKeyMods), tr("tHotkey")),
            ("Esc", tr("tEsc")),
            (tr("tClickKey"), tr("tClick")),
            ("⇧-click, ⇧⌘C", tr("tShiftClick")),
            ("⌃⌘C", tr("tCtrlC")),
            ("⌥⌘C", tr("tAltC")),
            ("⌘K", tr("tK")),
            ("⌘Y", tr("tY")),
            ("F5, ⌥Esc", tr("tF5")),
            ("⌘= / ⌘- / ⌘0", tr("tFont")),
            ("⌘R", tr("tR")),
            ("⌘,", tr("tComma")),
            (tr("tConvKey"), tr("tConv")),
            (tr("tCommentKey"), tr("tComment")),
            (tr("tTotalsKey"), tr("tTotals")),
            (";", tr("tArgs")),
        ]
    }

    var body: some View {
        let sections = HelpView.sections()
        let tips = HelpView.tips()
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(tr("helpHeader"))
                    .font(.title2.bold())
                Text(tr("helpIntro"))
                    .foregroundColor(.secondary)

                ForEach(sections.indices, id: \.self) { si in
                    let title = sections[si].0
                    let lines = sections[si].1
                    let results = engine.evaluate(lines: lines)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.headline)
                        ForEach(lines.indices, id: \.self) { li in
                            ExampleRow(expr: lines[li], result: results[li], onTap: onInsert)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("hKeys")).font(.headline)
                    ForEach(tips.indices, id: \.self) { ti in
                        HStack(alignment: .firstTextBaseline) {
                            Text(tips[ti].0)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color(nsColor: Theme.unit))
                                .frame(width: 170, alignment: .leading)
                            Text(tips[ti].1)
                                .font(.system(size: 12))
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 500, idealHeight: 720)
        .background(Color(nsColor: Theme.bg))
        .preferredColorScheme(.dark)
    }
}

private struct ExampleRow: View {
    let expr: String
    let result: LineResult
    let onTap: (String) -> Void

    private var resultText: String {
        if let d = result.display { return d }
        if let e = result.error { return "⚠︎ " + e }
        return ""
    }

    private var resultColor: Color {
        Color(nsColor: result.display != nil ? Theme.result : Theme.hint)
    }

    var body: some View {
        HStack {
            Text(expr)
                .font(.system(size: 13, design: .monospaced))
            Spacer()
            Text(resultText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(resultColor)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture { onTap(expr) }
    }
}
