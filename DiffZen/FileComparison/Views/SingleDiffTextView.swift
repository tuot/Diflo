import SwiftUI
import AppKit

// MARK: - 编辑器面板（承载 SingleDiffTextView）

struct DiffEditorPaneView: View {
    let side: ComparisonSide
    let buffer: EditorBuffer
    let oppositeLines: [String]
    let hunks: [DiffHunk]
    let selectedHunkID: DiffHunk.ID?
    let coordinator: DualScrollCoordinator
    let onEdit: (String) -> Void
    let onCursorChanged: (CursorPosition) -> Void

    var body: some View {
        SingleDiffTextView(
            side: side,
            buffer: buffer,
            oppositeLines: oppositeLines,
            hunks: hunks,
            selectedHunkID: selectedHunkID,
            coordinator: coordinator,
            onEdit: onEdit,
            onCursorChanged: onCursorChanged
        )
    }
}

// MARK: - NSViewRepresentable：承载一体化装订线与高亮的 DiffScrollView

struct SingleDiffTextView: NSViewRepresentable {
    let side: ComparisonSide
    let buffer: EditorBuffer
    let oppositeLines: [String]
    let hunks: [DiffHunk]
    let selectedHunkID: DiffHunk.ID?
    let coordinator: DualScrollCoordinator
    let onEdit: (String) -> Void
    let onCursorChanged: (CursorPosition) -> Void

    func makeCoordinator() -> ViewCoordinator {
        ViewCoordinator(self)
    }

    func makeNSView(context: Context) -> DiffScrollView {
        let scrollView = DiffScrollView()
        let textView = DiffTextView.createStandard(side: side)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        coordinator.register(scrollView: scrollView, for: side)

        context.coordinator.configure(
            buffer: buffer,
            oppositeLines: oppositeLines,
            hunks: hunks,
            selectedHunkID: selectedHunkID
        )

        // 首次打开空白对比时，自动让左侧聚焦
        if side == .left && buffer.text.isEmpty {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: DiffScrollView, context: Context) {
        context.coordinator.parent = self
        scrollView.tile()
        context.coordinator.configure(
            buffer: buffer,
            oppositeLines: oppositeLines,
            hunks: hunks,
            selectedHunkID: selectedHunkID
        )
    }


    // MARK: - Coordinator

    final class ViewCoordinator: NSObject, NSTextViewDelegate {
        var parent: SingleDiffTextView
        weak var textView: DiffTextView?
        weak var scrollView: DiffScrollView?
        private var isInternalUpdating = false

        init(_ parent: SingleDiffTextView) {
            self.parent = parent
        }

        func configure(
            buffer: EditorBuffer,
            oppositeLines: [String],
            hunks: [DiffHunk],
            selectedHunkID: DiffHunk.ID?
        ) {
            guard let textView else { return }

            if !isInternalUpdating && textView.string != buffer.text {
                textView.configure(
                    text: buffer.text,
                    lineCount: buffer.lineCount,
                    hunks: hunks,
                    side: parent.side,
                    selectedHunkID: selectedHunkID,
                    oppositeLines: oppositeLines
                )
            } else {
                textView.updateDiffHighlights(
                    lineCount: buffer.lineCount,
                    hunks: hunks,
                    side: parent.side,
                    selectedHunkID: selectedHunkID,
                    oppositeLines: oppositeLines
                )
            }

            if let scrollView {
                textView.resizeDocument(minimumSize: scrollView.contentSize)
            }
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            isInternalUpdating = true
            let newText = textView.string
            parent.onEdit(newText)
            updateCursorPosition(in: textView)
            if let scrollView {
                textView.resizeDocument(minimumSize: scrollView.contentSize)
            }
            isInternalUpdating = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            updateCursorPosition(in: textView)
        }

        private func updateCursorPosition(in textView: NSTextView) {
            let selectedLocation = textView.selectedRange().location
            let text = textView.string as NSString
            let safeLocation = min(selectedLocation, text.length)

            var line = 1
            var col = 1
            var idx = 0
            while idx < safeLocation {
                if text.character(at: idx) == 0x0A {
                    line += 1
                    col = 1
                } else {
                    col += 1
                }
                idx += 1
            }
            parent.onCursorChanged(CursorPosition(line: line, column: col))
        }
    }
}

// MARK: - 自定义 NSScrollView 子类：确保 frame 变化时 documentView 正确铺满视口

final class DiffScrollView: NSScrollView {
    override func layout() {
        super.layout()
        syncDocumentViewSize()
    }

    override func tile() {
        super.tile()
        syncDocumentViewSize()
    }

    override var frame: NSRect {
        didSet {
            syncDocumentViewSize()
        }
    }

    private func syncDocumentViewSize() {
        if let textView = documentView as? DiffTextView {
            textView.resizeDocument(minimumSize: contentSize)
            textView.needsDisplay = true
        }
    }
}
