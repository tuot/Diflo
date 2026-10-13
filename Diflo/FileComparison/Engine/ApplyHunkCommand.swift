import Foundation

nonisolated enum HunkApplicationError: Error, Equatable {
    case staleRevision
    case invalidRange
}

nonisolated enum ApplyHunkCommand {
    static func apply(
        _ hunk: DiffHunk,
        from source: ComparisonSide,
        left: EditorBuffer,
        right: EditorBuffer
    ) throws -> String {
        guard hunk.leftRevision == left.revision, hunk.rightRevision == right.revision else {
            throw HunkApplicationError.staleRevision
        }

        let sourceBuffer = source == .left ? left : right
        let targetBuffer = source == .left ? right : left
        let sourceRange = source == .left ? hunk.leftLineRange : hunk.rightLineRange
        let targetRange = source == .left ? hunk.rightLineRange : hunk.leftLineRange

        guard sourceRange.upperBound <= sourceBuffer.lines.count,
              targetRange.upperBound <= targetBuffer.lines.count else {
            throw HunkApplicationError.invalidRange
        }

        var lines = targetBuffer.lines
        lines.replaceSubrange(targetRange, with: sourceBuffer.lines[sourceRange])
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n") + (targetBuffer.hasTrailingNewline ? "\n" : "")
    }
}
