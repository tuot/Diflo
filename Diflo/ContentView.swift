import SwiftUI

struct ContentView: View {
    @State private var session: ComparisonSession
    @State private var fileActions: ComparisonFileActions

    init() {
        let session = ComparisonSession()
        session.enablePersistence(.shared)
        _session = State(initialValue: session)
        _fileActions = State(initialValue: ComparisonFileActions(session: session))
    }

    var body: some View {
        Group {
            if session.isWorkspacePresented {
                ComparisonWorkspaceView(session: session, fileActions: fileActions)
            } else {
                NewComparisonView(session: session, fileActions: fileActions)
            }
        }
        .disabled(session.isInteractionLocked)
        .frame(minWidth: 920, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .focusedSceneValue(\.comparisonUndoManager, session.isWorkspacePresented ? session.undoManager : nil)
        .background(ComparisonWindowBridge(actions: fileActions))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await fileActions.checkExternalChanges() }
        }
        .alert("操作失败", isPresented: errorBinding) {
            Button("好", action: session.dismissError)
        } message: {
            Text(session.errorMessage ?? "未知错误")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.dismissError() } }
        )
    }
}

#Preview {
    ContentView()
}
