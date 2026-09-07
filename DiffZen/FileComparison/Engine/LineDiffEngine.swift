import Foundation

nonisolated enum LineDiffEngine {
    static func compare(
        left: ParsedTextFile,
        right: ParsedTextFile,
        leftRevision: Int = 0,
        rightRevision: Int = 0
    ) -> DiffResult {
        let difference = right.lines.difference(from: left.lines)
        let removedOffsets = Set(difference.removals.compactMap { change -> Int? in
            guard case let .remove(offset, _, _) = change else { return nil }
            return offset
        })
        let insertedOffsets = Set(difference.insertions.compactMap { change -> Int? in
            guard case let .insert(offset, _, _) = change else { return nil }
            return offset
        })

        var rows: [DiffRow] = []
        rows.reserveCapacity(max(left.lines.count, right.lines.count))
        var leftIndex = 0
        var rightIndex = 0

        while leftIndex < left.lines.count || rightIndex < right.lines.count {
            if isUnchanged(
                left: left,
                right: right,
                leftIndex: leftIndex,
                rightIndex: rightIndex,
                removedOffsets: removedOffsets,
                insertedOffsets: insertedOffsets
            ) {
                rows.append(
                    DiffRow(
                        leftText: left.lines[leftIndex],
                        rightText: right.lines[rightIndex],
                        leftLineNumber: leftIndex + 1,
                        rightLineNumber: rightIndex + 1,
                        kind: .unchanged
                    )
                )
                leftIndex += 1
                rightIndex += 1
                continue
            }

            let removedStart = leftIndex
            while leftIndex < left.lines.count, removedOffsets.contains(leftIndex) {
                leftIndex += 1
            }

            let insertedStart = rightIndex
            while rightIndex < right.lines.count, insertedOffsets.contains(rightIndex) {
                rightIndex += 1
            }

            let removedCount = leftIndex - removedStart
            let insertedCount = rightIndex - insertedStart

            if removedCount == 0, insertedCount == 0 {
                appendFallbackRow(
                    to: &rows,
                    left: left,
                    right: right,
                    leftIndex: &leftIndex,
                    rightIndex: &rightIndex
                )
                continue
            }

            let pairedCount = min(removedCount, insertedCount)
            for offset in 0..<pairedCount {
                let oldIndex = removedStart + offset
                let newIndex = insertedStart + offset
                rows.append(
                    DiffRow(
                        leftText: left.lines[oldIndex],
                        rightText: right.lines[newIndex],
                        leftLineNumber: oldIndex + 1,
                        rightLineNumber: newIndex + 1,
                        kind: .modified
                    )
                )
            }

            for oldIndex in (removedStart + pairedCount)..<leftIndex {
                rows.append(
                    DiffRow(
                        leftText: left.lines[oldIndex],
                        rightText: nil,
                        leftLineNumber: oldIndex + 1,
                        rightLineNumber: nil,
                        kind: .deleted
                    )
                )
            }

            for newIndex in (insertedStart + pairedCount)..<rightIndex {
                rows.append(
                    DiffRow(
                        leftText: nil,
                        rightText: right.lines[newIndex],
                        leftLineNumber: nil,
                        rightLineNumber: newIndex + 1,
                        kind: .inserted
                    )
                )
            }
        }

        let hunks = DiffHunkBuilder.build(
            rows: rows,
            leftRevision: leftRevision,
            rightRevision: rightRevision
        )
        return DiffResult(
            leftFile: left,
            rightFile: right,
            rows: rows,
            hasTrailingNewlineDifference: left.hasTrailingNewline != right.hasTrailingNewline,
            hunks: hunks
        )
    }

    private static func isUnchanged(
        left: ParsedTextFile,
        right: ParsedTextFile,
        leftIndex: Int,
        rightIndex: Int,
        removedOffsets: Set<Int>,
        insertedOffsets: Set<Int>
    ) -> Bool {
        leftIndex < left.lines.count
            && rightIndex < right.lines.count
            && !removedOffsets.contains(leftIndex)
            && !insertedOffsets.contains(rightIndex)
            && left.lines[leftIndex] == right.lines[rightIndex]
    }

    private static func appendFallbackRow(
        to rows: inout [DiffRow],
        left: ParsedTextFile,
        right: ParsedTextFile,
        leftIndex: inout Int,
        rightIndex: inout Int
    ) {
        let hasLeft = leftIndex < left.lines.count
        let hasRight = rightIndex < right.lines.count
        let kind: DiffRow.Kind = hasLeft && hasRight ? .modified : (hasLeft ? .deleted : .inserted)

        rows.append(
            DiffRow(
                leftText: hasLeft ? left.lines[leftIndex] : nil,
                rightText: hasRight ? right.lines[rightIndex] : nil,
                leftLineNumber: hasLeft ? leftIndex + 1 : nil,
                rightLineNumber: hasRight ? rightIndex + 1 : nil,
                kind: kind
            )
        )

        if hasLeft { leftIndex += 1 }
        if hasRight { rightIndex += 1 }
    }
}
