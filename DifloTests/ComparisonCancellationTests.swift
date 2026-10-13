import Foundation
import Testing
@testable import Diflo

struct ComparisonCancellationTests {
    @Test @MainActor func closingWorkspaceRejectsInFlightResult() async throws {
        let worker = SuspendedComparisonWorker()
        let session = ComparisonSession(worker: worker)
        session.startBlank()
        await worker.waitForRequest()
        #expect(session.returnToLauncher(discardingChanges: true))
        await worker.release()
        try await Task.sleep(for: .milliseconds(30))
        #expect(session.result == nil)
        #expect(!session.isWorking)
    }

    @Test @MainActor func applyingAnEditRejectsStaleRevision() {
        let session = ComparisonSession()
        session.startBlank()
        session.edit(.left, text: "a")
        session.edit(.left, edit: TextEdit(range: NSRange(location: 0, length: 1), replacement: "b", baseRevision: 0))
        #expect(session.leftBuffer.text == "a")
        #expect(session.errorMessage != nil)
    }
}

private actor SuspendedComparisonWorker: ComparisonWorking {
    private var continuation: CheckedContinuation<Void, Never>?
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var started = false

    func waitForRequest() async {
        if !started { await withCheckedContinuation { requestWaiter = $0 } }
    }

    func release() { continuation?.resume(); continuation = nil }

    func compare(left: EditorBuffer, right: EditorBuffer, options: ComparisonOptions) async -> DiffResult {
        await withCheckedContinuation {
            continuation = $0
            started = true
            requestWaiter?.resume()
            requestWaiter = nil
        }
        return LineDiffEngine.compare(left: left.asParsedFile(), right: right.asParsedFile())
    }

    func load(from url: URL) async throws -> ParsedTextFile { try TextFileLoader.load(from: url) }
    func save(buffer: EditorBuffer, to url: URL, force: Bool) async throws -> Date? { nil }
}
