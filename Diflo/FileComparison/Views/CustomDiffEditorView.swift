import AppKit
import CoreText

// MARK: - 自绘编辑器主题色板

enum CustomEditorTheme {
    static func backgroundColor(isDark: Bool) -> NSColor {
        isDark ? NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
               : NSColor(red: 0.99, green: 0.99, blue: 1.0, alpha: 1.0)
    }

    static func gutterBackgroundColor(isDark: Bool) -> NSColor {
        isDark ? NSColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1.0)
               : NSColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1.0)
    }

    static func separatorColor(isDark: Bool) -> NSColor {
        isDark ? NSColor(white: 0.22, alpha: 1.0) : NSColor(white: 0.85, alpha: 1.0)
    }

    static func lineHighlight(kind: DiffHunk.Kind, isDark: Bool) -> NSColor {
        switch kind {
        case .leftOnly:
            return isDark
                ? NSColor(red: 0x7a / 255.0, green: 0x2a / 255.0, blue: 0x28 / 255.0, alpha: 0.85)
                : NSColor(red: 0xff / 255.0, green: 0xa5 / 255.0, blue: 0xa3 / 255.0, alpha: 0.70)
        case .rightOnly:
            return isDark
                ? NSColor(red: 0x12 / 255.0, green: 0x38 / 255.0, blue: 0x06 / 255.0, alpha: 0.85)
                : NSColor(red: 0xd0 / 255.0, green: 0xff / 255.0, blue: 0xa3 / 255.0, alpha: 0.70)
        case .modified:
            return isDark
                ? NSColor(red: 0x00 / 255.0, green: 0x32 / 255.0, blue: 0x66 / 255.0, alpha: 0.85)
                : NSColor(red: 0xbd / 255.0, green: 0xdd / 255.0, blue: 0xff / 255.0, alpha: 0.70)
        }
    }

    static func inlineDiffHighlight(isDark: Bool) -> NSColor {
        isDark
            ? NSColor(red: 0x24 / 255.0, green: 0x52 / 255.0, blue: 0x7e / 255.0, alpha: 0.95)
            : NSColor(red: 0x8a / 255.0, green: 0xc2 / 255.0, blue: 0xff / 255.0, alpha: 0.95)
    }
}

// MARK: - 基于 CoreText 的自绘文本编辑器视图 (路线 B)

final class CustomDiffEditorView: NSView, NSTextInputClient {
    static let rowHeight: CGFloat = 21.0
    static let verticalInset: CGFloat = 8.0
    static let gutterWidth: CGFloat = 52.0
    static let textPaddingLeft: CGFloat = 10.0

    // MARK: - 配置与数据
    private(set) var side: ComparisonSide = .left
    private(set) var text: String = ""
    private(set) var lines: [String] = []
    private var hunks: [DiffHunk] = []
    private var selectedHunkID: DiffHunk.ID?
    private var oppositeLines: [String] = []
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }

    var onEdit: ((String) -> Void)?
    var onCursorChanged: ((CursorPosition) -> Void)?

    // MARK: - 字体度量与排版
    let font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    lazy var charWidth: CGFloat = {
        ("M" as NSString).size(withAttributes: [.font: font]).width
    }()
    private var fontAscent: CGFloat = 10.0
    private var fontDescent: CGFloat = 3.0

    // MARK: - 光标与输入状态
    private(set) var caretLine: Int = 0
    private(set) var caretColumn: Int = 0
    private var isCaretVisible: Bool = true
    private var caretBlinkTimer: Timer?

    // IME 组合文本状态 (拼音输入)
    private var markedTextStorage: NSMutableAttributedString?
    private var markedSelectionRange: NSRange = NSRange(location: NSNotFound, length: 0)

    // MARK: - 响应与交互
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - 初始化
    init(side: ComparisonSide) {
        self.side = side
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        setupMetrics()
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupMetrics() {
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        fontAscent = CTFontGetAscent(ctFont)
        fontDescent = CTFontGetDescent(ctFont)
        placeholderString = side == .left ? "输入或粘贴左侧文本..." : "输入或粘贴右侧文本..."
    }

    deinit {
        stopCaretTimer()
    }

    // MARK: - 数据配置
    func configure(
        text: String,
        hunks: [DiffHunk],
        selectedHunkID: DiffHunk.ID?,
        oppositeLines: [String] = []
    ) {
        let textChanged = self.text != text
        self.text = text
        self.lines = text.isEmpty ? [] : text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        self.hunks = hunks
        self.selectedHunkID = selectedHunkID
        self.oppositeLines = oppositeLines

        if textChanged {
            clampCaret()
        }
        updateDocumentLayout()
        needsDisplay = true
    }

    private func updateDocumentLayout() {
        guard let scrollView = enclosingScrollView else { return }
        let viewport = scrollView.contentSize
        let contentLineCount = max(1, lines.count)
        let neededHeight = Self.verticalInset * 2 + CGFloat(contentLineCount) * Self.rowHeight
        let width = max(viewport.width, 300)
        let height = max(viewport.height, neededHeight)

        let targetFrame = NSRect(x: 0, y: 0, width: width, height: height)
        if frame != targetFrame {
            frame = targetFrame
        }
    }

    // MARK: - 渲染流水线 (draw)

    override func draw(_ dirtyRect: NSRect) {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // 1. 背景绘制 (编辑区与 Gutter)
        CustomEditorTheme.backgroundColor(isDark: isDark).setFill()
        dirtyRect.fill()

        let gutterRect = NSRect(x: 0, y: dirtyRect.minY, width: Self.gutterWidth, height: dirtyRect.height)
        CustomEditorTheme.gutterBackgroundColor(isDark: isDark).setFill()
        gutterRect.fill()

        CustomEditorTheme.separatorColor(isDark: isDark).setFill()
        NSRect(x: Self.gutterWidth - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()

        // 2. 计算当前可视行范围 (O(1) 视口虚拟化)
        let totalCount = max(1, lines.count)
        let firstRow = max(0, Int(floor((dirtyRect.minY - Self.verticalInset) / Self.rowHeight)))
        let lastRow = min(totalCount - 1, Int(ceil((dirtyRect.maxY - Self.verticalInset) / Self.rowHeight)))
        guard firstRow <= lastRow else { return }

        // 构建行号到 Hunk 的快速查找表
        var lineHunks: [Int: DiffHunk] = [:]
        for hunk in hunks {
            let range = side == .left ? hunk.leftLineRange : hunk.rightLineRange
            for line in range {
                lineHunks[line] = hunk
            }
        }

        let context = NSGraphicsContext.current?.cgContext

        // 3. 逐行绘制：背景色块、行内高亮、行号、文字
        for lineIndex in firstRow...lastRow {
            let rowY = Self.verticalInset + CGFloat(lineIndex) * Self.rowHeight
            let rowRect = NSRect(x: Self.gutterWidth, y: rowY, width: bounds.width - Self.gutterWidth, height: Self.rowHeight)

            // 3.1 差异行背景色
            if let hunk = lineHunks[lineIndex] {
                let color = CustomEditorTheme.lineHighlight(kind: hunk.kind, isDark: isDark)
                color.setFill()
                rowRect.fill()

                if hunk.id == selectedHunkID {
                    NSColor.controlAccentColor.setStroke()
                    let border = NSBezierPath(rect: rowRect.insetBy(dx: 0, dy: 0.5))
                    border.lineWidth = 1.0
                    border.stroke()
                }

                // 3.2 行内字符高亮 (Intra-line diff)
                if hunk.kind == .modified, lineIndex < lines.count {
                    drawIntraLineHighlights(lineIndex: lineIndex, hunk: hunk, rowY: rowY, isDark: isDark)
                }
            }

            // 3.3 Gutter 行号与状态标记 (+ / - / ~)
            drawGutterMarkerAndNumber(lineIndex: lineIndex, hunk: lineHunks[lineIndex], rowY: rowY, isDark: isDark)

            // 3.4 代码文字绘制 (CoreText)
            if lineIndex < lines.count {
                drawLineText(lineIndex: lineIndex, rowY: rowY, in: context, isDark: isDark)
            }
        }

        // 4. 空态占位文本
        if lines.isEmpty && !placeholderString.isEmpty {
            drawPlaceholder(isDark: isDark)
        }

        // 5. 绘制光标 (Caret)
        if window?.firstResponder === self && isCaretVisible {
            drawCaret()
        }
    }

    private func drawGutterMarkerAndNumber(lineIndex: Int, hunk: DiffHunk?, rowY: CGFloat, isDark: Bool) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        // 状态标记
        if let hunk {
            let marker: String
            let markerColor: NSColor
            switch hunk.kind {
            case .leftOnly: marker = "−"; markerColor = .systemRed
            case .rightOnly: marker = "+"; markerColor = .systemGreen
            case .modified: marker = "~"; markerColor = .systemBlue
            }
            let markerAttr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: markerColor]
            NSString(string: marker).draw(
                in: NSRect(x: 5, y: rowY + 3, width: 12, height: 16),
                withAttributes: markerAttr
            )
        }

        // 行号 (右对齐)
        let numStyle = NSMutableParagraphStyle()
        numStyle.alignment = .right
        let numAttr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: numStyle
        ]
        NSString(string: "\(lineIndex + 1)").draw(
            in: NSRect(x: 18, y: rowY + 3, width: Self.gutterWidth - 25, height: 16),
            withAttributes: numAttr
        )
    }

    private func drawLineText(lineIndex: Int, rowY: CGFloat, in context: CGContext?, isDark: Bool) {
        guard let context else { return }
        let lineText = lines[lineIndex]
        guard !lineText.isEmpty else { return }

        let textColor = isDark ? NSColor(white: 0.92, alpha: 1.0) : NSColor(white: 0.12, alpha: 1.0)
        let attrString = NSAttributedString(string: lineText, attributes: [
            .font: font,
            .foregroundColor: textColor
        ])

        let ctLine = CTLineCreateWithAttributedString(attrString)

        context.saveGState()
        let textX = Self.gutterWidth + Self.textPaddingLeft
        let baselineY = rowY + fontAscent + (Self.rowHeight - (fontAscent + fontDescent)) / 2.0
        context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
        context.textPosition = CGPoint(x: textX, y: baselineY)
        CTLineDraw(ctLine, context)
        context.restoreGState()
    }

    private func drawIntraLineHighlights(lineIndex: Int, hunk: DiffHunk, rowY: CGFloat, isDark: Bool) {
        let i = lineIndex - (side == .left ? hunk.leftLineRange.lowerBound : hunk.rightLineRange.lowerBound)
        let oppLineIndex = (side == .left ? hunk.rightLineRange.lowerBound : hunk.leftLineRange.lowerBound) + i

        guard lineIndex < lines.count, oppLineIndex < oppositeLines.count else { return }
        let leftLine = side == .left ? lines[lineIndex] : oppositeLines[oppLineIndex]
        let rightLine = side == .right ? lines[lineIndex] : oppositeLines[oppLineIndex]

        let (leftRanges, rightRanges) = IntraLineDiffEngine.diff(left: leftLine, right: rightLine)
        let ranges = side == .left ? leftRanges : rightRanges

        let intraColor = CustomEditorTheme.inlineDiffHighlight(isDark: isDark)
        intraColor.setFill()

        for range in ranges {
            let startX = Self.gutterWidth + Self.textPaddingLeft + CGFloat(range.location) * charWidth
            let width = max(CGFloat(range.length) * charWidth, 4)
            let rect = NSRect(x: startX, y: rowY + 1.5, width: width, height: Self.rowHeight - 3)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            path.fill()
        }
    }

    private func drawPlaceholder(isDark: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.placeholderTextColor
        ]
        let point = NSPoint(x: Self.gutterWidth + Self.textPaddingLeft, y: Self.verticalInset + 3)
        (placeholderString as NSString).draw(at: point, withAttributes: attrs)
    }

    private func drawCaret() {
        let caretRect = currentCaretRect()
        NSColor.controlAccentColor.setFill()
        caretRect.fill()
    }

    private func currentCaretRect() -> NSRect {
        let lineY = Self.verticalInset + CGFloat(caretLine) * Self.rowHeight
        let x = Self.gutterWidth + Self.textPaddingLeft + CGFloat(caretColumn) * charWidth
        return NSRect(x: x, y: lineY + 2, width: 1.5, height: Self.rowHeight - 4)
    }

    // MARK: - 焦点与光标定时器

    override func becomeFirstResponder() -> Bool {
        startCaretTimer()
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        stopCaretTimer()
        needsDisplay = true
        return super.resignFirstResponder()
    }

    private func startCaretTimer() {
        stopCaretTimer()
        isCaretVisible = true
        caretBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.isCaretVisible.toggle()
            self.setNeedsDisplay(self.currentCaretRect())
        }
    }

    private func stopCaretTimer() {
        caretBlinkTimer?.invalidate()
        caretBlinkTimer = nil
        isCaretVisible = false
    }

    // MARK: - 鼠标与点击定位

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        setCaret(at: point)
    }

    private func setCaret(at point: NSPoint) {
        let line = max(0, min(max(1, lines.count) - 1, Int((point.y - Self.verticalInset) / Self.rowHeight)))
        let lineLen = line < lines.count ? lines[line].count : 0
        let col = max(0, min(lineLen, Int(round((point.x - (Self.gutterWidth + Self.textPaddingLeft)) / charWidth))))

        caretLine = line
        caretColumn = col
        isCaretVisible = true
        startCaretTimer()
        onCursorChanged?(CursorPosition(line: caretLine + 1, column: caretColumn + 1))
        needsDisplay = true
    }

    private func clampCaret() {
        let maxLine = max(0, lines.count - 1)
        caretLine = max(0, min(caretLine, maxLine))
        let maxCol = caretLine < lines.count ? lines[caretLine].count : 0
        caretColumn = max(0, min(caretColumn, maxCol))
    }

    // MARK: - 键盘输入 (NSTextInputClient & 事件响应)

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    // MARK: - 基本按键指令实现

    override func insertNewline(_ sender: Any?) {
        splitLineAtCaret()
    }

    override func deleteBackward(_ sender: Any?) {
        deleteCharacterBeforeCaret()
    }

    override func moveLeft(_ sender: Any?) {
        if caretColumn > 0 {
            caretColumn -= 1
        } else if caretLine > 0 {
            caretLine -= 1
            caretColumn = lines[caretLine].count
        }
        notifyCursorChange()
    }

    override func moveRight(_ sender: Any?) {
        let lineLen = caretLine < lines.count ? lines[caretLine].count : 0
        if caretColumn < lineLen {
            caretColumn += 1
        } else if caretLine < lines.count - 1 {
            caretLine += 1
            caretColumn = 0
        }
        notifyCursorChange()
    }

    override func moveUp(_ sender: Any?) {
        if caretLine > 0 {
            caretLine -= 1
            caretColumn = min(caretColumn, lines[caretLine].count)
            notifyCursorChange()
        }
    }

    override func moveDown(_ sender: Any?) {
        if caretLine < lines.count - 1 {
            caretLine += 1
            caretColumn = min(caretColumn, lines[caretLine].count)
            notifyCursorChange()
        }
    }

    // MARK: - 文本变更逻辑

    private func insertStringAtCaret(_ string: String) {
        var currentLines = lines.isEmpty ? [""] : lines
        if caretLine >= currentLines.count {
            currentLines.append("")
        }

        let line = currentLines[caretLine]
        let prefix = String(line.prefix(caretColumn))
        let suffix = String(line.dropFirst(caretColumn))

        if string.contains("\n") {
            let parts = string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var newLines: [String] = []
            for (idx, part) in parts.enumerated() {
                if idx == 0 {
                    newLines.append(prefix + part)
                } else if idx == parts.count - 1 {
                    newLines.append(part + suffix)
                } else {
                    newLines.append(part)
                }
            }
            currentLines.replaceSubrange(caretLine...caretLine, with: newLines)
            caretLine += parts.count - 1
            caretColumn = parts.last?.count ?? 0
        } else {
            currentLines[caretLine] = prefix + string + suffix
            caretColumn += string.count
        }

        commitLines(currentLines)
    }

    private func splitLineAtCaret() {
        var currentLines = lines.isEmpty ? [""] : lines
        let line = currentLines[caretLine]
        let prefix = String(line.prefix(caretColumn))
        let suffix = String(line.dropFirst(caretColumn))

        currentLines[caretLine] = prefix
        currentLines.insert(suffix, at: caretLine + 1)
        caretLine += 1
        caretColumn = 0
        commitLines(currentLines)
    }

    private func deleteCharacterBeforeCaret() {
        guard !lines.isEmpty else { return }
        var currentLines = lines
        if caretColumn > 0 {
            var line = currentLines[caretLine]
            let idx = line.index(line.startIndex, offsetBy: caretColumn - 1)
            line.remove(at: idx)
            currentLines[caretLine] = line
            caretColumn -= 1
            commitLines(currentLines)
        } else if caretLine > 0 {
            let currentLine = currentLines.remove(at: caretLine)
            caretLine -= 1
            caretColumn = currentLines[caretLine].count
            currentLines[caretLine] += currentLine
            commitLines(currentLines)
        }
    }

    private func commitLines(_ newLines: [String]) {
        self.lines = newLines
        self.text = newLines.joined(separator: "\n")
        notifyCursorChange()
        updateDocumentLayout()
        needsDisplay = true
        onEdit?(self.text)
    }

    private func notifyCursorChange() {
        isCaretVisible = true
        startCaretTimer()
        onCursorChanged?(CursorPosition(line: caretLine + 1, column: caretColumn + 1))
        needsDisplay = true
    }

    // MARK: - NSTextInputClient 协议实现 (输入法支持)

    func insertText(_ string: Any, replacementRange: NSRange) {
        let str: String
        if let attr = string as? NSAttributedString {
            str = attr.string
        } else if let s = string as? String {
            str = s
        } else {
            return
        }
        unmarkText()
        insertStringAtCaret(str)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let attr = string as? NSAttributedString {
            markedTextStorage = NSMutableAttributedString(attributedString: attr)
        } else if let s = string as? String {
            markedTextStorage = NSMutableAttributedString(string: s)
        } else {
            markedTextStorage = nil
        }
        markedSelectionRange = selectedRange
        needsDisplay = true
    }

    func unmarkText() {
        markedTextStorage = nil
        markedSelectionRange = NSRange(location: NSNotFound, length: 0)
        needsDisplay = true
    }

    func selectedRange() -> NSRange {
        NSRange(location: caretColumn, length: 0)
    }

    func markedRange() -> NSRange {
        guard let markedTextStorage else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: caretColumn, length: markedTextStorage.length)
    }

    func hasMarkedText() -> Bool {
        markedTextStorage != nil
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard caretLine < lines.count else { return nil }
        let line = lines[caretLine]
        let nsLine = line as NSString
        guard range.location + range.length <= nsLine.length else { return nil }
        actualRange?.pointee = range
        return NSAttributedString(string: nsLine.substring(with: range))
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.font, .foregroundColor, .backgroundColor]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        let caretRect = currentCaretRect()
        let windowRect = convert(caretRect, to: nil)
        return window.convertToScreen(windowRect)
    }

    func characterIndex(for point: NSPoint) -> Int {
        caretColumn
    }
}
