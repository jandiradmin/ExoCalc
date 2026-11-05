import AppKit
import SwiftUI
import ServiceManagement
import ExoCalcCore

struct SettingsView: View {
    @ObservedObject private var s: AppSettings
    @ObservedObject private var ui: SettingsUIState
    private let onRefresh: () -> Void
    private let fonts: [String]

    private static let previewEngine = Engine(rates: RateStore(cacheURL: nil))

    init(onRefresh: @escaping () -> Void) {
        self.onRefresh = onRefresh
        self._s = ObservedObject(wrappedValue: AppSettings.shared)
        self._ui = ObservedObject(wrappedValue: SettingsUIState.shared)
        self.fonts = AppSettings.monospacedFamilies()
    }

    private var preview: String {
        let e = SettingsView.previewEngine
        e.settings = s.calcSettings
        return e.number(1234567.5, decimals: s.calcSettings.decimals) + "   ·   " + e.number(0.125, decimals: s.calcSettings.decimals)
    }

    var body: some View {
        Form {
            Section(tr("numbers")) {
                Picker(tr("decimalSep"), selection: $s.decimalSeparator) {
                    Text(tr("dot")).tag(".")
                    Text(tr("comma")).tag(",")
                }
                Picker(tr("groupSep"), selection: $s.groupingSeparator) {
                    Text(tr("gNone")).tag("")
                    Text(tr("gSpace")).tag(" ")
                    Text(tr("gComma")).tag(",")
                    Text(tr("gDot")).tag(".")
                    Text(tr("gApos")).tag("'")
                }
                Stepper(value: $s.decimals, in: 0...10) {
                    Text(tr("decimals", String(s.decimals)))
                }
                Toggle(tr("trimZeros"), isOn: $s.trimZeros)
                Text(tr("inputNote")).font(.caption).foregroundColor(.secondary)
                Picker(tr("dateFormat"), selection: $s.dateFormat) {
                    Text("31.12.2026").tag("dmy")
                    Text("12/31/2026").tag("mdy")
                    Text("2026-12-31").tag("ymd")
                }
                HStack {
                    Text(tr("example"))
                    Spacer()
                    Text(preview).font(.system(.body, design: .monospaced)).foregroundColor(Color(nsColor: Theme.result))
                }
            }

            Section(tr("font")) {
                Picker(tr("font"), selection: $s.fontName) {
                    Text(tr("systemMono")).tag("")
                    ForEach(fonts, id: \.self) { f in
                        Text(f).tag(f)
                    }
                }
                Stepper(value: $s.fontSize, in: 10...40, step: 1) {
                    Text(tr("fontSize", String(Int(s.fontSize))))
                }
            }

            Section(tr("behavior")) {
                Picker(tr("language"), selection: $s.language) {
                    Text(tr("langSystem")).tag("")
                    Text("Русский").tag("ru")
                    Text("Українська").tag("uk")
                    Text("English").tag("en")
                }
                HotKeyRecorder()
                Toggle(tr("showDock"), isOn: $s.showInDock)
                Toggle(tr("showMenuBar"), isOn: $s.showInMenuBar)
                Toggle(tr("hideOnDeactivate"), isOn: $s.hideOnDeactivate)
                Toggle(tr("alwaysOnTop"), isOn: $s.alwaysOnTop)
                Toggle(tr("showHints"), isOn: $s.showHints)
                Toggle(tr("launchAtLogin"), isOn: Binding(
                    get: { ui.launchAtLogin },
                    set: { setLogin($0) }
                ))
            }

            Section(tr("rates")) {
                Toggle(tr("useNBU"), isOn: $s.useNBU)
                Text(s.ratesStatus).foregroundColor(.secondary)
                Button(tr("refreshNow"), action: onRefresh)
                Text(tr("ratesSources"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 700)
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        ui.launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct HotKeyRecorder: View {
    @ObservedObject private var s: AppSettings
    @ObservedObject private var st: RecorderState

    init() {
        self._s = ObservedObject(wrappedValue: AppSettings.shared)
        self._st = ObservedObject(wrappedValue: RecorderState.shared)
    }

    var body: some View {
        HStack {
            Text(tr("hotkey"))
            Spacer()
            Button(st.recording ? tr("pressKeys")
                             : HotKeyFormat.string(code: s.hotKeyCode, mods: s.hotKeyMods)) {
                if st.recording { stop() } else { start() }
            }
        }
    }

    private func start() {
        st.recording = true
        HotKey.shared.unregister()
        st.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 {
                stop()
                return nil
            }
            let mods = HotKeyFormat.carbonMods(e.modifierFlags)
            if mods == 0 && !HotKeyFormat.isFunctionKey(Int(e.keyCode)) {
                NSSound.beep()
                return nil
            }
            s.hotKeyCode = Int(e.keyCode)
            s.hotKeyMods = mods
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = st.monitor { NSEvent.removeMonitor(m) }
        st.monitor = nil
        st.recording = false
        (NSApp.delegate as? AppDelegate)?.applyHotKey()
    }
}
