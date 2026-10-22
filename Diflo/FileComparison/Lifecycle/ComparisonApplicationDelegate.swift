import AppKit

@MainActor final class ComparisonApplicationDelegate: NSObject, NSApplicationDelegate {
    static var terminating = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.terminating else { return .terminateCancel }
        Self.terminating = true
        Task {
            var processed = Set<ObjectIdentifier>()
            var accepted: [ComparisonWindowDelegate] = []
            while let entry = ComparisonWindowDelegate.windows.first(where: { !processed.contains($0.key) }) {
                let value = entry.value
                value.actions.commitComposition()
                value.actions.setInteractionLocked(true)
                await value.actions.session.flushDraft()
                guard await value.actions.prepareToDiscard(sides: [.left, .right]) else {
                    for window in ComparisonWindowDelegate.windows.values { window.actions.setInteractionLocked(false) }
                    Self.terminating = false
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
                processed.insert(entry.key)
                accepted.append(value)
            }
            // All comparison windows are now locked; new windows opened by a system event
            // during an await are picked up by the loop before replying to termination.
            for entry in accepted {
                await entry.actions.session.discardDraft()
                entry.closeApproved = true
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
