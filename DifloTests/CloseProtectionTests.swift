import Foundation
import Testing
@testable import Diflo

@MainActor struct CloseProtectionTests {
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
