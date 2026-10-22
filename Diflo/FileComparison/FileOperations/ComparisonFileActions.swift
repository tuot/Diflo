import AppKit
import Observation

@MainActor @Observable
final class ComparisonFileActions {
    enum Decision { case save, discard, cancel }
    let session: ComparisonSession
    weak var window: NSWindow?
    private(set) var isPresentingDecision = false
    private var monitor: Timer?
    private var activeScopes: [URL] = []
    init(session: ComparisonSession) { self.session = session }

    func prepareToDiscard(sides: [ComparisonSide], decide: ((ComparisonSide) async -> Decision)? = nil,
                          save: ((ComparisonSide) async -> Bool)? = nil) async -> Bool {
        guard !isPresentingDecision else { return false }
        isPresentingDecision = true
        defer { isPresentingDecision = false }
        commitComposition()
        // Always finish ongoing saves before deciding whether the window can close.
        await session.waitForSaves()
        for side in sides where session.buffer(for: side).isDirty {
            let decision: Decision
            if let decide { decision = await decide(side) } else { decision = await prompt(side) }
            switch decision {
            case .cancel: return false
            case .discard: continue
            case .save:
                let success: Bool
                if let save { success = await save(side) }
                else { success = await self.save(side: side) }
                guard success, !session.buffer(for: side).isDirty else { return false }
            }
        }
        return true
    }

    private func prompt(_ side: ComparisonSide) async -> Decision {
        let alert = NSAlert()
        alert.messageText = "保存对“\(session.buffer(for: side).displayName)”的修改？"
        alert.informativeText = "尚未保存的修改将被丢弃。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "丢弃修改")
        alert.addButton(withTitle: "取消")
        let response = await present(alert)
        return response == .alertFirstButtonReturn ? .save : response == .alertSecondButtonReturn ? .discard : .cancel
    }

    func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        if let window {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        }
        return alert.runModal()
    }

    func setInteractionLocked(_ locked: Bool) {
        session.isInteractionLocked = locked
        func visit(_ view: NSView) {
            if let editor = view as? DiffTextView {
                let side: ComparisonSide = editor.accessibilityIdentifier() == "左侧文件内容" ? .left : .right
                editor.isEditable = !locked && !session.buffer(for: side).isReadOnly
            }
            view.subviews.forEach(visit)
        }
        if let content = window?.contentView { visit(content) }
    }
    func commitComposition() {
        func visit(_ view: NSView) {
            if let editor = view as? NSTextView, editor.hasMarkedText() {
                editor.unmarkText()
                editor.didChangeText()
            }
            view.subviews.forEach(visit)
        }
        if let content = window?.contentView { visit(content) }
    }

    func save(side: ComparisonSide, saveAs: Bool = false) async -> Bool {
        commitComposition()
        let buffer = session.buffer(for: side)
        guard let url = saveAs || buffer.url == nil ? FilePanel.saveTextFile(suggestedName: buffer.displayName) : buffer.url else { return false }
        let success = await session.save(side, to: url)
        if success { await session.recordRecent(); return true }
        guard session.lastSaveError == .externallyModified else { return false }
        session.dismissError()
        var metadataURL = url
        metadataURL.removeAllCachedResourceValues()
        let confirmedDate = try? metadataURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let alert = NSAlert()
        alert.messageText = "文件已被其他应用修改"
        alert.informativeText = "可将当前内容另存为，或覆盖磁盘版本。重新加载将丢弃当前编辑。"
        ["取消", "另存为…", "重新加载", "覆盖磁盘版本"].forEach { alert.addButton(withTitle: $0) }
        let response = await present(alert)
        switch response.rawValue {
        case NSApplication.ModalResponse.alertSecondButtonReturn.rawValue: return await save(side: side, saveAs: true)
        case NSApplication.ModalResponse.alertThirdButtonReturn.rawValue:
            await session.open(url, for: side)
            return false // A reload must never implicitly authorize closing the window.
        case NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1:
            if let confirmedDate { return await session.save(side, to: url, confirmedModificationDate: confirmedDate) }
            guard !FileManager.default.fileExists(atPath: url.path) else {
                session.reportError("文件再次发生变化，请重新保存并确认。")
                return false
            }
            return await session.save(side, to: url, force: true)
        default: return false
        }
    }

    func open(url: URL? = nil, side: ComparisonSide) async {
        guard !session.isInteractionLocked else { return }
        guard await prepareToDiscard(sides: [side]) else { return }
        guard let url = url ?? FilePanel.openTextFile() else { return }
        retainAccess(url)
        await session.open(url, for: side)
        await session.recordRecent()
    }

    func newComparison() async {
        guard !session.isInteractionLocked else { return }
        guard await prepareToDiscard(sides: [.left, .right]) else { return }
        await session.discardDraft()
        session.returnToLauncher(discardingChanges: true)
    }

    func reload(side: ComparisonSide, encoding: TextEncoding? = nil) async {
        guard !session.isInteractionLocked else { return }
        guard let url = session.buffer(for: side).url, await prepareToDiscard(sides: [side]) else { return }
        await session.open(url, for: side, encodingOverride: encoding)
    }

    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard NSApp.isActive else { return }
                await self?.checkExternalChanges()
            }
        }
    }
    func retainAccess(_ url: URL) {
        if url.startAccessingSecurityScopedResource() { activeScopes.append(url) }
    }
    func releaseAccess() {
        monitor?.invalidate(); monitor = nil
        activeScopes.forEach { $0.stopAccessingSecurityScopedResource() }
        activeScopes.removeAll()
    }

    func checkExternalChanges() async {
        guard !isPresentingDecision else { return }
        for side in [ComparisonSide.left, .right] {
            let buffer = session.buffer(for: side)
            guard let url = buffer.url, let expected = buffer.lastKnownModificationDate else { continue }
            do {
                var metadataURL = url
                metadataURL.removeAllCachedResourceValues()
                let values = try metadataURL.resourceValues(forKeys: [.contentModificationDateKey])
                if let actual = values.contentModificationDate, abs(actual.timeIntervalSince(expected)) > 0.001 {
                    session.protectionMessage = "“\(buffer.displayName)”已被其他应用修改。可从文件菜单重新加载，或将编辑另存为。"
                }
            } catch {
                session.protectionMessage = "“\(buffer.displayName)”已无法访问。当前编辑已保留，可另存为或重新选择文件。"
            }
        }
    }
}
