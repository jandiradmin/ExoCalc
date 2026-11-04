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

    static let sections: [(String, [String])] = [
        ("Арифметика", ["2 + 3 * 4", "(2 + 3) * 4", "2^10", "10 mod 3", "5!", "800 × 12", "800x12", "1/3"]),
        ("Проценты", ["100 + 15%", "250 - 20%", "15% of 800", "20% off 1500", "5% on 200"]),
        ("Функции и константы", ["sqrt(144)", "√2", "sin(30°)", "cos(pi)", "log(1000)", "ln(e)",
                                 "round(3.14159; 1)", "max(3; 9; 4)", "avg(10; 20; 60)", "2 pi"]),
        ("Валюты (мир, НБУ, крипта)", ["600 usd in uah", "$20 + €15", "100 € в грн", "1000 грн to usd",
                                       "0.05 btc in usd", "1 eth to uah", "5000 uah in eur"]),
        ("Единицы", ["18 °C in °F", "100 km in miles", "5 ft in cm", "70 kg in lb", "1.5 h in min",
                     "1 GB in MB", "100 km/h in m/s", "3 m * 4 m", "120 km / 1.5 h", "10 соток в м2",
                     "1 gal in l", "1 km + 300 m"]),
        ("Системы счисления и масштаб", ["255 in hex", "0xFF + 1", "10 in bin", "5k + 2.5 млн", "1234567 in sci"]),
        ("Переменные", ["цена = 1250", "кол = 3", "цена * кол", "prev + 100"]),
        ("Итоги блока (до пустой строки)", ["Аренда: 2000", "Свет: 150", "Интернет: 30", "итого"]),
    ]

    static let tips: [(String, String)] = [
        ("⌥⌘=", "показать / спрятать окно из любого приложения (меняется в настройках)"),
        ("Esc", "спрятать окно"),
        ("клик по результату", "скопировать результат"),
        ("⇧-клик, ⇧⌘C", "скопировать «выражение = результат»"),
        ("⌃⌘C", "скопировать только результат текущей строки"),
        ("⌥⌘C", "скопировать весь лист с результатами"),
        ("⌘K", "очистить лист (строки уходят в историю, ⌘Z — вернуть)"),
        ("⌘Y", "история вычислений"),
        ("F5 или ⌥Esc", "автодополнение единиц, валют, функций, переменных"),
        ("⌘= / ⌘- / ⌘0", "размер шрифта"),
        ("⌘R", "обновить курсы"),
        ("⌘,", "настройки: разделители, знаки после запятой, шрифт, горячая клавиша"),
        ("in, to, as, в, →", "перевод в другую единицу или валюту"),
        ("# или //", "комментарий; «Текст: 100» — подпись перед числом"),
        ("prev, sum / итого, avg", "предыдущий результат, сумма и среднее блока"),
        ("; ", "разделитель аргументов функций"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("ExoCalc — справка")
                    .font(.title2.bold())
                Text("Пишите выражения обычным текстом. Кликните по примеру — он добавится в лист.")
                    .foregroundColor(.secondary)

                ForEach(HelpView.sections.indices, id: \.self) { si in
                    let title = HelpView.sections[si].0
                    let lines = HelpView.sections[si].1
                    let results = engine.evaluate(lines: lines)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.headline)
                        ForEach(lines.indices, id: \.self) { li in
                            ExampleRow(expr: lines[li], result: results[li], onTap: onInsert)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Клавиши и приёмы").font(.headline)
                    ForEach(HelpView.tips.indices, id: \.self) { ti in
                        HStack(alignment: .firstTextBaseline) {
                            Text(HelpView.tips[ti].0)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color(nsColor: Theme.unit))
                                .frame(width: 170, alignment: .leading)
                            Text(HelpView.tips[ti].1)
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
