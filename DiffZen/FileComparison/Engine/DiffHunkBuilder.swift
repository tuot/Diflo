import Foundation

nonisolated enum DiffHunkBuilder {
    static func build(
        rows: [DiffRow],
        leftRevision: Int,
        rightRevision: Int
    ) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var index = 0

        while index < rows.count {
            guard rows[index].kind != .unchanged else {
                index += 1
                continue
            }

            let start = index
            while index < rows.count, rows[index].kind != .unchanged {
                index += 1
            }

            let leftStart = rows[..<start].count { $0.leftLineNumber != nil }
            let rightStart = rows[..<start].count { $0.rightLineNumber != nil }
            let changedRows = rows[start..<index]
            let leftCount = changedRows.count { $0.leftLineNumber != nil }
            let rightCount = changedRows.count { $0.rightLineNumber != nil }
            let leftRange = leftStart..<(leftStart + leftCount)
            let rightRange = rightStart..<(rightStart + rightCount)
            let kind: DiffHunk.Kind = if leftRange.isEmpty {
                .rightOnly
            } else if rightRange.isEmpty {
                .leftOnly
            } else {
                .modified
            }

            hunks.append(
                DiffHunk(
                    id: "\(leftRevision):\(rightRevision):\(start):\(index)",
                    kind: kind,
                    leftLineRange: leftRange,
                    rightLineRange: rightRange,
                    virtualRowRange: start..<index,
                    leftRevision: leftRevision,
                    rightRevision: rightRevision
                )
            )
        }
        return hunks
    }
}
