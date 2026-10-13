import Foundation

nonisolated enum IncrementalDiffEngine {
    struct Outcome: Sendable {
        let result: DiffResult
        let recomputedLineCount: Int
        let fallbackReason: String?
    }

    static func compare(previous: DiffResult, left: EditorBuffer, right: EditorBuffer, edit: TextEdit, side: ComparisonSide, options: ComparisonOptions) throws -> DiffResult {
        try compareDetailed(previous: previous, left: left, right: right, edit: edit, side: side, options: options).result
    }

    static func compareDetailed(previous: DiffResult, left: EditorBuffer, right: EditorBuffer, edit: TextEdit, side: ComparisonSide, options: ComparisonOptions) throws -> Outcome {
        try Task.checkCancellation()
        func fallback(_ reason: String) throws -> Outcome {
            .init(result: try LineDiffEngine.compareCancellable(left: left.asParsedFile(), right: right.asParsedFile(), leftRevision: left.revision, rightRevision: right.revision, options: options), recomputedLineCount: left.lineCount + right.lineCount, fallbackReason: reason)
        }
        guard previous.precision == .exact else { return try fallback("previous-coarse") }
        guard previous.options == options else { return try fallback("options-changed") }
        let oldRevision = side == .left ? previous.leftRevision : previous.rightRevision
        let current = side == .left ? left : right
        let other = side == .left ? right : left
        let otherRevision = side == .left ? previous.rightRevision : previous.leftRevision
        guard edit.baseRevision == oldRevision, current.revision == oldRevision + 1, other.revision == otherRevision else { return try fallback("revision-mismatch") }
        let oldFile = side == .left ? previous.leftFile : previous.rightFile
        let otherFile = side == .left ? previous.rightFile : previous.leftFile
        let oldText = text(of: oldFile)
        let oldNSString = oldText as NSString
        guard edit.range.location >= 0, edit.range.length >= 0, edit.range.location <= oldNSString.length, edit.range.length <= oldNSString.length - edit.range.location,
              Range(edit.range, in: oldText) != nil else { return try fallback("invalid-edit-range") }
        guard LineParser.normalize(oldNSString.replacingCharacters(in: edit.range, with: edit.replacement)) == current.text,
              text(of: otherFile) == other.text else { return try fallback("snapshot-mismatch") }
        let index = TextLineIndex(normalizedText: oldText)
        let first = index.line(containingUTF16Offset: edit.range.location)
        let last = index.line(containingUTF16Offset: NSMaxRange(edit.range))
        // Keep a full untouched line on either side of the edit as context.
        var before: (left: Int, right: Int)?
        var after: (left: Int, right: Int)?
        for (ordinal, block) in previous.alignment.blocks.enumerated() where block.kind == .equal {
            if ordinal & 1023 == 0 { try Task.checkCancellation() }
            let range = side == .left ? block.left : block.right
            let preceding = min(range.upperBound - 1, first - 2)
            if preceding >= range.lowerBound {
                let offset = preceding - range.lowerBound
                before = (block.left.lowerBound + offset, block.right.lowerBound + offset)
            }
            let following = max(range.lowerBound, last + 2)
            if after == nil && following < range.upperBound {
                let offset = following - range.lowerBound
                after = (block.left.lowerBound + offset, block.right.lowerBound + offset)
            }
        }
        guard let before, let after else { return try fallback("missing-equal-boundary") }
        let startLeft = before.left + 1, startRight = before.right + 1
        let oldEndLeft = after.left, oldEndRight = after.right
        let delta = current.lineCount - oldFile.lines.count
        let endLeft = oldEndLeft + (side == .left ? delta : 0)
        let endRight = oldEndRight + (side == .right ? delta : 0)
        guard endLeft >= startLeft, endRight >= startRight, endLeft < left.lineCount, endRight < right.lineCount else { return try fallback("unstable-boundary") }
        guard endLeft - startLeft + endRight - startRight <= 4096 else { return try fallback("region-too-large") }
        // Global uniqueness is deliberately conservative for repeated-line files.
        let anchors = [previous.leftFile.lines[before.left], previous.leftFile.lines[after.left]]
        for anchor in anchors {
            for lines in [left.lines, right.lines] {
                var count = 0
                for (offset, line) in lines.enumerated() {
                    if offset & 1023 == 0 { try Task.checkCancellation() }
                    if line == anchor { count += 1; if count > 1 { break } }
                }
                if count != 1 { return try fallback("ambiguous-boundary") }
            }
        }
        guard left.lines[before.left] == right.lines[before.right], left.lines[endLeft] == right.lines[endRight],
              left.lines[endLeft] == anchors[1], right.lines[endRight] == anchors[1] else { return try fallback("changed-boundary") }
        var prefixEnd: Int?, suffixStart: Int?
        for (i, row) in previous.rows.enumerated() {
            if i & 1023 == 0 { try Task.checkCancellation() }
            if row.leftLineNumber == before.left + 1 && row.rightLineNumber == before.right + 1 { prefixEnd = i + 1 }
            if row.leftLineNumber == after.left + 1 && row.rightLineNumber == after.right + 1 { suffixStart = i; break }
        }
        guard let prefixEnd, let suffixStart, prefixEnd <= suffixStart else { return try fallback("invalid-row-boundary") }
        let localLeft = slice(left.asParsedFile(), range: startLeft..<endLeft)
        let localRight = slice(right.asParsedFile(), range: startRight..<endRight)
        let local = try LineDiffEngine.compareCancellable(left: localLeft, right: localRight, options: options)
        var rows = Array(previous.rows[..<prefixEnd])
        for (i, row) in local.rows.enumerated() {
            if i & 1023 == 0 { try Task.checkCancellation() }
            rows.append(shift(row, left: startLeft, right: startRight))
        }
        for (i, row) in previous.rows[suffixStart...].enumerated() {
            if i & 1023 == 0 { try Task.checkCancellation() }
            rows.append(shift(row, left: side == .left ? delta : 0, right: side == .right ? delta : 0))
        }
        try Task.checkCancellation()
        let result = LineDiffEngine.result(left: left.asParsedFile(), right: right.asParsedFile(), leftRevision: left.revision, rightRevision: right.revision, options: options, rows: rows, precision: local.precision)
        return .init(result: result, recomputedLineCount: localLeft.lines.count + localRight.lines.count, fallbackReason: nil)
    }

    private static func text(of file: ParsedTextFile) -> String {
        file.normalizedText.isEmpty && !file.lines.isEmpty ? file.lines.joined(separator: "\n") + (file.hasTrailingNewline ? "\n" : "") : file.normalizedText
    }

    private static func slice(_ file: ParsedTextFile, range: Range<Int>) -> ParsedTextFile {
        .init(url: file.url, displayName: file.displayName, lines: Array(file.lines[range]), hasTrailingNewline: false, encodingName: file.encodingName)
    }

    private static func shift(_ row: DiffRow, left: Int, right: Int) -> DiffRow {
        .init(leftText: row.leftText, rightText: row.rightText, leftLineNumber: row.leftLineNumber.map { $0 + left }, rightLineNumber: row.rightLineNumber.map { $0 + right }, kind: row.kind)
    }
}
