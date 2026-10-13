import SwiftUI

@MainActor @Observable
final class NativeInlineHighlights {
    var left: [NSRange] = []
    var right: [NSRange] = []
    private let worker = InlineDiffWorker()
    private var task: Task<Void, Never>?
    private var generation = 0
    private var requestKey: String?
    private var requestedLeftText: String?
    private var requestedRightText: String?

    func update(session: ComparisonSession, coordinator: DualScrollCoordinator) {
        guard let result = session.result,
              result.leftRevision == session.leftBuffer.revision,
              result.rightRevision == session.rightBuffer.revision,
              result.options == session.options,
              result.leftFile.normalizedText == session.leftBuffer.text,
              result.rightFile.normalizedText == session.rightBuffer.text else {
            if requestKey != nil { cancel() }
            if !left.isEmpty { left = [] }
            if !right.isEmpty { right = [] }
            return
        }
        let leftBuffer = session.leftBuffer
        let rightBuffer = session.rightBuffer
        let visible = coordinator.editor(for: .left)?.geometry.visibleLines ?? 0..<0
        let rightVisible = coordinator.editor(for: .right)?.geometry.visibleLines ?? 0..<0
        let key = "\(leftBuffer.revision):\(rightBuffer.revision):\(session.options):\(visible):\(rightVisible)"
        guard key != requestKey || requestedLeftText != leftBuffer.text || requestedRightText != rightBuffer.text else { return }
        requestKey = key
        requestedLeftText = leftBuffer.text
        requestedRightText = rightBuffer.text
        generation += 1
        let request = generation
        task?.cancel()
        left = []; right = []
        let blocks = result.alignment.blocks.filter { block in
            block.kind == .replace && (block.left.overlaps(visible) || block.right.overlaps(rightVisible))
        }
        task = Task { [weak self] in
            guard let self else { return }
            var leftRanges: [NSRange] = []
            var rightRanges: [NSRange] = []
            for block in blocks {
                guard !Task.isCancelled else { return }
                let l = leftBuffer.lines[block.left].joined(separator: "\n")
                let r = rightBuffer.lines[block.right].joined(separator: "\n")
                guard let highlight = try? await worker.compare(left: l, right: r),
                      generation == request,
                      session.leftBuffer.revision == leftBuffer.revision,
                      session.rightBuffer.revision == rightBuffer.revision,
                      session.leftBuffer.text == leftBuffer.text,
                      session.rightBuffer.text == rightBuffer.text,
                      session.options == result.options,
                      session.result?.alignment == result.alignment else { return }
                let lOffset = leftBuffer.lineIndex.utf16Starts[block.left.lowerBound]
                let rOffset = rightBuffer.lineIndex.utf16Starts[block.right.lowerBound]
                leftRanges += highlight.leftRanges.map { NSRange(location: $0.location + lOffset, length: $0.length) }
                rightRanges += highlight.rightRanges.map { NSRange(location: $0.location + rOffset, length: $0.length) }
            }
            guard generation == request, !Task.isCancelled else { return }
            left = leftRanges; right = rightRanges
        }
    }

    func cancel() { task?.cancel(); generation += 1; requestKey = nil }
}

struct NativeDiffWorkspace: View {
    let session: ComparisonSession
    let scrollCoordinator: DualScrollCoordinator
    let onCursorChanged: (ComparisonSide, CursorPosition) -> Void
    @State private var highlights = NativeInlineHighlights()

    var body: some View {
        HStack(spacing: 0) {
            pane(.left, buffer: session.leftBuffer, ranges: highlights.left)
            NativeChangeGutterRepresentable(session: session, coordinator: scrollCoordinator)
                .frame(width: 52)
            pane(.right, buffer: session.rightBuffer, ranges: highlights.right)
            Divider()
            DiffOverviewRepresentable(
                hunks: session.result?.hunks ?? [],
                totalRows: max(session.leftBuffer.lineCount, session.rightBuffer.lineCount, 1),
                selectedHunkID: session.selectedHunkID,
                coordinator: scrollCoordinator,
                onSelectHunk: { session.selectHunk($0) }
            ).frame(width: 14)
        }
        .onAppear {
            scrollCoordinator.onViewportChanged = {
                // Layout callbacks may occur during SwiftUI updates; schedule state changes afterward.
                Task { @MainActor in highlights.update(session: session, coordinator: scrollCoordinator) }
            }
            update()
        }
        .onChange(of: session.result) { _, _ in highlights.cancel(); update() }
        .onChange(of: session.leftBuffer.text) { _, _ in update() }
        .onChange(of: session.rightBuffer.text) { _, _ in update() }
        .onChange(of: session.options) { _, _ in update() }
        .onDisappear { highlights.cancel(); scrollCoordinator.onViewportChanged = nil }
    }

    private func pane(_ side: ComparisonSide, buffer: EditorBuffer, ranges: [NSRange]) -> some View {
        NativeDiffPane(side: side, buffer: buffer, alignment: session.result?.alignment ?? DiffAlignment(rows: []), inlineRanges: ranges, scrollCoordinator: scrollCoordinator,
                       onEdit: { session.edit(side, edit: $0) }, onCursorChanged: { onCursorChanged(side, $0) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func update() {
        scrollCoordinator.alignment = session.result?.alignment ?? DiffAlignment(rows: [])
        highlights.update(session: session, coordinator: scrollCoordinator)
    }
}
