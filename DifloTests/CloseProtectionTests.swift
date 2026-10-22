import Foundation
import Testing
@testable import Diflo

@MainActor struct CloseProtectionTests {
    @Test func bothDirtySidesUseOneDiscardDecision() async {
        let session = ComparisonSession()
        session.startBlank()
        session.edit(.left, text: "left draft")
        session.edit(.right, text: "right draft")
        let actions = ComparisonFileActions(session: session)
        var prompts = 0
        let canClose = await actions.prepareToDiscard(sides: [.left, .right], decide: { _ in
            prompts += 1
            return .discard
        })
        #expect(canClose)
        #expect(prompts == 1)
    }

    @Test func saveAllPromptsOnceAndSavesBothSides() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = ComparisonSession()
        session.startBlank()
        session.edit(.left, text: "left draft")
        session.edit(.right, text: "right draft")
        let actions = ComparisonFileActions(session: session)
        var prompts = 0
        let canClose = await actions.prepareToDiscard(sides: [.left, .right], decide: { _ in
            prompts += 1
            return .save
        }, save: { side in
            await session.save(side, to: directory.appendingPathComponent(side.rawValue))
        })
        #expect(canClose)
        #expect(prompts == 1)
        #expect(!session.hasUnsavedChanges)
        #expect(try String(contentsOf: directory.appendingPathComponent("left"), encoding: .utf8) == "left draft")
        #expect(try String(contentsOf: directory.appendingPathComponent("right"), encoding: .utf8) == "right draft")
    }

    @Test func secondSaveFailureKeepsWindowAndRemainingDraft() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let session = ComparisonSession()
        session.startBlank()
        session.edit(.left, text: "left draft")
        session.edit(.right, text: "right draft")
        let actions = ComparisonFileActions(session: session)
        var prompts = 0
        let canClose = await actions.prepareToDiscard(sides: [.left, .right], decide: { _ in
            prompts += 1
            return .save
        }, save: { side in
            guard side == .left else { return false }
            return await session.save(side, to: url)
        })
        #expect(!canClose)
        #expect(prompts == 1)
        #expect(!session.leftBuffer.isDirty)
        #expect(session.rightBuffer.isDirty)
        #expect(session.rightBuffer.text == "right draft")
        #expect(session.isWorkspacePresented)
    }

    @Test func unchangedBuffersDoNotPrompt() async {
        let session = ComparisonSession()
        session.startBlank()
        let actions = ComparisonFileActions(session: session)
        var prompts = 0
        #expect(await actions.prepareToDiscard(sides: [.left, .right], decide: { _ in
            prompts += 1
            return .cancel
        }))
        #expect(prompts == 0)
    }

    @Test func cancelPreventsClose() async {
        let session = ComparisonSession()
        session.startBlank()
        session.edit(.left, text: "important")
        let actions = ComparisonFileActions(session: session)
        let canClose = await actions.prepareToDiscard(sides: [.left, .right], decide: { _ in .cancel }, save: { _ in true })
        #expect(!canClose)
        #expect(session.leftBuffer.text == "important")
    }
    @Test func failedSavePreventsClose() async {
        let session = ComparisonSession()
        session.startBlank()
        session.edit(.right, text: "important")
        let actions = ComparisonFileActions(session: session)
        #expect(await actions.prepareToDiscard(sides: [.left, .right], decide: { _ in .save }, save: { _ in false }) == false)
    }
}
