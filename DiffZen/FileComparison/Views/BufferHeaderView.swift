import SwiftUI

struct BufferHeaderView: View {
    let buffer: EditorBuffer
    let side: ComparisonSide
    let open: () -> Void
    let save: () -> Void
    let saveAs: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("打开\(sideName)文件", systemImage: "folder", action: open).labelStyle(.iconOnly)
            Image(systemName: "doc.text").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(buffer.displayName + (buffer.isDirty ? " •" : "")).lineLimit(1)
            Spacer()
            Button("保存\(sideName)", systemImage: "square.and.arrow.down", action: save)
                .labelStyle(.iconOnly)
                .disabled(!buffer.isDirty && buffer.url != nil)
            Button("另存\(sideName)为", systemImage: "ellipsis.circle", action: saveAs).labelStyle(.iconOnly)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sideName: String { side == .left ? "左侧" : "右侧" }
}
