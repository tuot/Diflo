import SwiftUI

struct ComparisonWorkspaceActions {
    let session: ComparisonSession
    let newComparison: () -> Void
    let saveLeft: () -> Void
    let saveRight: () -> Void
    let saveLeftAs: () -> Void
    let saveRightAs: () -> Void
}

private struct ComparisonWorkspaceActionsKey: FocusedValueKey {
    typealias Value = ComparisonWorkspaceActions
}

extension FocusedValues {
    var comparisonWorkspaceActions: ComparisonWorkspaceActions? {
        get { self[ComparisonWorkspaceActionsKey.self] }
        set { self[ComparisonWorkspaceActionsKey.self] = newValue }
    }
}

struct ComparisonWorkspaceCommands: Commands {
    @FocusedValue(\.comparisonWorkspaceActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("新建对比…") { actions?.newComparison() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Group {
                Button("保存左侧") { actions?.saveLeft() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("保存右侧") { actions?.saveRight() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("左侧另存为…") { actions?.saveLeftAs() }
                Button("右侧另存为…") { actions?.saveRightAs() }
            }
            .disabled(actions == nil)
        }

        CommandMenu("比较") {
            Group {
                Button("交换两侧") { actions?.session.swapBuffers() }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                Divider()
                Toggle("忽略行尾空白", isOn: option(\.ignoreTrailingWhitespace))
                Toggle("忽略所有空白", isOn: option(\.ignoreWhitespace))
                Toggle("忽略大小写", isOn: option(\.ignoreCase))
                Divider()
                Menu("批量合并") {
                    Button("全部采纳左侧内容 →") { actions?.session.applyAllHunks(from: .left) }
                    Button("全部采纳右侧内容 ←") { actions?.session.applyAllHunks(from: .right) }
                }
                .disabled(actions?.session.isWorking != false || actions?.session.result?.hunks.isEmpty != false)
            }
            .disabled(actions == nil)
        }
    }

    private func option(_ keyPath: WritableKeyPath<ComparisonOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { actions?.session.options[keyPath: keyPath] ?? false },
            set: { value in
                guard let session = actions?.session else { return }
                var options = session.options
                options[keyPath: keyPath] = value
                session.setOptions(options)
            }
        )
    }
}
