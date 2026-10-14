import SwiftUI
import AppKit

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
    var onTextEdit: ((TextEdit) -> Void)? = nil
    var sharedUndoManager: UndoManager? = nil

    func makeCoordinator() -> ViewCoordinator {
        ViewCoordinator(self)
    }

    func makeNSView(context: Context) -> DiffEditorContainerView {
        let scrollView = DiffOverlayScrollView()
        let textView = DiffTextView.createStandard(side: side)
        textView.sharedUndoManager = sharedUndoManager

        scrollView.documentView = textView
        scrollView.findBarPosition = .aboveContent
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder

        let placeholder = side == .left ? "输入或粘贴左侧文本..." : "输入或粘贴右侧文本..."
        let containerView = DiffEditorContainerView(
            scrollView: scrollView,
            placeholder: placeholder
        )
        containerView.onLayout = { coordinator.geometryChanged() }

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
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
        weak var containerView: DiffEditorContainerView?
        private var isInternalUpdating = false
        private var applyingExternal = false
        private var documentID: UUID?
        private var revision = 0
        private var lastCommittedText = ""
        private var pendingEdit: TextEdit?
        private var lastCursor: CursorPosition?
        private var deferredExternalUpdate = false

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
            guard !textView.hasMarkedText() else {
                deferredExternalUpdate = deferredExternalUpdate || documentID != buffer.documentID || revision != buffer.revision
                containerView?.setPlaceholderHidden(!textView.string.isEmpty)
                return
            }

            let isNewDocument = documentID != buffer.documentID
            if isNewDocument {
                textView.undoManager?.removeAllActions()
                pendingEdit = nil
                lastCursor = nil
            }
            applyingExternal = true
            if !isInternalUpdating {
                textView.configure(
                    text: buffer.text,
                    lineCount: buffer.lineCount,
                    hunks: hunks,
                    side: parent.side,
                    selectedHunkID: selectedHunkID,
                    oppositeLines: oppositeLines,
                    undoable: !isNewDocument && revision != buffer.revision,
                    lineIndex: buffer.lineIndex
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

            applyingExternal = false
            deferredExternalUpdate = false
            documentID = buffer.documentID
            revision = buffer.revision
            lastCommittedText = textView.string
            containerView?.setPlaceholderHidden(!buffer.text.isEmpty)
            textView.resizeDocument(minimumSize: scrollView?.contentSize ?? .zero)
            Task { @MainActor [weak self] in
                guard let self, let editor = self.textView else { return }
                self.updateCursorPosition(in: editor)
            }
        }

        // MARK: - NSTextViewDelegate

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !applyingExternal, !textView.hasMarkedText(), let replacementString else { return true }
            let normalized = LineParser.normalize(replacementString)
            if normalized != replacementString {
                textView.insertText(normalized, replacementRange: affectedCharRange)
                return false
            }
            pendingEdit = TextEdit(range: affectedCharRange, replacement: replacementString, baseRevision: revision)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !applyingExternal else { return }
            containerView?.setPlaceholderHidden(!textView.string.isEmpty)
            guard !textView.hasMarkedText() else { pendingEdit = nil; return }
            // A file or merge received during composition must not be overwritten by the old draft.
            if deferredExternalUpdate {
                pendingEdit = nil
                configure(buffer: parent.buffer, oppositeLines: parent.oppositeLines, hunks: parent.hunks, selectedHunkID: parent.selectedHunkID)
                return
            }
            let newText = textView.string
            guard newText != lastCommittedText else { pendingEdit = nil; return }
            isInternalUpdating = true
            if let pendingEdit, let onTextEdit = parent.onTextEdit,
               NSMaxRange(pendingEdit.range) <= (lastCommittedText as NSString).length,
               (lastCommittedText as NSString).replacingCharacters(in: pendingEdit.range, with: pendingEdit.replacement) == newText {
                onTextEdit(pendingEdit)
            } else {
                parent.onEdit(newText)
            }
            pendingEdit = nil
            revision += 1
            lastCommittedText = newText
            updateCursorPosition(in: textView)
            isInternalUpdating = false
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView, !textView.hasMarkedText(), textView.string != parent.buffer.text else { return }
            textDidChange(notification)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            updateCursorPosition(in: textView)
        }

        private func updateCursorPosition(in textView: DiffTextView) {
            guard !applyingExternal else { return }
            let text = textView.string as NSString
            let location = min(textView.selectedRange().location, text.length)
            let index = textView.lineIndex
            let line = index.line(containingUTF16Offset: location)
            let start = index.utf16Starts.indices.contains(line) ? index.utf16Starts[line] : 0
            let prefix = text.substring(with: NSRange(location: min(start, location), length: max(0, location - start)))
            let cursor = CursorPosition(line: line + 1, column: prefix.count + 1)
            guard cursor != lastCursor else { return }
            lastCursor = cursor
            parent.onCursorChanged(cursor)
        }
    }
}

final class DiffEditorContainerView: NSView {
    var onLayout: (() -> Void)?
    let scrollView: NSScrollView
    private let placeholderLabel: NSTextField

    override func layout() {
        super.layout()
        (scrollView.documentView as? DiffTextView)?.resizeDocument(minimumSize: scrollView.contentSize)
        onLayout?()
    }

    init(scrollView: NSScrollView, placeholder: String) {
        self.scrollView = scrollView
        self.placeholderLabel = NSTextField(labelWithString: placeholder)
        super.init(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = DiffTextView.editorFont
        placeholderLabel.textColor = .placeholderTextColor
        let placeholderContent = scrollView.documentView ?? scrollView.contentView
        placeholderContent.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: placeholderContent.leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: placeholderContent.topAnchor, constant: 10)
        ])
    }

    func setPlaceholderHidden(_ hidden: Bool) {
        placeholderLabel.isHidden = hidden
    }

    required init?(coder: NSCoder) {
        nil
    }
}
