import SwiftUI

struct NewComparisonView: View {
    let session: ComparisonSession

    @State private var leftURL: URL?
    @State private var rightURL: URL?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("新建对比")
                    .font(.largeTitle.weight(.semibold))
                Text("选择两个文本文件，或从空白内容开始")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                FileChoiceCard(side: .left, url: leftURL, choose: chooseLeft, onDropURL: { leftURL = $0 })
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                FileChoiceCard(side: .right, url: rightURL, choose: chooseRight, onDropURL: { rightURL = $0 })
            }
            HStack(spacing: 12) {
                Button("空白对比", systemImage: "doc.badge.plus", action: session.startBlank)
                    .controlSize(.large)
                Button("开始对比", systemImage: "arrow.right", action: startComparison)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(leftURL == nil && rightURL == nil)
            }
            Spacer()
        }
        .padding(40)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func chooseLeft() { leftURL = FilePanel.openTextFile() }
    private func chooseRight() { rightURL = FilePanel.openTextFile() }

    private func startComparison() {
        let leftURL = leftURL
        let rightURL = rightURL
        Task { await session.start(leftURL: leftURL, rightURL: rightURL) }
    }
}
