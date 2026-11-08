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
        keyboardType = .numbersAndPunctuation
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

    func insert(_ s: String) {
        insertText(s)
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

    init(target: CalcTextView) {
        self.target = target
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 46), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        let scroll = UIScrollView()
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
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
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
