import AppKit
import Testing
@testable import Diflo

@MainActor
struct HoverScrollerTests {
    @Test func cursorFollowsPointerLocationAcrossOverlappingEditorAndScrollerCallbacks() throws {
        let original = NSCursor.current
        defer { original.set() }
        let scroll = DiffOverlayScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let editor = DiffTextView.createStandard(side: .left)
        scroll.documentView = editor
        editor.configure(text: Array(repeating: "text", count: 100).joined(separator: "\n"),
                         lineCount: 100, hunks: [], side: .left, selectedHunkID: nil)
        scroll.tile()
        editor.resizeDocument(minimumSize: scroll.contentSize)
        scroll.reflectScrolledClipView(scroll.contentView)
        let scroller = scroll.verticalOverlayScroller
        scroller.alphaValue = 1
        func event(at point: NSPoint) throws -> NSEvent {
            try #require(NSEvent.enterExitEvent(with: .cursorUpdate, location: scroll.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        }
        let text = try event(at: NSPoint(x: 100, y: 150))
        let track = try event(at: NSPoint(x: 397, y: 150))
        NSCursor.arrow.set()
        scroll.mouseMoved(with: text)
        #expect(NSCursor.current == NSCursor.iBeam)
        scroller.cursorUpdate(with: text)
        #expect(NSCursor.current == NSCursor.iBeam)
        editor.cursorUpdate(with: track)
        #expect(NSCursor.current == NSCursor.arrow)
        scroller.mouseExited(with: text)
        #expect(NSCursor.current == NSCursor.iBeam)
        ChangeGutterView().mouseExited(with: text)
        #expect(NSCursor.current == NSCursor.iBeam)
        scroll.cursorUpdate(with: track)
        #expect(NSCursor.current == NSCursor.arrow)
        scroller.alphaValue = 0
        editor.cursorUpdate(with: track)
        #expect(NSCursor.current == NSCursor.iBeam)
        scroller.alphaValue = 1
        let knob = scroller.rect(for: .knob)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
            location: scroller.convert(NSPoint(x: knob.midX, y: knob.midY), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        scroller.mouseDown(with: down)
        editor.cursorUpdate(with: text)
        #expect(NSCursor.current == NSCursor.arrow)
        scroller.mouseDragged(with: text)
        #expect(NSCursor.current == NSCursor.arrow)
        scroll.cursorUpdate(with: text)
        #expect(NSCursor.current == NSCursor.arrow)
        scroller.mouseUp(with: text)
        #expect(NSCursor.current == NSCursor.iBeam)
    }

    @Test func hoveringTheScrollerReplacesTheEditorsTextCursorWithAnArrow() throws {
        let original = NSCursor.current
        defer { original.set() }
        let scroller = HoverScroller(frame: NSRect(x: 0, y: 0, width: 14, height: 200))
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        NSCursor.iBeam.set()
        scroller.mouseEntered(with: event)
        #expect(NSCursor.current == NSCursor.arrow)
        NSCursor.iBeam.set()
        scroller.cursorUpdate(with: event)
        #expect(NSCursor.current == NSCursor.arrow)
    }

    @Test(arguments: [false, true])
    func trackGrowsAndShrinksTogetherWithTheThumb(horizontal: Bool) async throws {
        try await Task.sleep(for: .milliseconds(1500))
        let scroller = HoverScroller(frame: NSRect(x: 0, y: 0, width: horizontal ? 200 : 16, height: horizontal ? 16 : 200))
        scroller.doubleValue = 0.5
        scroller.knobProportion = 0.4
        let enter = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        scroller.mouseEntered(with: enter)
        try await Task.sleep(for: .milliseconds(100))
        let growing = try trackThickness(scroller, horizontal: horizontal)
        try await Task.sleep(for: .milliseconds(250))
        let expanded = try trackThickness(scroller, horizontal: horizontal)
        #expect(growing > 0 && growing < expanded)
        let exit = try #require(NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        scroller.mouseExited(with: exit)
        try await Task.sleep(for: .milliseconds(100))
        let shrinking = try trackThickness(scroller, horizontal: horizontal)
        #expect(shrinking > 0 && shrinking < expanded)
        try await Task.sleep(for: .milliseconds(250))
        #expect(try trackThickness(scroller, horizontal: horizontal) == 0)
    }

    private func trackThickness(_ scroller: HoverScroller, horizontal: Bool) throws -> Int {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: horizontal ? 200 : 16, pixelsHigh: horizontal ? 16 : 200, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        scroller.bounds.fill()
        scroller.drawKnobSlot(in: scroller.bounds, highlight: false)
        return (0..<16).filter { pixel in
            let color = bitmap.colorAt(x: horizontal ? 5 : pixel, y: horizontal ? pixel : 5)?.usingColorSpace(.sRGB)
            return (color?.redComponent ?? 1) < 0.995
        }.count
    }

    @Test(arguments: [false, true])
    func thumbExpandsOnlyWhileHovered(horizontal: Bool) async throws {
        try await Task.sleep(for: .milliseconds(1500))
        let scroller = HoverScroller(frame: NSRect(x: 0, y: 0, width: horizontal ? 200 : 16, height: horizontal ? 16 : 200))
        scroller.doubleValue = 0.5
        scroller.knobProportion = 0.4
        let idle = try thumbThickness(scroller, horizontal: horizontal)
        let enter = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        scroller.mouseEntered(with: enter)
        #expect(try thumbThickness(scroller, horizontal: horizontal) == idle)
        try await Task.sleep(for: .milliseconds(100))
        let expanding = try thumbThickness(scroller, horizontal: horizontal)
        #expect(expanding > idle && expanding < 10)
        try await Task.sleep(for: .milliseconds(200))
        let hovered = try thumbThickness(scroller, horizontal: horizontal)
        #expect(idle > 0 && idle <= 4)
        #expect(hovered >= 9 && hovered > idle)
        let exit = try #require(NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        scroller.mouseExited(with: exit)
        #expect(try thumbThickness(scroller, horizontal: horizontal) == hovered)
        try await Task.sleep(for: .milliseconds(100))
        let shrinking = try thumbThickness(scroller, horizontal: horizontal)
        #expect(shrinking > idle && shrinking < hovered)
        try await Task.sleep(for: .milliseconds(200))
        #expect(try thumbThickness(scroller, horizontal: horizontal) == idle)
    }

    @Test func verticalThumbExpandsLeftAndHoverRevealsTheFullTrack() async throws {
        let scroller = HoverScroller(frame: NSRect(x: 0, y: 0, width: 16, height: 200))
        scroller.doubleValue = 0.5
        scroller.knobProportion = 0.4
        let idle = try thumbPixels(scroller, horizontal: false)
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        scroller.mouseEntered(with: event)
        try await Task.sleep(for: .milliseconds(300))
        let hovered = try thumbPixels(scroller, horizontal: false)
        #expect(try #require(hovered.first) < #require(idle.first))
        #expect(hovered.last == idle.last)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 200,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        scroller.bounds.fill()
        scroller.draw(scroller.bounds)
        #expect(try #require(bitmap.colorAt(x: 3, y: 5)?.usingColorSpace(.sRGB)).redComponent < 0.98)
        #expect(try #require(bitmap.colorAt(x: 3, y: 195)?.usingColorSpace(.sRGB)).redComponent < 0.98)
    }

    private func thumbThickness(_ scroller: HoverScroller, horizontal: Bool) throws -> Int {
        try thumbPixels(scroller, horizontal: horizontal).count
    }

    private func thumbPixels(_ scroller: HoverScroller, horizontal: Bool) throws -> [Int] {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: horizontal ? 200 : 16, pixelsHigh: horizontal ? 16 : 200, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        scroller.bounds.fill()
        scroller.drawKnob()
        return (0..<16).filter { pixel in
            let color = bitmap.colorAt(x: horizontal ? 100 : pixel, y: horizontal ? pixel : 100)?.usingColorSpace(.sRGB)
            return (color?.redComponent ?? 1) < 0.95
        }
    }
}

@MainActor
struct OverlayScrollLayoutTests {
    @Test func thumbIsVisibleInTheWindowAfterMouseActivity() async throws {
        let scroll = DiffOverlayScrollView(frame: .zero)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = scroll
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1600, height: 1200))
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(450))
        scroll.tile()
        scroll.contentView.scroll(to: NSPoint(x: 600, y: 450))
        scroll.reflectScrolledClipView(scroll.contentView)
        let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 40, y: 40),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        scroll.mouseMoved(with: event)
        // A fresh activity can start the delayed reveal after window layout has settled.
        try await Task.sleep(for: .milliseconds(650))
        let bitmap = try #require(scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds))
        scroll.cacheDisplay(in: scroll.bounds, to: bitmap)
        let scroller = scroll.verticalOverlayScroller
        let point = scroller.convert(NSPoint(x: scroller.bounds.maxX - 3, y: scroller.bounds.midY), to: scroll)
        let x = Int(point.x * CGFloat(bitmap.pixelsWide) / scroll.bounds.width)
        let y = Int(point.y * CGFloat(bitmap.pixelsHigh) / scroll.bounds.height)
        let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        #expect(color.redComponent < 0.95, "Thumb pixel: \(color), frame: \(scroller.frame), knob: \(scroller.rect(for: .knob))")
        let knob = scroller.rect(for: .knob)
        func mouse(_ type: NSEvent.EventType, point: NSPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: scroller.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        scroller.mouseDown(with: try mouse(.leftMouseDown, point: NSPoint(x: knob.midX, y: knob.midY)))
        let destination = NSPoint(x: knob.midX, y: (scroller.bounds.height - knob.height) * 0.75 + knob.height / 2)
        scroller.mouseDragged(with: try mouse(.leftMouseDragged, point: destination))
        scroller.mouseUp(with: try mouse(.leftMouseUp, point: destination))
        #expect(abs(scroll.contentView.bounds.minY - 225) < 0.01)
        #expect(abs(scroller.doubleValue - 0.75) < 0.01)
    }

    @Test(arguments: [false, true])
    func installedScrollerActuallyPaintsItsThumb(horizontal: Bool) throws {
        let scroll = DiffOverlayScrollView(frame: .zero)
        scroll.borderType = .noBorder
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1600, height: 1200))
        scroll.tile()
        scroll.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        scroll.tile()
        scroll.contentView.scroll(to: NSPoint(x: 600, y: 450))
        scroll.reflectScrolledClipView(scroll.contentView)
        let scroller = horizontal ? scroll.horizontalOverlayScroller : scroll.verticalOverlayScroller
        let width = Int(scroller.bounds.width), height = Int(scroller.bounds.height)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        scroller.bounds.fill()
        scroller.draw(scroller.bounds)
        let painted = (0..<(horizontal ? height : width)).filter { pixel in
            let color = bitmap.colorAt(x: horizontal ? width / 2 : pixel,
                                       y: horizontal ? pixel : height / 2)?.usingColorSpace(.sRGB)
            return (color?.redComponent ?? 1) < 0.95
        }
        #expect(!painted.isEmpty, "Actual scroller bounds: \(scroller.bounds), knob: \(scroller.rect(for: .knob)), enabled: \(scroller.isEnabled)")
    }

    @Test func overlayThumbAndTrackActionsMoveTheDocumentAndSynchronizeTheOtherPane() {
        let coordinator = DualScrollCoordinator()
        func pane() -> DiffOverlayScrollView {
            let scroll = DiffOverlayScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            scroll.borderType = .noBorder
            scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1600, height: 1200))
            scroll.tile()
            return scroll
        }
        let left = pane(), right = pane()
        coordinator.register(scrollView: left, for: .left)
        coordinator.register(scrollView: right, for: .right)
        left.verticalOverlayScroller.doubleValue = 0.75
        left.scrollOverlayScroller(left.verticalOverlayScroller, part: .knob)
        #expect(left.contentView.bounds.minY == 225)
        #expect(right.contentView.bounds.minY == 225)
        left.horizontalOverlayScroller.doubleValue = 0.25
        left.scrollOverlayScroller(left.horizontalOverlayScroller, part: .knob)
        #expect(left.contentView.bounds.minX == 300)
        #expect(right.contentView.bounds.minX == 300)
        left.scrollOverlayScroller(left.verticalOverlayScroller, part: .incrementPage)
        #expect(left.contentView.bounds.minY == 0)
        #expect(right.contentView.bounds.minY == 0)
        withExtendedLifetime(coordinator) {}
    }

    @Test func visibleScrollersDoNotReserveSpaceBetweenEditorAndGutter() {
        let scroll = DiffOverlayScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = false
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1600, height: 1200))
        scroll.scrollerStyle = .legacy
        scroll.tile()
        #expect(scroll.contentView.frame == scroll.bounds)
        #expect(scroll.verticalOverlayScroller.frame.intersects(scroll.contentView.frame) == true)
        #expect(scroll.horizontalOverlayScroller.frame.intersects(scroll.contentView.frame) == true)
    }

    @Test func mouseMovementRevealsTheThumbWithoutScrollingAndIdleFadesIt() async throws {
        let scroll = DiffOverlayScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scroll.hasVerticalScroller = false
        let scroller = scroll.verticalOverlayScroller
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 1200))
        scroll.tile()
        let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 40, y: 40),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        // Let initial layout activity finish and fade before testing a fresh reveal.
        try await Task.sleep(for: .milliseconds(1800))
        #expect(scroller.alphaValue == 0)
        scroll.mouseMoved(with: event)
        #expect(scroller.alphaValue == 0)
        #expect(scroll.contentView.bounds.origin == .zero)
        try await Task.sleep(for: .milliseconds(250))
        #expect(scroller.alphaValue > 0 && scroller.alphaValue < 1)
        // Continuous movement must not restart the appearance delay.
        scroll.mouseMoved(with: event)
        try await Task.sleep(for: .milliseconds(100))
        #expect(scroller.alphaValue > 0 && scroller.alphaValue < 1)
        try await Task.sleep(for: .milliseconds(300))
        #expect(scroller.alphaValue == 1)
        try await Task.sleep(for: .milliseconds(850))
        #expect(scroller.alphaValue > 0 && scroller.alphaValue < 1)
        try await Task.sleep(for: .milliseconds(250))
        #expect(scroller.alphaValue == 0)
    }
}

@MainActor
struct TrackpadBoundaryTests {
    @Test func verticalGestureKeepsHorizontalPositionThroughMomentum() throws {
        let scroll = pane()
        try send(scroll, x: 3, y: 30, phase: 1)
        try send(scroll, x: 40, y: 5, phase: 2)
        try send(scroll, x: 0, y: 0, phase: 4)
        try send(scroll, x: 20, y: 4, momentum: 1)
        try send(scroll, x: 15, y: 3, momentum: 2)
        #expect(scroll.contentView.bounds.minX == 200)
        #expect(scroll.contentView.bounds.minY > 200)
    }

    @Test func horizontalGestureKeepsVerticalPositionAndNextGestureCanScrollVertically() throws {
        let scroll = pane()
        try send(scroll, x: 30, y: 3, phase: 1)
        try send(scroll, x: 5, y: 40, phase: 2)
        #expect(scroll.contentView.bounds.minX < 200)
        #expect(scroll.contentView.bounds.minY == 200)
        let x = scroll.contentView.bounds.minX
        try send(scroll, x: 2, y: 20, phase: 1)
        #expect(scroll.contentView.bounds.minX == x)
        #expect(scroll.contentView.bounds.minY > 200)
    }

    @Test func zeroDeltaBeginningWaitsForTheFirstMovement() throws {
        let scroll = pane()
        try send(scroll, x: 0, y: 0, phase: 1)
        try send(scroll, x: 2, y: 20, phase: 2)
        #expect(scroll.contentView.bounds.minX == 200)
        #expect(scroll.contentView.bounds.minY > 200)
    }

    @Test func shiftWheelStillScrollsHorizontally() throws {
        let scroll = pane()
        try send(scroll, x: 0, y: 20, shift: true)
        #expect(scroll.contentView.bounds.minX < 200)
        #expect(scroll.contentView.bounds.minY == 200)
    }

    @Test func phaseLessEventsChooseTheirOwnMainDirection() throws {
        let scroll = pane()
        try send(scroll, x: 2, y: 20)
        #expect(scroll.contentView.bounds.minX == 200)
        let y = scroll.contentView.bounds.minY
        try send(scroll, x: 20, y: 2)
        #expect(scroll.contentView.bounds.minX < 200)
        #expect(scroll.contentView.bounds.minY == y)
    }

    private func pane() -> DiffOverlayScrollView {
        let scroll = DiffOverlayScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.borderType = .noBorder
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        scroll.tile()
        scroll.contentView.scroll(to: NSPoint(x: 200, y: 200))
        return scroll
    }

    private func send(_ scroll: DiffOverlayScrollView, x: Int32, y: Int32,
                      phase: Int64 = 0, momentum: Int64 = 0, shift: Bool = false) throws {
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0))
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        if shift { cg.flags = .maskShift }
        scroll.scrollWheel(with: try #require(NSEvent(cgEvent: cg)))
    }

    @Test func preciseAndMomentumScrollEventsStayInsideAllFourEdges() throws {
        let scroll = DiffOverlayScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.borderType = .noBorder
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        scroll.tile()
        for phase in [Int64(1), Int64(2)] {
            for delta in [Int32(10000), -10000] {
                let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: delta, wheel2: delta, wheel3: 0))
                cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
                cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: phase)
                let event = try #require(NSEvent(cgEvent: cg))
                scroll.scrollWheel(with: event)
                let rect = scroll.contentView.documentRect
                let bounds = scroll.contentView.bounds
                #expect(bounds.minX >= rect.minX)
                #expect(bounds.minY >= rect.minY)
                #expect(bounds.maxX <= rect.maxX)
                #expect(bounds.maxY <= rect.maxY)
            }
        }
    }
}
