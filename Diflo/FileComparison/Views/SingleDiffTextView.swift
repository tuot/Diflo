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

    func makeNSView(context: Context) -> DiffEditorContainerView {
        let scrollView = NSScrollView()
        let textView = DiffTextView.createStandard(side: side)
        let rulerView = LineNumberRulerView(scrollView: scrollView, side: side)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder

        let placeholder = side == .left ? "输入或粘贴左侧文本..." : "输入或粘贴右侧文本..."
        let containerView = DiffEditorContainerView(
            scrollView: scrollView,
            lineNumberView: rulerView,
            placeholder: placeholder
        )

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.rulerView = rulerView
        context.coordinator.containerView = containerView

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

        return containerView
    }

    func updateNSView(_ containerView: DiffEditorContainerView, context: Context) {
        context.coordinator.parent = self
        let scrollView = containerView.scrollView
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
        weak var scrollView: NSScrollView?
        weak var rulerView: LineNumberRulerView?
        weak var containerView: DiffEditorContainerView?
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

            if !isInternalUpdating {
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

            rulerView?.configure(lineCount: buffer.lineCount, hunks: hunks)
            containerView?.setPlaceholderHidden(!buffer.text.isEmpty)
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            isInternalUpdating = true
            let newText = textView.string
            parent.onEdit(newText)
            containerView?.setPlaceholderHidden(!newText.isEmpty)
            updateCursorPosition(in: textView)
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

final class DiffEditorContainerView: NSView {
    let scrollView: NSScrollView
    private let placeholderLabel: NSTextField

    init(scrollView: NSScrollView, lineNumberView: NSView, placeholder: String) {
        self.scrollView = scrollView
        self.placeholderLabel = NSTextField(labelWithString: placeholder)
        super.init(frame: .zero)
        lineNumberView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lineNumberView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        placeholderLabel.textColor = .placeholderTextColor
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            lineNumberView.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineNumberView.topAnchor.constraint(equalTo: topAnchor),
            lineNumberView.bottomAnchor.constraint(equalTo: bottomAnchor),
            lineNumberView.widthAnchor.constraint(equalToConstant: 62),
            scrollView.leadingAnchor.constraint(equalTo: lineNumberView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 70),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        ])
    }

    func setPlaceholderHidden(_ hidden: Bool) {
        placeholderLabel.isHidden = hidden
    }

    required init?(coder: NSCoder) {
        nil
    }
}
