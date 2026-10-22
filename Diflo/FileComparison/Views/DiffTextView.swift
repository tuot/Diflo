import AppKit
import CoreText

final class DiffTextView: NSTextView {
    static let editorFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    static let fontHeight = ceil(editorFont.ascender - editorFont.descender + editorFont.leading)
    static let rowHeight = fontHeight + 2
    static let verticalInset: CGFloat = 8.0
    static let gutterWidth: CGFloat = 46.0

    static func diffBandRect(for lines: Range<Int>, width: CGFloat, offset: CGFloat = 0) -> NSRect {
        let y = verticalInset + CGFloat(lines.lowerBound) * rowHeight - offset
        return NSRect(x: 0, y: lines.isEmpty ? y - 1 : y, width: width,
                      height: lines.isEmpty ? 2 : CGFloat(lines.count) * rowHeight)
    }

    private(set) var wrapsLines = false
    private var showsWhitespace = false
    private var preferredTabWidth = 4
    var effectiveRowHeight: CGFloat {
        let font = font ?? Self.editorFont
        return ceil(font.ascender - font.descender + font.leading) + 2
    }

    func applyPreferences(fontSize: Double, tabWidth: Int, wrapLines: Bool, showWhitespace: Bool) {
        guard !hasMarkedText() else { return }
        let nextFont = NSFont.monospacedSystemFont(ofSize: min(28, max(10, fontSize)), weight: .regular)
        guard font != nextFont || wrapsLines != wrapLines || showsWhitespace != showWhitespace || preferredTabWidth != tabWidth else { return }
        font = nextFont
        wrapsLines = wrapLines
        showsWhitespace = showWhitespace
        preferredTabWidth = tabWidth
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = effectiveRowHeight
        paragraph.maximumLineHeight = effectiveRowHeight
        paragraph.defaultTabInterval = (" " as NSString).size(withAttributes: [.font: nextFont]).width * CGFloat(tabWidth)
        paragraph.tabStops = []
        paragraph.lineBreakMode = wrapLines ? .byWordWrapping : .byClipping
        defaultParagraphStyle = paragraph
        textStorage?.addAttributes([.font: nextFont, .paragraphStyle: paragraph], range: NSRange(location: 0, length: (string as NSString).length))
        typingAttributes = baseAttributes
        measuredWidth = nil; lineWidthCache.removeAll(); inlineVisibleLines = nil
        resizeDocument(minimumSize: enclosingScrollView?.contentSize ?? frame.size)
        needsDisplay = true
    }

    func lineY(_ line: Int) -> CGFloat {
        if !wrapsLines { return Self.verticalInset + CGFloat(line) * effectiveRowHeight }
        if line < lineIndex.utf16Starts.count, let rect = lineRect(at: max(0, line)) { return rect.minY }
        if let last = lineRect(at: max(0, lineIndex.utf16Starts.count - 1)) { return last.maxY }
        return Self.verticalInset
    }

    func bandRect(for lines: Range<Int>, width: CGFloat, offset: CGFloat = 0) -> NSRect {
        let top = lineY(lines.lowerBound) - offset
        return NSRect(x: 0, y: lines.isEmpty ? top - 1 : top, width: width,
                      height: lines.isEmpty ? 2 : max(effectiveRowHeight, lineY(lines.upperBound) - lineY(lines.lowerBound)))
    }

    private func visibleLogicalLines(in rect: NSRect) -> Range<Int> {
        let count = lineIndex.utf16Starts.count
        if !wrapsLines {
            let first = Int(min(CGFloat(count), max(0, floor((rect.minY - Self.verticalInset) / effectiveRowHeight))))
            let end = Int(min(CGFloat(count), max(CGFloat(first), ceil((rect.maxY - Self.verticalInset) / effectiveRowHeight) + 1)))
            return first..<end
        }
        func find(_ y: CGFloat) -> Int {
            var low = 0, high = count
            while low < high { let middle = (low + high) / 2; if lineY(middle) < y { low = middle + 1 } else { high = middle } }
            return low
        }
        let first = max(0, find(rect.minY) - 1)
        return first..<min(count, max(first, find(rect.maxY) + 1))
    }

    private var contentStorageHolder: NSTextContentStorage?
    private var measuredWidth: CGFloat?
    private var lineWidthCache: [String: CGFloat] = [:]
    private var rowHighlights: [DiffRowPresentation.Highlight] = []
    private var selectedRows: Range<Int>?
    private var emptyHighlights: [(Int, DiffRowPresentation.Highlight)] = []
    private var lineCount: Int = 1
    private let localUndoManager = UndoManager()
    var onFocus: (() -> Void)?
    var sharedUndoManager: UndoManager?
    override var undoManager: UndoManager? { sharedUndoManager ?? localUndoManager }
    // NSTextView's default origin getter can force complete document layout.
    // This editor pins its unwrapped container to these fixed insets.
    override var textContainerOrigin: NSPoint {
        NSPoint(x: textContainerInset.width, y: textContainerInset.height)
    }
    private(set) var lineIndex = TextLineIndex(normalizedText: "")
    private var indexedText = ""
    private var decorationHunks: [DiffHunk] = []
    private var decorationSide: ComparisonSide = .left
    private var decorationLineCount = 0
    private let inlineWorker = InlineDiffWorker()
    private var inlineTask: Task<Void, Never>?
    private var inlineGeneration = 0
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
        [.font: font ?? Self.editorFont, .foregroundColor: NSColor.textColor,
         .paragraphStyle: defaultParagraphStyle ?? NSParagraphStyle.default]
    }

    private func synchronizeLineIndex(_ supplied: TextLineIndex? = nil) {
        let text = string
        if indexedText != text {
            indexedText = text
            measuredWidth = nil
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

    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard isEditable, !hasMarkedText(), let text = pasteboard.string(forType: type) else { return false }
        insertText(text, replacementRange: selectedRange())
        return true
    }

    @objc func pasteFormatted(_ sender: Any?) { _ = readFormattedSelection(from: .general) }
    @discardableResult func readFormattedSelection(from pasteboard: NSPasteboard) -> Bool {
        guard isEditable, !hasMarkedText(), let source = pasteboard.string(forType: .string) else { return false }
        let text = PasteFormatter.format(source) ?? source
        if selectedRange() == NSRange(location: 0, length: (string as NSString).length) {
            applyUndoableText(text, selection: NSRange(location: (text as NSString).length, length: 0))
        } else { insertText(source, replacementRange: selectedRange()) }
        return true
    }

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
        if accepted { onFocus?() }
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
        let textView = DiffTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
        textView.contentStorageHolder = textView.textLayoutManager?.textContentManager as? NSTextContentStorage
        textView.font = Self.editorFont
        textView.textColor = NSColor.textColor
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Self.rowHeight
        paragraph.maximumLineHeight = Self.rowHeight
        paragraph.alignment = .left
        // Continue the system's 28pt tab stops beyond its finite default list.
        paragraph.defaultTabInterval = 28
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
        let visible = visibleLogicalLines(in: rect)
        let first = min(rowHighlights.count, visible.lowerBound)
        let end = min(rowHighlights.count, visible.upperBound)
        if first < end {
            for row in first..<end {
                guard let color = Self.backgroundColor(for: rowHighlights[row], appearance: effectiveAppearance) else { continue }
                let band = bandRect(for: row..<(row + 1), width: bounds.width)
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
            let row = lineRect(at: line) ?? Self.diffBandRect(for: line..<(line + 1), width: bounds.width)
            let band = NSRect(x: bounds.minX, y: row.minY, width: bounds.width, height: row.height).insetBy(dx: 0, dy: 0.5)
            if band.intersects(rect) {
                let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                NSColor.systemYellow.withAlphaComponent(dark ? 0.16 : 0.20).setFill()
                band.fill()
            }
        }
        if let selectedRows, !selectedRows.isEmpty {
            let block = bandRect(for: selectedRows, width: bounds.width)
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: block.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            outline.stroke()
        }
        for (line, highlight) in emptyHighlights {
            let y = lineY(line)
            guard y >= rect.minY - 2, y <= rect.maxY + 2,
                  let color = Self.backgroundColor(for: highlight, appearance: effectiveAppearance) else { continue }
            color.setFill()
            let band = bandRect(for: line..<line, width: bounds.width)
            band.fill()
            let selected = selectedRows?.isEmpty == true && selectedRows?.lowerBound == line
            let edgeHeight: CGFloat = selected ? 1 : 0.5
            (selected ? NSColor.controlAccentColor : color.blended(withFraction: 0.25, of: .labelColor) ?? color).setFill()
            NSRect(x: band.minX, y: band.minY, width: band.width, height: edgeHeight).fill()
            NSRect(x: band.minX, y: band.maxY - edgeHeight, width: band.width, height: edgeHeight).fill()
        }
        drawWhitespace(in: rect)
    }

    // Only visible changed lines are refined off the main actor. Decorations never edit text storage.
    private func clearInlineHighlights() {
        inlineTask?.cancel()
        inlineGeneration += 1
        removeInlineHighlights()
    }

    private func removeInlineHighlights() {
        guard let manager = textLayoutManager, let content = manager.textContentManager else { return }
        // Rendering ranges move with native edits. Clearing by old NSRange offsets
        // leaves highlights behind when text is inserted before them.
        manager.removeRenderingAttribute(.backgroundColor, for: content.documentRange)
    }

    func refreshInlineHighlights() {
        guard !hasMarkedText() else { inlineVisibleLines = nil; return }
        let viewport = visibleRect
        guard viewport.minY.isFinite, viewport.maxY.isFinite, effectiveRowHeight > 0 else { return }
        let logicalVisible = visibleLogicalLines(in: viewport)
        let first = min(lineIndex.lines.count, logicalVisible.lowerBound)
        let end = min(lineIndex.lines.count, logicalVisible.upperBound)
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
                if let textRange = self.textRange(for: range) {
                    self.textLayoutManager?.addRenderingAttribute(.backgroundColor, value: color, for: textRange)
                }
            }
            self.needsDisplay = true
        }
    }

    private func textRange(for range: NSRange) -> NSTextRange? {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              NSMaxRange(range) <= (string as NSString).length,
              let content = textLayoutManager?.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    /// TextKit 2 row geometry, with fixed-height geometry for its empty extra row.
    func lineRect(at line: Int) -> NSRect? {
        guard lineIndex.utf16Starts.indices.contains(line),
              let manager = textLayoutManager,
              let content = manager.textContentManager,
              let range = textRange(for: NSRange(location: lineIndex.utf16Starts[line], length: 0)) else { return nil }
        let offset = lineIndex.utf16Starts[line]
        // Requesting ensuresExtraLineFragment forces layout through the document
        // end. Its empty row has known geometry because this editor never wraps.
        if offset == lineIndex.utf16Count {
            let y: CGFloat
            if wrapsLines && line > 0 { y = lineRect(at: line - 1)?.maxY ?? Self.verticalInset }
            else { y = Self.verticalInset + CGFloat(line) * effectiveRowHeight }
            return NSRect(x: textContainerOrigin.x, y: y, width: 0, height: effectiveRowHeight)
        }
        var rect: NSRect?
        manager.enumerateTextLayoutFragments(from: range.location, options: [.ensuresLayout]) { fragment in
            let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let localOffset = offset - start
            if self.wrapsLines {
                rect = fragment.layoutFragmentFrame.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
                return false
            }
            if let row = fragment.textLineFragments.first(where: {
                NSLocationInRange(localOffset, $0.characterRange) || ($0.characterRange.length == 0 && localOffset == $0.characterRange.location)
            }) {
                rect = row.typographicBounds.offsetBy(dx: fragment.layoutFragmentFrame.minX + self.textContainerOrigin.x,
                                                     dy: fragment.layoutFragmentFrame.minY + self.textContainerOrigin.y)
            }
            return false
        }
        return rect
    }

    @objc func goToLine(_ sender: Any?) {
        guard let window else { return }
        let field = NSTextField(string: "")
        field.placeholderString = "1–\(lineIndex.utf16Starts.count)"
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        let alert = NSAlert()
        alert.messageText = String(localized: "行号跳转")
        alert.accessoryView = field
        alert.addButton(withTitle: "跳转"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            guard let line = Int(field.stringValue), self.lineIndex.utf16Starts.indices.contains(line - 1) else { NSSound.beep(); return }
            let range = NSRange(location: self.lineIndex.utf16Starts[line - 1], length: 0)
            self.setSelectedRange(range); self.scrollRangeToVisible(range)
            self.window?.makeFirstResponder(self)
        }
    }

    private func drawWhitespace(in dirtyRect: NSRect) {
        guard showsWhitespace, let window else { return }
        let text = string as NSString
        let visible = visibleLogicalLines(in: dirtyRect)
        var remaining = 2_000
        for line in visible {
            let start = lineIndex.utf16Starts[line]
            let end = line + 1 < lineIndex.utf16Starts.count ? lineIndex.utf16Starts[line + 1] : text.length
            for offset in start..<end where remaining > 0 {
                let character = text.character(at: offset)
                guard character == 32 || character == 9 else { continue }
                remaining -= 1
                let screenRect = firstRect(forCharacterRange: NSRange(location: offset, length: 1), actualRange: nil)
                let rect = convert(window.convertFromScreen(screenRect), from: nil)
                guard rect.intersects(dirtyRect) else { continue }
                (character == 9 ? "→" : "·" as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY), withAttributes: [.font: font ?? Self.editorFont, .foregroundColor: NSColor.tertiaryLabelColor])
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    func fittedInsertionPointRect(_ rect: NSRect) -> NSRect {
        let font = font ?? Self.editorFont
        let fontHeight = ceil(font.ascender - font.descender + font.leading)
        let height = min(rect.height, fontHeight)
        return NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: fittedInsertionPointRect(rect), color: color, turnedOn: flag)
    }

    func resizeDocument(minimumSize: NSSize) {
        let scrollView = enclosingScrollView ?? (superview as? NSClipView)?.superview as? NSScrollView
        let viewportSize = scrollView?.contentSize ?? minimumSize
        let minHeight = max(minimumSize.height, viewportSize.height, 200)
        if wrapsLines {
            let width = max(40, viewportSize.width)
            textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            if let manager = textLayoutManager, let content = manager.textContentManager {
                manager.ensureLayout(for: content.documentRange)
                let height = max(minHeight, manager.usageBoundsForTextContainer.maxY + Self.verticalInset * 2)
                let target = NSRect(x: 0, y: 0, width: width, height: height)
                if frame != target { frame = target }
            }
            refreshInlineHighlights()
            return
        }
        textContainer?.containerSize = NSSize(width: 10_000_000, height: CGFloat.greatestFiniteMagnitude)

        guard let manager = textLayoutManager else { return }
        // Seed an initially empty layout cache with just the first row.
        _ = lineRect(at: 0)
        // Bounds-based ensureLayout can visit the whole document to discover the
        // requested Y coordinate. Our fixed rows map the viewport to text directly.
        let viewport = scrollView?.documentVisibleRect ?? bounds
        let starts = lineIndex.utf16Starts
        let first = min(starts.count - 1, max(0, Int(floor((viewport.minY - Self.verticalInset) / effectiveRowHeight))))
        let end = min(starts.count, max(first + 1, Int(ceil((viewport.maxY - Self.verticalInset) / effectiveRowHeight)) + 1))
        let startOffset = starts[first]
        let endOffset = end < starts.count ? starts[end] : lineIndex.utf16Count
        if let range = textRange(for: NSRange(location: startOffset, length: endOffset - startOffset)) {
            manager.ensureLayout(for: range)
        }
        let usedRect = manager.usageBoundsForTextContainer
        if measuredWidth == nil {
            var currentWidths: [String: CGFloat] = [:]
            var maximum: CGFloat = 0
            for line in lineIndex.lines {
                let width: CGFloat
                if let cached = currentWidths[line] ?? lineWidthCache[line] {
                    width = cached
                } else {
                    let attributed = NSAttributedString(string: line, attributes: baseAttributes)
                    width = ceil(CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)))
                }
                currentWidths[line] = width
                maximum = max(maximum, width)
            }
            lineWidthCache = currentWidths
            measuredWidth = maximum
        }
        let newWidth = max(viewportSize.width, ceil(usedRect.maxX), measuredWidth ?? 0, 200)
        let neededHeight = Self.verticalInset * 2 + CGFloat(lineIndex.utf16Starts.count) * effectiveRowHeight
        let newHeight = max(minHeight, neededHeight)

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
