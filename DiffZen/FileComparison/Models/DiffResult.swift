import Foundation

nonisolated struct DiffResult: Equatable, Sendable {
    let leftFile: ParsedTextFile
    let rightFile: ParsedTextFile
    let rows: [DiffRow]
    let hasTrailingNewlineDifference: Bool
    var hunks: [DiffHunk] = []

    var insertedCount: Int {
        rows.count { $0.kind == .inserted }
    }

    var deletedCount: Int {
        rows.count { $0.kind == .deleted }
    }

    var modifiedCount: Int {
        rows.count { $0.kind == .modified }
    }

    var differenceCount: Int {
        insertedCount + deletedCount + modifiedCount + (hasTrailingNewlineDifference ? 1 : 0)
    }
}
