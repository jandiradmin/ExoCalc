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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        computeSlots()
        for s in slots where s.rect.insetBy(dx: -8, dy: -4).intersects(dirtyRect) {
            if s.line == flashLine {
                NSColor(white: 1, alpha: 0.14).setFill()
                NSBezierPath(roundedRect: s.rect.insetBy(dx: -6, dy: -1), xRadius: 4, yRadius: 4).fill()
            }
            s.text.draw(at: s.rect.origin)
        }
    }

    func flash(_ line: Int) {
        flashLine = line
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.flashLine = nil
            self?.needsDisplay = true
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let s = slots.first(where: { $0.isResult && $0.rect.insetBy(dx: -6, dy: -3).contains(p) }) {
            let full = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            onResultClick?(s.line, full)
            flash(s.line)
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for s in slots where s.isResult {
            addCursorRect(s.rect.insetBy(dx: -6, dy: -3), cursor: .pointingHand)
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
