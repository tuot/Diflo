import Testing
@testable import Diflo

struct SequenceDiffTests {
    @Test func exhaustedBudgetCoversInputs() throws {
        let result = try SequenceDiff.compare(left: [1, 2], right: [3, 4, 5], budget: .init(maximumSteps: 0, maximumTraceBytes: 0))
        #expect(result.blocks == [DiffBlock(kind: .replace, left: 0..<2, right: 0..<3)])
        #expect(result.precision == .coarse)
    }

    @Test func sequenceBlocksReconstructTarget() throws {
        let inputs = [[], [1], [1, 2, 1], [2, 1, 2], [1, 2, 3, 4], [5, 6]]
        for left in inputs {
            for right in inputs {
                let result = try SequenceDiff.compare(left: left, right: right, budget: .default)
                var output: [Int] = []
                var l = 0, r = 0
                for block in result.blocks {
                    #expect(block.left.lowerBound == l)
                    #expect(block.right.lowerBound == r)
                    if block.kind == .equal {
                        #expect(Array(left[block.left]) == Array(right[block.right]))
                        output += left[block.left]
                    } else { output += right[block.right] }
                    l = block.left.upperBound
                    r = block.right.upperBound
                }
                #expect(l == left.count && r == right.count)
                #expect(output == right)
                #expect(result.precision == .exact)
            }
        }
    }
}
