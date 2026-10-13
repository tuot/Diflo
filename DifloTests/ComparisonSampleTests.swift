import Testing
@testable import Diflo

@MainActor
struct ComparisonSampleTests {
    @Test func samplesExerciseAllBlockKindsAndTrailingNewline() throws {
        let session = ComparisonSession()
        session.startSamples()
        #expect(session.isWorkspacePresented)
        #expect(session.leftBuffer.url == nil)
        #expect(session.rightBuffer.url == nil)
        let result = try LineDiffEngine.compareCancellable(left: session.leftBuffer.asParsedFile(), right: session.rightBuffer.asParsedFile())
        #expect(result.hunks.contains { $0.kind == .leftOnly })
        #expect(result.hunks.contains { $0.kind == .rightOnly })
        #expect(result.hunks.contains { $0.kind == .modified })
        #expect(!session.leftBuffer.hasTrailingNewline)
        #expect(session.rightBuffer.hasTrailingNewline)
    }

    @Test func clearingOneSidePreservesTheOtherSide() {
        let session = ComparisonSession()
        session.startSamples()
        let right = session.rightBuffer
        session.edit(.left, text: "")
        #expect(session.leftBuffer.text.isEmpty)
        #expect(session.rightBuffer == right)
        #expect(session.leftBuffer.isDirty)
    }
}
