import SwiftUI
import AppKit

struct DiffOverviewRepresentable: NSViewRepresentable {
    let hunks: [DiffHunk]
    let totalRows: Int
    let selectedHunkID: DiffHunk.ID?
    let coordinator: DualScrollCoordinator
    let onSelectHunk: (DiffHunk.ID?) -> Void

    func makeNSView(context: Context) -> DiffOverviewView {
        let view = DiffOverviewView()
        coordinator.overviewView = view
        view.onScrollToProgress = { progress in
            coordinator.scrollToProgress(progress)
        }
        configure(view)
        return view
    }

    func updateNSView(_ nsView: DiffOverviewView, context: Context) {
        coordinator.overviewView = nsView
        nsView.onScrollToProgress = { progress in
            coordinator.scrollToProgress(progress)
        }
        configure(nsView)
    }


    private func configure(_ view: DiffOverviewView) {
        view.editor = coordinator.rightScrollView?.documentView as? DiffTextView
        view.configure(
            hunks: hunks,
            totalRows: totalRows,
            selectedHunkID: selectedHunkID,
            select: onSelectHunk
        )
        view.updateViewport(progress: coordinator.viewportProgress, visibleFraction: coordinator.visibleFraction)
    }
}
