import SwiftUI

struct ComparisonWorkspaceView: View {
    let session: ComparisonSession

    @State private var scrollCoordinator = DualScrollCoordinator()
    @State private var cursorPositions: [ComparisonSide: CursorPosition] = [
        .left: .start,
        .right: .start
    ]
    @State private var isDiscardConfirmationPresented = false
    @State private var isReplacementConfirmationPresented = false
    @State private var pendingReplacementSide: ComparisonSide?
    @State private var confirmedReplacementSide: ComparisonSide?

    var body: some View {
        VStack(spacing: 0) {
            // 文件标头与编辑器两侧对齐，低频操作通过右键菜单提供。
            HStack(spacing: 0) {
                BufferHeaderView(
                    buffer: session.leftBuffer,
                    side: .left,
                    open: { open(.left) },
                    clear: { clear(.left) },
                    save: { save(.left, saveAs: false) },
                    saveAs: { save(.left, saveAs: true) }
                )
                panelSeparator
                    .overlay {
                        DifferenceNavigationView(session: session)
                    }
                BufferHeaderView(
                    buffer: session.rightBuffer,
                    side: .right,
                    open: { open(.right) },
                    clear: { clear(.right) },
                    save: { save(.right, saveAs: false) },
                    saveAs: { save(.right, saveAs: true) }
                )
                Divider().opacity(0.5)
                Color.clear.frame(width: 12)
            }
            .frame(height: 44)
            .background(.bar)
            .zIndex(10)

            Divider().opacity(0.5).zIndex(10)

            MeldDualEditorWorkspaceView(
                session: session,
                scrollCoordinator: scrollCoordinator,
                onCursorChanged: { side, pos in cursorPositions[side] = pos }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            HStack(spacing: 0) {
                BufferStatusBar(buffer: session.leftBuffer, cursor: cursorPositions[.left] ?? .start)
                Color.clear.frame(width: ChangeGutterView.preferredWidth)
                BufferStatusBar(buffer: session.rightBuffer, cursor: cursorPositions[.right] ?? .start)
                Color.clear.frame(width: 12)
            }
            .frame(height: 30)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.35))
                    .frame(height: 0.5)
            }
            .zIndex(10)
        }
        .focusedSceneValue(\.comparisonWorkspaceActions, ComparisonWorkspaceActions(
            session: session,
            newComparison: requestReturn,
            saveLeft: { save(.left, saveAs: false) },
            saveRight: { save(.right, saveAs: false) },
            saveLeftAs: { save(.left, saveAs: true) },
            saveRightAs: { save(.right, saveAs: true) }
        ))
        .toolbar(removing: .title)
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .principal) {
                    windowTitle
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .principal) {
                    windowTitle
                }
            }
            ToolbarItem(placement: .primaryAction) {
                WorkspaceToolbar(
                    returnToLauncher: requestReturn
                )
            }
        }
        .sheet(isPresented: $isDiscardConfirmationPresented) {
            IconlessDialog(
                title: "有未保存的修改",
                message: Text("返回新建页将丢失左右两侧尚未保存的内容。")
            ) {
                Button("取消", role: .cancel) { isDiscardConfirmationPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("丢弃修改", role: .destructive) {
                    isDiscardConfirmationPresented = false
                    discardAndReturn()
                }
            }
        }
        .sheet(isPresented: $isReplacementConfirmationPresented, onDismiss: openConfirmedReplacement) {
            if let side = pendingReplacementSide {
                let buffer = side == .left ? session.leftBuffer : session.rightBuffer
                IconlessDialog(
                    title: "替换未保存的内容？",
                    message: Text("“\(buffer.displayName)”的修改将被丢弃。")
                ) {
                    Button("取消", role: .cancel) { isReplacementConfirmationPresented = false }
                        .keyboardShortcut(.cancelAction)
                    Button("丢弃并打开", role: .destructive) {
                        confirmedReplacementSide = side
                        isReplacementConfirmationPresented = false
                    }
                }
            }
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

    private var windowTitle: some View {
        Text("Diflo")
            .font(.system(size: 13, weight: .semibold))
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
        let buffer = side == .left ? session.leftBuffer : session.rightBuffer
        if buffer.isDirty {
            pendingReplacementSide = side
            isReplacementConfirmationPresented = true
        } else {
            openFile(side)
        }
    }

    private func openFile(_ side: ComparisonSide) {
        guard let url = FilePanel.openTextFile() else { return }
        Task { await session.open(url, for: side) }
    }

    private func openConfirmedReplacement() {
        pendingReplacementSide = nil
        guard let side = confirmedReplacementSide else { return }
        confirmedReplacementSide = nil
        openFile(side)
    }

    private func save(_ side: ComparisonSide, saveAs: Bool) {
        let buffer = side == .left ? session.leftBuffer : session.rightBuffer
        let url = saveAs || buffer.url == nil
            ? FilePanel.saveTextFile(suggestedName: buffer.displayName)
            : buffer.url
        guard let url else { return }
        Task { await session.save(side, to: url) }
    }
}
