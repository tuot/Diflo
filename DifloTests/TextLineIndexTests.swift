import Foundation
import Testing
@testable import Diflo

struct TextLineIndexTests {
    @Test func indexesUTF16AndTrailingDisplayLine() {
        let index = TextLineIndex(normalizedText: "🙂\nx\n")
        #expect(index.lines == ["🙂", "x"])
        #expect(index.utf16Starts == [0, 3, 5])
        #expect(index.line(containingUTF16Offset: 3) == 1)
        #expect(index.line(containingUTF16Offset: 5) == 2)
        #expect(index.hasTrailingNewline)
    }

    @Test func emptyAndSingleNewlineKeepParserSemantics() {
        #expect(TextLineIndex(normalizedText: "").lines.isEmpty)
        #expect(TextLineIndex(normalizedText: "").utf16Starts == [0])
        #expect(TextLineIndex(normalizedText: "\n").lines == [""])
    }

    @Test func snapshotRemainsUnchangedAfterEditing() throws {
        let original = EditorBuffer.blank(named: "left").updatingText("a🙂b\r\nc")
        let updated = try original.applying(TextEdit(
            range: NSRange(location: 1, length: 2), replacement: "x\r\ny", baseRevision: original.revision
        ))
        #expect(original.lines == ["a🙂b", "c"])
        #expect(updated.text == "ax\nyb\nc")
        #expect(updated.lines == ["ax", "yb", "c"])
        #expect(updated.lineIndex.utf16Starts == [0, 3, 6])
        #expect(updated.revision == original.revision + 1)
    }

    @Test func rejectsStaleAndInvalidEdits() {
        let buffer = EditorBuffer.blank(named: "left").updatingText("🙂")
        #expect(throws: TextEditError.staleRevision) {
            try buffer.applying(TextEdit(range: NSRange(location: 0, length: 0), replacement: "x", baseRevision: 0))
        }
        #expect(throws: TextEditError.invalidRange) {
            try buffer.applying(TextEdit(range: NSRange(location: 1, length: 1), replacement: "x", baseRevision: buffer.revision))
        }
    }
}
