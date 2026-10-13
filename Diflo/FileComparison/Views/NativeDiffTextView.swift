import AppKit

/// TextKit 2 exclusively. Decorations never mutate the document's attributed storage.
final class NativeDiffTextView: NSTextView {
    var lineIndex = TextLineIndex(normalizedText: "")
    var changedLines: [(Range<Int>, NSColor)] = []
    var inlineRanges: [NSRange] = []
    private(set) var geometry = DiffViewportGeometry()
    var onGeometryChanged: (() -> Void)?
    private var inlineRects: [CGRect] = []
    private let localUndoManager = UndoManager()
    override var undoManager: UndoManager? { super.undoManager ?? localUndoManager }

    convenience init(usingTextLayoutManager: Bool) {
        let storage = NSTextContentStorage()
        let manager = NSTextLayoutManager()
        storage.addTextLayoutManager(manager)
        let container = NSTextContainer(size: NSSize(width: 10000000, height: 10000000))
        manager.textContainer = container
        self.init(frame: .zero, textContainer: container)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); configure() }

    private func configure() {
        isEditable = true
        isSelectable = true
        allowsUndo = true
        isRichText = false
        importsGraphics = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textContainerInset = NSSize(width: 48, height: 10)
        isHorizontallyResizable = true
        isVerticallyResizable = true
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = false
        textContainer?.containerSize = maxSize
        autoresizingMask = [.width]
    }

    func applyExternalText(_ text: String, undoable: Bool) {
        guard string != text, !hasMarkedText() else { return }
        let selection = selectedRange()
        if undoable {
            let whole = NSRange(location: 0, length: (string as NSString).length)
            if shouldChangeText(in: whole, replacementString: text) {
                replaceCharacters(in: whole, with: text)
                didChangeText()
            }
        } else { string = text; undoManager?.removeAllActions() }
        setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
    }

    override func layout() {
        super.layout()
        refreshGeometry()
    }

    func refreshGeometry() {
        ComparisonDiagnostics.measure("ViewportUpdate") { collectGeometry() }
    }

    private func collectGeometry() {
        guard let manager = textLayoutManager, let content = manager.textContentManager,
              let viewport = manager.textViewportLayoutController.viewportRange else { return }
        var rects: [Int: CGRect] = [:]
        let origin = textContainerOrigin
        manager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
            let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            for line in fragment.textLineFragments {
                let offset = start + line.characterRange.location
                let logical = self.lineIndex.line(containingUTF16Offset: offset)
                let rect = line.typographicBounds.offsetBy(dx: fragment.layoutFragmentFrame.minX + origin.x, dy: fragment.layoutFragmentFrame.minY + origin.y)
                if rect.intersects(self.visibleRect) { rects[logical] = rects[logical].map { $0.union(rect) } ?? rect }
            }
            return fragment.rangeInElement.endLocation.compare(viewport.endLocation) == .orderedAscending
        }
        let first = rects.keys.min() ?? 0
        geometry = DiffViewportGeometry(visibleLines: first..<((rects.keys.max().map { $0 + 1 }) ?? first), lineRects: rects)
        inlineRects.removeAll(keepingCapacity: true)
        let visibleStart = content.offset(from: content.documentRange.location, to: viewport.location)
        let visibleEnd = content.offset(from: content.documentRange.location, to: viewport.endLocation)
        for range in inlineRanges {
            let clipped = NSIntersectionRange(range, NSRange(location: visibleStart, length: max(0, visibleEnd - visibleStart)))
            guard clipped.length > 0,
                  let start = content.location(content.documentRange.location, offsetBy: clipped.location),
                  let end = content.location(start, offsetBy: clipped.length),
                  let textRange = NSTextRange(location: start, end: end) else { continue }
            manager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, rect, _, _ in
                self.inlineRects.append(rect.offsetBy(dx: origin.x, dy: origin.y))
                return true
            }
        }
        needsDisplay = true
        onGeometryChanged?()
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        var first = 0, end = changedLines.count
        while first < end {
            let middle = (first + end) / 2
            if changedLines[middle].0.upperBound < geometry.visibleLines.lowerBound { first = middle + 1 } else { end = middle }
        }
        for (range, color) in changedLines[first...] {
            if range.lowerBound > geometry.visibleLines.upperBound { break }
            guard let region = geometry.rect(for: range) else { continue }
            color.withAlphaComponent(0.14).setFill()
            NSRect(x: visibleRect.minX, y: region.minY, width: visibleRect.width, height: region.height).intersection(rect).fill()
        }
        NSColor.systemBlue.withAlphaComponent(0.24).setFill()
        for region in inlineRects where region.intersects(rect) { region.fill() }
        for (line, region) in geometry.lineRects where region.intersects(rect) {
            let label = "\(line + 1)" as NSString
            label.draw(at: NSPoint(x: visibleRect.minX + 6, y: region.minY), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
        }
    }

    func navigate(to line: Int) {
        let starts = lineIndex.utf16Starts
        let offset = starts.indices.contains(line) ? starts[line] : (string as NSString).length
        scrollRangeToVisible(NSRange(location: offset, length: 0))
        needsLayout = true
        layoutSubtreeIfNeeded()
        refreshGeometry()
    }
}
