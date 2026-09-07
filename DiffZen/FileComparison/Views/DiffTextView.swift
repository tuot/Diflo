import AppKit

final class DiffTextView: NSTextView {
    static let rowHeight: CGFloat = 21
    static let verticalInset: CGFloat = 8

    private var rowHighlights: [DiffRowPresentation.Highlight] = []
    private var selectedRows: Range<Int>?
    var placeholderString: String? {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let placeholder = placeholderString {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.placeholderTextColor
            ]
            let point = NSPoint(x: textContainerInset.width + 2, y: Self.verticalInset + 2)
            (placeholder as NSString).draw(at: point, withAttributes: attrs)
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard !rowHighlights.isEmpty else { return }
        let firstRow = max(0, Int(floor((rect.minY - Self.verticalInset) / Self.rowHeight)))
        let lastRow = min(
            rowHighlights.count - 1,
            Int(ceil((rect.maxY - Self.verticalInset) / Self.rowHeight))
        )
        guard firstRow <= lastRow else { return }

        for index in firstRow...lastRow {
            let rowRect = NSRect(
                x: rect.minX,
                y: Self.verticalInset + CGFloat(index) * Self.rowHeight,
                width: rect.width,
                height: Self.rowHeight
            ).intersection(rect)
            if let color = backgroundColor(for: rowHighlights[index]) {
                color.setFill()
                NSBezierPath.fill(rowRect)
            }
            if selectedRows?.contains(index) == true {
                NSColor.controlAccentColor.setStroke()
                let path = NSBezierPath(rect: rowRect.insetBy(dx: 0, dy: 0.5))
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    func configure(
        text: String,
        lineCount: Int,
        hunks: [DiffHunk],
        side: ComparisonSide,
        selectedHunkID: DiffHunk.ID?,
        oppositeLines: [String] = []
    ) {
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

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = Self.rowHeight
        paragraphStyle.maximumLineHeight = Self.rowHeight
        paragraphStyle.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]
        self.typingAttributes = attributes
        if string != text {
            let selection = selectedRange()
            textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        } else {
            textStorage?.addAttributes(attributes, range: NSRange(location: 0, length: textStorage?.length ?? 0))
        }

        applyIntraLineHighlights(
            text: text,
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

    private func applyIntraLineHighlights(
        text: String,
        hunks: [DiffHunk],
        side: ComparisonSide,
        selectedHunkID: DiffHunk.ID?,
        oppositeLines: [String]
    ) {
        guard !oppositeLines.isEmpty, let textStorage else { return }
        textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: textStorage.length))
        let currentLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !currentLines.isEmpty else { return }

        var lineStarts: [Int] = [0]
        for line in currentLines.dropLast() {
            lineStarts.append(lineStarts.last! + (line as NSString).length + 1)
        }

        for hunk in hunks where hunk.kind == .modified {
            let lineCount = min(hunk.leftLineRange.count, hunk.rightLineRange.count)
            let isSelected = hunk.id == selectedHunkID
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let intraBase = isDark
                ? NSColor(red: 0x24 / 255.0, green: 0x52 / 255.0, blue: 0x7e / 255.0, alpha: 1.0)
                : NSColor(red: 0x8a / 255.0, green: 0xc2 / 255.0, blue: 0xff / 255.0, alpha: 1.0)
            let intraColor = intraBase.withAlphaComponent(isSelected ? 0.95 : 0.80)

            for i in 0..<lineCount {
                let leftIdx = hunk.leftLineRange.lowerBound + i
                let rightIdx = hunk.rightLineRange.lowerBound + i
                guard leftIdx < (side == .left ? currentLines.count : oppositeLines.count),
                      rightIdx < (side == .right ? currentLines.count : oppositeLines.count) else { continue }

                let leftLine = side == .left ? currentLines[leftIdx] : oppositeLines[leftIdx]
                let rightLine = side == .right ? currentLines[rightIdx] : oppositeLines[rightIdx]
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
        guard let textContainer, let layoutManager else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let viewportSize = enclosingScrollView?.contentSize ?? minimumSize
        let effectiveMinWidth = max(minimumSize.width, viewportSize.width, 100)
        let effectiveMinHeight = max(minimumSize.height, viewportSize.height, 100)
        let targetWidth = max(effectiveMinWidth, ceil(usedRect.width + textContainerInset.width * 2))
        let targetHeight = max(effectiveMinHeight, ceil(usedRect.height + textContainerInset.height * 2))
        if frame.width != targetWidth || frame.height != targetHeight {
            frame.size = NSSize(width: targetWidth, height: targetHeight)
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
