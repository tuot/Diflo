import Foundation
import Testing
@testable import Diflo

struct ComparisonPersistenceTests {
    @Test @MainActor func snapshotRestoresDirtyBuffersAndOptions() throws {
        let session = ComparisonSession()
        session.startBlank()
        session.edit(.left, text: "未保存🌟\n")
        session.setOptions(ComparisonOptions(ignoreCase: true))
        let data = try JSONEncoder().encode(session.snapshot())
        let snapshot = try JSONDecoder().decode(ComparisonSnapshot.self, from: data)
        let recovered = ComparisonSession()
        recovered.restore(snapshot)
        #expect(recovered.leftBuffer.text == "未保存🌟\n")
        #expect(recovered.leftBuffer.isDirty)
        #expect(recovered.options.ignoreCase)
    }

    @Test func discardedDraftCannotBeResurrected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ComparisonStore(directory: root)
        let snapshot = await ComparisonSession().snapshot()
        try await store.saveDraft(snapshot, generation: 1)
        try await store.deleteDraft(id: snapshot.id, generation: 3)
        try await store.saveDraft(snapshot, generation: 2)
        #expect(try await store.drafts().isEmpty)
    }

    @Test func claimIsExclusiveAcrossWindows() async {
        let store = ComparisonStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let id = UUID()
        #expect(await store.claimDraft(id: id))
        #expect(await store.claimDraft(id: id) == false)
        await store.releaseDraft(id: id)
        #expect(await store.claimDraft(id: id))
    }

    @Test func staleLauncherCannotDeleteClaimedDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ComparisonStore(directory: root)
        let snapshot = await ComparisonSession().snapshot()
        try await store.saveDraft(snapshot, generation: 1)
        _ = await store.claimDraft(id: snapshot.id)
        do { try await store.deleteDraft(id: snapshot.id, generation: Int.max) } catch {}
        await store.releaseDraft(id: snapshot.id)
        #expect(try await store.drafts().count == 1)
    }

    @Test func corruptDraftDoesNotHideHealthyDrafts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ComparisonStore(directory: root)
        let snapshot = await ComparisonSession().snapshot()
        try await store.saveDraft(snapshot, generation: 1)
        let corrupt = root.appendingPathComponent("draft-corrupt.json")
        try Data("broken".utf8).write(to: corrupt)
        #expect(try await store.drafts().count == 1)
        #expect(try Data(contentsOf: corrupt) == Data("broken".utf8))
    }
}
