import SwiftUI

struct WorkspaceToolbar: View {
    let session: ComparisonSession
    let returnToLauncher: () -> Void
    let saveLeft: () -> Void
    let saveRight: () -> Void
    let saveLeftAs: () -> Void
    let saveRightAs: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("返回", systemImage: "chevron.left", action: returnToLauncher)
            Divider().frame(height: 18)
            Button("上一个差异", systemImage: "chevron.up", action: session.selectPreviousHunk)
                .labelStyle(.iconOnly)
                .help("上一个差异 (⌘↑)")
                .keyboardShortcut(.upArrow, modifiers: [.command])
                .disabled(session.result?.hunks.isEmpty != false)
            Button("下一个差异", systemImage: "chevron.down", action: session.selectNextHunk)
                .labelStyle(.iconOnly)
                .help("下一个差异 (⌘↓)")
                .keyboardShortcut(.downArrow, modifiers: [.command])
                .disabled(session.result?.hunks.isEmpty != false)
            Spacer()
            if session.isWorking { ProgressView().controlSize(.small) }
            Text(summary)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            moreMenu
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.bar)
    }

    private var moreMenu: some View {
        Menu {
            Button("保存左侧", action: saveLeft)
                .keyboardShortcut("s", modifiers: [.command])
            Button("保存右侧", action: saveRight)
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("左侧另存为…", action: saveLeftAs)
            Button("右侧另存为…", action: saveRightAs)
            Divider()
            Button("撤销", action: undo)
            Button("重做", action: redo)
            Button("交换两侧", action: session.swapBuffers)
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Menu("比较选项") {
                Toggle("忽略行尾空白", isOn: Binding(
                    get: { session.options.ignoreTrailingWhitespace },
                    set: { var opts = session.options; opts.ignoreTrailingWhitespace = $0; session.setOptions(opts) }
                ))
                Toggle("忽略所有空白", isOn: Binding(
                    get: { session.options.ignoreWhitespace },
                    set: { var opts = session.options; opts.ignoreWhitespace = $0; session.setOptions(opts) }
                ))
                Toggle("忽略大小写", isOn: Binding(
                    get: { session.options.ignoreCase },
                    set: { var opts = session.options; opts.ignoreCase = $0; session.setOptions(opts) }
                ))
            }
            Menu("批量合并") {
                Button("全部采纳左侧内容 (→)") { session.applyAllHunks(from: .left) }
                Button("全部采纳右侧内容 (←)") { session.applyAllHunks(from: .right) }
            }
            if let hunk = session.selectedHunk {
                Divider()
                Button("复制差异块到右侧") { session.applyHunk(hunk, from: .left) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("复制差异块到左侧") { session.applyHunk(hunk, from: .right) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("删除左侧差异块") { session.deleteHunk(hunk, from: .left) }
                Button("删除右侧差异块") { session.deleteHunk(hunk, from: .right) }
            }
        } label: {
            Label("更多", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .help("更多操作")
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var summary: String {
        guard let result = session.result else { return "正在比较…" }
        return result.differenceCount == 0 ? "内容相同" : "\(result.hunks.count) 个差异块"
    }

    private func undo() { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
    private func redo() { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
}
