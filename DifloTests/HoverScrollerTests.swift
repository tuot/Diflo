import AppKit
import Testing
@testable import Diflo

@MainActor
struct HoverScrollerTests {
    @Test(arguments: [false, true])
    func thumbExpandsOnlyWhileHovered(horizontal: Bool) throws {
        let scroller = HoverScroller(frame: NSRect(x: 0, y: 0, width: horizontal ? 200 : 16, height: horizontal ? 16 : 200))
        scroller.scrollerStyle = .legacy
        scroller.doubleValue = 0.5
        scroller.knobProportion = 0.4
        let idle = try thumbThickness(scroller, horizontal: horizontal)
        let enter = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        scroller.mouseEntered(with: enter)
        let hovered = try thumbThickness(scroller, horizontal: horizontal)
        #expect(idle > 0 && idle <= 4)
        #expect(hovered >= 7 && hovered > idle)
        let exit = try #require(NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        scroller.mouseExited(with: exit)
        #expect(try thumbThickness(scroller, horizontal: horizontal) == idle)
    }

    private func thumbThickness(_ scroller: NSScroller, horizontal: Bool) throws -> Int {
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
        }.count
    }
}

@MainActor
struct OverlayScrollLayoutTests {
    @Test func visibleScrollersDoNotReserveSpaceBetweenEditorAndGutter() {
        let scroll = DiffOverlayScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = false
        scroll.verticalScroller = HoverScroller(frame: .zero)
        scroll.horizontalScroller = HoverScroller(frame: .zero)
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1600, height: 1200))
        scroll.scrollerStyle = .legacy
        scroll.tile()
        #expect(scroll.contentView.frame == scroll.bounds)
        #expect(scroll.scrollerStyle == .overlay)
        #expect(scroll.verticalScroller?.frame.intersects(scroll.contentView.frame) == true)
        #expect(scroll.horizontalScroller?.frame.intersects(scroll.contentView.frame) == true)
    }
}

@MainActor
struct TrackpadBoundaryTests {
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
