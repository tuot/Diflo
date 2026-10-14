import Foundation

nonisolated struct DiffAlignment: Equatable, Sendable {
    let blocks: [DiffBlock]

    init(blocks: [DiffBlock]) {
        self.blocks = blocks
    }

    init(rows: [DiffRow]) {
        var result: [DiffBlock] = []
        var left = 0, right = 0, startLeft = 0, startRight = 0
        var equal: Bool?
        func flush() {
            guard let equal else { return }
            let kind: DiffBlock.Kind = equal ? .equal : (left == startLeft ? .insert : (right == startRight ? .delete : .replace))
            result.append(.init(kind: kind, left: startLeft..<left, right: startRight..<right))
        }
        for row in rows {
            let nextEqual = row.kind == .unchanged
            if equal != nextEqual {
                flush()
                startLeft = left; startRight = right; equal = nextEqual
            }
            if row.leftLineNumber != nil { left += 1 }
            if row.rightLineNumber != nil { right += 1 }
        }
        flush()
        self.init(blocks: result)
    }
}
