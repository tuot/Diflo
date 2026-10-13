import AppKit

/// Retains native scrolling and hit testing while keeping the idle thumb unobtrusive.
final class HoverScroller: NSScroller {
    private var isHovered = false
    private var hoverTrackingArea: NSTrackingArea?

    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) { drawKnob() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        needsDisplay = true
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        var thumb = rect(for: .knob)
        let thickness: CGFloat = isHovered ? 8 : 2.5
        if bounds.height > bounds.width {
            thumb.origin.x = bounds.midX - thickness / 2
            thumb.size.width = thickness
        } else {
            thumb.origin.y = bounds.midY - thickness / 2
            thumb.size.height = thickness
        }
        NSColor.secondaryLabelColor.withAlphaComponent(isHovered ? 0.65 : 0.4).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }
}

/// AppKit's system preference can otherwise restore a reserved legacy scroller lane.
final class DiffOverlayScrollView: NSScrollView {
    // The external connector must be painted in the same cycle as the document.
    override class var isCompatibleWithResponsiveScrolling: Bool { false }
    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }

    override func scrollWheel(with event: NSEvent) {
        guard documentView != nil else { return }
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : lineScroll
        var dx = event.scrollingDeltaX * scale
        var dy = event.scrollingDeltaY * scale
        if event.modifierFlags.contains(.shift), dx == 0 {
            dx = dy
            dy = 0
        }
        let clip = contentView
        var proposed = clip.bounds
        proposed.origin.x -= dx
        proposed.origin.y += clip.isFlipped ? -dy : dy
        let constrained = clip.constrainBoundsRect(proposed)
        // Consume precise and momentum events here; AppKit's rubber-band engine never runs.
        clip.scroll(to: constrained.origin)
        reflectScrolledClipView(clip)
    }

    override func tile() {
        super.tile()
        // The editor reaches the gutter edge even when both scrollers are visible.
        contentView.frame = bounds
        let thickness: CGFloat = 12
        let bottom = isFlipped ? bounds.maxY - thickness : bounds.minY
        verticalScroller?.frame = NSRect(x: bounds.maxX - thickness, y: bounds.minY,
                                        width: thickness, height: bounds.height)
        horizontalScroller?.frame = NSRect(x: bounds.minX, y: bottom,
                                          width: bounds.width - thickness, height: thickness)
    }
}
