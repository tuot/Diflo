import AppKit
import Testing
@testable import Diflo

@MainActor
struct SharedUndoTests {
    @Test(arguments: ["header\nmerged\nfooter", ""])
    func undoingWholeDocumentEditsRestoresTheCaret(text: String) {
        let editor = DiffTextView.createStandard(side: .left)
        editor.configure(text: "header\noriginal\nfooter", lineCount: 3, hunks: [], side: .left, selectedHunkID: nil)
        let history = editor.undoManager!
        history.groupsByEvent = false
        editor.setSelectedRange(NSRange(location: 9, length: 0))
        history.beginUndoGrouping()
        editor.applyExternalText(text, undoable: true)
        history.endUndoGrouping()
        let editedSelection = editor.selectedRange()

        history.undo()
        #expect(editor.string == "header\noriginal\nfooter")
        #expect(editor.selectedRange() == NSRange(location: 9, length: 0))
        history.redo()
        #expect(editor.string == text)
        #expect(editor.selectedRange() == editedSelection)
        history.undo()
        #expect(editor.selectedRange() == NSRange(location: 9, length: 0))
    }

    @Test func undoingClearRestoresAnExistingSelectionWithUTF16Offsets() {
        let editor = DiffTextView.createStandard(side: .left)
        editor.configure(text: "你好🌟abc", lineCount: 1, hunks: [], side: .left, selectedHunkID: nil)
        let history = editor.undoManager!
        history.groupsByEvent = false
        editor.setSelectedRange(NSRange(location: 2, length: 2))
        history.beginUndoGrouping()
        editor.applyExternalText("", undoable: true)
        history.endUndoGrouping()

        history.undo()
        #expect(editor.string == "你好🌟abc")
        #expect(editor.selectedRange() == NSRange(location: 2, length: 2))
        history.redo()
        #expect(editor.string.isEmpty)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test func undoAndRedoFollowTheOrderOfEditsAcrossBothEditors() {
        let shared = UndoManager()
        shared.groupsByEvent = false
        let left = DiffTextView.createStandard(side: .left)
        let right = DiffTextView.createStandard(side: .right)
        left.sharedUndoManager = shared
        right.sharedUndoManager = shared
        left.configure(text: "left", lineCount: 1, hunks: [], side: .left, selectedHunkID: nil)
        right.configure(text: "right", lineCount: 1, hunks: [], side: .right, selectedHunkID: nil)
        shared.beginUndoGrouping()
        left.applyExternalText("left edited", undoable: true)
        shared.endUndoGrouping()
        shared.beginUndoGrouping()
        right.applyExternalText("", undoable: true)
        shared.endUndoGrouping()
        left.undoManager?.undo()
        #expect(right.string == "right")
        #expect(left.string == "left edited")
        right.undoManager?.undo()
        #expect(left.string == "left")
        left.undoManager?.redo()
        #expect(left.string == "left edited")
        left.undoManager?.redo()
        #expect(right.string.isEmpty)
    }
}
