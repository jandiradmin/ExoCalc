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


    private static func tips() -> [(String, String)] {
        [
            (HotKeyFormat.string(code: AppSettings.shared.hotKeyCode, mods: AppSettings.shared.hotKeyMods), tr("tHotkey")),
            ("Esc", tr("tEsc")),
            (tr("tClickKey"), tr("tClick")),
            ("⌘-click, ⇧⌘C", tr("tShiftClick")),
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
        let sections = Examples.helpSections()
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
