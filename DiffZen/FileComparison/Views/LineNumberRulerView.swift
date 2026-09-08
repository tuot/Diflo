import AppKit

final class LineNumberRulerView: NSRulerView {
    private let side: ComparisonSide
    private var lineCount = 0
    private var lineKinds: [Int: DiffHunk.Kind] = [:]

    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView, side: ComparisonSide) {
        self.side = side
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 62
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func clipViewBoundsDidChange() {
        needsDisplay = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(lineCount: Int, hunks: [DiffHunk]) {
        self.lineCount = lineCount
        var kinds: [Int: DiffHunk.Kind] = [:]
        for hunk in hunks {
            let range = side == .left ? hunk.leftLineRange : hunk.rightLineRange
            for line in range {
                kinds[line] = hunk.kind
            }
        }
        self.lineKinds = kinds
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath.fill(rect)

        guard let scrollView else { return }
        let effectiveLineCount = max(1, lineCount)
        let visibleRect = scrollView.documentVisibleRect
        let firstRow = max(
            0,
            Int(floor((visibleRect.minY - DiffTextView.verticalInset) / DiffTextView.rowHeight))
        )
        let lastRow = min(
            effectiveLineCount - 1,
            Int(ceil((visibleRect.maxY - DiffTextView.verticalInset) / DiffTextView.rowHeight))
        )
        guard firstRow <= lastRow else { return }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let numberStyle = NSMutableParagraphStyle()
        numberStyle.alignment = .right

        for index in firstRow...lastRow {
            let y = DiffTextView.verticalInset
                + CGFloat(index) * DiffTextView.rowHeight
                - visibleRect.minY
                + 3

            if let kind = lineKinds[index] {
                let marker: String
                let markerColor: NSColor
                switch kind {
                case .leftOnly:
                    marker = "−"
                    markerColor = .systemRed
                case .rightOnly:
                    marker = "+"
                    markerColor = .systemGreen
                case .modified:
                    marker = "~"
                    markerColor = .systemBlue
                }
                NSString(string: marker).draw(
                    in: NSRect(x: 5, y: y, width: 12, height: 16),
                    withAttributes: [.font: font, .foregroundColor: markerColor]
                )
            }

            NSString(string: String(index + 1)).draw(
                in: NSRect(x: 18, y: y, width: ruleThickness - 25, height: 16),
                withAttributes: [
                    .font: font,
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: numberStyle
                ]
            )
        }

        NSColor.separatorColor.setFill()
        NSBezierPath.fill(NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height))
    }
}
