import AppKit
import Testing
@testable import Diflo

@MainActor
struct MeldRenderingTests {
    @Test func emptyBandAndRowBandShareTheSameConnectorCoordinates() {
        let empty = DiffTextView.diffBandRect(for: 3..<3, width: 64, offset: 7.5)
        let row = DiffTextView.diffBandRect(for: 3..<4, width: 400, offset: 7.5)
        #expect(empty.height == 2)
        #expect(empty.midY == row.minY)
        #expect(row.height == DiffTextView.rowHeight)
    }

    @Test func textRowsMatchGutterAndConnectorHeight() throws {
        let editor = DiffTextView.createStandard(side: .left)
        editor.configure(text: "same\nchanged\nend", lineCount: 3, hunks: [], side: .left, selectedHunkID: nil)
        let manager = try #require(editor.layoutManager)
        manager.ensureLayout(for: try #require(editor.textContainer))
        let first = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let second = manager.lineFragmentRect(forGlyphAt: 5, effectiveRange: nil)
        #expect(abs(second.minY - first.minY - DiffTextView.rowHeight) < 0.1)
    }

    @Test func longLinesDoNotWrapAndDisplaceFollowingConnectors() throws {
        let editor = DiffTextView.createStandard(side: .left)
        editor.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        editor.configure(text: String(repeating: "x", count: 200) + "\nend", lineCount: 2, hunks: [], side: .left, selectedHunkID: nil)
        let manager = try #require(editor.layoutManager)
        manager.ensureLayout(for: try #require(editor.textContainer))
        let second = manager.lineFragmentRect(forGlyphAt: 201, effectiveRange: nil)
        #expect(abs(second.minY - DiffTextView.rowHeight) < 0.1)
    }

    @Test(arguments: [DiffHunk.Kind.modified, .leftOnly, .rightOnly])
    func changedBlocksFillTheEntireEditorWidth(kind: DiffHunk.Kind) throws {
        let editor = DiffTextView.createStandard(side: .left)
        let hunk = DiffHunk(id: "test", kind: kind, leftLineRange: 1..<3, rightLineRange: 1..<2, virtualRowRange: 1..<3, leftRevision: 0, rightRevision: 0)
        editor.configure(text: "same\nleft\nextra\nend", lineCount: 4, hunks: [hunk], side: .left, selectedHunkID: nil)
        editor.frame = NSRect(x: 0, y: 0, width: 400, height: 120)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 120, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 400, height: 120).fill()
        editor.drawBackground(in: editor.bounds)
        let color = try #require(bitmap.colorAt(x: 300, y: 120 - Int(DiffTextView.verticalInset + 1.5 * DiffTextView.rowHeight))?.usingColorSpace(.sRGB))
        switch kind {
        case .modified: #expect(color.blueComponent - color.redComponent > 0.05)
        case .leftOnly: #expect(color.redComponent - color.greenComponent > 0.05)
        case .rightOnly: #expect(color.greenComponent - color.redComponent > 0.05)
        }
    }
}
