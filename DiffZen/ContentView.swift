import SwiftUI

struct ContentView: View {
    @State private var session = ComparisonSession()

    var body: some View {
        Group {
            if session.isWorkspacePresented {
                ComparisonView(session: session)
            } else {
                NewComparisonView(session: session)
            }
        }
        .frame(minWidth: 920, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
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
