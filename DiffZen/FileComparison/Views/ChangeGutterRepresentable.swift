import SwiftUI
import AppKit

struct ChangeGutterRepresentable: NSViewRepresentable {
    let hunks: [DiffHunk]
    let selectedHunkID: DiffHunk.ID?
    let coordinator: DualScrollCoordinator
    let onSelectHunk: (DiffHunk.ID?) -> Void
    let onApplyHunk: (DiffHunk, ComparisonSide) -> Void

    func makeNSView(context: Context) -> ChangeGutterView {
        let view = ChangeGutterView()
        coordinator.gutterView = view
        configure(view)
        return view
    }

    func updateNSView(_ nsView: ChangeGutterView, context: Context) {
        coordinator.gutterView = nsView
        configure(nsView)
    }


    private func configure(_ view: ChangeGutterView) {
        view.configure(
            hunks: hunks,
            selectedHunkID: selectedHunkID,
            leftOffset: coordinator.leftOffset,
            rightOffset: coordinator.rightOffset,
            select: onSelectHunk,
            apply: onApplyHunk
        )
    }
}
