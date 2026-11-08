import SwiftUI
import UIKit
import ExoCalcCore

/// Text editor with a column of results on the right.
/// Tap a green result to copy it; hold it to copy "expression = result".
final class CalcTextView: UITextView, UITextViewDelegate, UIGestureRecognizerDelegate {
    weak var model: CalcModel?
    private(set) var results: [LineResult] = []
    private var lineRanges: [NSRange] = []
    private let overlay = ResultLayer()
    private var resultColumn: CGFloat = 110
    private let rightPad: CGFloat = 14
    private var isHighlighting = false
    private var tapGR: UITapGestureRecognizer!
    private var holdGR: UILongPressGestureRecognizer!

    struct Slot {
        let rect: CGRect
        let line: Int
        let text: NSAttributedString
        let isResult: Bool
    }
    private(set) var slots: [Slot] = []
    var flashLine: Int?

    init(model: CalcModel) {
        self.model = model
        // TextKit 1 stack: results are placed with NSLayoutManager line fragments.
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        lm.addTextContainer(tc)
        super.init(frame: .zero, textContainer: tc)
        backgroundColor = Theme.bg
        textColor = Theme.text
        tintColor = Theme.result
        keyboardAppearance = .dark
        keyboardType = .default
        inputView = numericKeyboard ? NumPad(target: self) : nil
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 40, right: resultColumn)
        delegate = self
        overlay.owner = self
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        overlay.contentMode = .redraw
        addSubview(overlay)
        inputAccessoryView = KeyBar(target: self)

        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
        tapGR = tap
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(onHold(_:)))
        hold.minimumPressDuration = 0.4
        hold.delegate = self
        addGestureRecognizer(hold)
        holdGR = hold

        applyFont()
        text = model.text
        recalc()
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyFont() {
        let size = CGFloat(model?.fontSize ?? 15)
        font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        recalc()
    }

    private var resultFont: UIFont {
        UIFont.monospacedSystemFont(ofSize: CGFloat(model?.fontSize ?? 15), weight: .medium)
    }

    // MARK: - Evaluate and highlight

    private static func splitLines(_ ns: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var loc = 0
        let len = ns.length
        while true {
            let r = ns.range(of: "\n", options: [], range: NSRange(location: loc, length: len - loc))
            if r.location == NSNotFound {
                ranges.append(NSRange(location: loc, length: len - loc))
                break
            }
            ranges.append(NSRange(location: loc, length: r.location - loc))
            loc = r.location + 1
        }
        return ranges
    }

    var lines: [String] { text.components(separatedBy: "\n") }

    func recalc() {
        guard let model = model else { return }
        let ns = text as NSString
        lineRanges = CalcTextView.splitLines(ns)
        results = model.evaluate(lines)
        highlight()
        updateColumn()
        setNeedsLayout()
        overlay.setNeedsDisplay()
    }

    private func highlight() {
        guard let font = font else { return }
        isHighlighting = true
        let sel = selectedRange
        let storage = textStorage
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: Theme.text], range: NSRange(location: 0, length: storage.length))
        for (idx, r) in lineRanges.enumerated() where idx < results.count {
            for h in results[idx].highlights {
                let start = r.location + h.start, len = h.end - h.start
                guard len > 0, start + len <= storage.length else { continue }
                storage.addAttribute(.foregroundColor, value: Theme.color(h.kind), range: NSRange(location: start, length: len))
            }
        }
        storage.endEditing()
        selectedRange = sel
        isHighlighting = false
    }

    private func updateColumn() {
        var w: CGFloat = 60
        let attrs: [NSAttributedString.Key: Any] = [.font: resultFont]
        for r in results { if let d = r.display { w = max(w, (d as NSString).size(withAttributes: attrs).width) } }
        let col = min(w + rightPad + 16, max(120, bounds.width * 0.48))
        if Swift.abs(col - resultColumn) > 1 {
            resultColumn = col
            textContainerInset.right = col
        }
    }

    // MARK: - Layout of results

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = max(contentSize.height, bounds.height)
        let f = CGRect(x: 0, y: 0, width: bounds.width, height: h)
        if overlay.frame != f {
            overlay.frame = f
            overlay.setNeedsDisplay()
        }
        bringSubviewToFront(overlay)
    }

    override var bounds: CGRect {
        didSet { if oldValue.width != bounds.width { updateColumn(); overlay.setNeedsDisplay() } }
    }

    func computeSlots() {
        slots = []
        let lm = layoutManager
        let length = textStorage.length
        let font = resultFont
        for (idx, r) in lineRanges.enumerated() {
            guard idx < results.count, r.location < length, r.length > 0 else { continue }
            let res = results[idx]
            let text: String
            let color: UIColor
            var isResult = true
            if let d = res.display {
                text = d
                color = res.warning != nil ? Theme.hint : Theme.result
            } else if res.error != nil,
                      (textStorage.string as NSString).substring(with: r).contains(where: { $0.isNumber }) {
                text = "?"
                color = Theme.hint
                isResult = false
            } else {
                continue
            }
            let gi = lm.glyphIndexForCharacter(at: r.location)
            let frag = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
            let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            var size = attr.size()
            let maxW = resultColumn - rightPad - 8
            if size.width > maxW { size.width = maxW }
            let x = bounds.width - rightPad - size.width
            let y = frag.minY + textContainerInset.top + (frag.height - size.height) / 2
            slots.append(Slot(rect: CGRect(x: x, y: y, width: size.width, height: size.height),
                              line: idx, text: attr, isResult: isResult))
        }
    }

    fileprivate func drawResults(_ rect: CGRect) {
        computeSlots()
        for s in slots where s.rect.insetBy(dx: -8, dy: -4).intersects(rect) {
            if s.line == flashLine {
                Theme.number.withAlphaComponent(0.16).setFill()
                UIBezierPath(roundedRect: s.rect.insetBy(dx: -6, dy: -2), cornerRadius: 5).fill()
            }
            s.text.draw(with: s.rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
    }

    private func flash(_ line: Int) {
        flashLine = line
        overlay.setNeedsDisplay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.flashLine = nil
            self?.overlay.setNeedsDisplay()
        }
    }

    // MARK: - Taps on results

    private func resultSlot(at p: CGPoint) -> Slot? {
        computeSlots()
        return slots.first { s in
            s.isResult && CGRect(x: s.rect.minX - 16, y: s.rect.minY - 8,
                                 width: bounds.width - s.rect.minX + 16, height: s.rect.height + 16).contains(p)
        }
    }

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g === tapGR || g === holdGR {
            return resultSlot(at: g.location(in: self)) != nil
        }
        return super.gestureRecognizerShouldBegin(g)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        // Our result gestures win over the text view's own taps (caret, selection).
        (g === tapGR || g === holdGR) && other !== tapGR && other !== holdGR
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, let s = resultSlot(at: g.location(in: self)) else { return }
        copyLine(s.line, full: false)
    }

    @objc private func onHold(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let s = resultSlot(at: g.location(in: self)) else { return }
        copyLine(s.line, full: true)
    }

    private func copyLine(_ idx: Int, full: Bool) {
        guard idx < results.count, let d = results[idx].display else { return }
        let ls = lines
        model?.copy(line: idx < ls.count ? ls[idx] : "", result: d, full: full)
        flash(idx)
    }

    func copyAll() {
        model?.copyAll(lines: lines, results: results)
    }

    // MARK: - Editing

    func textViewDidChange(_ tv: UITextView) {
        if isHighlighting { return }
        model?.textChanged(text)
        recalc()
    }

    func textViewDidChangeSelection(_ tv: UITextView) {
        if let w = currentWarning() { model?.status = "⚠ " + w } else if model?.statusIsCopy == false { model?.status = "" }
    }

    private func currentWarning() -> String? {
        let loc = selectedRange.location
        for (idx, r) in lineRanges.enumerated() where loc <= r.location + r.length {
            guard idx < results.count else { return nil }
            return results[idx].warning ?? (results[idx].display == nil && r.length > 0 ? results[idx].error : nil)
        }
        return nil
    }

    /// Inserts a key's text without doubling spaces: "100 usd" + " in " + " btc" → "100 usd in btc".
    func insert(_ s: String) {
        var piece = s
        let ns = text as NSString
        let sel = selectedRange
        let before: Character? = sel.location > 0 ? Character(ns.substring(with: NSRange(location: sel.location - 1, length: 1))) : nil
        let afterLoc = sel.location + sel.length
        let after: Character? = afterLoc < ns.length ? Character(ns.substring(with: NSRange(location: afterLoc, length: 1))) : nil
        if piece != " " && piece != "\n" {
            // No leading space at line start, after a space, or right after "/", "^", "(".
            if before == nil || before == " " || before == "\n" || before == "/" || before == "^" || before == "(" {
                piece = String(piece.drop(while: { $0 == " " }))
            }
            if after == " " { while piece.hasSuffix(" ") { piece.removeLast() } }
        } else if piece == " " && (before == " " || after == " ") {
            return
        }
        if piece.isEmpty { return }
        insertText(piece)
        afterExternalChange()
    }

    func deleteOne() {
        deleteBackward()
        afterExternalChange()
    }

    // MARK: - Keyboard mode and undo

    /// Digits keypad (operators are on the key bar) or the full text keyboard.
    var numericKeyboard: Bool {
        get { UserDefaults.standard.object(forKey: "numericKeyboard") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "numericKeyboard") }
    }

    func toggleKeyboard() {
        numericKeyboard.toggle()
        // Our own keypad works with any keyboard (also third-party ones like SwiftKey).
        inputView = numericKeyboard ? NumPad(target: self) : nil
        (inputAccessoryView as? KeyBar)?.updateModeKey()
        reloadInputViews()
    }

    func undoStep() {
        guard let um = undoManager, um.canUndo else { UINotificationFeedbackGenerator().notificationOccurred(.warning); return }
        um.undo()
        afterExternalChange()
    }

    func redoStep() {
        guard let um = undoManager, um.canRedo else { UINotificationFeedbackGenerator().notificationOccurred(.warning); return }
        um.redo()
        afterExternalChange()
    }

    func afterExternalChange() {
        model?.textChanged(text)
        recalc()
        scrollRangeToVisible(selectedRange)
    }

    func appendText(_ s: String) {
        let t = text.hasSuffix("\n") || text.isEmpty ? String(s.drop(while: { $0 == "\n" })) : s
        text += (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + t
        model?.textChanged(text)
        recalc()
        selectedRange = NSRange(location: (text as NSString).length, length: 0)
        scrollRangeToVisible(selectedRange)
    }

    func replaceAll(_ s: String) {
        // Through the undo-aware path so shake/⌘Z can bring it back.
        let all = textRange(from: beginningOfDocument, to: endOfDocument)
        if let all = all { replace(all, withText: s) } else { text = s }
        model?.textChanged(text)
        recalc()
    }
}

final class ResultLayer: UIView {
    weak var owner: CalcTextView?
    override func draw(_ rect: CGRect) {
        owner?.drawResults(rect)
    }
}

/// Row of keys above the keyboard: operators, conversion words, currencies.
final class KeyBar: UIInputView {
    private weak var target: CalcTextView?
    private var modeKey: UIButton!
    private var scroll: UIScrollView!

    init(target: CalcTextView) {
        self.target = target
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 46), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        let scroll = UIScrollView()
        self.scroll = scroll
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        let conv = L10n.lang == .ru ? "в" : (L10n.lang == .uk ? "у" : "in")
        let keys: [(String, String)] = [
            ("+", " + "), ("−", " - "), ("×", " * "), ("÷", " / "), ("^", "^"), ("(", "("), (")", ")"),
            ("%", "%"), ("=", " = "), (":", ":"), (conv, " \(conv) "),
            ("$", "$"), ("€", "€"), ("₴", "₴"), ("usd", " usd"), ("uah", " uah"), ("eur", " eur"), ("btc", " btc"),
            ("km", " km"), ("kg", " kg"), ("h", " h"), ("min", " min"), ("#", "# "),
        ]
        for (title, insert) in keys {
            stack.addArrangedSubview(makeKey(title) { [weak self] in self?.target?.insert(insert) })
        }
        addSubview(scroll)
        scroll.addSubview(stack)
        let done = makeKey("⌄") { [weak self] in self?.target?.resignFirstResponder() }
        done.translatesAutoresizingMaskIntoConstraints = false
        addSubview(done)
        // Fixed on the left: keyboard mode, undo, redo
        let left = UIStackView()
        left.axis = .horizontal
        left.spacing = 6
        left.translatesAutoresizingMaskIntoConstraints = false
        modeKey = makeKey("abc") { [weak self] in self?.target?.toggleKeyboard() }
        left.addArrangedSubview(modeKey)
        left.addArrangedSubview(makeIconKey("arrow.uturn.backward") { [weak self] in self?.target?.undoStep() })
        left.addArrangedSubview(makeIconKey("arrow.uturn.forward") { [weak self] in self?.target?.redoStep() })
        addSubview(left)
        updateModeKey()
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            left.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            left.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            scroll.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: done.leadingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            done.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            done.centerYAnchor.constraint(equalTo: centerYAnchor),
            done.heightAnchor.constraint(equalToConstant: 36),
            heightAnchor.constraint(equalToConstant: 46),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// "abc" switches to the text keyboard, "123" back to the digits keypad.
    func updateModeKey() {
        let numeric = target?.numericKeyboard ?? true
        modeKey?.configuration?.title = numeric ? "abc" : "123"
        modeKey?.configuration?.baseBackgroundColor = UIColor(white: 0.45, alpha: 1)
        // In "123" mode the keypad has all signs; the bar only scrolls extras over the text keyboard.
        scroll?.isHidden = numeric
    }

    private func makeIconKey(_ symbol: String, action: @escaping () -> Void) -> UIButton {
        var cfg = UIButton.Configuration.plain()
        cfg.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        cfg.baseForegroundColor = UIColor(white: 0.85, alpha: 1)
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        let b = UIButton(configuration: cfg, primaryAction: UIAction { _ in
            UIDevice.current.playInputClick()
            action()
        })
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        return b
    }

    private func makeKey(_ title: String, action: @escaping () -> Void) -> UIButton {
        var cfg = UIButton.Configuration.filled()
        cfg.title = title
        cfg.baseBackgroundColor = UIColor(white: 0.32, alpha: 1)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .medium
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a
            a.font = UIFont.monospacedSystemFont(ofSize: 17, weight: .medium)
            return a
        }
        let b = UIButton(configuration: cfg, primaryAction: UIAction { _ in
            UIDevice.current.playInputClick()
            action()
        })
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        return b
    }
}

extension KeyBar: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

/// Digits keypad shown instead of the system keyboard in "123" mode.
final class NumPad: UIInputView {
    private weak var target: CalcTextView?
    private var repeatTimer: Timer?
    private let grid = UIStackView()
    private var page = 0

    init(target: CalcTextView) {
        self.target = target
        let h: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 300 : 236
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: h), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        grid.axis = .vertical
        grid.spacing = 6
        grid.distribution = .fillEqually
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 6),
            grid.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -6),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            grid.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -4),
            heightAnchor.constraint(equalToConstant: h),
        ])
        build()
    }

    /// Page 1: digits. Page 2 ("#+="): powers, currencies, units, conversion word.
    private func build() {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let sep = target?.model?.decimalSeparator == "," ? "," : "."
        let conv = L10n.lang == .ru ? "в" : (L10n.lang == .uk ? "у" : "in")
        let at = L10n.lang == .en ? "at" : "при"
        let rows: [[String]] = page == 0 ? [
            ["7", "8", "9", "÷", "⌫"],
            ["4", "5", "6", "×", "("],
            ["1", "2", "3", "−", ")"],
            ["#+=", "0", sep, "+", "⏎"],
        ] : [
            ["^", "%", "=", ":", "/", "⌫"],
            ["$", "€", "₴", "usd", "uah", "eur"],
            ["btc", "km", "kg", "h", "min", "#"],
            ["123", conv, at, "␣", "⏎"],
        ]
        for row in rows {
            let r = UIStackView()
            r.axis = .horizontal
            r.spacing = 6
            r.distribution = .fillEqually
            for k in row { r.addArrangedSubview(key(k)) }
            grid.addArrangedSubview(r)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func key(_ k: String) -> UIButton {
        let isDigit = (k.first?.isNumber == true && k != "123") || k == "." || k == ","
        var cfg = UIButton.Configuration.filled()
        cfg.title = k
        cfg.cornerStyle = .medium
        cfg.baseForegroundColor = .white
        cfg.baseBackgroundColor = k == "⏎" ? Theme.result.withAlphaComponent(0.55)
            : (isDigit ? UIColor(white: 0.36, alpha: 1) : UIColor(white: 0.24, alpha: 1))
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a
            a.font = UIFont.systemFont(ofSize: isDigit ? 26 : (k.count > 2 ? 18 : 22), weight: isDigit ? .regular : .medium)
            return a
        }
        let b = UIButton(configuration: cfg)
        if k == "⌫" {
            b.addTarget(self, action: #selector(backDown), for: .touchDown)
            b.addTarget(self, action: #selector(backUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        } else {
            b.addAction(UIAction { [weak self] _ in
                UIDevice.current.playInputClick()
                self?.press(k)
            }, for: .touchUpInside)
        }
        return b
    }

    private func press(_ k: String) {
        guard let t = target else { return }
        let conv = L10n.lang == .ru ? "в" : (L10n.lang == .uk ? "у" : "in")
        let at = L10n.lang == .en ? "at" : "при"
        switch k {
        case "#+=", "123":
            page = page == 0 ? 1 : 0
            build()
        case "⏎": t.insert("\n")
        case "=": t.insert(" = ")
        case "usd", "uah", "eur", "btc", "km", "kg", "h", "min": t.insert(" " + k)
        case conv: t.insert(" \(conv) ")
        case at: t.insert(" \(at) ")
        case "␣": t.insert(" ")
        case "/": t.insert("/")
        case "#": t.insert("# ")
        case "÷": t.insert(" / ")
        case "×": t.insert(" * ")
        case "−": t.insert(" - ")
        case "+": t.insert(" + ")
        default: t.insert(k)
        }
    }

    @objc private func backDown() {
        UIDevice.current.playInputClick()
        target?.deleteOne()
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                self?.target?.deleteOne()
            }
        }
    }

    @objc private func backUp() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

extension NumPad: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

/// SwiftUI wrapper for the editor.
struct CalcEditor: UIViewRepresentable {
    let model: CalcModel

    func makeUIView(context: Context) -> CalcTextView {
        let tv = CalcTextView(model: model)
        model.editor = tv
        return tv
    }

    func updateUIView(_ tv: CalcTextView, context: Context) {}
}
