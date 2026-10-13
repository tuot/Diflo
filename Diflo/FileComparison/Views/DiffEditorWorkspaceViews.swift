import SwiftUI

// MARK: - Meld 官方配色规范体系 (提炼自 meld-base 与 meld-dark)

enum MeldTheme {
    static func insertBackground(isDark: Bool) -> Color {
        isDark ? Color(red: 0x12 / 255.0, green: 0x38 / 255.0, blue: 0x06 / 255.0)
               : Color(red: 0xd0 / 255.0, green: 0xff / 255.0, blue: 0xa3 / 255.0).opacity(0.85)
    }

    static func insertBorder(isDark: Bool) -> Color {
        isDark ? Color(red: 0x24 / 255.0, green: 0x55 / 255.0, blue: 0x15 / 255.0)
               : Color(red: 0xa5 / 255.0, green: 0xff / 255.0, blue: 0x4c / 255.0)
    }

    static func replaceBackground(isDark: Bool) -> Color {
        isDark ? Color(red: 0x00 / 255.0, green: 0x32 / 255.0, blue: 0x66 / 255.0)
               : Color(red: 0xbd / 255.0, green: 0xdd / 255.0, blue: 0xff / 255.0).opacity(0.85)
    }

    static func replaceBorder(isDark: Bool) -> Color {
        isDark ? Color(red: 0x00 / 255.0, green: 0x53 / 255.0, blue: 0xa6 / 255.0)
               : Color(red: 0x65 / 255.0, green: 0xb2 / 255.0, blue: 0xff / 255.0)
    }

    static func inlineDiffBackground(isDark: Bool) -> Color {
        isDark ? Color(red: 0x24 / 255.0, green: 0x52 / 255.0, blue: 0x7e / 255.0)
               : Color(red: 0x8a / 255.0, green: 0xc2 / 255.0, blue: 0xff / 255.0)
    }

    static func deleteBackground(isDark: Bool) -> Color {
        isDark ? Color(red: 0x7a / 255.0, green: 0x2a / 255.0, blue: 0x28 / 255.0)
               : Color(red: 0xff / 255.0, green: 0xa5 / 255.0, blue: 0xa3 / 255.0).opacity(0.85)
    }

    static func deleteBorder(isDark: Bool) -> Color {
        isDark ? Color(red: 0xac / 255.0, green: 0x3b / 255.0, blue: 0x39 / 255.0)
               : Color(red: 0xff / 255.0, green: 0x4f / 255.0, blue: 0x4c / 255.0)
    }
}

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

// MARK: - 右侧 Overview 标尺

struct SwiftUIOverviewView: View {
    let hunks: [DiffHunk]
    let totalLines: Int

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color(nsColor: .controlBackgroundColor).opacity(0.7)

                let visualLines = max(totalLines, 60)
                let heightScale = proxy.size.height / CGFloat(visualLines)

                ForEach(hunks) { hunk in
                    let startLine = min(hunk.leftLineRange.lowerBound, hunk.rightLineRange.lowerBound)
                    let lineCount = max(hunk.leftLineRange.count, hunk.rightLineRange.count, 1)
                    let y = CGFloat(startLine) * heightScale
                    let height = max(CGFloat(lineCount) * heightScale, 4)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(hunkColor(hunk))
                        .frame(height: height)
                        .offset(y: y)
                }
            }
        }
        .frame(width: 14)
    }

    private func hunkColor(_ hunk: DiffHunk) -> Color {
        switch hunk.kind {
        case .leftOnly: return MeldTheme.deleteBorder(isDark: isDark)
        case .rightOnly: return MeldTheme.insertBorder(isDark: isDark)
        case .modified: return MeldTheme.replaceBorder(isDark: isDark)
        }
    }
}
