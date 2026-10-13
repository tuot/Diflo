import Foundation

nonisolated struct DiffResult: Equatable, Sendable {
    let leftFile: ParsedTextFile
    let rightFile: ParsedTextFile
    let rows: [DiffRow]
    let hasTrailingNewlineDifference: Bool
    var hunks: [DiffHunk]
    let alignment: DiffAlignment
    let precision: DiffPrecision
    let options: ComparisonOptions
    let leftRevision: Int
    let rightRevision: Int

    init(leftFile: ParsedTextFile, rightFile: ParsedTextFile, rows: [DiffRow],
         hasTrailingNewlineDifference: Bool, hunks: [DiffHunk] = [],
         alignment: DiffAlignment? = nil, precision: DiffPrecision = .exact,
         options: ComparisonOptions = .default, leftRevision: Int = 0, rightRevision: Int = 0) {
        self.leftFile = leftFile
        self.rightFile = rightFile
        self.rows = rows
        self.hasTrailingNewlineDifference = hasTrailingNewlineDifference
        self.hunks = hunks
        self.alignment = alignment ?? DiffAlignment(rows: rows)
        self.precision = precision
        self.options = options
        self.leftRevision = leftRevision
        self.rightRevision = rightRevision
    }

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
