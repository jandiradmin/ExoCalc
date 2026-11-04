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
            Section("Числа") {
                Picker("Десятичный разделитель", selection: $s.decimalSeparator) {
                    Text("Точка — 1.5").tag(".")
                    Text("Запятая — 1,5").tag(",")
                }
                Picker("Разделитель тысяч", selection: $s.groupingSeparator) {
                    Text("Нет — 1000000").tag("")
                    Text("Пробел — 1 000 000").tag(" ")
                    Text("Запятая — 1,000,000").tag(",")
                    Text("Точка — 1.000.000").tag(".")
                    Text("Апостроф — 1'000'000").tag("'")
                }
                Stepper(value: $s.decimals, in: 0...10) {
                    Text("Знаков после запятой: \(s.decimals)")
                }
                Toggle("Убирать лишние нули (2.50 → 2.5)", isOn: $s.trimZeros)
                HStack {
                    Text("Пример")
                    Spacer()
                    Text(preview).font(.system(.body, design: .monospaced)).foregroundColor(Color(nsColor: Theme.result))
                }
            }

            Section("Шрифт") {
                Picker("Шрифт", selection: $s.fontName) {
                    Text("Системный моноширинный (SF Mono)").tag("")
                    ForEach(fonts, id: \.self) { f in
                        Text(f).tag(f)
                    }
                }
                Stepper(value: $s.fontSize, in: 10...40, step: 1) {
                    Text("Размер: \(Int(s.fontSize))  (⌘= / ⌘-)")
                }
            }

            Section("Поведение") {
                HotKeyRecorder()
                Toggle("Прятать окно при переходе в другое приложение", isOn: $s.hideOnDeactivate)
                Toggle("Поверх всех окон", isOn: $s.alwaysOnTop)
                Toggle("Подсказки об ошибках в строках", isOn: $s.showHints)
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { ui.launchAtLogin },
                    set: { setLogin($0) }
                ))
            }

            Section("Курсы валют") {
                Toggle("Гривна по официальному курсу НБУ", isOn: $s.useNBU)
                Text(s.ratesStatus).foregroundColor(.secondary)
                Button("Обновить сейчас", action: onRefresh)
                Text("Мировые курсы — open.er-api.com, крипта — CoinGecko, НБУ — bank.gov.ua. Обновляются автоматически каждые 4 часа и хранятся офлайн.")
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
            Text("Горячая клавиша (глобальная)")
            Spacer()
            Button(st.recording ? "Нажмите сочетание… (Esc — отмена)"
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
