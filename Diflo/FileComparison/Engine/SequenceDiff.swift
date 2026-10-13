import Foundation

nonisolated struct SequenceDiffResult: Equatable, Sendable {
    let blocks: [DiffBlock]
    let precision: DiffPrecision
}

/// Bounded Myers search. Each trace layer stores only its reachable diagonals.
nonisolated enum SequenceDiff {
    static func compare(left: [Int], right: [Int], budget: DiffBudget = .default) throws -> SequenceDiffResult {
        try Task.checkCancellation()
        var counter = DiffStepCounter(maximum: budget.maximumSteps)
        var prefix = 0, suffix = 0
        var middle: [DiffBlock] = []
        var precision: DiffPrecision = .exact
        do {
            while prefix < min(left.count, right.count) {
                try counter.step()
                guard left[prefix] == right[prefix] else { break }
                prefix += 1
            }
            while suffix < min(left.count, right.count) - prefix {
                try counter.step()
                guard left[left.count - suffix - 1] == right[right.count - suffix - 1] else { break }
                suffix += 1
            }
            middle = try search(left: left, right: right, leftRange: prefix..<(left.count - suffix), rightRange: prefix..<(right.count - suffix), budget: budget, counter: &counter)
        } catch is DiffStepCounter.Exhausted {
            precision = .coarse
            middle = changed(left: prefix..<(left.count - suffix), right: prefix..<(right.count - suffix))
        }
        try Task.checkCancellation()
        var blocks: [DiffBlock] = []
        if prefix > 0 { blocks.append(.init(kind: .equal, left: 0..<prefix, right: 0..<prefix)) }
        blocks += middle
        if suffix > 0 { blocks.append(.init(kind: .equal, left: (left.count - suffix)..<left.count, right: (right.count - suffix)..<right.count)) }
        return .init(blocks: blocks, precision: precision)
    }

    private static func changed(left: Range<Int>, right: Range<Int>) -> [DiffBlock] {
        guard !left.isEmpty || !right.isEmpty else { return [] }
        return [.init(kind: left.isEmpty ? .insert : (right.isEmpty ? .delete : .replace), left: left, right: right)]
    }

    private static func search(left: [Int], right: [Int], leftRange: Range<Int>, rightRange: Range<Int>, budget: DiffBudget, counter: inout DiffStepCounter) throws -> [DiffBlock] {
        let n = leftRange.count, m = rightRange.count
        if n == 0 || m == 0 { return changed(left: leftRange, right: rightRange) }
        var trace: [[Int]] = []
        var bytes = 0
        func value(_ layer: [Int], _ depth: Int, _ diagonal: Int) -> Int {
            guard abs(diagonal) <= depth else { return -1 }
            return layer[diagonal + depth]
        }
        for d in 0...(n + m) {
            try counter.step()
            let layerBytes = (2 * d + 1) * MemoryLayout<Int>.stride + MemoryLayout<[Int]>.stride
            guard layerBytes <= max(0, budget.maximumTraceBytes) - bytes else { throw DiffStepCounter.Exhausted.budget }
            bytes += layerBytes
            var layer = [Int](repeating: -1, count: 2 * d + 1)
            for k in stride(from: -d, through: d, by: 2) {
                try counter.step()
                var x: Int
                if d == 0 { x = 0 }
                else {
                    let previous = trace[d - 1]
                    if k == -d || (k != d && value(previous, d - 1, k - 1) < value(previous, d - 1, k + 1)) {
                        x = value(previous, d - 1, k + 1)
                    } else { x = value(previous, d - 1, k - 1) + 1 }
                }
                var y = x - k
                while x < n && y < m && x >= 0 && y >= 0 {
                    try counter.step()
                    guard left[leftRange.lowerBound + x] == right[rightRange.lowerBound + y] else { break }
                    x += 1; y += 1
                }
                layer[k + d] = x
                if x >= n && y >= m {
                    // Backtrack matched coordinates; gaps become complete change blocks.
                    var matches: [(Int, Int)] = []
                    var bx = n, by = m
                    if d > 0 {
                        for depth in stride(from: d, through: 1, by: -1) {
                            try counter.step()
                            let diagonal = bx - by
                            let previous = trace[depth - 1]
                            let previousK: Int
                            if diagonal == -depth || (diagonal != depth && value(previous, depth - 1, diagonal - 1) < value(previous, depth - 1, diagonal + 1)) { previousK = diagonal + 1 }
                            else { previousK = diagonal - 1 }
                            let px = value(previous, depth - 1, previousK), py = px - previousK
                            while bx > px && by > py {
                                try counter.step()
                                bx -= 1; by -= 1; matches.append((bx, by))
                            }
                            bx = px; by = py
                        }
                    }
                    while bx > 0 && by > 0 {
                        try counter.step()
                        bx -= 1; by -= 1; matches.append((bx, by))
                    }
                    var result: [DiffBlock] = [], lx = 0, ry = 0
                    for (mx, my) in matches.reversed() {
                        try counter.step()
                        result += changed(left: (leftRange.lowerBound + lx)..<(leftRange.lowerBound + mx), right: (rightRange.lowerBound + ry)..<(rightRange.lowerBound + my))
                        let equal = DiffBlock(kind: .equal, left: (leftRange.lowerBound + mx)..<(leftRange.lowerBound + mx + 1), right: (rightRange.lowerBound + my)..<(rightRange.lowerBound + my + 1))
                        if let last = result.last, last.kind == .equal, last.left.upperBound == equal.left.lowerBound, last.right.upperBound == equal.right.lowerBound {
                            result[result.count - 1] = .init(kind: .equal, left: last.left.lowerBound..<equal.left.upperBound, right: last.right.lowerBound..<equal.right.upperBound)
                        } else { result.append(equal) }
                        lx = mx + 1; ry = my + 1
                    }
                    result += changed(left: (leftRange.lowerBound + lx)..<leftRange.upperBound, right: (rightRange.lowerBound + ry)..<rightRange.upperBound)
                    return result
                }
            }
            trace.append(layer)
        }
        return changed(left: leftRange, right: rightRange)
    }
}
