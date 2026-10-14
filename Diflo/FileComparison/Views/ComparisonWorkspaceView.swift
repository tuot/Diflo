import SwiftUI

struct ComparisonWorkspaceView: View {
    let session: ComparisonSession

    @State private var scrollCoordinator = DualScrollCoordinator()
    @State private var cursorPositions: [ComparisonSide: CursorPosition] = [
        .left: .start,
        .right: .start
    ]
    @State private var isDiscardConfirmationPresented = false

    var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部工具栏 (保证在最高图层)
            WorkspaceToolbar(
                session: session,
                returnToLauncher: requestReturn,
                saveLeft: { save(.left, saveAs: false) },
                saveRight: { save(.right, saveAs: false) },
                saveLeftAs: { save(.left, saveAs: true) },
                saveRightAs: { save(.right, saveAs: true) }
            )
            .frame(maxWidth: .infinity)
            .zIndex(10)

            Divider().opacity(0.5).zIndex(10)

            // 2. 文件标头栏
            HStack(spacing: 0) {
                BufferHeaderView(
                    buffer: session.leftBuffer,
                    side: .left,
                    open: { open(.left) },
                    clear: { clear(.left) }
                )
                panelSeparator
                BufferHeaderView(
                    buffer: session.rightBuffer,
                    side: .right,
                    open: { open(.right) },
                    clear: { clear(.right) }
                )
                Divider().opacity(0.5)
                Color.clear.frame(width: 12)
            }
            .frame(height: 38)
            .background(Color(nsColor: .controlBackgroundColor))
            .zIndex(10)

            Divider().opacity(0.5).zIndex(10)

            // 3. 中间对比工作区：可编辑双栏 + 贝塞尔曲面连线 + Hunk 感知滚动同步
            MeldDualEditorWorkspaceView(
                session: session,
                scrollCoordinator: scrollCoordinator,
                onCursorChanged: { side, pos in cursorPositions[side] = pos }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            Divider().opacity(0.5).zIndex(10)

            // 4. 底部状态栏
            HStack(spacing: 0) {
                BufferStatusBar(buffer: session.leftBuffer, cursor: cursorPositions[.left] ?? .start)
                panelSeparator
                BufferStatusBar(buffer: session.rightBuffer, cursor: cursorPositions[.right] ?? .start)
                Divider().opacity(0.5)
                Color.clear.frame(width: 12)
            }
            .frame(height: 24)
            .background(.bar)
            .zIndex(10)
        }
        .confirmationDialog(
            "有未保存的修改",
            isPresented: $isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("丢弃修改", role: .destructive, action: discardAndReturn)
            Button("取消", role: .cancel) {}
        } message: {
            Text("返回新建页将丢失左右两侧尚未保存的内容。")
        }
        .onChange(of: session.selectedHunkID) { _, newID in
            if let newID, let hunk = session.result?.hunks.first(where: { $0.id == newID }) {
                scrollCoordinator.scrollTo(hunk: hunk)
            }
        }
        .onChange(of: session.result?.hunks) { _, newHunks in
            scrollCoordinator.updateHunks(newHunks ?? [])
        }
    }

    private func clear(_ side: ComparisonSide) {
        let scrollView = side == .left ? scrollCoordinator.leftScrollView : scrollCoordinator.rightScrollView
        if let editor = scrollView?.documentView as? DiffTextView {
            editor.window?.makeFirstResponder(editor)
            editor.unmarkText()
            editor.applyExternalText("", undoable: true)
        } else {
            session.edit(side, text: "")
        }
    }

    private var panelSeparator: some View {
        Color.clear
            .frame(width: ChangeGutterView.preferredWidth)
            .overlay {
                HStack(spacing: 0) {
                    Divider()
                    Spacer(minLength: 0)
                    Divider()
                }
                .opacity(0.5)
            }
    }

    private func requestReturn() {
        if !session.returnToLauncher(discardingChanges: false) {
            isDiscardConfirmationPresented = true
        }
    }

    private func discardAndReturn() {
        session.returnToLauncher(discardingChanges: true)
    }

    private func open(_ side: ComparisonSide) {
        guard confirmReplacingIfNeeded(side), let url = FilePanel.openTextFile() else { return }
        Task { await session.open(url, for: side) }
    }

    private func save(_ side: ComparisonSide, saveAs: Bool) {
        let buffer = side == .left ? session.leftBuffer : session.rightBuffer
        let url = saveAs || buffer.url == nil
            ? FilePanel.saveTextFile(suggestedName: buffer.displayName)
            : buffer.url
        guard let url else { return }
        Task { await session.save(side, to: url) }
    }

    private func confirmReplacingIfNeeded(_ side: ComparisonSide) -> Bool {
        let buffer = side == .left ? session.leftBuffer : session.rightBuffer
        guard buffer.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "替换未保存的内容？"
        alert.informativeText = "“\(buffer.displayName)”的修改将被丢弃。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "丢弃并打开")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
