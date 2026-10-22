import AppKit
import Testing
@testable import Diflo

@MainActor
struct TextKit2EditorTests {
    @Test func insertingBeforeAnInlineHighlightDoesNotLeaveStaleRenderingAttributes() async throws {
        let editor = DiffTextView.createStandard(side: .left)
        let hunk = DiffHunk(id: "inline", kind: .modified, leftLineRange: 0..<1, rightLineRange: 0..<1,
                            virtualRowRange: 0..<1, leftRevision: 0, rightRevision: 0)
        editor.configure(text: "prefix OLD tail", lineCount: 1, hunks: [hunk], side: .left,
                         selectedHunkID: nil, oppositeLines: ["prefix NEW tail"])
        for _ in 0..<100 {
            if inlineBackground(in: editor, at: 7) != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(inlineBackground(in: editor, at: 7) != nil)
        editor.insertText("XXXXX", replacementRange: NSRange(location: 0, length: 0))
        editor.updateDiffHighlights(lineCount: 1, hunks: [], side: .left, selectedHunkID: nil)
        #expect(editor.string == "XXXXXprefix OLD tail")
        #expect(inlineBackground(in: editor, at: 12) == nil)
        #expect(editor.textLayoutManager != nil)
    }

    @Test(arguments: ["", "first\n", "你好🌟\nمرحبا\n", String(repeating: "x", count: 2_000) + "\nend", String(repeating: "x\t", count: 50) + "END\nnext"])
    func lineGeometryMatchesFixedRows(text: String) throws {
        let editor = DiffTextView.createStandard(side: .left)
        editor.configure(text: text, lineCount: text.components(separatedBy: "\n").count, hunks: [], side: .left, selectedHunkID: nil)
        for line in editor.lineIndex.utf16Starts.indices {
            let rect = try #require(editor.lineRect(at: line))
            #expect(abs(rect.minY - DiffTextView.verticalInset - CGFloat(line) * DiffTextView.rowHeight) < 0.1)
            #expect(abs(rect.height - DiffTextView.rowHeight) < 0.1)
            #expect(rect.minX < 1, "Code editor paragraphs must stay visible at the left edge, including RTL text")
        }
        #expect(editor.textLayoutManager != nil)
    }

    @Test func largeDocumentScrollSizeIncludesTrailingEmptyLineAndLongOffscreenText() throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let editor = DiffTextView.createStandard(side: .left)
        scroll.documentView = editor
        let manager = try #require(editor.textLayoutManager)
        let counter = TextKit2FragmentCounter()
        manager.delegate = counter
        let text = Array(repeating: "short", count: 19_999).joined(separator: "\n") + "\n" + String(repeating: "x", count: 2_000) + "\n"
        editor.configure(text: text, lineCount: 20_000, hunks: [], side: .left, selectedHunkID: nil)
        editor.resizeDocument(minimumSize: scroll.contentSize)
        #expect(editor.frame.height >= 20_001 * DiffTextView.rowHeight + 2 * DiffTextView.verticalInset)
        #expect(editor.frame.width > 10_000)
        #expect(editor.textLayoutManager != nil)
        #expect(counter.fragments < 500,
                "Sizing a 20,000-line document must not request complete text layout")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 19_990 * DiffTextView.rowHeight))
        editor.resizeDocument(minimumSize: scroll.contentSize)
        #expect(editor.textLayoutManager != nil)
        #expect(counter.fragments < 500, "Scrolling to distant lines must keep layout local")
    }

    @Test func inlineHighlightRendersWithoutChangingTheDocumentOrUndoHistory() async throws {
        let editor = DiffTextView.createStandard(side: .left)
        editor.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        editor.appearance = try #require(NSAppearance(named: .aqua))
        let text = "你好🌟 OLD tail"
        let hunk = DiffHunk(id: "inline", kind: .modified, leftLineRange: 0..<1, rightLineRange: 0..<1,
                            virtualRowRange: 0..<1, leftRevision: 0, rightRevision: 0)
        editor.configure(text: text, lineCount: 1, hunks: [hunk], side: .left, selectedHunkID: nil,
                         oppositeLines: ["你好🌟 NEW tail"])
        let offset = (text as NSString).range(of: "OLD").location
        let storage = try #require(editor.textStorage)
        let history = try #require(editor.undoManager)
        #expect(!history.canUndo)
        for _ in 0..<100 {
            if inlineBackground(in: editor, at: offset) != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(inlineBackground(in: editor, at: offset) != nil)
        #expect(storage.attribute(.backgroundColor, at: offset, effectiveRange: nil) == nil)
        #expect(editor.string == text)
        #expect(!history.canUndo)
        #expect(editor.textLayoutManager != nil)

        let manager = try #require(editor.textLayoutManager)
        let content = try #require(manager.textContentManager)
        let start = try #require(content.location(content.documentRange.location, offsetBy: offset))
        let end = try #require(content.location(start, offsetBy: 3))
        let range = try #require(NSTextRange(location: start, end: end))
        manager.ensureLayout(for: range)
        var segment: NSRect?
        manager.enumerateTextSegments(in: range, type: .standard, options: []) { _, rect, _, _ in
            segment = rect.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
            return false
        }
        let rect = try #require(segment)
        let captureBounds = editor.bounds
        let bitmap = try #require(editor.bitmapImageRepForCachingDisplay(in: captureBounds))
        editor.cacheDisplay(in: captureBounds, to: bitmap)
        // cacheDisplay produces backing pixels; the editor geometry is in points.
        let scaleX = CGFloat(bitmap.pixelsWide) / captureBounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / captureBounds.height
        var highlightedPixels = 0
        let minX = max(0, Int(rect.minX * scaleX)), maxX = min(bitmap.pixelsWide, Int(rect.maxX * scaleX))
        let minY = max(0, Int(rect.minY * scaleY)), maxY = min(bitmap.pixelsHigh, Int(rect.maxY * scaleY))
        for y in minY..<maxY {
            for x in minX..<maxX {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.blueComponent > color.redComponent + 0.1 {
                    highlightedPixels += 1
                }
            }
        }
        #expect(highlightedPixels > (maxX - minX) * (maxY - minY) / 10)
        editor.updateDiffHighlights(lineCount: 1, hunks: [], side: .left, selectedHunkID: nil)
        #expect(inlineBackground(in: editor, at: offset) == nil)
        #expect(!history.canUndo)
        #expect(editor.textLayoutManager != nil)
    }

    @Test func editorKeepsTextKit2AfterEditingAndUndo() throws {
        let editor = DiffTextView.createStandard(side: .left)
        #expect(editor.textLayoutManager != nil)
        editor.configure(text: "你好🌟\nnext\n", lineCount: 2, hunks: [], side: .left, selectedHunkID: nil)
        #expect(editor.textLayoutManager != nil)
        let history = try #require(editor.undoManager)
        history.groupsByEvent = false
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        history.beginUndoGrouping()
        editor.applyExternalText("changed", undoable: true)
        history.endUndoGrouping()
        history.undo()
        #expect(editor.string == "你好🌟\nnext\n")
        #expect(editor.selectedRange() == NSRange(location: 4, length: 0))
        #expect(editor.textLayoutManager != nil)
        history.redo()
        #expect(editor.string == "changed")
        #expect(editor.textLayoutManager != nil)
    }
}
