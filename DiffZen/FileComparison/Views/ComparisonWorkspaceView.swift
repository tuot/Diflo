import SwiftUI

struct ComparisonWorkspaceView: View {
    let session: ComparisonSession

    @State private var scrollCoordinator = DualScrollCoordinator()
    @State private var cursorPositions: [ComparisonSide: CursorPosition] = [
        .left: .start,
        .right: .start
    ]
    @State private var isDiscardConfirmationPresented = false
    @State private var hiddenIdenticalBanners: Set<ComparisonSide> = []

    var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部工具栏 (保证在最高图层)
            WorkspaceToolbar(
                session: session,
                returnToLauncher: requestReturn,
                saveLeft: { save(.left, saveAs: false) },
                saveRight: { save(.right, saveAs: false) }
            )
            .frame(maxWidth: .infinity)
            .zIndex(10)

            Divider().zIndex(10)

            // 2. 文件标头栏
            HStack(spacing: 0) {
                BufferHeaderView(
                    buffer: session.leftBuffer,
                    side: .left,
                    open: { open(.left) },
                    save: { save(.left, saveAs: false) },
                    saveAs: { save(.left, saveAs: true) }
                )
                Divider()
                BufferHeaderView(
                    buffer: session.rightBuffer,
                    side: .right,
                    open: { open(.right) },
                    save: { save(.right, saveAs: false) },
                    saveAs: { save(.right, saveAs: true) }
                )
            }
            .frame(height: 46)
            .zIndex(10)

            Divider().zIndex(10)

            if session.result?.differenceCount == 0,
               (!session.leftBuffer.text.isEmpty || !session.rightBuffer.text.isEmpty),
               hiddenIdenticalBanners.count < 2 {
                HStack(spacing: 0) {
                    IdenticalContentBanner(
                        isHidden: hiddenIdenticalBanners.contains(.left),
                        hide: { hiddenIdenticalBanners.insert(.left) }
                    )
                    Divider()
                    IdenticalContentBanner(
                        isHidden: hiddenIdenticalBanners.contains(.right),
                        hide: { hiddenIdenticalBanners.insert(.right) }
                    )
                }
                .frame(height: 48)
                .zIndex(10)
                Divider().zIndex(10)
            }

            // 3. 中间对比工作区：Meld 官方级双栏编辑器与贝塞尔曲面连线
            // 3. 中间对比工作区：Meld 官方级双栏编辑器与贝塞尔曲面连线
            MeldDualEditorWorkspaceView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            Divider().zIndex(10)

            // 4. 底部状态栏
            HStack(spacing: 0) {
                BufferStatusBar(buffer: session.leftBuffer, cursor: cursorPositions[.left] ?? .start)
                Divider()
                BufferStatusBar(buffer: session.rightBuffer, cursor: cursorPositions[.right] ?? .start)
            }
            .frame(height: 28)
            .zIndex(10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

private struct IdenticalContentBanner: View {
    let isHidden: Bool
    let hide: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if !isHidden {
                Image(systemName: "lightbulb.max")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("文件完全相同")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button("隐藏", action: hide)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .systemYellow).opacity(isHidden ? 0 : 0.09))
    }
}
