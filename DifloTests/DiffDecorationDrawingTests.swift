import AppKit
import Testing
@testable import Diflo

@MainActor
struct DiffDecorationDrawingTests {
    @Test func partialBackgroundRedrawDoesNotRepaintOutsideTheDirtyRect() throws {
        let editor = DiffTextView.createStandard(side: .left)
        let hunk = DiffHunk(id: "modified", kind: .modified, leftLineRange: 0..<2,
                            rightLineRange: 0..<2, virtualRowRange: 0..<2, leftRevision: 0, rightRevision: 0)
        editor.configure(text: "before\nunchanged", lineCount: 2, hunks: [hunk], side: .left, selectedHunkID: nil)
        editor.frame = NSRect(x: 0, y: 0, width: 400, height: 80)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 80,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.magenta.setFill()
        editor.bounds.fill()
        editor.drawBackground(in: NSRect(x: 0, y: 8, width: 100, height: DiffTextView.rowHeight))
        let outside = try #require(bitmap.colorAt(x: 300, y: 80 - Int(8 + DiffTextView.rowHeight / 2))?.usingColorSpace(.sRGB))
        #expect(outside.redComponent > 0.95)
        #expect(outside.greenComponent < 0.05)
        #expect(outside.blueComponent > 0.95)
    }

    @Test func scrollingKeepsExistingInlineHighlightsWhileRefinementRuns() async throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let editor = DiffTextView.createStandard(side: .left)
        scroll.documentView = editor
        let lines = Array(repeating: "prefix OLD tail", count: 30)
        let hunk = DiffHunk(id: "modified", kind: .modified, leftLineRange: 0..<30,
                            rightLineRange: 0..<30, virtualRowRange: 0..<30, leftRevision: 0, rightRevision: 0)
        editor.configure(text: lines.joined(separator: "\n"), lineCount: 30, hunks: [hunk],
                         side: .left, selectedHunkID: nil, oppositeLines: Array(repeating: "prefix NEW tail", count: 30))
        editor.resizeDocument(minimumSize: scroll.contentSize)
        let manager = try #require(editor.layoutManager)
        let offset = editor.lineIndex.utf16Starts[4] + 7
        for _ in 0..<100 {
            if manager.temporaryAttribute(.backgroundColor, atCharacterIndex: offset, effectiveRange: nil) != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: offset, effectiveRange: nil) != nil)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: DiffTextView.rowHeight))
        editor.refreshInlineHighlights()
        #expect(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: offset, effectiveRange: nil) != nil)
        let newlyVisibleOffset = editor.lineIndex.utf16Starts[11] + 7
        for _ in 0..<100 {
            if manager.temporaryAttribute(.backgroundColor, atCharacterIndex: newlyVisibleOffset, effectiveRange: nil) != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: newlyVisibleOffset, effectiveRange: nil) != nil)
        #expect(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: offset, effectiveRange: nil) != nil)
        editor.updateDiffHighlights(lineCount: 30, hunks: [], side: .left, selectedHunkID: nil)
        #expect(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: offset, effectiveRange: nil) == nil)
    }

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
