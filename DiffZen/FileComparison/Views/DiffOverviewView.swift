import AppKit

final class DiffOverviewView: NSView {
    private var hunks: [DiffHunk] = []
    private var totalRows = 1
    private var selectedHunkID: DiffHunk.ID?
    private var select: ((DiffHunk.ID?) -> Void)?
    var onScrollToProgress: ((Double) -> Void)?

    private var viewportProgress: Double = 0
    private var visibleFraction: Double = 1.0

    override var isFlipped: Bool { true }

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
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        for hunk in hunks {
            let y = Double(hunk.virtualRowRange.lowerBound) / Double(totalRows) * bounds.height
            let height = max(3, Double(hunk.virtualRowRange.count) / Double(totalRows) * bounds.height)
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
            let vpHeight = max(14, bounds.height * visibleFraction)
            let maxTravel = bounds.height - vpHeight
            let vpY = max(0, min(bounds.height - vpHeight, maxTravel * viewportProgress))
            let vpRect = NSRect(x: 1, y: vpY, width: bounds.width - 2, height: vpHeight)

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
        let fraction = max(0, min(1, point.y / max(1, bounds.height)))
        let row = Int(fraction * Double(totalRows))
        let hunk = hunks.min {
            abs($0.virtualRowRange.lowerBound - row) < abs($1.virtualRowRange.lowerBound - row)
        }
        select?(hunk?.id)
        onScrollToProgress?(fraction)
    }

    private func color(for hunk: DiffHunk) -> NSColor {
        switch hunk.kind {
        case .leftOnly: .systemRed
        case .rightOnly: .systemGreen
        case .modified: .systemBlue
        }
    }
}
