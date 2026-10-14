import AppKit

/// Owns thumb geometry and drawing so AppKit cannot apply a separate hidden knob layer.
final class HoverScroller: NSControl {
    static let overlayThickness: CGFloat = 14
    fileprivate static weak var activeDrag: HoverScroller?
    private var isHovered = false
    private var isDragging = false
    private var hoverTrackingArea: NSTrackingArea?
    private var fadeTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var expansionTask: Task<Void, Never>?
    private var expansion: CGFloat = 0
    private var expansionTarget: CGFloat = 0
    private var dragOffset: CGFloat = 0
    private(set) var hitPart: NSScroller.Part = .noPart
    var knobProportion: CGFloat = 1 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var doubleValue: Double {
        get { super.doubleValue }
        set { super.doubleValue = min(1, max(0, newValue)); needsDisplay = true }
    }

    func rect(for part: NSScroller.Part) -> NSRect {
        guard part == .knob else { return part == .knobSlot ? bounds : .zero }
        let vertical = bounds.height > bounds.width
        let length = vertical ? bounds.height : bounds.width
        let knobLength = min(length, max(24, length * min(1, max(0, knobProportion))))
        let position = CGFloat(doubleValue) * max(0, length - knobLength)
        return vertical
            ? NSRect(x: bounds.minX, y: bounds.minY + position, width: bounds.width, height: knobLength)
            : NSRect(x: bounds.minX + position, y: bounds.minY, width: knobLength, height: bounds.height)
    }

    deinit { fadeTask?.cancel(); revealTask?.cancel(); expansionTask?.cancel() }

    private func updateExpansion() {
        let target: CGFloat = isHovered || isDragging ? 1 : 0
        guard target != expansionTarget else { return }
        expansionTarget = target
        expansionTask?.cancel()
        let initial = expansion
        let start = ProcessInfo.processInfo.systemUptime
        expansionTask = Task { @MainActor [weak self] in
            do {
                while !Task.isCancelled {
                    let progress = min(1, max(0, (ProcessInfo.processInfo.systemUptime - start) / 0.3))
                    guard let self else { return }
                    let eased = progress * progress * (3 - 2 * progress)
                    self.expansion = initial + (target - initial) * eased
                    self.needsDisplay = true
                    if progress == 1 { return }
                    try await Task.sleep(for: .milliseconds(16))
                }
            } catch {}
        }
    }

    func noteActivity() {
        fadeTask?.cancel()
        if alphaValue < 1, revealTask == nil {
            let initialOpacity = alphaValue
            let revealStart = ProcessInfo.processInfo.systemUptime + (initialOpacity == 0 ? 0.15 : 0)
            revealTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(max(0, revealStart - ProcessInfo.processInfo.systemUptime)))
                    while !Task.isCancelled {
                        let progress = min(1, max(0, (ProcessInfo.processInfo.systemUptime - revealStart) / 0.45))
                        guard let self else { return }
                        let eased = progress * progress * (3 - 2 * progress)
                        self.alphaValue = initialOpacity + (1 - initialOpacity) * eased
                        if progress == 1 { self.revealTask = nil; return }
                        try await Task.sleep(for: .milliseconds(16))
                    }
                } catch {}
            }
        }
        guard !isHovered, !isDragging else { return }
        let idleDeadline = ProcessInfo.processInfo.systemUptime + 1
        fadeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, idleDeadline - ProcessInfo.processInfo.systemUptime)))
                guard !Task.isCancelled, let opacity = self?.alphaValue else { return }
                self?.revealTask?.cancel()
                self?.revealTask = nil
                while !Task.isCancelled {
                    let progress = min(1, max(0, (ProcessInfo.processInfo.systemUptime - idleDeadline) / 0.45))
                    guard let self else { return }
                    self.alphaValue = opacity * (1 - progress * progress * (3 - 2 * progress))
                    if progress == 1 { return }
                    try await Task.sleep(for: .milliseconds(16))
                }
            } catch {}
        }
    }

    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds.intersection(dirtyRect)).addClip()
        drawKnobSlot(in: bounds, highlight: false)
        drawKnob()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    private func updatePointerCursor(with event: NSEvent) {
        if let scroll = superview as? DiffOverlayScrollView {
            scroll.updatePointerCursor(with: event)
        } else {
            NSCursor.arrow.set()
        }
    }

    override func cursorUpdate(with event: NSEvent) { updatePointerCursor(with: event) }

    override func mouseEntered(with event: NSEvent) {
        updatePointerCursor(with: event)
        isHovered = true
        updateExpansion()
        noteActivity()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        updatePointerCursor(with: event)
        isHovered = false
        updateExpansion()
        noteActivity()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointerCursor(with: event)
        noteActivity()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let knob = rect(for: .knob)
        let vertical = bounds.height > bounds.width
        isDragging = true
        Self.activeDrag = self
        NSCursor.arrow.set()
        updateExpansion()
        noteActivity()
        if knob.contains(point) {
            hitPart = .knob
            dragOffset = vertical ? point.y - knob.minY : point.x - knob.minX
        } else {
            hitPart = (vertical ? point.y < knob.minY : point.x < knob.minX) ? .decrementPage : .incrementPage
            sendAction(action, to: target)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, hitPart == .knob else { return }
        NSCursor.arrow.set()
        let point = convert(event.locationInWindow, from: nil)
        let vertical = bounds.height > bounds.width
        let knob = rect(for: .knob)
        let travel = vertical ? bounds.height - knob.height : bounds.width - knob.width
        let position = vertical ? point.y - bounds.minY : point.x - bounds.minX
        doubleValue = Double((position - dragOffset) / max(1, travel))
        sendAction(action, to: target)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        if Self.activeDrag === self { Self.activeDrag = nil }
        updateExpansion()
        hitPart = .noPart
        noteActivity()
        updatePointerCursor(with: event)
        needsDisplay = true
    }

    func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        guard expansion > 0 else { return }
        var track = bounds
        let thickness = thumbThickness + 4 * expansion
        // Start at the thumb's width, then grow its surrounding padding with the same animation.
        if bounds.height > bounds.width {
            track.origin.x = bounds.maxX - 2 + 2 * expansion - thickness
            track.size.width = thickness
        } else {
            track.origin.y = bounds.maxY - 2 + 2 * expansion - thickness
            track.size.height = thickness
        }
        NSColor.secondaryLabelColor.withAlphaComponent(0.12 * expansion).setFill()
        track.intersection(bounds).intersection(slotRect).fill()
    }

    private var thumbThickness: CGFloat { 3 + 7 * expansion }

    func drawKnob() {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        var thumb = rect(for: .knob)
        let thickness = thumbThickness
        if bounds.height > bounds.width {
            thumb.origin.x = bounds.maxX - 2 - thickness
            thumb.size.width = thickness
        } else {
            thumb.origin.y = bounds.maxY - 2 - thickness
            thumb.size.height = thickness
        }
        NSColor.secondaryLabelColor.withAlphaComponent(0.4 + 0.25 * expansion).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }
}

/// Overlay geometry with our own visibility timing instead of AppKit's scroll-only fade.
final class DiffOverlayScrollView: NSScrollView {
    let verticalOverlayScroller = HoverScroller(frame: NSRect(x: 0, y: 0, width: HoverScroller.overlayThickness, height: 200))
    let horizontalOverlayScroller = HoverScroller(frame: NSRect(x: 0, y: 0, width: 200, height: HoverScroller.overlayThickness))
    private var activityTrackingArea: NSTrackingArea?
    private enum ScrollAxis { case horizontal, vertical }
    private var gestureAxis: ScrollAxis?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installOverlayScrollers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installOverlayScrollers()
    }

    private func installOverlayScrollers() {
        for scroller in [verticalOverlayScroller, horizontalOverlayScroller] {
            scroller.alphaValue = 0
            scroller.target = self
            scroller.action = #selector(overlayScrollerChanged(_:))
            addSubview(scroller)
        }
    }

    private func updateOverlayScrollers() {
        guard let document = documentView else {
            verticalOverlayScroller.isHidden = true
            horizontalOverlayScroller.isHidden = true
            return
        }
        let clip = contentView.bounds
        let insets = contentView.contentInsets
        let verticalRange = scrollRange(vertical: true)
        let horizontalRange = scrollRange(vertical: false)
        let verticalTravel = verticalRange.upperBound - verticalRange.lowerBound
        let horizontalTravel = horizontalRange.upperBound - horizontalRange.lowerBound
        verticalOverlayScroller.isHidden = verticalTravel == 0
        horizontalOverlayScroller.isHidden = horizontalTravel == 0
        verticalOverlayScroller.knobProportion = min(1, max(0, clip.height - insets.top - insets.bottom) / max(1, document.bounds.height))
        horizontalOverlayScroller.knobProportion = min(1, max(0, clip.width - insets.left - insets.right) / max(1, document.bounds.width))
        let verticalProgress = verticalTravel > 0 ? (clip.minY - verticalRange.lowerBound) / verticalTravel : 0
        verticalOverlayScroller.doubleValue = contentView.isFlipped ? verticalProgress : 1 - verticalProgress
        horizontalOverlayScroller.doubleValue = horizontalTravel > 0 ? (clip.minX - horizontalRange.lowerBound) / horizontalTravel : 0
    }

    private func scrollRange(vertical: Bool) -> ClosedRange<CGFloat> {
        let document = documentView?.bounds ?? .zero
        let clip = contentView.bounds
        let insets = contentView.contentInsets
        let leadingInset = vertical ? (contentView.isFlipped ? insets.top : insets.bottom) : insets.left
        let trailingInset = vertical ? (contentView.isFlipped ? insets.bottom : insets.top) : insets.right
        let start = (vertical ? document.minY : document.minX) - leadingInset
        let end = (vertical ? document.maxY - clip.height : document.maxX - clip.width) + trailingInset
        return start...max(start, end)
    }

    @objc private func overlayScrollerChanged(_ sender: HoverScroller) {
        scrollOverlayScroller(sender, part: sender.hitPart)
    }

    func scrollOverlayScroller(_ sender: HoverScroller, part: NSScroller.Part) {
        guard documentView != nil else { return }
        let vertical = sender === verticalOverlayScroller
        let viewport = vertical ? contentView.bounds.height : contentView.bounds.width
        let range = scrollRange(vertical: vertical)
        let travel = range.upperBound - range.lowerBound
        let reversed = vertical && !contentView.isFlipped
        var origin = contentView.bounds.origin
        var position = vertical ? origin.y : origin.x
        switch part {
        case .knob:
            position = (reversed ? 1 - sender.doubleValue : sender.doubleValue) * travel
                + range.lowerBound
        case .incrementPage, .decrementPage:
            let direction: CGFloat = part == .incrementPage ? 1 : -1
            position += direction * (reversed ? -1 : 1) * viewport * 0.9
        default: return
        }
        if vertical { origin.y = position } else { origin.x = position }
        var proposed = contentView.bounds
        proposed.origin = origin
        contentView.scroll(to: contentView.constrainBoundsRect(proposed).origin)
        reflectScrolledClipView(contentView)
    }

    // The external connector must be painted in the same cycle as the document.
    override class var isCompatibleWithResponsiveScrolling: Bool { false }
    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let activityTrackingArea { removeTrackingArea(activityTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        activityTrackingArea = area
    }

    private func revealScrollers() {
        verticalOverlayScroller.noteActivity()
        horizontalOverlayScroller.noteActivity()
    }

    /// All overlapping tracking areas resolve the same pointer location, regardless of callback order.
    func updatePointerCursor(with event: NSEvent) {
        if HoverScroller.activeDrag != nil {
            NSCursor.arrow.set()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard contentView.frame.contains(point),
              !(isFindBarVisible && findBarView?.frame.contains(point) == true) else { return }
        let overScroller = [verticalOverlayScroller, horizontalOverlayScroller].contains {
            !$0.isHidden && $0.alphaValue > 0.01 && $0.frame.contains(point)
        }
        let text = documentView as? NSTextView
        if !overScroller, text?.isEditable == true || text?.isSelectable == true {
            NSCursor.iBeam.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func cursorUpdate(with event: NSEvent) { updatePointerCursor(with: event) }

    override func mouseEntered(with event: NSEvent) {
        revealScrollers()
        updatePointerCursor(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        revealScrollers()
        updatePointerCursor(with: event)
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateOverlayScrollers()
        revealScrollers()
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
        let hasGesturePhase = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) || !hasGesturePhase {
            gestureAxis = nil
        }
        defer {
            if event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) || !hasGesturePhase {
                gestureAxis = nil
            }
        }
        // Keep the first movement's axis through finger lift and momentum.
        // A zero-delta begin event must not choose a direction yet.
        if gestureAxis == nil, dx != 0 || dy != 0 {
            gestureAxis = abs(dx) > abs(dy) ? .horizontal : .vertical
        }
        switch gestureAxis {
        case .horizontal: dy = 0
        case .vertical: dx = 0
        case nil: break
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
        // Newer AppKit versions overlay the find bar and reserve space using content insets.
        var viewport = contentView.frame
        if isFindBarVisible, let bar = findBarView {
            let overlap = viewport.intersection(convert(bar.bounds, from: bar))
            if !overlap.isEmpty {
                viewport.size.height -= overlap.height
                if overlap.minY == viewport.minY { viewport.origin.y += overlap.height }
            }
        }
        let thickness = HoverScroller.overlayThickness
        let bottom = isFlipped ? viewport.maxY - thickness : viewport.minY
        verticalOverlayScroller.frame = NSRect(x: viewport.maxX - thickness, y: viewport.minY,
                                        width: thickness, height: viewport.height)
        horizontalOverlayScroller.frame = NSRect(x: viewport.minX, y: bottom,
                                          width: viewport.width - thickness, height: thickness)
        updateOverlayScrollers()
    }
}
