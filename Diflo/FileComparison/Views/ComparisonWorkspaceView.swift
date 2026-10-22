import SwiftUI

struct ComparisonWorkspaceView: View {
    let session: ComparisonSession
    var fileActions: ComparisonFileActions? = nil

    private var actions: ComparisonFileActions { fileActions ?? ComparisonFileActions(session: session) }

    @State private var scrollCoordinator = DualScrollCoordinator()
    @State private var cursorPositions: [ComparisonSide: CursorPosition] = [
        .left: .start,
        .right: .start
    ]

    var body: some View {
        VStack(spacing: 0) {
            if let message = session.protectionMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message).font(.callout)
                    Spacer()
                    Button("关闭提示") { session.protectionMessage = nil }
                }.padding(8).background(.yellow.opacity(0.12))
            }
            // 文件标头与编辑器两侧对齐，低频操作通过右键菜单提供。
            HStack(spacing: 0) {
                BufferHeaderView(
                    buffer: session.leftBuffer,
                    side: .left,
                    open: { open(.left) },
                    clear: { clear(.left) },
                    save: { save(.left, saveAs: false) },
                    saveAs: { save(.left, saveAs: true) },
                    onDropURL: { url in Task { await actions.open(url: url, side: .left) } }
                )
                panelSeparator
                    .overlay {
                        DifferenceNavigationView(session: session)
                    }
                HStack(spacing: 0) {
                    if session.result?.precision == .coarse {
                        Label("粗略比较", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.orange.opacity(0.10), in: .capsule)
                            .fixedSize()
                            .padding(.leading, 10)
                            .help("计算已达到预算，当前为粗略结果，合并范围可能扩大。")
                    }
                    BufferHeaderView(
                        buffer: session.rightBuffer,
                        side: .right,
                        open: { open(.right) },
                        clear: { clear(.right) },
                        save: { save(.right, saveAs: false) },
                        saveAs: { save(.right, saveAs: true) },
                        onDropURL: { url in Task { await actions.open(url: url, side: .right) } }
                    )
                }
                .frame(maxWidth: .infinity)
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
                onCursorChanged: { side, pos in cursorPositions[side] = pos; session.cursors[side] = pos }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            HStack(spacing: 0) {
                BufferStatusBar(buffer: session.leftBuffer, cursor: cursorPositions[.left] ?? .start)
                comparisonFooterStatus
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
            openLeft: { open(.left) },
            openRight: { open(.right) },
            reload: { side, encoding in Task { await actions.reload(side: side, encoding: encoding) } },
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
        .onChange(of: session.selectedHunkID) { _, newID in
            if let newID, let hunk = session.result?.hunks.first(where: { $0.id == newID }) {
                scrollCoordinator.scrollTo(hunk: hunk)
            }
        }
        .onChange(of: session.result?.hunks) { _, newHunks in
            scrollCoordinator.updateHunks(newHunks ?? [])
        }
    }

    private var comparisonFooterStatus: some View {
        HStack(spacing: 6) {
            if session.result?.hasTrailingNewlineDifference == true {
                Text("末尾换行不同")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.04), in: .capsule)
                    .help("一个文件末尾有换行符，另一个没有。")
            }
            if session.options.ignoreWhitespace {
                Text("忽略空白")
            } else if session.options.ignoreTrailingWhitespace {
                Text("忽略行尾空白")
            }
            if session.options.ignoreCase {
                Text("忽略大小写")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .fixedSize()
        .padding(.horizontal, 4)
        .frame(minWidth: ChangeGutterView.preferredWidth)
    }

    private var windowTitle: some View {
        Text("Diflo")
            .font(.system(size: 13, weight: .semibold))
    }

    private func clear(_ side: ComparisonSide) {
        guard !session.buffer(for: side).isReadOnly else { return }
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

    private func requestReturn() { Task { await actions.newComparison() } }
    private func open(_ side: ComparisonSide) { Task { await actions.open(side: side) } }
    private func save(_ side: ComparisonSide, saveAs: Bool) { Task { await actions.save(side: side, saveAs: saveAs) } }
}
