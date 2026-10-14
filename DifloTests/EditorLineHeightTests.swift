import AppKit
import Testing
@testable import Diflo

@MainActor
struct EditorLineHeightTests {
    @Test func unchangedRefreshDoesNotRewriteTextStorage() {
        let editor = DiffTextView.createStandard(side: .left)
        editor.configure(text: "one\ntwo", lineCount: 2, hunks: [], side: .left, selectedHunkID: nil)
        let revision = editor.textStorage?.string
        let storage = editor.textStorage!
        final class Counter: @unchecked Sendable { var edits = 0 }
        let counter = Counter()
        let observer = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { _ in counter.edits += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        editor.configure(text: "one\ntwo", lineCount: 2, hunks: [], side: .left, selectedHunkID: nil)
        #expect(counter.edits == 0)
        #expect(storage.string == revision)
    }

    @Test func externalMergeCanBeUndone() {
        let editor = DiffTextView.createStandard(side: .left)
        editor.configure(text: "before", lineCount: 1, hunks: [], side: .left, selectedHunkID: nil)
        editor.undoManager?.groupsByEvent = false
        editor.undoManager?.beginUndoGrouping()
        editor.applyExternalText("after", undoable: true)
        editor.undoManager?.endUndoGrouping()
        #expect(editor.string == "after")
        #expect(editor.undoManager?.canUndo == true)
        editor.undoManager?.undo()
        #expect(editor.string == "before")
    }

    @Test func rowHeightStaysCloseToTheFontMetrics() {
        let naturalHeight = ceil(DiffTextView.editorFont.ascender - DiffTextView.editorFont.descender + DiffTextView.editorFont.leading)
        #expect(DiffTextView.rowHeight >= naturalHeight)
        #expect(DiffTextView.rowHeight <= naturalHeight + 3)
    }

    @Test func caretUsesFontHeightAndStaysCenteredWithinTheRow() {
        let editor = DiffTextView.createStandard(side: .left)
        let proposed = NSRect(x: 10, y: 8, width: 1, height: 22)
        let caret = editor.fittedInsertionPointRect(proposed)
        let naturalHeight = ceil(DiffTextView.editorFont.ascender - DiffTextView.editorFont.descender + DiffTextView.editorFont.leading)
        #expect(caret.height == naturalHeight)
        #expect(caret.midY == proposed.midY)
        #expect(caret.minX == proposed.minX)
        #expect(editor.fittedInsertionPointRect(NSRect(x: 0, y: 0, width: 1, height: 5)).height == 5)
    }

    @Test func selectedMultilineBlockHasNoBordersBetweenItsRows() throws {
        let editor = DiffTextView.createStandard(side: .right)
        let hunk = DiffHunk(id: "test", kind: .rightOnly, leftLineRange: 0..<0, rightLineRange: 0..<5, virtualRowRange: 0..<5, leftRevision: 0, rightRevision: 0)
        editor.configure(text: "a\nb\nc\nd\ne", lineCount: 5, hunks: [hunk], side: .right, selectedHunkID: hunk.id)
        editor.frame = NSRect(x: 0, y: 0, width: 400, height: 150)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 150, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        editor.bounds.fill()
        editor.drawBackground(in: editor.bounds)
        let y = 150 - Int(DiffTextView.verticalInset + 2 * DiffTextView.rowHeight)
        let color = try #require(bitmap.colorAt(x: 300, y: y)?.usingColorSpace(.sRGB))
        #expect(color.greenComponent > color.blueComponent)
    }
}
