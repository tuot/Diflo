import Foundation

nonisolated struct DiffAlignment: Equatable, Sendable {
    let blocks: [DiffBlock]
    private let leftBlocks: [Int]
    private let rightBlocks: [Int]

    init(blocks: [DiffBlock]) {
        self.blocks = blocks
        leftBlocks = blocks.indices.filter { !blocks[$0].left.isEmpty }
        rightBlocks = blocks.indices.filter { !blocks[$0].right.isEmpty }
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

    private func block(at line: Int, side: ComparisonSide) -> DiffBlock? {
        let indices = side == .left ? leftBlocks : rightBlocks
        var low = 0, high = indices.count
        while low < high {
            let mid = (low + high) / 2
            let block = blocks[indices[mid]]
            let range = side == .left ? block.left : block.right
            if range.upperBound <= line { low = mid + 1 } else { high = mid }
        }
        guard low < indices.count else { return nil }
        let block = blocks[indices[low]]
        return (side == .left ? block.left : block.right).contains(line) ? block : nil
    }

    func oppositeLine(for line: Int, side: ComparisonSide) -> Int? {
        guard let block = block(at: line, side: side) else { return nil }
        let source = side == .left ? block.left : block.right
        let target = side == .left ? block.right : block.left
        let offset = line - source.lowerBound
        return offset < target.count ? target.lowerBound + offset : nil
    }

    func mappedLine(_ position: Double, from side: ComparisonSide) -> Double {
        let sourceEnd = side == .left ? blocks.last?.left.upperBound : blocks.last?.right.upperBound
        let targetEnd = side == .left ? blocks.last?.right.upperBound : blocks.last?.left.upperBound
        let end = Double(sourceEnd ?? 0)
        let position = position.isFinite ? min(max(0, position), end) : 0
        guard position < end, let block = block(at: Int(position), side: side) else { return Double(targetEnd ?? 0) }
        let source = side == .left ? block.left : block.right
        let target = side == .left ? block.right : block.left
        return Double(target.lowerBound) + (position - Double(source.lowerBound)) * Double(target.count) / Double(source.count)
    }
}
