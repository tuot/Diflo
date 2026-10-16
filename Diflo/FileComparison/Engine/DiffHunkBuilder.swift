import Foundation

nonisolated enum DiffHunkBuilder {
    static func build(
        rows: [DiffRow],
        leftRevision: Int,
        rightRevision: Int
    ) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var index = 0
        var leftOffset = 0
        var rightOffset = 0

        while index < rows.count {
            guard rows[index].kind != .unchanged else {
                if rows[index].leftLineNumber != nil { leftOffset += 1 }
                if rows[index].rightLineNumber != nil { rightOffset += 1 }
                index += 1
                continue
            }

            let start = index

            // 连续差异作为一个合并单元，包含不等长替换末尾的增删行。
            while index < rows.count, rows[index].kind != .unchanged {
                index += 1
            }

            let leftStart = leftOffset
            let rightStart = rightOffset
            let changedRows = rows[start..<index]
            let leftCount = changedRows.count { $0.leftLineNumber != nil }
            let rightCount = changedRows.count { $0.rightLineNumber != nil }
            leftOffset += leftCount
            rightOffset += rightCount
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
