import SwiftUI

struct BufferHeaderView: View {
    let buffer: EditorBuffer
    let side: ComparisonSide
    let open: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("打开\(sideName)文件", systemImage: "folder", action: open)
                .labelStyle(.iconOnly)
                .help("打开\(sideName)文件")
            Text(buffer.displayName + (buffer.isDirty ? " •" : ""))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button("清空\(sideName)", systemImage: "eraser", action: clear)
                .labelStyle(.iconOnly)
                .help("清空\(sideName)文本，可撤销")
                .disabled(buffer.text.isEmpty)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sideName: String { side == .left ? "左侧" : "右侧" }
}
