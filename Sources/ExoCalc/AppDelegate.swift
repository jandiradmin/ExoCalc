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
    private var lastLang: Lang = L10n.lang

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let s = AppSettings.shared
        NSApp.setActivationPolicy(s.showInDock ? .regular : .accessory)
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
        let policy: NSApplication.ActivationPolicy = s.showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            if policy == .regular { NSApp.activate(ignoringOtherApps: true) }
        }
        statusItem?.isVisible = s.showInMenuBar || !s.showInDock
        if lastLang != L10n.lang {
            lastLang = L10n.lang
            buildMainMenu()
            for w in [helpWindow, historyWindow] { w?.close() }
            helpWindow = nil
            historyWindow = nil
            settingsWindow?.title = tr("settingsTitle")
            updateRatesStatus()
        }
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
            calc.flashStatus(tr("hotkeyBusy", HotKeyFormat.string(code: s.hotKeyCode, mods: s.hotKeyMods)))
        }
        calc.updateStatus()
    }

    // MARK: - Rates

    @objc func refreshRates() {
        AppSettings.shared.ratesStatus = tr("updating")
        rates.refresh { [weak self] ok in
            if !ok { self?.calc.flashStatus(tr("ratesFailed")) }
            self?.updateRatesStatus()
        }
    }

    func ratesTimeText() -> String {
        guard let d = rates.updated else { return tr("never") }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "dd.MM HH:mm"
        return f.string(from: d)
    }

    func updateRatesStatus() {
        var s = rates.updated == nil ? tr("ratesNotLoaded") : tr("ratesUpdated", ratesTimeText())
        if AppSettings.shared.useNBU, let nd = rates.nbuDate { s += " · " + tr("nbuOn", nd) }
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
            settingsWindow = makeWindow(tr("settingsTitle"),
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
            helpWindow = makeWindow(tr("helpTitle"), view, resizable: true)
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
            historyWindow = makeWindow(tr("historyTitle"), view, resizable: true)
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
        statusItem.isVisible = AppSettings.shared.showInMenuBar || !AppSettings.shared.showInDock
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
        add(tr("showHide", hk), #selector(toggleWindow))
        add(tr("history"), #selector(showHistory))
        add(tr("help"), #selector(showHelp))
        add(tr("settings…"), #selector(showSettings))
        add(tr("refreshRates"), #selector(refreshRates))
        m.addItem(.separator())
        let quit = NSMenuItem(title: tr("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
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
            item(tr("about"), #selector(showAbout), "", [], target: self),
            .separator(),
            item(tr("settings…"), #selector(showSettings), ",", target: self),
            .separator(),
            item(tr("closeWindow"), #selector(NSWindow.performClose(_:)), "w"),
            item(tr("quit"), #selector(NSApplication.terminate(_:)), "q"),
        ])

        let find = item(tr("find…"), #selector(NSTextView.performFindPanelAction(_:)), "f")
        find.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        submenu(tr("edit"), [
            item(tr("undo"), Selector(("undo:")), "z"),
            item(tr("redo"), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item(tr("cut"), #selector(NSText.cut(_:)), "x"),
            item(tr("copy"), #selector(NSText.copy(_:)), "c"),
            item(tr("paste"), #selector(NSText.paste(_:)), "v"),
            item(tr("selectAll"), #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item(tr("copyLine"), #selector(CalcWindowController.copyCurrentLine(_:)), "c", [.command, .shift], target: calc),
            item(tr("copyResult"), #selector(CalcWindowController.copyCurrentResult(_:)), "c", [.command, .control], target: calc),
            item(tr("copyAll"), #selector(CalcWindowController.copyAll(_:)), "c", [.command, .option], target: calc),
            .separator(),
            find,
            item(tr("complete"), #selector(NSTextView.complete(_:)), "\u{1b}", [.option]),
        ])

        submenu(tr("sheet"), [
            item(tr("clearSheet"), #selector(CalcWindowController.clearSheet(_:)), "k", target: calc),
            item(tr("history"), #selector(showHistory), "y", target: self),
            .separator(),
            item(tr("bigger"), #selector(biggerFont), "=", target: self),
            item(tr("smaller"), #selector(smallerFont), "-", target: self),
            item(tr("actualSize"), #selector(resetFont), "0", target: self),
            .separator(),
            item(tr("refreshRates"), #selector(refreshRates), "r", target: self),
        ])

        let f1 = String(Character(Unicode.Scalar(UInt32(NSF1FunctionKey))!))
        submenu(tr("help"), [
            item(tr("helpItem"), #selector(showHelp), f1, [], target: self),
            item(tr("helpAlt"), #selector(showHelp), "/", [.command], target: self),
        ])

        NSApp.mainMenu = main
    }
}
