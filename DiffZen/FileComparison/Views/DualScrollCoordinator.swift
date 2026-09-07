import AppKit

@MainActor
final class DualScrollCoordinator: NSObject {
    var leftOffset: Double = 0
    var rightOffset: Double = 0
    var viewportProgress: Double = 0
    var visibleFraction: Double = 1.0

    weak var leftScrollView: NSScrollView?
    weak var rightScrollView: NSScrollView?
    weak var gutterView: ChangeGutterView?
    weak var overviewView: DiffOverviewView?

    private var isSynchronizing = false

    func register(scrollView: NSScrollView, for side: ComparisonSide) {
        if side == .left {
            leftScrollView = scrollView
        } else {
            rightScrollView = scrollView
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        guard !isSynchronizing, let clipView = notification.object as? NSClipView else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }

        let sourceIsLeft = clipView === leftScrollView?.contentView
        guard let source = sourceIsLeft ? leftScrollView : rightScrollView,
              let target = sourceIsLeft ? rightScrollView : leftScrollView else { return }

        let sourceMax = max(0, (source.documentView?.bounds.height ?? 0) - source.contentSize.height)
        let targetMax = max(0, (target.documentView?.bounds.height ?? 0) - target.contentSize.height)
        let progress = sourceMax > 0 ? source.contentView.bounds.minY / sourceMax : 0

        var targetOrigin = target.contentView.bounds.origin
        targetOrigin.y = min(max(0, progress * targetMax), targetMax)
        target.contentView.scroll(to: targetOrigin)
        target.reflectScrolledClipView(target.contentView)

        leftOffset = Double(leftScrollView?.contentView.bounds.minY ?? 0)
        rightOffset = Double(rightScrollView?.contentView.bounds.minY ?? 0)
        viewportProgress = progress

        let docHeight = max(1, source.documentView?.bounds.height ?? 1)
        visibleFraction = min(1.0, source.contentSize.height / docHeight)

        gutterView?.updateOffsets(left: leftOffset, right: rightOffset)
        overviewView?.updateViewport(progress: viewportProgress, visibleFraction: visibleFraction)
    }

    func scrollToProgress(_ progress: Double) {
        for scrollView in [leftScrollView, rightScrollView].compactMap({ $0 }) {
            let maxScroll = max(0, (scrollView.documentView?.bounds.height ?? 0) - scrollView.contentSize.height)
            var origin = scrollView.contentView.bounds.origin
            origin.y = maxScroll * progress
            scrollView.contentView.animator().setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func scrollTo(hunk: DiffHunk) {
        if let leftScrollView {
            scrollTo(scrollView: leftScrollView, line: hunk.leftLineRange.lowerBound)
        }
        if let rightScrollView {
            scrollTo(scrollView: rightScrollView, line: hunk.rightLineRange.lowerBound)
        }
    }

    private func scrollTo(scrollView: NSScrollView, line: Int) {
        var point = scrollView.contentView.bounds.origin
        point.y = max(0, DiffTextView.verticalInset + Double(line) * DiffTextView.rowHeight - 80)
        scrollView.contentView.animator().setBoundsOrigin(point)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
