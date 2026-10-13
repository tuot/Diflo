import Testing
@testable import Diflo

struct DiffAlignmentTests {
    @Test func insertionShiftsMatchingLine() {
        let map = DiffAlignment(rows: [
            .init(leftText: nil, rightText: "new", leftLineNumber: nil, rightLineNumber: 1, kind: .inserted),
            .init(leftText: "a", rightText: "a", leftLineNumber: 1, rightLineNumber: 2, kind: .unchanged)
        ])
        #expect(map.oppositeLine(for: 0, side: .left) == 1)
        #expect(map.oppositeLine(for: 0, side: .right) == nil)
        #expect(map.mappedLine(0, from: .left) == 1)
    }
    @Test func replacementInterpolatesAndClamps() {
        let map = DiffAlignment(blocks: [.init(kind: .replace, left: 0..<2, right: 0..<4)])
        #expect(map.mappedLine(1, from: .left) == 2)
        #expect(map.mappedLine(9, from: .left) == 4)
        #expect(DiffAlignment(rows: []).mappedLine(2, from: .right) == 0)
    }
}
