import AppKit

final class DiffTextView: NSTextView {
    static let editorFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    static let rowHeight = ceil(NSLayoutManager().defaultLineHeight(for: editorFont)) + 2
    static let verticalInset: CGFloat = 8.0
    static let gutterWidth: CGFloat = 46.0

    static func diffBandRect(for lines: Range<Int>, width: CGFloat, offset: CGFloat = 0) -> NSRect {
        let y = verticalInset + CGFloat(lines.lowerBound) * rowHeight - offset
        return NSRect(x: 0, y: lines.isEmpty ? y - 1 : y, width: width,
                      height: lines.isEmpty ? 2 : CGFloat(lines.count) * rowHeight)
    }

    private var textStorageHolder: NSTextStorage?
    private var rowHighlights: [DiffRowPresentation.Highlight] = []
    private var selectedRows: Range<Int>?
    private var emptyHighlights: [(Int, DiffRowPresentation.Highlight)] = []
    private var lineCount: Int = 1
    private let localUndoManager = UndoManager()
    var sharedUndoManager: UndoManager?
    override var undoManager: UndoManager? { sharedUndoManager ?? localUndoManager }
    private(set) var lineIndex = TextLineIndex(normalizedText: "")
    private var indexedText = ""
    private var decorationHunks: [DiffHunk] = []
    private var decorationSide: ComparisonSide = .left
    private var decorationLineCount = 0
    private let inlineWorker = InlineDiffWorker()
    private var inlineTask: Task<Void, Never>?
    private var inlineGeneration = 0
    private var inlineRanges: [NSRange] = []
    private var oppositeLines: [String] = []
    private var inlineInputText: String?
    private var inlineInputHunks: [DiffHunk] = []
    private var inlineInputOpposite: [String] = []
    private var inlineInputSide: ComparisonSide = .left
    private var inlineVisibleLines: Range<Int>?

    deinit {
        inlineTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        if let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged), name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    @objc private func viewportChanged() { refreshInlineHighlights() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        inlineVisibleLines = nil
        refreshInlineHighlights()
        needsDisplay = true
    }

    override func didChangeText() {
        if !hasMarkedText() {
            synchronizeLineIndex()
            typingAttributes = baseAttributes
            inlineVisibleLines = nil
        }
        super.didChangeText()
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: Self.editorFont, .foregroundColor: NSColor.textColor,
         .paragraphStyle: defaultParagraphStyle ?? NSParagraphStyle.default]
    }

    private func synchronizeLineIndex(_ supplied: TextLineIndex? = nil) {
        let text = string
        if indexedText != text {
            indexedText = text
            lineIndex = supplied ?? TextLineIndex(normalizedText: text)
        }
    }

    func applyExternalText(_ text: String, undoable: Bool) {
        guard string != text, !hasMarkedText() else { return }
        clearInlineHighlights()
        let selection = selectedRange()
        if undoable {
            applyUndoableText(text, selection: NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            return
        } else {
            textStorage?.setAttributedString(NSAttributedString(string: text, attributes: baseAttributes))
            undoManager?.removeAllActions()
        }
        synchronizeLineIndex()
        setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
    }

    private func applyUndoableText(_ text: String, selection: NSRange) {
        let previousText = string
        let previousSelection = selectedRange()
        let manager = undoManager
        breakUndoCoalescing()
        // Native whole-document undo selects the entire restored text. Record the
        // selection explicitly and suppress that native undo entry.
        manager?.disableUndoRegistration()
        let range = NSRange(location: 0, length: (previousText as NSString).length)
        let accepted = shouldChangeText(in: range, replacementString: text)
        if accepted { replaceCharacters(in: range, with: text) }
        manager?.enableUndoRegistration()
        guard accepted else { return }
        manager?.registerUndo(withTarget: self) { editor in
            editor.applyUndoableText(previousText, selection: previousSelection)
        }
        synchronizeLineIndex()
        setSelectedRange(selection)
        didChangeText()
        breakUndoCoalescing()
    }

    var placeholderString: String? {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func cursorUpdate(with event: NSEvent) {
        if let scroll = enclosingScrollView as? DiffOverlayScrollView {
            scroll.updatePointerCursor(with: event)
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        (enclosingScrollView as? DiffOverlayScrollView)?.updatePointerCursor(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = true
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        breakUndoCoalescing()
        let accepted = super.resignFirstResponder()
        needsDisplay = true
        return accepted
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) { undoManager?.redo() }
            else { undoManager?.undo() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    static func createStandard(side: ComparisonSide) -> DiffTextView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        )
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = DiffTextView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 600),
            textContainer: textContainer
        )
        textView.textStorageHolder = textStorage
        textView.font = Self.editorFont
        textView.textColor = NSColor.textColor
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Self.rowHeight
        paragraph.maximumLineHeight = Self.rowHeight
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: textView.font!, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        textView.textContainerInset = NSSize(width: 0, height: Self.verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 10_000_000, height: CGFloat.greatestFiniteMagnitude)
        textView.placeholderString = side == .left ? "输入或粘贴左侧文本..." : "输入或粘贴右侧文本..."
        let accessibilityName = side == .left ? "左侧文件内容" : "右侧文件内容"
        textView.setAccessibilityIdentifier(accessibilityName)
        textView.setAccessibilityLabel(accessibilityName)
        return textView
    }

    // MARK: - 数据配置与行高锁定

    func configure(
        text: String,
        lineCount: Int,
        hunks: [DiffHunk],
        side: ComparisonSide,
        selectedHunkID: DiffHunk.ID?,
        oppositeLines: [String] = [],
        undoable: Bool = false,
        lineIndex: TextLineIndex? = nil
    ) {
        guard !hasMarkedText() else { return }
        self.lineCount = max(1, lineCount)
        updateHighlightsArray(lineCount: self.lineCount, hunks: hunks, side: side, selectedHunkID: selectedHunkID)

        if indexedText != text {
            applyExternalText(text, undoable: undoable)
            indexedText = text
            if let lineIndex { self.lineIndex = lineIndex }
        }
        self.oppositeLines = oppositeLines
        refreshInlineHighlights()

        let accessibilityName = side == .left ? "左侧文件内容" : "右侧文件内容"
        setAccessibilityIdentifier(accessibilityName)
        setAccessibilityLabel(accessibilityName)
        needsDisplay = true
    }

    func updateDiffHighlights(
        lineCount: Int,
        hunks: [DiffHunk],
        side: ComparisonSide,
        selectedHunkID: DiffHunk.ID?,
        oppositeLines: [String] = []
    ) {
        guard !hasMarkedText() else { return }
        self.lineCount = max(1, lineCount)
        updateHighlightsArray(lineCount: self.lineCount, hunks: hunks, side: side, selectedHunkID: selectedHunkID)
        synchronizeLineIndex()
        self.oppositeLines = oppositeLines
        refreshInlineHighlights()
        needsDisplay = true
    }

    private func updateHighlightsArray(lineCount: Int, hunks: [DiffHunk], side: ComparisonSide, selectedHunkID: DiffHunk.ID?) {
        if decorationHunks != hunks || decorationSide != side || decorationLineCount != lineCount {
            decorationHunks = hunks
            decorationSide = side
            decorationLineCount = lineCount
            rowHighlights = Array(repeating: .none, count: max(1, lineCount))
            emptyHighlights = []
            for hunk in hunks {
                let range = side == .left ? hunk.leftLineRange : hunk.rightLineRange
                let highlight: DiffRowPresentation.Highlight
                switch hunk.kind {
                case .leftOnly: highlight = .deletion
                case .rightOnly: highlight = .insertion
                case .modified: highlight = .modification
                }
                if range.isEmpty { emptyHighlights.append((range.lowerBound, highlight)) }
                for index in range where index < rowHighlights.count {
                    rowHighlights[index] = highlight
                }
            }
        }
        selectedRows = hunks.first { $0.id == selectedHunkID }.map {
            side == .left ? $0.leftLineRange : $0.rightLineRange
        }
    }

    override func drawBackground(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds.intersection(rect)).addClip()
        super.drawBackground(in: rect)
        let first = max(0, Int(floor((rect.minY - Self.verticalInset) / Self.rowHeight)))
        let end = min(rowHighlights.count, Int(ceil((rect.maxY - Self.verticalInset) / Self.rowHeight)))
        if first < end {
            for row in first..<end {
                guard let color = Self.backgroundColor(for: rowHighlights[row], appearance: effectiveAppearance) else { continue }
                let band = NSRect(x: bounds.minX, y: Self.verticalInset + CGFloat(row) * Self.rowHeight, width: bounds.width, height: Self.rowHeight)
                color.setFill()
                band.fill()
                color.blended(withFraction: 0.25, of: .labelColor)?.setFill()
                if row == 0 || rowHighlights[row - 1] != rowHighlights[row] {
                    NSRect(x: band.minX, y: band.minY, width: band.width, height: 0.5).fill()
                }
                if row + 1 == rowHighlights.count || rowHighlights[row + 1] != rowHighlights[row] {
                    NSRect(x: band.minX, y: band.maxY - 0.5, width: band.width, height: 0.5).fill()
                }
            }
        }
        if window?.firstResponder === self {
            let line = lineIndex.line(containingUTF16Offset: selectedRange().location)
            let band = Self.diffBandRect(for: line..<(line + 1), width: bounds.width).insetBy(dx: 0, dy: 0.5)
            if band.intersects(rect) {
                let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                NSColor.systemYellow.withAlphaComponent(dark ? 0.16 : 0.20).setFill()
                band.fill()
            }
        }
        if let selectedRows, !selectedRows.isEmpty {
            let block = NSRect(x: bounds.minX, y: Self.verticalInset + CGFloat(selectedRows.lowerBound) * Self.rowHeight,
                               width: bounds.width, height: CGFloat(selectedRows.count) * Self.rowHeight)
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: block.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            outline.stroke()
        }
        for (line, highlight) in emptyHighlights {
            let y = Self.verticalInset + CGFloat(line) * Self.rowHeight
            guard y >= rect.minY - 2, y <= rect.maxY + 2,
                  let color = Self.backgroundColor(for: highlight, appearance: effectiveAppearance) else { continue }
            color.setFill()
            let band = Self.diffBandRect(for: line..<line, width: bounds.width)
            band.fill()
            let selected = selectedRows?.isEmpty == true && selectedRows?.lowerBound == line
            let edgeHeight: CGFloat = selected ? 1 : 0.5
            (selected ? NSColor.controlAccentColor : color.blended(withFraction: 0.25, of: .labelColor) ?? color).setFill()
            NSRect(x: band.minX, y: band.minY, width: band.width, height: edgeHeight).fill()
            NSRect(x: band.minX, y: band.maxY - edgeHeight, width: band.width, height: edgeHeight).fill()
        }
    }

    // Only visible changed lines are refined off the main actor. Decorations never edit text storage.
    private func clearInlineHighlights() {
        inlineTask?.cancel()
        inlineGeneration += 1
        removeInlineHighlights()
    }

    private func removeInlineHighlights() {
        let document = NSRange(location: 0, length: (string as NSString).length)
        for range in inlineRanges {
            let clipped = NSIntersectionRange(range, document)
            if clipped.length > 0 { layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: clipped) }
        }
        inlineRanges = []
    }

    func refreshInlineHighlights() {
        guard !hasMarkedText() else { inlineVisibleLines = nil; return }
        let viewport = visibleRect
        guard viewport.minY.isFinite, viewport.maxY.isFinite, Self.rowHeight > 0 else { return }
        let first = Int(min(CGFloat(lineIndex.lines.count), max(0, floor((viewport.minY - Self.verticalInset) / Self.rowHeight))))
        let end = Int(min(CGFloat(lineIndex.lines.count), max(CGFloat(first), ceil((viewport.maxY - Self.verticalInset) / Self.rowHeight))))
        let visible = first..<end
        let text = indexedText
        let inputsChanged = inlineInputText != text || inlineInputHunks != decorationHunks ||
            inlineInputSide != decorationSide || inlineInputOpposite != oppositeLines
        guard inlineVisibleLines != visible || inputsChanged else { return }
        if inputsChanged {
            clearInlineHighlights()
        } else {
            // Scrolling changes the work to request, not the validity of existing decorations.
            inlineTask?.cancel()
            inlineGeneration += 1
        }
        inlineVisibleLines = visible
        inlineInputText = text
        inlineInputHunks = decorationHunks
        inlineInputOpposite = oppositeLines
        inlineInputSide = decorationSide
        let blocks = decorationHunks.filter { $0.kind == .modified && (decorationSide == .left ? $0.leftLineRange : $0.rightLineRange).overlaps(visible) }
        guard !blocks.isEmpty, !oppositeLines.isEmpty else { return }
        let generation = inlineGeneration
        let index = lineIndex
        let opposite = oppositeLines
        let side = decorationSide
        let worker = inlineWorker
        inlineTask = Task { [weak self] in
            var ranges: [NSRange] = []
            for block in blocks {
                let current = side == .left ? block.leftLineRange : block.rightLineRange
                for line in max(current.lowerBound, visible.lowerBound)..<min(current.upperBound, visible.upperBound) {
                    guard !Task.isCancelled else { return }
                    let otherLine = (side == .left ? block.rightLineRange.lowerBound : block.leftLineRange.lowerBound) + line - current.lowerBound
                    let otherRange = side == .left ? block.rightLineRange : block.leftLineRange
                    guard otherRange.contains(otherLine), index.lines.indices.contains(line), opposite.indices.contains(otherLine) else { continue }
                    let ownText = index.lines[line], otherText = opposite[otherLine]
                    guard let result = try? await worker.compare(left: side == .left ? ownText : otherText, right: side == .right ? ownText : otherText) else { return }
                    let changes = side == .left ? result.leftRanges : result.rightRanges
                    ranges += changes.map { NSRange(location: index.utf16Starts[line] + $0.location, length: $0.length) }
                }
            }
            guard let self, !Task.isCancelled, self.inlineGeneration == generation, self.string == text else { return }
            guard !self.hasMarkedText() else { self.inlineVisibleLines = nil; return }
            // Replace decorations together on the main actor, without an empty frame in between.
            self.removeInlineHighlights()
            let isDark = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let color = isDark ? NSColor(red: 0.14, green: 0.32, blue: 0.49, alpha: 0.9) : NSColor(red: 0.54, green: 0.76, blue: 1, alpha: 0.65)
            for range in ranges where NSMaxRange(range) <= index.utf16Count {
                self.layoutManager?.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
            }
            self.inlineRanges = ranges
            self.needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    func fittedInsertionPointRect(_ rect: NSRect) -> NSRect {
        let fontHeight = ceil((layoutManager ?? NSLayoutManager()).defaultLineHeight(for: font ?? Self.editorFont))
        let height = min(rect.height, fontHeight)
        return NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: fittedInsertionPointRect(rect), color: color, turnedOn: flag)
    }

    func resizeDocument(minimumSize: NSSize) {
        guard let scrollView = enclosingScrollView ?? (superview as? NSClipView)?.superview as? NSScrollView else { return }
        let viewportSize = scrollView.contentSize
        let minHeight = max(minimumSize.height, viewportSize.height, 200)

        guard let textContainer, let layoutManager else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let newWidth = max(viewportSize.width, ceil(usedRect.maxX + textContainerInset.width * 2), 200)
        let usedHeight = ceil(usedRect.height + textContainerInset.height * 2)
        let neededHeight = Self.verticalInset * 2 + CGFloat(max(1, lineCount)) * Self.rowHeight
        let newHeight = max(minHeight, usedHeight, neededHeight)

        let targetFrame = NSRect(x: 0, y: 0, width: newWidth, height: newHeight)
        if frame != targetFrame {
            frame = targetFrame
        }
        refreshInlineHighlights()
    }

    static func backgroundColor(for highlight: DiffRowPresentation.Highlight, appearance: NSAppearance) -> NSColor? {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch highlight {
        case .none:
            return nil
        case .insertion:
            return isDark
                ? NSColor(red: 0x12 / 255.0, green: 0x38 / 255.0, blue: 0x06 / 255.0, alpha: 0.85)
                : NSColor(red: 0xd0 / 255.0, green: 0xff / 255.0, blue: 0xa3 / 255.0, alpha: 0.45)
        case .deletion:
            return isDark
                ? NSColor(red: 0x7a / 255.0, green: 0x2a / 255.0, blue: 0x28 / 255.0, alpha: 0.85)
                : NSColor(red: 0xff / 255.0, green: 0xa5 / 255.0, blue: 0xa3 / 255.0, alpha: 0.45)
        case .modification:
            return isDark
                ? NSColor(red: 0x00 / 255.0, green: 0x32 / 255.0, blue: 0x66 / 255.0, alpha: 0.85)
                : NSColor(red: 0xbd / 255.0, green: 0xdd / 255.0, blue: 0xff / 255.0, alpha: 0.45)
        }
    }
}
