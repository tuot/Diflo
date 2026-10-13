import AppKit
import Testing
@testable import Diflo

@MainActor struct NativeDiffEditorTests {
    @Test func factoryUsesTextKit2() {
        let view = NativeDiffTextView(usingTextLayoutManager: true)
        #expect(view.textLayoutManager != nil)
        #expect(view.isEditable)
        #expect(view.allowsUndo)
    }

    @Test func externalReplacementPreservesSelectionAndSupportsUndo() {
        let view = NativeDiffTextView(usingTextLayoutManager: true)
        view.string = "a🙂b"
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.applyExternalText("a🙂changed", undoable: true)
        #expect(view.string == "a🙂changed")
        #expect(view.selectedRange().location == 3)
        view.undoManager?.undo()
        #expect(view.string == "a🙂b")
    }

    @Test func missingGeometryDoesNotInventCoordinates() {
        let geometry = DiffViewportGeometry(visibleLines: 4..<6, lineRects: [4: CGRect(x: 0, y: 80, width: 30, height: 20)])
        #expect(geometry.y(for: 1) == nil)
        #expect(geometry.y(for: 4.5) == 90)
    }
}
