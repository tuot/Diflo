import AppKit

final class ChangeGutterView: NSView {
    private var hunks: [DiffHunk] = []
    private var selectedHunkID: DiffHunk.ID?
    private var leftOffset: Double = 0
    private var rightOffset: Double = 0
    private var select: ((DiffHunk.ID?) -> Void)?
    private var apply: ((DiffHunk, ComparisonSide) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var hoveredHunkID: DiffHunk.ID?
    private var hoveredButtonSide: ComparisonSide?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    func configure(
        hunks: [DiffHunk],
        selectedHunkID: DiffHunk.ID?,
        leftOffset: Double,
        rightOffset: Double,
        select: @escaping (DiffHunk.ID?) -> Void,
        apply: @escaping (DiffHunk, ComparisonSide) -> Void
    ) {
        self.hunks = hunks
        self.selectedHunkID = selectedHunkID
        self.leftOffset = leftOffset
        self.rightOffset = rightOffset
        self.select = select
        self.apply = apply
        needsDisplay = true
    }

    func updateOffsets(left: Double, right: Double) {
        leftOffset = left
        rightOffset = right
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // AppKit may invalidate an ancestor's entire area; never paint over the editors.
        NSBezierPath(rect: bounds).addClip()
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        NSColor.separatorColor.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: dirtyRect.minY, width: 1, height: dirtyRect.height))
        NSBezierPath.fill(NSRect(x: bounds.maxX - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height))

        for hunk in hunks {
            let leftRect = lineRect(hunk.leftLineRange, offset: leftOffset)
            let rightRect = lineRect(hunk.rightLineRange, offset: rightOffset)

            // Viewport culling to maintain 60fps on large files
            if max(leftRect.maxY, rightRect.maxY) < bounds.minY - 40 ||
               min(leftRect.minY, rightRect.minY) > bounds.maxY + 40 {
                continue
            }

            let path = bezierPath(for: hunk)

            let isSelected = hunk.id == selectedHunkID
            let hunkColor = color(for: hunk)

            let highlight: DiffRowPresentation.Highlight = hunk.kind == .modified ? .modification : (hunk.kind == .leftOnly ? .deletion : .insertion)
            DiffTextView.backgroundColor(for: highlight, appearance: effectiveAppearance)?.setFill()
            path.fill()

            hunkColor.withAlphaComponent(isSelected ? 0.85 : 0.5).setStroke()
            path.lineWidth = isSelected ? 1.5 : 1.0
            path.stroke()

            drawActionButtons(for: hunk, leftRect: leftRect, rightRect: rightRect)
        }
    }

    private func bezierPath(for hunk: DiffHunk) -> NSBezierPath {
        let leftRect = lineRect(hunk.leftLineRange, offset: leftOffset)
        let rightRect = lineRect(hunk.rightLineRange, offset: rightOffset)

        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: leftRect.minY))
        path.curve(
            to: NSPoint(x: bounds.maxX, y: rightRect.minY),
            controlPoint1: NSPoint(x: bounds.midX, y: leftRect.minY),
            controlPoint2: NSPoint(x: bounds.midX, y: rightRect.minY)
        )
        path.line(to: NSPoint(x: bounds.maxX, y: rightRect.maxY))
        path.curve(
            to: NSPoint(x: 0, y: leftRect.maxY),
            controlPoint1: NSPoint(x: bounds.midX, y: rightRect.maxY),
            controlPoint2: NSPoint(x: bounds.midX, y: leftRect.maxY)
        )
        path.close()
        return path
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        var foundHunkID: DiffHunk.ID?
        var foundSide: ComparisonSide?

        for hunk in hunks {
            let leftBtn = leftButtonRect(centerY: lineRect(hunk.leftLineRange, offset: leftOffset).midY)
            let rightBtn = rightButtonRect(centerY: lineRect(hunk.rightLineRange, offset: rightOffset).midY)

            if leftBtn.contains(point) {
                foundHunkID = hunk.id
                foundSide = .right // clicking left button applies from right
                break
            } else if rightBtn.contains(point) {
                foundHunkID = hunk.id
                foundSide = .left // clicking right button applies from left
                break
            } else if bezierPath(for: hunk).contains(point) {
                foundHunkID = hunk.id
                break
            }
        }

        if foundSide != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }

        if foundHunkID != hoveredHunkID || foundSide != hoveredButtonSide {
            hoveredHunkID = foundHunkID
            hoveredButtonSide = foundSide
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        if hoveredHunkID != nil || hoveredButtonSide != nil {
            hoveredHunkID = nil
            hoveredButtonSide = nil
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for hunk in hunks {
            let leftBtn = leftButtonRect(centerY: lineRect(hunk.leftLineRange, offset: leftOffset).midY)
            let rightBtn = rightButtonRect(centerY: lineRect(hunk.rightLineRange, offset: rightOffset).midY)

            if leftBtn.contains(point) {
                select?(hunk.id)
                apply?(hunk, .right)
                return
            } else if rightBtn.contains(point) {
                select?(hunk.id)
                apply?(hunk, .left)
                return
            } else if bezierPath(for: hunk).contains(point) {
                select?(hunk.id)
                return
            }
        }
        select?(nil)
    }

    private func lineRect(_ range: Range<Int>, offset: Double) -> NSRect {
        if range.isEmpty {
            let center = DiffTextView.verticalInset + Double(range.lowerBound) * DiffTextView.rowHeight - offset
            return NSRect(x: 0, y: center - 1.5, width: bounds.width, height: 3)
        } else {
            let start = DiffTextView.verticalInset + Double(range.lowerBound) * DiffTextView.rowHeight - offset
            let height = DiffTextView.rowHeight * Double(range.count)
            return NSRect(x: 0, y: start, width: bounds.width, height: height)
        }
    }

    private func leftButtonRect(centerY: Double) -> NSRect {
        NSRect(x: 6, y: centerY - 10, width: 20, height: 20)
    }

    private func rightButtonRect(centerY: Double) -> NSRect {
        NSRect(x: bounds.maxX - 26, y: centerY - 10, width: 20, height: 20)
    }

    private func drawActionButtons(for hunk: DiffHunk, leftRect: NSRect, rightRect: NSRect) {
        let leftBtn = leftButtonRect(centerY: leftRect.midY)
        let rightBtn = rightButtonRect(centerY: rightRect.midY)
        let hunkColor = color(for: hunk)

        // Draw left button (←: copy right to left)
        drawButton(
            rect: leftBtn,
            arrow: "←",
            isHovered: hunk.id == hoveredHunkID && hoveredButtonSide == .right,
            tintColor: hunkColor
        )

        // Draw right button (→: copy left to right)
        drawButton(
            rect: rightBtn,
            arrow: "→",
            isHovered: hunk.id == hoveredHunkID && hoveredButtonSide == .left,
            tintColor: hunkColor
        )
    }

    private func drawButton(rect: NSRect, arrow: String, isHovered: Bool, tintColor: NSColor) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2)
        if isHovered {
            tintColor.withAlphaComponent(0.30).setFill()
            path.fill()
            tintColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }

        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: isHovered ? tintColor : NSColor.labelColor
        ]
        let str = NSString(string: arrow)
        let size = str.size(withAttributes: attributes)
        let origin = NSPoint(
            x: rect.midX - size.width / 2.0,
            y: rect.midY - size.height / 2.0
        )
        str.draw(at: origin, withAttributes: attributes)
    }

    private func color(for hunk: DiffHunk) -> NSColor {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch hunk.kind {
        case .leftOnly:
            return isDark
                ? NSColor(red: 0xac / 255.0, green: 0x3b / 255.0, blue: 0x39 / 255.0, alpha: 1.0)
                : NSColor(red: 0xff / 255.0, green: 0x4f / 255.0, blue: 0x4c / 255.0, alpha: 1.0)
        case .rightOnly:
            return isDark
                ? NSColor(red: 0x24 / 255.0, green: 0x55 / 255.0, blue: 0x15 / 255.0, alpha: 1.0)
                : NSColor(red: 0xa5 / 255.0, green: 0xff / 255.0, blue: 0x4c / 255.0, alpha: 1.0)
        case .modified:
            return isDark
                ? NSColor(red: 0x00 / 255.0, green: 0x53 / 255.0, blue: 0xa6 / 255.0, alpha: 1.0)
                : NSColor(red: 0x65 / 255.0, green: 0xb2 / 255.0, blue: 0xff / 255.0, alpha: 1.0)
        }
    }
}
