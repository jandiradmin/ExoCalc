import AppKit
import SwiftUI
import Combine
import ExoCalcCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let rates = RateStore(cacheURL: Storage.ratesURL)
    lazy var engine = Engine(rates: rates)
    let history = History()
    var calc: CalcWindowController!
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    var helpWindow: NSWindow?
    var historyWindow: NSWindow?

    private var cancellables = Set<AnyCancellable>()
    private var lastHotKey: (Int, Int) = (-1, -1)
    private var refreshTimer: Timer?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let s = AppSettings.shared
        rates.useNBU = s.useNBU
        engine.settings = s.calcSettings

        calc = CalcWindowController(engine: engine, history: history)
        calc.onHide = { [weak self] in self?.hideWindow() }
        calc.hotKeyText = { HotKeyFormat.string(code: AppSettings.shared.hotKeyCode, mods: AppSettings.shared.hotKeyMods) }
        calc.ratesText = { [weak self] in self?.ratesTimeText() ?? "" }
        calc.applyAppearance()
        calc.loadState()

        buildMainMenu()
        setupStatusItem()

        HotKey.shared.action = { [weak self] in self?.toggleWindow() }
        applyHotKey()

        rates.onChange = { [weak self] in
            self?.calc.recalc()
            self?.updateRatesStatus()
        }
        updateRatesStatus()
        refreshRates()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.rates.isStale { self.refreshRates() }
        }

        s.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.settingsChanged() } }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(self, selector: #selector(appResigned),
                                               name: NSApplication.didResignActiveNotification, object: nil)
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        calc.recordCurrentLine()
        calc.saveState()
    }

    private func settingsChanged() {
        let s = AppSettings.shared
        if rates.useNBU != s.useNBU {
            rates.useNBU = s.useNBU
            updateRatesStatus()
        }
        calc.applyAppearance()
        if lastHotKey != (s.hotKeyCode, s.hotKeyMods) { applyHotKey() }
    }

    // MARK: - Window

    @objc func toggleWindow() {
        if calc.window.isVisible && calc.window.isKeyWindow && NSApp.isActive {
            hideWindow()
        } else {
            showWindow()
        }
    }

    @objc func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        calc.window.makeKeyAndOrderFront(nil)
        calc.window.makeFirstResponder(calc.textView)
    }

    @objc func hideWindow() {
        calc.recordCurrentLine()
        calc.saveState()
        calc.window.orderOut(nil)
        let others = [settingsWindow, helpWindow, historyWindow].contains { $0?.isVisible == true }
        if !others { NSApp.hide(nil) }
    }

    @objc private func appResigned() {
        guard AppSettings.shared.hideOnDeactivate, calc.window.isVisible else { return }
        calc.recordCurrentLine()
        calc.saveState()
        calc.window.orderOut(nil)
    }

    // MARK: - Hotkey

    func applyHotKey() {
        let s = AppSettings.shared
        lastHotKey = (s.hotKeyCode, s.hotKeyMods)
        let ok = HotKey.shared.register(code: UInt32(s.hotKeyCode), mods: UInt32(s.hotKeyMods))
        if !ok {
            calc.flashStatus("Сочетание \(HotKeyFormat.string(code: s.hotKeyCode, mods: s.hotKeyMods)) занято — выберите другое в настройках")
        }
        calc.updateStatus()
    }

    // MARK: - Rates

    @objc func refreshRates() {
        AppSettings.shared.ratesStatus = "Обновление…"
        rates.refresh { [weak self] ok in
            if !ok { self?.calc.flashStatus("Не удалось обновить курсы — используется сохранённый кэш") }
            self?.updateRatesStatus()
        }
    }

    func ratesTimeText() -> String {
        guard let d = rates.updated else { return "нет" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "dd.MM HH:mm"
        return f.string(from: d)
    }

    func updateRatesStatus() {
        var s = rates.updated == nil ? "Курсы ещё не загружены" : "Обновлено: \(ratesTimeText())"
        if AppSettings.shared.useNBU, let nd = rates.nbuDate { s += " · НБУ на \(nd)" }
        if let r = rates.rate("USD", "UAH") { s += " · 1 USD = \(engine.number(r, decimals: 4)) UAH" }
        AppSettings.shared.ratesStatus = s
        calc.updateStatus()
    }

    // MARK: - Windows

    private func makeWindow<V: View>(_ title: String, _ view: V, resizable: Bool) -> NSWindow {
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = title
        w.styleMask = resizable ? [.titled, .closable, .resizable] : [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.center()
        return w
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow("Настройки ExoCalc",
                                        SettingsView(onRefresh: { [weak self] in self?.refreshRates() }),
                                        resizable: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showHelp() {
        if helpWindow == nil {
            let view = HelpView(engine: engine) { [weak self] expr in
                self?.calc.insertLine(expr)
                self?.showWindow()
            }
            helpWindow = makeWindow("Справка ExoCalc", view, resizable: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        helpWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showHistory() {
        if historyWindow == nil {
            let view = HistoryView(history: history) { [weak self] expr in
                self?.calc.insertLine(expr)
                self?.showWindow()
            }
            historyWindow = makeWindow("История ExoCalc", view, resizable: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc func biggerFont() { AppSettings.shared.fontSize = min(40, AppSettings.shared.fontSize + 1) }
    @objc func smallerFont() { AppSettings.shared.fontSize = max(10, AppSettings.shared.fontSize - 1) }
    @objc func resetFont() { AppSettings.shared.fontSize = 15 }

    // MARK: - Status bar item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            let img = NSImage(systemSymbolName: "equal.square", accessibilityDescription: "ExoCalc")
            img?.isTemplate = true
            b.image = img
            b.target = self
            b.action = #selector(statusClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusClicked(_ sender: Any?) {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            statusItem.menu = makeStatusMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleWindow()
        }
    }

    private func makeStatusMenu() -> NSMenu {
        let m = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
            it.target = self
            m.addItem(it)
        }
        let hk = HotKeyFormat.string(code: AppSettings.shared.hotKeyCode, mods: AppSettings.shared.hotKeyMods)
        add("Показать / скрыть  (\(hk))", #selector(toggleWindow))
        add("История", #selector(showHistory))
        add("Справка", #selector(showHelp))
        add("Настройки…", #selector(showSettings))
        add("Обновить курсы", #selector(refreshRates))
        m.addItem(.separator())
        let quit = NSMenuItem(title: "Выйти из ExoCalc", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        m.addItem(quit)
        return m
    }

    // MARK: - Main menu (needed for ⌘C/⌘V and shortcuts)

    private func buildMainMenu() {
        let main = NSMenu()

        func item(_ title: String, _ action: Selector?, _ key: String,
                  _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
            it.keyEquivalentModifierMask = mods
            it.target = target
            return it
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem()
            let menu = NSMenu(title: title)
            items.forEach { menu.addItem($0) }
            holder.submenu = menu
            main.addItem(holder)
        }

        submenu("ExoCalc", [
            item("О программе ExoCalc", #selector(showAbout), "", [], target: self),
            .separator(),
            item("Настройки…", #selector(showSettings), ",", target: self),
            .separator(),
            item("Закрыть окно", #selector(NSWindow.performClose(_:)), "w"),
            item("Выйти", #selector(NSApplication.terminate(_:)), "q"),
        ])

        let find = item("Найти…", #selector(NSTextView.performFindPanelAction(_:)), "f")
        find.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        submenu("Правка", [
            item("Отменить", Selector(("undo:")), "z"),
            item("Повторить", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Вырезать", #selector(NSText.cut(_:)), "x"),
            item("Копировать", #selector(NSText.copy(_:)), "c"),
            item("Вставить", #selector(NSText.paste(_:)), "v"),
            item("Выделить всё", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Копировать строку с результатом", #selector(CalcWindowController.copyCurrentLine(_:)), "c", [.command, .shift], target: calc),
            item("Копировать только результат", #selector(CalcWindowController.copyCurrentResult(_:)), "c", [.command, .control], target: calc),
            item("Копировать весь лист с результатами", #selector(CalcWindowController.copyAll(_:)), "c", [.command, .option], target: calc),
            .separator(),
            find,
            item("Автодополнение", #selector(NSTextView.complete(_:)), "\u{1b}", [.option]),
        ])

        submenu("Лист", [
            item("Очистить лист", #selector(CalcWindowController.clearSheet(_:)), "k", target: calc),
            item("История", #selector(showHistory), "y", target: self),
            .separator(),
            item("Крупнее", #selector(biggerFont), "=", target: self),
            item("Мельче", #selector(smallerFont), "-", target: self),
            item("Обычный размер", #selector(resetFont), "0", target: self),
            .separator(),
            item("Обновить курсы", #selector(refreshRates), "r", target: self),
        ])

        let f1 = String(Character(Unicode.Scalar(UInt32(NSF1FunctionKey))!))
        submenu("Справка", [
            item("Справка ExoCalc", #selector(showHelp), f1, [], target: self),
            item("Справка (альтернатива)", #selector(showHelp), "/", [.command], target: self),
        ])

        NSApp.mainMenu = main
    }
}
