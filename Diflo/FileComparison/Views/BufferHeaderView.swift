import SwiftUI

struct BufferHeaderView: View {
    let buffer: EditorBuffer
    let side: ComparisonSide
    let open: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("打开\(sideName)文件", systemImage: "folder", action: open).labelStyle(.iconOnly)
            Text(buffer.displayName + (buffer.isDirty ? " •" : "")).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sideName: String { side == .left ? "左侧" : "右侧" }
}
