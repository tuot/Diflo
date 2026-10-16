import SwiftUI

struct WorkspaceToolbar: View {
    let session: ComparisonSession
    let returnToLauncher: () -> Void
    let saveLeft: () -> Void
    let saveRight: () -> Void
    let saveLeftAs: () -> Void
    let saveRightAs: () -> Void

    var body: some View {
        Menu {
            Button("新建对比…", systemImage: "square.and.pencil", action: returnToLauncher)
            Divider()
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
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func undo() { session.undoManager.undo() }
    private func redo() { session.undoManager.redo() }
}
