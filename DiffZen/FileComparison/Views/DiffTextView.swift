import AppKit

final class DiffTextView: NSTextView {
    static let rowHeight: CGFloat = 22.0
    static let verticalInset: CGFloat = 8.0
    static let gutterWidth: CGFloat = 46.0

    private var textStorageHolder: NSTextStorage?
    private var rowHighlights: [DiffRowPresentation.Highlight] = []
    private var selectedRows: Range<Int>?
    private var lineCount: Int = 1

    var placeholderString: String? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static func createStandard(side: ComparisonSide) -> DiffTextView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = DiffTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600), textContainer: textContainer)
        textView.textStorageHolder = textStorage
        textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // 核心：左侧向右缩进，给内置装订线留出空间
        textView.textContainerInset = NSSize(width: Self.gutterWidth + 8, height: Self.verticalInset)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.placeholderString = side == .left ? "输入或粘贴左侧文本..." : "输入或粘贴右侧文本..."
        return textView
    }

    override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: textContainer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - 核心绘制：装订线行号 + 差异行背景色块 + 占位提示

    override func drawBackground(in rect: NSRect) {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // 1. 铺底色
        NSColor.textBackgroundColor.setFill()
        rect.fill()

        // 2. 绘制一体化装订线背景与分割线 (同视口绝对对齐)
        let gutterRect = NSRect(x: 0, y: rect.minY, width: Self.gutterWidth, height: rect.height)
        NSColor.controlBackgroundColor.setFill()
        gutterRect.fill()

        NSColor.separatorColor.setFill()
        NSRect(x: Self.gutterWidth - 1, y: rect.minY, width: 1, height: rect.height).fill()

        // 3. 计算可视行范围 (严格按 22.0pt 虚拟化)
        let totalCount = max(1, lineCount)
        let firstRow = max(0, Int(floor((rect.minY - Self.verticalInset) / Self.rowHeight)))
        let lastRow = min(totalCount - 1, Int(ceil((rect.maxY - Self.verticalInset) / Self.rowHeight)))

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let numStyle = NSMutableParagraphStyle()
        numStyle.alignment = .right
        let numAttr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: numStyle
        ]

        if firstRow <= lastRow {
            for index in firstRow...lastRow {
                let rowY = Self.verticalInset + CGFloat(index) * Self.rowHeight

                // 3.1 差异行背景高亮 (铺满文字行)
                if index < rowHighlights.count, let color = backgroundColor(for: rowHighlights[index]) {
                    color.setFill()
                    let rowRect = NSRect(x: Self.gutterWidth, y: rowY, width: bounds.width - Self.gutterWidth, height: Self.rowHeight)
                    rowRect.fill()
                }

                // 3.2 选中行边框
                if selectedRows?.contains(index) == true {
                    NSColor.controlAccentColor.setStroke()
                    let border = NSBezierPath(rect: NSRect(x: Self.gutterWidth, y: rowY + 0.5, width: bounds.width - Self.gutterWidth, height: Self.rowHeight - 1))
                    border.lineWidth = 1.0
                    border.stroke()
                }

                // 3.3 变动标记 (+ / - / ~)
                if index < rowHighlights.count {
                    let highlight = rowHighlights[index]
                    let marker: String?
                    let markerColor: NSColor
                    switch highlight {
                    case .deletion: marker = "−"; markerColor = .systemRed
                    case .insertion: marker = "+"; markerColor = .systemGreen
                    case .modification: marker = "~"; markerColor = .systemBlue
                    case .none: marker = nil; markerColor = .clear
                    }
                    if let marker {
                        let mAttr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: markerColor]
                        NSString(string: marker).draw(in: NSRect(x: 3, y: rowY + 3, width: 10, height: 16), withAttributes: mAttr)
                    }
                }

                // 3.4 行号 (右对齐，与文字像素级水平对齐)
                NSString(string: "\(index + 1)").draw(
                    in: NSRect(x: 12, y: rowY + 3, width: Self.gutterWidth - 18, height: 16),
                    withAttributes: numAttr
                )
            }
        }

        // 4. 空态占位文本
        if string.isEmpty, let placeholder = placeholderString {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                .foregroundColor: NSColor.placeholderTextColor
            ]
            let point = NSPoint(x: Self.gutterWidth + 8, y: Self.verticalInset + 3)
            (placeholder as NSString).draw(at: point, withAttributes: attrs)
        }
    }

    // MARK: - 数据配置与行高锁定

    func configure(
        text: String,
        lineCount: Int,
        hunks: [DiffHunk],
        side: ComparisonSide,
        selectedHunkID: DiffHunk.ID?,
        oppositeLines: [String] = []
    ) {
        self.lineCount = max(1, lineCount)
        updateHighlightsArray(lineCount: self.lineCount, hunks: hunks, side: side, selectedHunkID: selectedHunkID)

        // 锁定单行行高为精准 22.0pt
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = Self.rowHeight
        paragraphStyle.maximumLineHeight = Self.rowHeight
        paragraphStyle.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]
        self.typingAttributes = attributes

        if string != text {
            let selection = selectedRange()
            textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        } else if let len = textStorage?.length, len > 0 {
            textStorage?.addAttributes(attributes, range: NSRange(location: 0, length: len))
        }

        applyIntraLineHighlights(
            text: string,
            hunks: hunks,
            side: side,
            selectedHunkID: selectedHunkID,
            oppositeLines: oppositeLines
        )

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
        self.lineCount = max(1, lineCount)
        updateHighlightsArray(lineCount: self.lineCount, hunks: hunks, side: side, selectedHunkID: selectedHunkID)
        applyIntraLineHighlights(
            text: string,
            hunks: hunks,
            side: side,
            selectedHunkID: selectedHunkID,
            oppositeLines: oppositeLines
        )
        needsDisplay = true
    }

    private func updateHighlightsArray(lineCount: Int, hunks: [DiffHunk], side: ComparisonSide, selectedHunkID: DiffHunk.ID?) {
        rowHighlights = Array(repeating: .none, count: max(1, lineCount))
        for hunk in hunks {
            let range = side == .left ? hunk.leftLineRange : hunk.rightLineRange
            let highlight: DiffRowPresentation.Highlight
            switch hunk.kind {
            case .leftOnly: highlight = .deletion
            case .rightOnly: highlight = .insertion
            case .modified: highlight = .modification
            }
            for index in range where index < rowHighlights.count {
                rowHighlights[index] = highlight
            }
        }
        selectedRows = hunks.first { $0.id == selectedHunkID }.map {
            side == .left ? $0.leftLineRange : $0.rightLineRange
        }
    }

    // MARK: - 字符级差异高亮 (通过 TextKit 直接上色，100% 严丝合缝)

    private func applyIntraLineHighlights(
        text: String,
        hunks: [DiffHunk],
        side: ComparisonSide,
        selectedHunkID: DiffHunk.ID?,
        oppositeLines: [String]
    ) {
        guard let textStorage else { return }
        textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: textStorage.length))
        guard !oppositeLines.isEmpty else { return }

        let currentLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !currentLines.isEmpty else { return }

        var lineStarts: [Int] = [0]
        for line in currentLines.dropLast() {
            lineStarts.append(lineStarts.last! + (line as NSString).length + 1)
        }

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let intraBase = isDark
            ? NSColor(red: 0x24 / 255.0, green: 0x52 / 255.0, blue: 0x7e / 255.0, alpha: 1.0)
            : NSColor(red: 0x8a / 255.0, green: 0xc2 / 255.0, blue: 0xff / 255.0, alpha: 1.0)

        for hunk in hunks where hunk.kind == .modified {
            let lineCount = min(hunk.leftLineRange.count, hunk.rightLineRange.count)
            let isSelected = hunk.id == selectedHunkID
            let intraColor = intraBase.withAlphaComponent(isSelected ? 0.95 : 0.80)

            for i in 0..<lineCount {
                let leftIdx = hunk.leftLineRange.lowerBound + i
                let rightIdx = hunk.rightLineRange.lowerBound + i

                let leftLine = side == .left
                    ? (leftIdx < currentLines.count ? currentLines[leftIdx] : "")
                    : (leftIdx < oppositeLines.count ? oppositeLines[leftIdx] : "")
                let rightLine = side == .left
                    ? (rightIdx < oppositeLines.count ? oppositeLines[rightIdx] : "")
                    : (rightIdx < currentLines.count ? currentLines[rightIdx] : "")

                let (leftRanges, rightRanges) = IntraLineDiffEngine.diff(left: leftLine, right: rightLine)
                let ranges = side == .left ? leftRanges : rightRanges
                let currentIdx = side == .left ? leftIdx : rightIdx

                guard currentIdx < lineStarts.count else { continue }
                let lineStart = lineStarts[currentIdx]

                for range in ranges {
                    let docRange = NSRange(location: lineStart + range.location, length: range.length)
                    if docRange.location + docRange.length <= textStorage.length {
                        textStorage.addAttribute(.backgroundColor, value: intraColor, range: docRange)
                    }
                }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    func resizeDocument(minimumSize: NSSize) {
        guard let scrollView = enclosingScrollView ?? (superview as? NSClipView)?.superview as? NSScrollView else { return }
        let viewportSize = scrollView.contentSize
        let newWidth = max(viewportSize.width, 200)
        let minHeight = max(minimumSize.height, viewportSize.height, 200)

        guard let textContainer, let layoutManager else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2)
        let neededHeight = Self.verticalInset * 2 + CGFloat(max(1, lineCount)) * Self.rowHeight
        let newHeight = max(minHeight, usedHeight, neededHeight)

        let targetFrame = NSRect(x: 0, y: 0, width: newWidth, height: newHeight)
        if frame != targetFrame {
            frame = targetFrame
        }
    }

    private func backgroundColor(for highlight: DiffRowPresentation.Highlight) -> NSColor? {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch highlight {
        case .none:
            return nil
        case .insertion:
            return isDark
                ? NSColor(red: 0x12 / 255.0, green: 0x38 / 255.0, blue: 0x06 / 255.0, alpha: 0.85)
                : NSColor(red: 0xd0 / 255.0, green: 0xff / 255.0, blue: 0xa3 / 255.0, alpha: 0.70)
        case .deletion:
            return isDark
                ? NSColor(red: 0x7a / 255.0, green: 0x2a / 255.0, blue: 0x28 / 255.0, alpha: 0.85)
                : NSColor(red: 0xff / 255.0, green: 0xa5 / 255.0, blue: 0xa3 / 255.0, alpha: 0.70)
        case .modification:
            return isDark
                ? NSColor(red: 0x00 / 255.0, green: 0x32 / 255.0, blue: 0x66 / 255.0, alpha: 0.85)
                : NSColor(red: 0xbd / 255.0, green: 0xdd / 255.0, blue: 0xff / 255.0, alpha: 0.70)
        }
    }
}
