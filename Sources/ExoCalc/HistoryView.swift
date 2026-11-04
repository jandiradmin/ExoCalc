import AppKit
import SwiftUI
import ExoCalcCore

struct HistoryView: View {
    @ObservedObject private var history: History
    private let onInsert: (String) -> Void
    @ObservedObject private var ui: HistoryUIState

    init(history: History, onInsert: @escaping (String) -> Void) {
        self._history = ObservedObject(wrappedValue: history)
        self._ui = ObservedObject(wrappedValue: HistoryUIState())
        self.onInsert = onInsert
    }

    private var filtered: [History.Entry] {
        ui.query.isEmpty ? history.entries : history.entries.filter { $0.line.localizedCaseInsensitiveContains(ui.query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField(tr("searchHistory"), text: $ui.query)
                    .textFieldStyle(.roundedBorder)
                Button(tr("clearAll")) { history.clear() }
                    .disabled(history.entries.isEmpty)
            }
            .padding(10)

            List(selection: $ui.selection) {
                ForEach(filtered) { e in
                    HStack(spacing: 8) {
                        Text(e.expr)
                            .font(.system(size: 13, design: .monospaced))
                            .lineLimit(1)
                        Text("= \(e.result)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Color(nsColor: Theme.result))
                            .lineLimit(1)
                        Spacer()
                        Text(e.date, format: .dateTime.day().month(.twoDigits).hour().minute())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .tag(e.id)
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                Button(tr("insertToSheet")) { insert(ids) }
                Button(tr("copyExprResult")) { copy(ids) }
                Divider()
                Button(tr("delete")) { history.remove(ids: ids) }
            } primaryAction: { ids in
                insert(ids)
            }

            HStack {
                Text(tr("historyCount", String(filtered.count)))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(tr("copy")) { copy(ui.selection) }
                    .disabled(ui.selection.isEmpty)
                Button(tr("insertToSheet")) { insert(ui.selection) }
                    .disabled(ui.selection.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(minWidth: 540, minHeight: 400)
    }

    private func entries(_ ids: Set<UUID>) -> [History.Entry] {
        filtered.filter { ids.contains($0.id) }
    }

    private func insert(_ ids: Set<UUID>) {
        for e in entries(ids).reversed() { onInsert(e.expr) }
    }

    private func copy(_ ids: Set<UUID>) {
        let s = entries(ids).map { $0.line }.joined(separator: "\n")
        guard !s.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
