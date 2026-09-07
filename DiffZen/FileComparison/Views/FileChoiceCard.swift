import SwiftUI

struct FileChoiceCard: View {
    let side: ComparisonSide
    let url: URL?
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 12) {
                Image(systemName: url == nil ? "doc.badge.plus" : "doc.text.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(url == nil ? Color.secondary : Color.accentColor)
                Text(url?.lastPathComponent ?? title)
                    .font(.headline)
                    .lineLimit(1)
                Text(url == nil ? "点击选择文件" : url?.deletingLastPathComponent().path(percentEncoded: false) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 270, height: 126)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 1)
        }
        .accessibilityLabel("选择\(title)文件")
    }

    private var title: String { side == .left ? "左侧" : "右侧" }
}
