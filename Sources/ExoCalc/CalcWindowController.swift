import AppKit
import ExoCalcCore

final class CalcWindowController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    let window: NSWindow
    let textView: CalcTextView
    let scrollView: NSScrollView
    let statusLabel: NSTextField
    let engine: Engine
    let history: History
    private let textStorage: NSTextStorage   // keep TextKit 1 stack alive (layout manager/container are not retained by the text view)

    var onHide: (() -> Void)?
    var hotKeyText: () -> String = { "" }
    var ratesText: () -> String = { "" }

    private var saveWork: DispatchWorkItem?
    private var statusOverrideUntil = Date.distantPast
    private let statusHeight: CGFloat = 24

    private static func welcomeLines(hotkey: String) -> [String] {
        switch L10n.lang {
        case .ru: return [
            "# Добро пожаловать в ExoCalc! Пишите выражение — ответ появится справа.",
            "# F1 — справка · Esc — спрятать · \(hotkey) — вызвать из любого приложения",
            "14*5", "500*4", "(2+2)*4", "2^10", "1/3", "",
            "# Проценты", "20% от 1500", "1500 - 20%", "",
            "# Валюты (курсы обновляются сами)", "600 долларов в гривнах", "100 евро в грн", "0.01 btc в usd", "",
            "# Единицы измерения", "18 цельсия в фаренгейтах", "100 км в милях", "1 галлон в литрах", "70 кг в фунтах", "",
            "# Числа в любом формате", "300 000,00 * 2", "300,000.00 * 2", "",
            "# Переменные и итоги", "цена = 1250", "цена * 3", "",
            "Аренда: 2000", "Свет: 150", "итого",
        ]
        case .uk: return [
            "# Ласкаво просимо до ExoCalc! Пишіть вираз — відповідь з’явиться праворуч.",
            "# F1 — довідка · Esc — сховати · \(hotkey) — викликати з будь-якої програми",
            "14*5", "500*4", "(2+2)*4", "2^10", "1/3", "",
            "# Відсотки", "20% від 1500", "1500 - 20%", "",
            "# Валюти (курси оновлюються самі)", "600 доларів у гривнях", "100 євро у грн", "0.01 btc у usd", "",
            "# Одиниці виміру", "18 цельсія у фаренгейтах", "100 км у милях", "1 галон у літрах", "70 кг у фунтах", "",
            "# Числа в будь-якому форматі", "300 000,00 * 2", "300,000.00 * 2", "",
            "# Змінні та підсумки", "ціна = 1250", "ціна * 3", "",
            "Оренда: 2000", "Світло: 150", "разом",
        ]
        case .en: return [
            "# Welcome to ExoCalc! Type an expression — the answer appears on the right.",
            "# F1 — help · Esc — hide · \(hotkey) — open from any app",
            "14*5", "500*4", "(2+2)*4", "2^10", "1/3", "",
            "# Percentages", "20% of 1500", "1500 - 20%", "",
            "# Currencies (rates update automatically)", "600 usd in uah", "100 eur in usd", "0.01 btc in usd", "",
            "# Units", "18 celsius in fahrenheit", "100 km in miles", "1 gallon in liters", "70 kg in lb", "",
            "# Numbers in any format", "300 000,00 * 2", "300,000.00 * 2", "",
            "# Variables and totals", "price = 1250", "price * 3", "",
            "Rent: 2000", "Power: 150", "total",
        ]
        }
    }

    /// Example sheet; each line shows its answer after "=", like a worked example.
    func welcomeText() -> String {
        let lines = CalcWindowController.welcomeLines(hotkey: hotKeyText())
        let res = engine.evaluate(lines: lines)
        return zip(lines, res).map { line, r in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") || t.contains("=") || t.allSatisfy({ $0.isLetter }) { return line }
            guard let d = r.display else { return line }
            return "\(line) = \(d)"
        }.joined(separator: "\n")
    }

    @objc func insertExamples(_ sender: Any?) {
        insertLine("\n" + welcomeText())
    }

    init(engine: Engine, history: History) {
        self.engine = engine
        self.history = history

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)

        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(containerSize: NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = false
        lm.addTextContainer(tc)
        lm.allowsNonContiguousLayout = false
        textStorage = storage
        textView = CalcTextView(frame: NSRect(x: 0, y: 0, width: 720, height: 496), textContainer: tc)
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 24, width: 720, height: 496))
        statusLabel = NSTextField(labelWithString: "")
        super.init()
        setupWindow()
    }

    private func setupWindow() {
        window.title = "ExoCalc"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.bg
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 340, height: 180)
        window.delegate = self

        guard let cv = window.contentView else { return }
        let b = cv.bounds

        scrollView.frame = NSRect(x: 0, y: statusHeight, width: b.width, height: b.height - statusHeight)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.bg

        let tv = textView
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        tv.textContainerInset = NSSize(width: 14, height: 12)
        tv.drawsBackground = true
        tv.backgroundColor = Theme.bg
        tv.insertionPointColor = .white
        tv.textColor = Theme.text
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.selectedTextAttributes = [.backgroundColor: NSColor(white: 1, alpha: 0.18)]
        tv.delegate = self
        scrollView.documentView = tv

        statusLabel.frame = NSRect(x: 14, y: 4, width: b.width - 28, height: 16)
        statusLabel.autoresizingMask = [.width]
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = Theme.status
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.cell?.truncatesLastVisibleLine = true

        cv.addSubview(scrollView)
        cv.addSubview(statusLabel)

        let overlay = ResultOverlay(frame: scrollView.frame)
        overlay.autoresizingMask = [.width, .height]
        overlay.owner = tv
        cv.addSubview(overlay, positioned: .above, relativeTo: scrollView)
        tv.overlay = overlay
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView, queue: .main) { [weak tv] _ in
            tv?.refreshResults()
        }

        window.center()
        window.setFrameAutosaveName("ExoCalcMain")

        tv.onEscape = { [weak self] in self?.onHide?() }
        tv.onNewline = { [weak self] idx in self?.recordHistory(line: idx) }
        tv.onResultClick = { [weak self] idx, full in self?.copyLine(idx, full: full) }
        tv.completionProvider = { [weak self] p in self?.engine.completions(for: p) ?? [] }
    }

    // MARK: - State

    func loadState() {
        if let s = Storage.loadSheet(), !s.text.hasPrefix("# ExoCalc — F1") {
            textView.string = s.text
            let loc = min(max(0, s.selection), (s.text as NSString).length)
            textView.setSelectedRange(NSRange(location: loc, length: 0))
            recalc()
            let y = CGFloat(s.scrollY)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            }
        } else {
            textView.string = welcomeText()
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
            recalc()
        }
    }

    func saveState() {
        saveWork?.cancel()
        Storage.saveSheet(Storage.Sheet(text: textView.string,
                                        selection: textView.selectedRange().location,
                                        scrollY: Double(scrollView.contentView.bounds.origin.y)))
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.saveState() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    // MARK: - Appearance

    func applyAppearance() {
        let s = AppSettings.shared
        let f = s.font()
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 4
        textView.font = f
        textView.defaultParagraphStyle = ps
        textView.typingAttributes = [.font: f, .foregroundColor: Theme.text, .paragraphStyle: ps]
        if let ts = textView.textStorage {
            ts.beginEditing()
            let full = NSRange(location: 0, length: ts.length)
            ts.addAttribute(.font, value: f, range: full)
            ts.addAttribute(.paragraphStyle, value: ps, range: full)
            ts.endEditing()
        }
        textView.resultFont = s.resultFont()
        textView.showHints = s.showHints
        window.level = s.alwaysOnTop ? .floating : .normal
        engine.settings = s.calcSettings
        recalc()
    }

    // MARK: - Evaluation

    func recalc() {
        normalizeNewlines()
        let ns = textView.string as NSString
        let ranges = CalcTextView.splitLines(ns)
        let lines = ranges.map { ns.substring(with: $0) }
        let results = engine.evaluate(lines: lines, recordVariables: true)
        textView.lineRanges = ranges
        textView.results = results
        applyHighlights(ranges, results)
        updateResultColumn()
        textView.refreshResults()
        window.invalidateCursorRects(for: textView)
        updateStatus()
    }

    private func normalizeNewlines() {
        guard textView.string.utf16.contains(13), let ts = textView.textStorage else { return }
        let sel = textView.selectedRange()
        let fixed = textView.string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        ts.replaceCharacters(in: NSRange(location: 0, length: ts.length), with: fixed)
        let len = (fixed as NSString).length
        textView.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
    }

    private func applyHighlights(_ ranges: [NSRange], _ results: [LineResult]) {
        guard let ts = textView.textStorage, ts.length > 0 else { return }
        ts.beginEditing()
        ts.addAttribute(.foregroundColor, value: Theme.text, range: NSRange(location: 0, length: ts.length))
        for (idx, lr) in results.enumerated() where idx < ranges.count {
            let base = ranges[idx].location
            let maxLen = ranges[idx].length
            for h in lr.highlights {
                let s = max(0, min(h.start, maxLen))
                let e = max(s, min(h.end, maxLen))
                guard e > s else { continue }
                ts.addAttribute(.foregroundColor, value: Theme.color(h.kind), range: NSRange(location: base + s, length: e - s))
            }
        }
        ts.endEditing()
    }

    private func updateResultColumn() {
        var maxW: CGFloat = 0
        let attrs: [NSAttributedString.Key: Any] = [.font: textView.resultFont]
        for r in textView.results {
            if let d = r.display {
                maxW = max(maxW, (d as NSString).size(withAttributes: attrs).width)
            }
        }
        var w = (maxW + 40) / 40
        w = w.rounded(.up) * 40
        w = min(max(w, 120), max(120, textView.bounds.width * 0.55))
        if Swift.abs(w - textView.resultColumn) > 1 {
            textView.resultColumn = w
            textView.updateContainerWidth()
        }
    }

    // MARK: - Status bar

    func flashStatus(_ text: String) {
        statusOverrideUntil = Date().addingTimeInterval(2.5)
        statusLabel.textColor = Theme.result
        statusLabel.stringValue = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in self?.updateStatus() }
    }

    func updateStatus() {
        if Date() < statusOverrideUntil { return }
        let idx = textView.currentLine
        if idx < textView.results.count, idx < textView.lineRanges.count {
            let r = textView.results[idx]
            let ns = textView.string as NSString
            let range = textView.lineRanges[idx]
            let line = range.location + range.length <= ns.length ? ns.substring(with: range) : ""
            if let e = r.error, AppSettings.shared.showHints,
               !line.trimmingCharacters(in: .whitespaces).isEmpty {
                statusLabel.textColor = Theme.hint
                statusLabel.stringValue = "⚠︎ \(e)"
                return
            }
            if r.display != nil {
                statusLabel.textColor = Theme.status
                statusLabel.stringValue = tr("stResult")
                return
            }
        }
        statusLabel.textColor = Theme.status
        statusLabel.stringValue = tr("stDefault", hotKeyText(), ratesText())
    }

    // MARK: - Copy & history

    private func expression(of idx: Int) -> String {
        guard idx < textView.lineRanges.count else { return "" }
        let ns = textView.string as NSString
        let range = textView.lineRanges[idx]
        guard range.location + range.length <= ns.length else { return "" }
        var expr = ns.substring(with: range)
        if let cut = expr.range(of: "//") { expr = String(expr[..<cut.lowerBound]) }
        if let eq = expr.range(of: "=", options: .backwards) {
            let before = String(expr[..<eq.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !before.isEmpty { expr = before }
        }
        return expr.trimmingCharacters(in: .whitespaces)
    }

    func copyString(line idx: Int, full: Bool) -> String? {
        guard idx < textView.results.count, let d = textView.results[idx].display else { return nil }
        return full ? "\(expression(of: idx)) = \(d)" : d
    }

    func copyLine(_ idx: Int, full: Bool) {
        guard let s = copyString(line: idx, full: full) else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        flashStatus(tr("copied", s))
    }

    @objc func copyCurrentLine(_ sender: Any?) {
        let idx = textView.currentLine
        copyLine(idx, full: true)
        textView.flash(idx)
    }

    @objc func copyCurrentResult(_ sender: Any?) {
        let idx = textView.currentLine
        copyLine(idx, full: false)
        textView.flash(idx)
    }

    @objc func copyAll(_ sender: Any?) {
        let ns = textView.string as NSString
        var out: [String] = []
        for (idx, r) in textView.lineRanges.enumerated() {
            if idx < textView.results.count, let d = textView.results[idx].display {
                out.append("\(expression(of: idx)) = \(d)")
            } else {
                out.append(ns.substring(with: r).trimmingCharacters(in: .whitespaces))
            }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(out.joined(separator: "\n"), forType: .string)
        flashStatus(tr("copiedAll"))
    }

    func recordHistory(line idx: Int) {
        guard idx < textView.results.count, let d = textView.results[idx].display else { return }
        history.add(expr: expression(of: idx), result: d)
    }

    func recordCurrentLine() {
        recordHistory(line: textView.currentLine)
    }

    @objc func clearSheet(_ sender: Any?) {
        for idx in 0..<textView.results.count { recordHistory(line: idx) }
        let len = (textView.string as NSString).length
        let all = NSRange(location: 0, length: len)
        if textView.shouldChangeText(in: all, replacementString: "") {
            textView.replaceCharacters(in: all, with: "")
            textView.didChangeText()
        }
        flashStatus(tr("cleared"))
    }

    func insertLine(_ s: String) {
        let ns = textView.string as NSString
        var text = s
        if ns.length > 0 && !textView.string.hasSuffix("\n") { text = "\n" + s }
        let r = NSRange(location: ns.length, length: 0)
        if textView.shouldChangeText(in: r, replacementString: text) {
            textView.replaceCharacters(in: r, with: text)
            textView.didChangeText()
        }
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.scrollRangeToVisible(NSRange(location: end, length: 0))
    }

    // MARK: - Delegates

    func textDidChange(_ notification: Notification) {
        recalc()
        scheduleSave()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateStatus()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onHide?()
        return false
    }

    func windowDidResize(_ notification: Notification) {
        updateResultColumn()
    }
}
