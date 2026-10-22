import SwiftUI

struct ComparisonWorkspaceActions {
    let session: ComparisonSession
    let newComparison: () -> Void
    let saveLeft: () -> Void
    let saveRight: () -> Void
    let openLeft: () -> Void
    let openRight: () -> Void
    let reload: (ComparisonSide, TextEncoding?) -> Void
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
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建对比窗口") {
                guard !ComparisonApplicationDelegate.terminating else { return }
                openWindow(id: "comparison")
            }.keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(after: .importExport) {
            Button("打开左侧文件…") { actions?.openLeft() }.keyboardShortcut("o", modifiers: .command)
            Button("打开右侧文件…") { actions?.openRight() }.keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
            Group {
                Button("保存") { saveActive(saveAs: false) }.keyboardShortcut("s", modifiers: .command)
                Button("另存为…") { saveActive(saveAs: true) }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("全部保存") { actions?.saveLeft(); actions?.saveRight() }
                Divider()
                Button("保存左侧") { actions?.saveLeft() }
                Button("保存右侧") { actions?.saveRight() }
                Button("左侧另存为…") { actions?.saveLeftAs() }
                Button("右侧另存为…") { actions?.saveRightAs() }
                Divider()
                Button("重新加载当前文件") { if let actions { actions.reload(actions.session.activeSide, nil) } }
                Menu("使用编码重新打开") {
                    ForEach([TextEncoding.utf8, .utf8BOM, .utf16LittleEndian, .utf16BigEndian, .gb18030], id: \.displayName) { encoding in
                        Button(encoding.displayName) { if let actions { actions.reload(actions.session.activeSide, encoding) } }
                    }
                }
                Menu("保存编码") {
                    ForEach([TextEncoding.utf8, .utf8BOM, .utf16LittleEndian, .utf16BigEndian], id: \.displayName) { encoding in
                        Button(encoding.displayName) { if let actions { actions.session.changeFormat(side: actions.session.activeSide, encoding: encoding) } }
                    }
                }
                Menu("换行符") {
                    ForEach(LineEnding.allCases, id: \.rawValue) { ending in
                        Button(ending.displayName) { if let actions { actions.session.changeFormat(side: actions.session.activeSide, lineEnding: ending) } }
                    }
                }
            }.disabled(actions == nil || actions?.session.isInteractionLocked == true)
        }

        CommandMenu("比较") {
            Group {
                Toggle("当前侧只读", isOn: Binding(get: { actions.map { $0.session.buffer(for: $0.session.activeSide).isReadOnly } ?? false }, set: { value in
                    if let actions { actions.session.setReadOnly(value, side: actions.session.activeSide) }
                }))
                Divider()
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
            .disabled(actions == nil || actions?.session.isInteractionLocked == true)
        }
    }

    private func saveActive(saveAs: Bool) {
        guard let actions else { return }
        if actions.session.activeSide == .left { if saveAs { actions.saveLeftAs() } else { actions.saveLeft() } }
        else { if saveAs { actions.saveRightAs() } else { actions.saveRight() } }
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
