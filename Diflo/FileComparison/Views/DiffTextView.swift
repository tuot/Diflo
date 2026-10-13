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

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        textView.textContainerInset = NSSize(width: 5, height: Self.verticalInset)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
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
        oppositeLines: [String] = []
    ) {
        self.lineCount = max(1, lineCount)
        updateHighlightsArray(lineCount: self.lineCount, hunks: hunks, side: side, selectedHunkID: selectedHunkID)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: NSColor.textColor
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
