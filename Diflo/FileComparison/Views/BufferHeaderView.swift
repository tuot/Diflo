import SwiftUI
import UniformTypeIdentifiers

struct BufferHeaderView: View {
    let buffer: EditorBuffer
    let side: ComparisonSide
    let open: () -> Void
    let clear: () -> Void
    let save: () -> Void
    let saveAs: () -> Void
    var onDropURL: ((URL) -> Void)? = nil

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if buffer.isReadOnly { Image(systemName: "lock").accessibilityLabel("只读") }
                Text(buffer.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if buffer.isDirty {
                    Circle()
                        .fill(.tint)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(openHelp)
        .accessibilityLabel("\(sideName)：\(buffer.displayName)\(buffer.isDirty ? "，未保存" : "")")
        .accessibilityHint("打开文件，右键显示文件操作")
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first, let onDropURL else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in onDropURL(url) } }
            }
            return true
        }
        .contextMenu {
            Button("打开\(sideName)文件…", systemImage: "folder", action: open)
            Divider()
            Button("保存\(sideName)", systemImage: "square.and.arrow.down", action: save)
            Button("\(sideName)另存为…", action: saveAs)
            Divider()
            Button("清空\(sideName)", systemImage: "eraser", action: clear)
                .disabled(buffer.text.isEmpty)
        }
    }

    private var sideName: String { side == .left ? "左侧" : "右侧" }

    private var openHelp: String {
        let instruction = "点击打开\(sideName)文件 · 右键显示更多操作"
        guard let url = buffer.url else { return instruction }
        return "\(url.path(percentEncoded: false))\n\(instruction)"
    }
}
