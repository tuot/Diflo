import AppKit

final class ChangeGutterView: NSView {
    static let preferredWidth: CGFloat = 88
    var scrollOffsets: (() -> (left: Double, right: Double))?
    private var hunks: [DiffHunk] = []
    private var selectedHunkID: DiffHunk.ID?
    private var leftOffset: Double = 0
    private var rightOffset: Double = 0
    private var select: ((DiffHunk.ID?) -> Void)?
    private var apply: ((DiffHunk, ComparisonSide) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var hoveredHunkID: DiffHunk.ID?
    private var hoveredButtonSide: ComparisonSide?
    private var accessibleButtons: [String: MergeAccessibilityElement] = [:]

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "差异合并" }
    override func accessibilityChildren() -> [Any]? {
        var children: [MergeAccessibilityElement] = []
        var keys = Set<String>()
        for hunk in hunks {
            for button in mergeButtons(for: hunk) where button.rect.intersects(bounds) {
                let key = "\(hunk.id)-\(button.source)"
                keys.insert(key)
                let element = accessibleButtons[key] ?? MergeAccessibilityElement()
                element.setAccessibilityParent(self)
                element.setAccessibilityRole(.button)
                element.setAccessibilityEnabled(true)
                element.setAccessibilityLabel(button.source == .left ? "采纳左侧内容到右侧" : "采纳右侧内容到左侧")
                element.setAccessibilityFrameInParentSpace(button.rect)
                element.action = { [weak self] in
                    self?.apply?(hunk, button.source)
                }
                accessibleButtons[key] = element
                children.append(element)
            }
        }
        accessibleButtons = accessibleButtons.filter { keys.contains($0.key) }
        return children
    }

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
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        for hunk in hunks {
            let leftRect = connectionBand(for: hunk, side: .left)
            let rightRect = connectionBand(for: hunk, side: .right)

            // Viewport culling to maintain 60fps on large files
            if max(leftRect.maxY, rightRect.maxY) < bounds.minY - 40 ||
               min(leftRect.minY, rightRect.minY) > bounds.maxY + 40 {
                continue
            }

            let path = bezierPath(for: hunk)

            let isSelected = hunk.id == selectedHunkID
            let hunkColor = color(for: hunk)

            let highlight: DiffRowPresentation.Highlight = hunk.kind == .modified ? .modification : (hunk.kind == .leftOnly ? .deletion : .insertion)
            let fill = DiffTextView.backgroundColor(for: highlight, appearance: effectiveAppearance) ?? hunkColor
            fill.setFill()
            path.fill()

            let outline = NSBezierPath()
            let edgeWidth: CGFloat = isSelected ? 1 : 0.5
            let inset = edgeWidth / 2
            for edge in [(leftRect.minY + inset, rightRect.minY + inset), (leftRect.maxY - inset, rightRect.maxY - inset)] {
                outline.move(to: NSPoint(x: bounds.minX, y: edge.0))
                outline.curve(to: NSPoint(x: bounds.maxX, y: edge.1),
                              controlPoint1: NSPoint(x: bounds.midX, y: edge.0),
                              controlPoint2: NSPoint(x: bounds.midX, y: edge.1))
            }
            (isSelected ? NSColor.controlAccentColor : fill.blended(withFraction: 0.25, of: .labelColor) ?? hunkColor).setStroke()
            outline.lineWidth = edgeWidth
            outline.stroke()

            drawActionButtons(for: hunk)
        }
    }

    private func bezierPath(for hunk: DiffHunk) -> NSBezierPath {
        let leftRect = connectionBand(for: hunk, side: .left)
        let rightRect = connectionBand(for: hunk, side: .right)

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
            if let button = mergeButtons(for: hunk).first(where: { $0.rect.contains(point) }) {
                foundHunkID = hunk.id
                foundSide = button.source
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
            toolTip = foundSide.map { $0 == .left ? "采纳左侧内容 →" : "← 采纳右侧内容" }
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        if hoveredHunkID != nil || hoveredButtonSide != nil {
            hoveredHunkID = nil
            hoveredButtonSide = nil
            toolTip = nil
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for hunk in hunks {
            if let button = mergeButtons(for: hunk).first(where: { $0.rect.contains(point) }) {
                apply?(hunk, button.source)
                return
            } else if bezierPath(for: hunk).contains(point) {
                select?(hunk.id)
                return
            }
        }
        select?(nil)
    }

    func connectionBand(for hunk: DiffHunk, side: ComparisonSide) -> NSRect {
        let offsets = scrollOffsets?() ?? (leftOffset, rightOffset)
        return DiffTextView.diffBandRect(for: side == .left ? hunk.leftLineRange : hunk.rightLineRange,
                                        width: bounds.width, offset: CGFloat(side == .left ? offsets.0 : offsets.1))
    }

    private func mergeButtons(for hunk: DiffHunk) -> [(source: ComparisonSide, rect: NSRect)] {
        var buttons: [(ComparisonSide, NSRect)] = []
        if !hunk.leftLineRange.isEmpty {
            let y = connectionBand(for: hunk, side: .left).minY
            buttons.append((.left, NSRect(x: bounds.minX + 2, y: y, width: 22, height: DiffTextView.rowHeight)))
        }
        if !hunk.rightLineRange.isEmpty {
            let y = connectionBand(for: hunk, side: .right).minY
            buttons.append((.right, NSRect(x: bounds.maxX - 24, y: y, width: 22, height: DiffTextView.rowHeight)))
        }
        return buttons
    }

    private func drawActionButtons(for hunk: DiffHunk) {
        for button in mergeButtons(for: hunk) {
            drawButton(rect: button.rect, source: button.source,
                       isHovered: hunk.id == hoveredHunkID && hoveredButtonSide == button.source,
                       tintColor: color(for: hunk))
        }
    }

    private func drawButton(rect: NSRect, source: ComparisonSide, isHovered: Bool, tintColor: NSColor) {
        if isHovered {
            tintColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).fill()
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.scaleX(by: source == .left ? 1 : -1, yBy: 1)
        transform.concat()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: -6, y: -1.5))
        for point in [NSPoint(x: 0, y: -1.5), NSPoint(x: 0, y: -5), NSPoint(x: 6, y: 0),
                      NSPoint(x: 0, y: 5), NSPoint(x: 0, y: 1.5), NSPoint(x: -6, y: 1.5)] {
            arrow.line(to: point)
        }
        arrow.close()
        (isHovered ? tintColor : NSColor.labelColor).setFill()
        arrow.fill()
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

private final class MergeAccessibilityElement: NSAccessibilityElement {
    var action: (() -> Void)?
    override func accessibilityPerformPress() -> Bool {
        guard let action else { return false }
        action()
        return true
    }
}
