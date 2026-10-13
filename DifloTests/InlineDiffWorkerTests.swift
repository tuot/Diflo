import Foundation
import Testing
@testable import Diflo

struct InlineDiffWorkerTests {
    @Test func appendedTextLeavesOriginalUnmarked() async throws {
        let result = try await InlineDiffWorker().compare(left: "hello", right: "hello world")
        #expect(result.leftRanges.isEmpty)
        #expect(result.rightRanges == [NSRange(location: 5, length: 6)])
    }
    @Test func emojiAndCombiningCharactersStayWhole() async throws {
        let result = try await InlineDiffWorker().compare(left: "a🙂e\u{301}z", right: "a🙃xz")
        #expect(result.leftRanges == [NSRange(location: 1, length: 4)])
        #expect(result.rightRanges == [NSRange(location: 1, length: 3)])
    }
    @Test func excessiveBlocksUseCoarseRanges() async throws {
        let result = try await InlineDiffWorker().compare(left: String(repeating: "x", count: 20_001), right: "y")
        #expect(result.precision == .coarse)
        #expect(result.leftRanges == [NSRange(location: 0, length: 20_001)])
    }
    @Test func cacheEvictsWithinBothLimits() async throws {
        let worker = InlineDiffWorker(maximumEntries: 2, maximumBytes: 4096)
        _ = try await worker.compare(left: "a", right: "b")
        _ = try await worker.compare(left: "c", right: "d")
        _ = try await worker.compare(left: "e", right: "f")
        #expect(await worker.cacheEntryCount == 2)
        #expect(await worker.cacheBytes <= 4096)
    }
}
