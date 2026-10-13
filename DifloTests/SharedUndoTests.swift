import AppKit
import Testing
@testable import Diflo

@MainActor
struct SharedUndoTests {
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
