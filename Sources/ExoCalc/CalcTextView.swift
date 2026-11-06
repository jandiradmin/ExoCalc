import AppKit
import ExoCalcCore

/// Text editor that draws each line's result right-aligned in a column on the right.
final class CalcTextView: NSTextView {
    var results: [LineResult] = []
    var lineRanges: [NSRange] = []
    var resultFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)
    var resultColumn: CGFloat = 140
    var showHints = true
    var flashLine: Int?

    var onEscape: (() -> Void)?
    var onNewline: ((Int) -> Void)?
    var onResultClick: ((Int, Bool) -> Void)?
    var completionProvider: ((String) -> [String])?

    private let rightPad: CGFloat = 18

    private struct Slot {
        let rect: NSRect
        let line: Int
        let text: NSAttributedString
        let isResult: Bool
    }
    private var slots: [Slot] = []

    // MARK: - Lines

    static func splitLines(_ ns: NSString) -> [NSRange] {
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

    func lineIndex(forChar loc: Int) -> Int {
        for (idx, r) in lineRanges.enumerated() where loc <= r.location + r.length {
            return idx
        }
        return max(0, lineRanges.count - 1)
    }

    var currentLine: Int { lineIndex(forChar: selectedRange().location) }

    private func lineHasDigit(_ r: NSRange) -> Bool {
        let ns = string as NSString
        guard r.location + r.length <= ns.length else { return false }
        return ns.substring(with: r).contains { $0.isNumber }
    }

    // MARK: - Layout of the result column

    func updateContainerWidth() {
        guard let tc = textContainer else { return }
        let w = max(80, bounds.width - resultColumn - textContainerInset.width * 2)
        if Swift.abs(tc.containerSize.width - w) > 0.5 {
            tc.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateContainerWidth()
        refreshResults()
    }

    private func computeSlots() {
        slots = []
        guard let lm = layoutManager else { return }
        let length = (string as NSString).length
        let origin = textContainerOrigin
        for (idx, r) in lineRanges.enumerated() {
            guard idx < results.count, r.location < length, r.length > 0 else { continue }
            let res = results[idx]
            let text: String
            let color: NSColor
            var isResult = true
            if let d = res.display {
                text = d
                color = Theme.result
            } else if res.error != nil && showHints && lineHasDigit(r) {
                text = "?"
                color = Theme.hint
                isResult = false
            } else {
                continue
            }
            let gi = lm.glyphIndexForCharacter(at: r.location)
            let frag = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
            let glyphLoc = lm.location(forGlyphAt: gi)
            let attr = NSAttributedString(string: text, attributes: [.font: resultFont, .foregroundColor: color])
            let size = attr.size()
            let x = bounds.width - rightPad - size.width
            let y = frag.minY + origin.y + glyphLoc.y - resultFont.ascender
            slots.append(Slot(rect: NSRect(x: x, y: y, width: size.width, height: size.height),
                              line: idx, text: attr, isResult: isResult))
        }
    }

    /// Results are drawn by a transparent overlay placed above the scroll view
    /// (drawing inside NSTextView is not shown on recent macOS).
    weak var overlay: ResultOverlay?

    func debugSlots() -> String {
        computeSlots()
        let first = slots.first.map { "\($0.rect) \($0.text.string)" } ?? "none"
        return "bounds=\(bounds) slots=\(slots.count) first=\(first) overlay=\(String(describing: overlay?.frame)) draws=\(ResultOverlay.drawCount)"
    }

    func refreshResults() {
        computeSlots()
        overlay?.needsDisplay = true
    }

    fileprivate func drawResults(in view: NSView, _ dirtyRect: NSRect) {
        computeSlots()
        for s in slots {
            let r = convert(s.rect, to: view)
            guard r.insetBy(dx: -8, dy: -4).intersects(dirtyRect) else { continue }
            if s.line == flashLine {
                NSColor(white: 1, alpha: 0.14).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: -6, dy: -1), xRadius: 4, yRadius: 4).fill()
            }
            s.text.draw(at: r.origin)
        }
    }

    func flash(_ line: Int) {
        flashLine = line
        refreshResults()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.flashLine = nil
            self?.refreshResults()
        }
    }

    // MARK: - Mouse

    /// Generous click area around a result: a bit wider and the full line height.
    private func hitRect(_ s: Slot) -> NSRect {
        NSRect(x: s.rect.minX - 12, y: s.rect.minY - 4,
               width: bounds.width - s.rect.minX + 12, height: s.rect.height + 8)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let mods = event.modifierFlags
        if let s = slots.first(where: { $0.isResult && hitRect($0).contains(p) }) {
            onResultClick?(s.line, mods.contains(.shift) || mods.contains(.command))
            flash(s.line)
            return
        }
        // ⌘-click on an expression copies "expression = result"
        if mods.contains(.command) && !mods.contains(.shift) {
            let ch = characterIndexForInsertion(at: p)
            let line = lineIndex(forChar: ch)
            if line < results.count, results[line].display != nil {
                onResultClick?(line, true)
                flash(line)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for s in slots where s.isResult {
            addCursorRect(hitRect(s), cursor: .pointingHand)
        }
    }

    // MARK: - Keys

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func insertNewline(_ sender: Any?) {
        onNewline?(currentLine)
        super.insertNewline(sender)
    }

    override func completions(forPartialWordRange charRange: NSRange,
                              indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        let partial = (string as NSString).substring(with: charRange)
        guard let list = completionProvider?(partial), !list.isEmpty else { return nil }
        index.pointee = 0
        return list
    }
}

final class ResultOverlay: NSView {
    static var drawCount = 0
    weak var owner: CalcTextView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        ResultOverlay.drawCount += 1
        owner?.drawResults(in: self, dirtyRect)
    }
}
