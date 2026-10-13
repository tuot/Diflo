import SwiftUI

struct NativeDiffPane: NSViewRepresentable {
    let side: ComparisonSide
    let buffer: EditorBuffer
    let alignment: DiffAlignment
    let inlineRanges: [NSRange]
    let scrollCoordinator: DualScrollCoordinator
    let onEdit: (TextEdit) -> Void
    let onCursorChanged: (CursorPosition) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        let editor = NativeDiffTextView(usingTextLayoutManager: true)
        editor.frame = scroll.contentView.bounds
        editor.string = buffer.text
        editor.lineIndex = buffer.lineIndex
        editor.delegate = context.coordinator
        scroll.documentView = editor
        context.coordinator.editor = editor
        context.coordinator.revision = buffer.revision
        scrollCoordinator.register(scrollView: scroll, for: side)
        editor.onGeometryChanged = { [weak scrollCoordinator] in scrollCoordinator?.geometryChanged() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let isDifferentDocument = coordinator.parent.buffer.url != buffer.url || buffer.revision < coordinator.revision
        coordinator.parent = self
        guard let editor = scroll.documentView as? NativeDiffTextView else { return }
        if editor.string != buffer.text, !editor.hasMarkedText() {
            coordinator.applyingExternal = true
            editor.applyExternalText(buffer.text, undoable: !isDifferentDocument && coordinator.revision != buffer.revision)
            coordinator.applyingExternal = false
        }
        coordinator.revision = buffer.revision
        editor.lineIndex = buffer.lineIndex
        if coordinator.alignment != alignment {
            coordinator.alignment = alignment
            editor.changedLines = alignment.blocks.compactMap { block in
            guard block.kind != .equal else { return nil }
            let color: NSColor = block.kind == .replace ? .systemBlue : (block.kind == .insert ? .systemGreen : .systemRed)
            return (side == .left ? block.left : block.right, color)
        }
            }
        editor.inlineRanges = inlineRanges
        editor.refreshGeometry()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeDiffPane
        weak var editor: NativeDiffTextView?
        var revision = 0
        var applyingExternal = false
        var alignment: DiffAlignment?
        private var pendingEdit: TextEdit?
        init(_ parent: NativeDiffPane) { self.parent = parent }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if !applyingExternal, let replacementString {
                let normalized = LineParser.normalize(replacementString)
                if normalized != replacementString {
                    textView.insertText(normalized, replacementRange: affectedCharRange)
                    return false
                }
                pendingEdit = TextEdit(range: affectedCharRange, replacement: replacementString, baseRevision: revision)
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !applyingExternal, let editor else { return }
            if let pendingEdit {
                parent.onEdit(pendingEdit)
            } else {
                // Some undo/IME edits arrive without the single-range delegate callback.
                parent.onEdit(TextEdit(range: NSRange(location: 0, length: (parent.buffer.text as NSString).length), replacement: editor.string, baseRevision: revision))
            }
            pendingEdit = nil
            revision += 1
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor else { return }
            let offset = min(editor.selectedRange().location, (editor.string as NSString).length)
            let index = editor.lineIndex
            let line = index.line(containingUTF16Offset: offset)
            let start = index.utf16Starts.indices.contains(line) ? index.utf16Starts[line] : 0
            let prefix = (editor.string as NSString).substring(with: NSRange(location: min(start, offset), length: max(0, offset - start)))
            parent.onCursorChanged(CursorPosition(line: line + 1, column: prefix.count + 1))
        }
    }
}
