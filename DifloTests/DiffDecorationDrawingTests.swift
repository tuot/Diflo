import AppKit
import Testing
@testable import Diflo

@MainActor
struct DiffDecorationDrawingTests {
    @Test func gutterDoesNotPaintOverAdjacentEditors() {
        #expect(decorationKeepsDrawingInsideBounds(ChangeGutterView()))
    }

    @Test func overviewDoesNotPaintOverAdjacentEditors() {
        #expect(decorationKeepsDrawingInsideBounds(DiffOverviewView()))
    }

    private func decorationKeepsDrawingInsideBounds(_ view: NSView) -> Bool {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.magenta.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        context.cgContext.translateBy(x: 40, y: 20)
        view.frame = NSRect(x: 0, y: 0, width: 20, height: 30)
        view.draw(NSRect(x: -40, y: -20, width: 120, height: 80))
        context.flushGraphics()
        let outside = bitmap.colorAt(x: 5, y: 5)!.usingColorSpace(.sRGB)!
        let inside = bitmap.colorAt(x: 50, y: 40)!.usingColorSpace(.sRGB)!
        return outside.redComponent > 0.95 && outside.greenComponent < 0.05 && outside.blueComponent > 0.95 && inside.greenComponent > 0.1
    }
}
