import SwiftUI

struct WorkspaceToolbar: View {
    let session: ComparisonSession
    let returnToLauncher: () -> Void
    let saveLeft: () -> Void
    let saveRight: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("返回", systemImage: "chevron.left", action: returnToLauncher)
            Divider().frame(height: 18)
            Button("上一个差异", systemImage: "chevron.up", action: session.selectPreviousHunk)
                .keyboardShortcut(.upArrow, modifiers: [.command])
                .disabled(session.result?.hunks.isEmpty != false)
            Button("下一个差异", systemImage: "chevron.down", action: session.selectNextHunk)
                .keyboardShortcut(.downArrow, modifiers: [.command])
                .disabled(session.result?.hunks.isEmpty != false)
            Divider().frame(height: 18)
            Button("撤销", systemImage: "arrow.uturn.backward", action: undo).labelStyle(.iconOnly)
            Button("重做", systemImage: "arrow.uturn.forward", action: redo).labelStyle(.iconOnly)
            Button("交换两侧", systemImage: "arrow.left.arrow.right", action: session.swapBuffers)
                .labelStyle(.iconOnly)
                .help("交换两侧文件 (⌘⇧X)")
                .keyboardShortcut("x", modifiers: [.command, .shift])
            if let hunk = session.selectedHunk {
                Divider().frame(height: 18)
                Button("复制到右侧", systemImage: "arrow.right") { session.applyHunk(hunk, from: .left) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("复制到左侧", systemImage: "arrow.left") { session.applyHunk(hunk, from: .right) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Menu("删除差异块", systemImage: "trash") {
                    Button("删除左侧块") { session.deleteHunk(hunk, from: .left) }
                    Button("删除右侧块") { session.deleteHunk(hunk, from: .right) }
                }
            }
            Spacer()
            if session.isWorking { ProgressView().controlSize(.small) }
            Text(summary)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Button("保存左侧", systemImage: "square.and.arrow.down", action: saveLeft)
                .labelStyle(.iconOnly)
                .help("保存左侧 (⌘S)")
                .keyboardShortcut("s", modifiers: [.command])
            Button("保存右侧", systemImage: "square.and.arrow.down.on.square", action: saveRight)
                .labelStyle(.iconOnly)
                .help("保存右侧 (⌘⇧S)")
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.bar)
    }

    private var summary: String {
        guard let result = session.result else { return "正在比较…" }
        return result.differenceCount == 0 ? "内容相同" : "\(result.hunks.count) 个差异块"
    }

    private func undo() { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
    private func redo() { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
}
