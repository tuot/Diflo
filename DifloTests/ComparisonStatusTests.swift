import Foundation
import AppKit
import Testing
@testable import Diflo

struct ComparisonStatusTests {
    @Test @MainActor func formatChangeKeepsMergeRevisionsCurrent() async throws {
        let session = ComparisonSession()
        session.startBlank()
        session.edit(.left, text: "old")
        session.edit(.right, text: "new")
        for _ in 0..<100 where session.isWorking { try await Task.sleep(for: .milliseconds(10)) }
        session.changeFormat(side: .left, encoding: .utf8BOM)
        for _ in 0..<100 where session.isWorking { try await Task.sleep(for: .milliseconds(10)) }
        let hunk = try #require(session.result?.hunks.first)
        #expect(hunk.leftRevision == session.leftBuffer.revision)
    }
    @Test @MainActor func finalNewlineHasVisibleMergeButtons() throws {
        let view = ChangeGutterView(frame: NSRect(x: 0, y: 0, width: 88, height: 200))
        let hunk = DiffHunk(id: "eof", kind: .modified, leftLineRange: 1..<1, rightLineRange: 1..<1, virtualRowRange: 1..<1, leftRevision: 0, rightRevision: 0, isTrailingNewline: true)
        view.configure(hunks: [hunk], selectedHunkID: nil, leftOffset: 0, rightOffset: 0, select: { _ in }, apply: { _, _ in })
        #expect(view.accessibilityChildren()?.count == 2)
    }
    @Test func finalNewlineHasNavigableMergeAction() throws {
        let left = EditorBuffer.blank(named: "left").updatingText("same\n")
        let right = EditorBuffer.blank(named: "right").updatingText("same")
        let result = LineDiffEngine.compare(left: left.asParsedFile(), right: right.asParsedFile(), leftRevision: left.revision, rightRevision: right.revision)
        let hunk = try #require(result.hunks.first)
        #expect(hunk.isTrailingNewline)
        #expect(try ApplyHunkCommand.apply(hunk, from: .left, left: left, right: right) == "same\n")
        #expect(try ApplyHunkCommand.apply(hunk, from: .right, left: left, right: right) == "same")
    }
    @Test func ignoredEqualityIsExplained() {
        let left = LineParser.parse("hello", url: URL(fileURLWithPath: "/tmp/a"), encodingName: "UTF-8")
        let right = LineParser.parse("HELLO", url: URL(fileURLWithPath: "/tmp/b"), encodingName: "UTF-8")
        let result = LineDiffEngine.compare(left: left, right: right, options: ComparisonOptions(ignoreCase: true))
        #expect(result.statusDescription == "按当前忽略规则相同")
    }
}
