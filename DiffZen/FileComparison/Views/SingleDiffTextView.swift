import SwiftUI
import AppKit

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

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = DiffTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: DiffTextView.verticalInset)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 400)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: 300,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        scrollView.documentView = textView

        let rulerView = LineNumberRulerView(scrollView: scrollView, side: side)
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        DispatchQueue.main.async {
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            rulerView.needsDisplay = true
            textView.resizeDocument(minimumSize: scrollView.contentSize)
        }

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView
        context.coordinator.scrollView = scrollView

        coordinator.register(scrollView: scrollView, for: side)

        textView.placeholderString = side == .left ? "输入或粘贴左侧文本..." : "输入或粘贴右侧文本..."
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak textView, weak scrollView] _ in
            guard let textView, let scrollView else { return }
            textView.resizeDocument(minimumSize: scrollView.contentSize)
        }

        // Initial configure
        context.coordinator.configure(
            buffer: buffer,
            oppositeLines: oppositeLines,
            hunks: hunks,
            selectedHunkID: selectedHunkID
        )

        // Focus if blank left editor
        if side == .left, buffer.url == nil, buffer.text.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let window = scrollView.window {
                    window.makeFirstResponder(textView)
                    textView.setSelectedRange(NSRange(location: 0, length: 0))
                }
            }
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configure(
            buffer: buffer,
            oppositeLines: oppositeLines,
            hunks: hunks,
            selectedHunkID: selectedHunkID
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? 400,
            height: proposal.height ?? 600
        )
    }

    final class ViewCoordinator: NSObject, NSTextViewDelegate {
        var parent: SingleDiffTextView
        weak var textView: DiffTextView?
        weak var rulerView: LineNumberRulerView?
        weak var scrollView: NSScrollView?
        private var isProgrammatic = false

        init(_ parent: SingleDiffTextView) {
            self.parent = parent
        }

        func configure(
            buffer: EditorBuffer,
            oppositeLines: [String],
            hunks: [DiffHunk],
            selectedHunkID: DiffHunk.ID?
        ) {
            guard let textView, let rulerView, let scrollView else { return }
            isProgrammatic = true
            textView.configure(
                text: buffer.text,
                lineCount: buffer.lineCount,
                hunks: hunks,
                side: parent.side,
                selectedHunkID: selectedHunkID,
                oppositeLines: oppositeLines
            )
            isProgrammatic = false
            rulerView.configure(lineCount: buffer.lineCount, hunks: hunks)
            textView.resizeDocument(minimumSize: scrollView.contentSize)
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammatic, let textView = notification.object as? NSTextView else { return }
            guard !textView.hasMarkedText() else { return }
            parent.onEdit(textView.string)
            reportCursor(for: textView)
            if let scrollView {
                (textView as? DiffTextView)?.resizeDocument(minimumSize: scrollView.contentSize)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            reportCursor(for: textView)
        }

        private func reportCursor(for textView: NSTextView) {
            let location = min(textView.selectedRange().location, (textView.string as NSString).length)
            let prefix = (textView.string as NSString).substring(to: location)
            let parts = prefix.split(separator: "\n", omittingEmptySubsequences: false)
            parent.onCursorChanged(CursorPosition(line: max(1, parts.count), column: (parts.last?.count ?? 0) + 1))
        }
    }
}
