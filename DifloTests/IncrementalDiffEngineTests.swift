import Foundation
import Testing
@testable import Diflo

struct IncrementalDiffEngineTests {
    @Test func localEditPreservesAlignmentWithoutFullComparison() throws {
        let original = EditorBuffer.blank(named: "left").updatingText((0..<100).map { "line \($0)" }.joined(separator: "\n"))
        let right = EditorBuffer.blank(named: "right").updatingText(original.text)
        let previous = LineDiffEngine.compare(left: original.asParsedFile(), right: right.asParsedFile(), leftRevision: original.revision, rightRevision: right.revision)
        let edit = TextEdit(range: NSRange(location: original.lineIndex.utf16Starts[50], length: 7), replacement: "changed", baseRevision: original.revision)
        let left = try original.applying(edit)
        let outcome = try IncrementalDiffEngine.compareDetailed(previous: previous, left: left, right: right, edit: edit, side: .left, options: .default)
        #expect(outcome.fallbackReason == nil)
        #expect(outcome.recomputedLineCount < 20)
        #expect(outcome.result.rows.filter { $0.kind != .unchanged }.count == 1)
        #expect(outcome.result.leftRevision == left.revision)
    }
    @Test func staleEditFallsBackToCurrentSnapshots() throws {
        let left = EditorBuffer.blank(named: "left").updatingText("a\nb\nc")
        let right = EditorBuffer.blank(named: "right").updatingText("a\nb\nc")
        let previous = LineDiffEngine.compare(left: left.asParsedFile(), right: right.asParsedFile(), leftRevision: left.revision, rightRevision: right.revision)
        let edit = TextEdit(range: NSRange(location: 2, length: 1), replacement: "x", baseRevision: 99)
        let outcome = try IncrementalDiffEngine.compareDetailed(previous: previous, left: left, right: right, edit: edit, side: .left, options: .default)
        #expect(outcome.fallbackReason != nil)
        #expect(outcome.result.differenceCount == 0)
    }
}
