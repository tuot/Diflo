import SwiftUI
import AppKit

struct ComparisonWindowBridge: NSViewRepresentable {
    let actions: ComparisonFileActions
    func makeNSView(context: Context) -> WindowBridgeView { WindowBridgeView(actions: actions) }
    func updateNSView(_ view: WindowBridgeView, context: Context) {}
}

final class WindowBridgeView: NSView {
    let actions: ComparisonFileActions
    init(actions: ComparisonFileActions) { self.actions = actions; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        ComparisonWindowDelegate.install(window: window, actions: actions)
    }
}

@MainActor final class ComparisonWindowDelegate: NSObject, NSWindowDelegate {
    static var windows: [ObjectIdentifier: ComparisonWindowDelegate] = [:]
    weak var window: NSWindow?
    weak var previous: (any NSWindowDelegate)?
    let actions: ComparisonFileActions
    var closeApproved = false
    private var checking = false
    init(window: NSWindow, actions: ComparisonFileActions) {
        self.window = window; self.actions = actions; self.previous = window.delegate
        super.init()
    }
    static func install(window: NSWindow, actions: ComparisonFileActions) {
        let key = ObjectIdentifier(window)
        guard windows[key] == nil else { return }
        let delegate = ComparisonWindowDelegate(window: window, actions: actions)
        windows[key] = delegate
        actions.window = window
        actions.startMonitoring()
        window.delegate = delegate
        if ComparisonApplicationDelegate.terminating { actions.setInteractionLocked(true) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closeApproved else { return true }
        guard !checking else { return false }
        checking = true
        Task { [self] in
            await actions.session.flushDraft()
            if await actions.prepareToDiscard(sides: [.left, .right]) {
                await actions.session.discardDraft()
                closeApproved = true
                window?.performClose(nil)
            }
            checking = false
        }
        return false
    }
    func windowWillClose(_ notification: Notification) {
        previous?.windowWillClose?(notification)
        actions.releaseAccess()
        if let window { Self.windows[ObjectIdentifier(window)] = nil }
    }
    override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || previous?.responds(to: selector) == true }
    override func forwardingTarget(for selector: Selector!) -> Any? { previous?.responds(to: selector) == true ? previous : super.forwardingTarget(for: selector) }
}
