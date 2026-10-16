import SwiftUI

struct WorkspaceToolbar: View {
    let returnToLauncher: () -> Void

    var body: some View {
        Button("新建对比", systemImage: "plus", action: returnToLauncher)
            .labelStyle(.titleAndIcon)
            .help("新建对比 (⌘N)")
    }
}
