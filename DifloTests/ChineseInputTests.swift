import AppKit
import Testing
@testable import Diflo

@MainActor
struct ChineseInputTests {
    @Test func refreshingTheEditorPreservesActiveComposition() {
        let editor = DiffTextView.createStandard(side: .left)
        editor.configure(text: "", lineCount: 0, hunks: [], side: .left, selectedHunkID: nil)
        editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let selection = editor.selectedRange()
        let markedRange = editor.markedRange()
        editor.configure(text: "", lineCount: 0, hunks: [], side: .left, selectedHunkID: nil)
        editor.updateDiffHighlights(lineCount: 0, hunks: [], side: .left, selectedHunkID: nil)
        #expect(editor.string == "nihao")
        #expect(editor.hasMarkedText())
        #expect(editor.markedRange() == markedRange)
        #expect(editor.selectedRange() == selection)
    }

    @Test func coordinatorPublishesChineseOnlyAfterTheCandidateIsCommitted() {
        var edits: [String] = []
        let buffer = EditorBuffer.blank(named: "左侧")
        let parent = SingleDiffTextView(side: .left, buffer: buffer, oppositeLines: [], hunks: [], selectedHunkID: nil, coordinator: DualScrollCoordinator(), onEdit: { edits.append($0) }, onCursorChanged: { _ in })
        let coordinator = parent.makeCoordinator()
        let editor = DiffTextView.createStandard(side: .left)
        editor.delegate = coordinator
        coordinator.textView = editor
        coordinator.configure(buffer: buffer, oppositeLines: [], hunks: [], selectedHunkID: nil)
        editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        coordinator.configure(buffer: buffer, oppositeLines: [], hunks: [], selectedHunkID: nil)
        #expect(edits.isEmpty)
        #expect(editor.string == "nihao")
        #expect(editor.hasMarkedText())
        editor.insertText("你好", replacementRange: NSRange(location: NSNotFound, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        #expect(!editor.hasMarkedText())
        #expect(editor.string == "你好")
        #expect(edits.last == "你好")
    }
    @Test func committingAnOldCompositionDoesNotOverwriteANewDocument() {
        var edits: [String] = []
        let buffer = EditorBuffer.blank(named: "left")
        var parent = SingleDiffTextView(side: .left, buffer: buffer, oppositeLines: [], hunks: [], selectedHunkID: nil, coordinator: DualScrollCoordinator(), onEdit: { edits.append($0) }, onCursorChanged: { _ in })
        let coordinator = parent.makeCoordinator()
        let editor = DiffTextView.createStandard(side: .left)
        editor.delegate = coordinator
        coordinator.textView = editor
        coordinator.configure(buffer: buffer, oppositeLines: [], hunks: [], selectedHunkID: nil)
        editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let next = EditorBuffer.blank(named: "next").updatingText("new document")
        parent = SingleDiffTextView(side: .left, buffer: next, oppositeLines: [], hunks: [], selectedHunkID: nil, coordinator: parent.coordinator, onEdit: { edits.append($0) }, onCursorChanged: { _ in })
        coordinator.parent = parent
        coordinator.configure(buffer: next, oppositeLines: [], hunks: [], selectedHunkID: nil)
        editor.insertText("你好", replacementRange: NSRange(location: NSNotFound, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        #expect(editor.string == "new document")
        #expect(edits.isEmpty)
    }

}
