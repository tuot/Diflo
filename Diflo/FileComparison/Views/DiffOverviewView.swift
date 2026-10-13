import AppKit

final class DiffOverviewView: NSView {
    private var hunks: [DiffHunk] = []
    private var totalRows = 1
    private var selectedHunkID: DiffHunk.ID?
    private var select: ((DiffHunk.ID?) -> Void)?
    var onScrollToProgress: ((Double) -> Void)?

    private var viewportProgress: Double = 0
    private var visibleFraction: Double = 1.0
    private var dragOffset: CGFloat = 0

    override var isFlipped: Bool { true }

    private var documentHeight: CGFloat {
        max(bounds.height, DiffTextView.verticalInset * 2 + CGFloat(totalRows) * DiffTextView.rowHeight)
    }

    var viewportRect: NSRect {
        let height = min(bounds.height, max(14, bounds.height * visibleFraction))
        return NSRect(x: 1, y: (bounds.height - height) * viewportProgress,
                      width: max(0, bounds.width - 2), height: height)
    }

    func configure(
        hunks: [DiffHunk],
        totalRows: Int,
        selectedHunkID: DiffHunk.ID?,
        select: @escaping (DiffHunk.ID?) -> Void
    ) {
        self.hunks = hunks
        self.totalRows = max(1, totalRows)
        self.selectedHunkID = selectedHunkID
        self.select = select
        needsDisplay = true
    }

    func updateViewport(progress: Double, visibleFraction: Double) {
        self.viewportProgress = max(0, min(1, progress))
        self.visibleFraction = max(0.01, min(1, visibleFraction))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Keep ancestor-sized dirty rectangles inside the narrow overview strip.
        NSBezierPath(rect: bounds).addClip()
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        for hunk in hunks {
            let y = (DiffTextView.verticalInset + CGFloat(hunk.rightLineRange.lowerBound) * DiffTextView.rowHeight) / max(1, documentHeight) * bounds.height
            let height = max(3, CGFloat(hunk.rightLineRange.count) * DiffTextView.rowHeight / max(1, documentHeight) * bounds.height)
            color(for: hunk).setFill()
            NSBezierPath(roundedRect: NSRect(x: 2, y: y, width: bounds.width - 4, height: height), xRadius: 1.5, yRadius: 1.5).fill()
            if hunk.id == selectedHunkID {
                NSColor.labelColor.setStroke()
                let highlightRect = NSRect(x: 1, y: y - 1, width: bounds.width - 2, height: height + 2)
                NSBezierPath(roundedRect: highlightRect, xRadius: 2, yRadius: 2).stroke()
            }
        }

        // Draw visible viewport indicator
        if visibleFraction < 0.99 {
            let vpRect = viewportRect

            NSColor.labelColor.withAlphaComponent(0.09).setFill()
            NSBezierPath(roundedRect: vpRect, xRadius: 2, yRadius: 2).fill()
            NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
            NSBezierPath(roundedRect: vpRect, xRadius: 2, yRadius: 2).stroke()
        }

        // Divider on left edge
        NSColor.separatorColor.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 0.5, height: bounds.height))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let thumb = viewportRect
        dragOffset = thumb.contains(point) ? point.y - thumb.minY : thumb.height / 2
        if !thumb.contains(point) { scroll(to: point.y) }
    }

    override func mouseDragged(with event: NSEvent) {
        scroll(to: convert(event.locationInWindow, from: nil).y)
    }

    private func scroll(to y: CGFloat) {
        let travel = bounds.height - viewportRect.height
        guard travel > 0 else { return }
        onScrollToProgress?(Double(max(0, min(1, (y - dragOffset) / travel))))
    }

    private func color(for hunk: DiffHunk) -> NSColor {
        switch hunk.kind {
        case .leftOnly: .systemRed
        case .rightOnly: .systemGreen
        case .modified: .systemBlue
        }
    }
}
