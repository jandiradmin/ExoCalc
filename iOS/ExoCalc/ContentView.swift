import SwiftUI
import ExoCalcCore

struct ContentView: View {
    @EnvironmentObject var model: CalcModel
    @State private var showHelp = false
    @State private var showSettings = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CalcEditor(model: model)
                    .ignoresSafeArea(.container, edges: .bottom)
                statusBar
            }
            .background(Color(Theme.bg))
            .navigationTitle("ExoCalc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(Theme.bg), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
                        .keyboardShortcut("/", modifiers: .command)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button { model.editor?.undoStep() } label: { Label(tr("undo"), systemImage: "arrow.uturn.backward") }
                        Button { model.editor?.redoStep() } label: { Label(tr("redo"), systemImage: "arrow.uturn.forward") }
                        Divider()
                        Button { model.editor?.copyAll() } label: { Label(tr("copyAll"), systemImage: "doc.on.doc") }
                        Button { model.insertExamples() } label: { Label(tr("examples"), systemImage: "text.badge.plus") }
                        Button { model.refreshRates() } label: { Label(tr("refreshNow"), systemImage: "arrow.clockwise") }
                        Divider()
                        Button(role: .destructive) { confirmClear = true } label: { Label(tr("clearSheet"), systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
            .confirmationDialog(tr("clearSheet"), isPresented: $confirmClear, titleVisibility: .visible) {
                Button(tr("clearSheet"), role: .destructive) { model.clearSheet() }
            }
            .sheet(isPresented: $showHelp) { HelpSheet().environmentObject(model) }
            .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(model) }
        }
    }

    private var statusBar: some View {
        let text = model.status.isEmpty ? model.ratesStatus : model.status
        let color: Color = model.statusIsCopy ? Color(Theme.result)
            : (model.status.hasPrefix("⚠") ? Color(Theme.hint) : Color(Theme.status))
        return Text(text)
            .font(.caption)
            .foregroundColor(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(Theme.bg))
            .animation(.easeOut(duration: 0.15), value: model.status)
    }
}

struct HelpSheet: View {
    @EnvironmentObject var model: CalcModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(tr("helpTapHint"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                ForEach(Array(Examples.helpSections().enumerated()), id: \.offset) { _, sec in
                    Section(sec.0) {
                        ForEach(sec.1, id: \.self) { ex in
                            Button {
                                model.insertLine(ex)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(ex).font(.system(.body, design: .monospaced)).foregroundColor(.primary)
                                    Spacer()
                                    Text(model.engine.evaluate(ex).display ?? "")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(Color(Theme.result))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(tr("help"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("done")) { dismiss() } }
            }
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var m: CalcModel
    @Environment(\.dismiss) private var dismiss

    private var preview: String {
        m.engine.number(1234567.5, decimals: m.calcSettings.decimals) + "   ·   " + m.engine.number(0.125, decimals: m.calcSettings.decimals)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("numbers")) {
                    Picker(tr("decimalSep"), selection: $m.decimalSeparator) {
                        Text(tr("dot")).tag(".")
                        Text(tr("comma")).tag(",")
                    }
                    Picker(tr("groupSep"), selection: $m.groupingSeparator) {
                        Text(tr("gNone")).tag("")
                        Text(tr("gSpace")).tag(" ")
                        Text(tr("gComma")).tag(",")
                        Text(tr("gDot")).tag(".")
                        Text(tr("gApos")).tag("'")
                    }
                    Stepper(value: $m.decimals, in: 0...10) { Text(tr("decimals", String(m.decimals))) }
                    Toggle(tr("trimZeros"), isOn: $m.trimZeros)
                    Picker(tr("dateFormat"), selection: $m.dateFormat) {
                        Text("31.12.2026").tag("dmy")
                        Text("12/31/2026").tag("mdy")
                        Text("2026-12-31").tag("ymd")
                    }
                    HStack {
                        Text(tr("example"))
                        Spacer()
                        Text(preview).font(.system(.footnote, design: .monospaced)).foregroundColor(Color(Theme.result))
                    }
                }
                Section(tr("font")) {
                    Stepper(value: $m.fontSize, in: 12...30, step: 1) { Text(tr("fontSize", String(Int(m.fontSize)))) }
                }
                Section(tr("behavior")) {
                    Picker(tr("language"), selection: $m.language) {
                        Text(tr("langSystem")).tag("")
                        Text("Русский").tag("ru")
                        Text("Українська").tag("uk")
                        Text("English").tag("en")
                    }
                }
                Section(tr("rates")) {
                    Toggle(tr("useNBU"), isOn: $m.useNBU)
                    Text(m.ratesStatus).font(.footnote).foregroundColor(.secondary)
                    Button(tr("refreshNow")) { m.refreshRates() }
                    Text(tr("ratesSources")).font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle(tr("settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("done")) { dismiss() } }
            }
        }
    }
}
