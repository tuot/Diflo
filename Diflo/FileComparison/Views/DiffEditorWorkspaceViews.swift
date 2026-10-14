import SwiftUI

// MARK: - Meld 原生双栏工作区 (NSTextView + 一体化装订线 + Hunk 感知滚动同步)

struct MeldDualEditorWorkspaceView: View {
    let session: ComparisonSession
    let scrollCoordinator: DualScrollCoordinator
    let onCursorChanged: (ComparisonSide, CursorPosition) -> Void

    var body: some View {
        HStack(spacing: 0) {
            // 左侧编辑器 (NSTextView + 一体化装订线 + 行号 + 差异高亮)
            SingleDiffTextView(
                side: .left,
                buffer: session.leftBuffer,
                oppositeLines: session.rightBuffer.lines,
                hunks: session.result?.hunks ?? [],
                selectedHunkID: session.selectedHunkID,
                coordinator: scrollCoordinator,
                onEdit: { session.edit(.left, text: $0) },
                onCursorChanged: { onCursorChanged(.left, $0) },
                onTextEdit: { session.edit(.left, edit: $0) },
                sharedUndoManager: session.undoManager
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 中央 Gutter 连线带 (贝塞尔曲线 + 双向合并按钮)
            ChangeGutterRepresentable(
                hunks: session.result?.hunks ?? [],
                selectedHunkID: session.selectedHunkID,
                coordinator: scrollCoordinator,
                onSelectHunk: { session.selectHunk($0) },
                onApplyHunk: { hunk, side in session.applyHunk(hunk, from: side) }
            )
            .frame(width: ChangeGutterView.preferredWidth).frame(maxHeight: .infinity)

            // 右侧编辑器 (NSTextView + 一体化装订线 + 行号 + 差异高亮)
            SingleDiffTextView(
                side: .right,
                buffer: session.rightBuffer,
                oppositeLines: session.leftBuffer.lines,
                hunks: session.result?.hunks ?? [],
                selectedHunkID: session.selectedHunkID,
                coordinator: scrollCoordinator,
                onEdit: { session.edit(.right, text: $0) },
                onCursorChanged: { onCursorChanged(.right, $0) },
                onTextEdit: { session.edit(.right, edit: $0) },
                sharedUndoManager: session.undoManager
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // 右侧 Overview 缩略图
            DiffOverviewRepresentable(
                hunks: session.result?.hunks ?? [],
                totalRows: max(session.rightBuffer.lineCount, 1),
                selectedHunkID: session.selectedHunkID,
                coordinator: scrollCoordinator,
                onSelectHunk: { session.selectHunk($0) }
            )
            .frame(width: 12).frame(maxHeight: .infinity)
        }
    }
}
