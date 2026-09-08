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
            let currentKind = rows[index].kind

            // 对于修改行 (modified)，单行独立拆分为精细 Hunk，方便独立对比与逐行合并
            if currentKind == .modified {
                index += 1
            } else {
                // 连续插入或连续删除，聚合为同一个增删块
                while index < rows.count, rows[index].kind == currentKind {
                    index += 1
                }
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
