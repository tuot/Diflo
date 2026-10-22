import AppKit

@MainActor
final class DualScrollCoordinator: NSObject {
    var leftOffset: Double = 0
    var rightOffset: Double = 0
    var viewportProgress: Double = 0
    var visibleFraction: Double = 1.0
    var hunks: [DiffHunk] = []

    weak var leftScrollView: NSScrollView?
    weak var rightScrollView: NSScrollView?
    weak var gutterView: ChangeGutterView?
    weak var overviewView: DiffOverviewView?

    private var isSynchronizing = false
    private var leftHorizontalOffset: CGFloat = 0
    private var rightHorizontalOffset: CGFloat = 0

    func geometryChanged() {
        gutterView?.needsDisplay = true
        overviewView?.needsDisplay = true
        if let scroll = rightScrollView, let document = scroll.documentView {
            let height = max(1, document.bounds.height)
            let travel = max(0, height - scroll.contentSize.height)
            viewportProgress = travel > 0 ? scroll.contentView.bounds.minY / travel : 0
            visibleFraction = min(1, scroll.contentSize.height / height)
            overviewView?.updateViewport(progress: viewportProgress, visibleFraction: visibleFraction)
        }
    }

    func register(scrollView: NSScrollView, for side: ComparisonSide) {
        if side == .left {
            leftScrollView = scrollView
            leftOffset = scrollView.contentView.bounds.minY
            leftHorizontalOffset = scrollView.contentView.bounds.minX
        } else {
            rightScrollView = scrollView
            rightOffset = scrollView.contentView.bounds.minY
            rightHorizontalOffset = scrollView.contentView.bounds.minX
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

    func updateHunks(_ hunks: [DiffHunk]) {
        self.hunks = hunks
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
        let sourceY = Double(source.contentView.bounds.minY)
        let verticalChanged = sourceY != (sourceIsLeft ? leftOffset : rightOffset)
        let sourceX = source.contentView.bounds.minX
        let horizontalChanged = sourceX != (sourceIsLeft ? leftHorizontalOffset : rightHorizontalOffset)

        let targetY: Double
        if !verticalChanged {
            targetY = target.contentView.bounds.minY
        } else {
            targetY = mapScrollPosition(sourceY: sourceY, sourceIsLeft: sourceIsLeft, sourceMax: sourceMax, targetMax: targetMax, sourceViewport: source.contentSize.height, targetViewport: target.contentSize.height)
        }

        var targetOrigin = target.contentView.bounds.origin
        targetOrigin.y = CGFloat(targetY)
        if horizontalChanged {
            let targetMaxX = max(0, (target.documentView?.bounds.width ?? 0) - target.contentSize.width)
            targetOrigin.x = min(targetMaxX, max(0, sourceX))
        }
        target.contentView.scroll(to: targetOrigin)
        target.reflectScrolledClipView(target.contentView)

        leftOffset = Double(leftScrollView?.contentView.bounds.minY ?? 0)
        rightOffset = Double(rightScrollView?.contentView.bounds.minY ?? 0)
        leftHorizontalOffset = leftScrollView?.contentView.bounds.minX ?? 0
        rightHorizontalOffset = rightScrollView?.contentView.bounds.minX ?? 0
        let overviewScroll = rightScrollView ?? source
        let docHeight = max(1, overviewScroll.documentView?.bounds.height ?? 1)
        let overviewMax = max(0, docHeight - overviewScroll.contentSize.height)
        viewportProgress = overviewMax > 0 ? overviewScroll.contentView.bounds.minY / overviewMax : 0
        visibleFraction = min(1.0, overviewScroll.contentSize.height / docHeight)

        geometryChanged()
        gutterView?.updateOffsets(left: leftOffset, right: rightOffset)
        overviewView?.updateViewport(progress: viewportProgress, visibleFraction: visibleFraction)
    }

    /// Interpolate around each diff over a viewport so empty source ranges cannot jump.
    private func mapScrollPosition(sourceY: Double, sourceIsLeft: Bool, sourceMax: Double, targetMax: Double,
                                   sourceViewport: Double, targetViewport: Double) -> Double {
        guard targetMax > 0 else { return 0 }
        if sourceY <= 0 { return sourceY }
        if sourceMax > 0, sourceY >= sourceMax { return targetMax + (sourceY - sourceMax) }
        guard sourceMax > 0 else { return 0 }

        let sourceEditor = (sourceIsLeft ? leftScrollView : rightScrollView)?.documentView as? DiffTextView
        let targetEditor = (sourceIsLeft ? rightScrollView : leftScrollView)?.documentView as? DiffTextView
        func position(_ line: Int, editor: DiffTextView?) -> Double {
            Double(editor?.lineY(line) ?? (DiffTextView.verticalInset + CGFloat(line) * DiffTextView.rowHeight))
        }
        var transitions: [(sourceStart: Double, sourceEnd: Double, targetStart: Double, targetEnd: Double)] = []
        for hunk in hunks {
            let source = sourceIsLeft ? hunk.leftLineRange : hunk.rightLineRange
            let target = sourceIsLeft ? hunk.rightLineRange : hunk.leftLineRange
            let start = min(sourceMax, max(0, position(source.lowerBound, editor: sourceEditor) - sourceViewport / 2))
            let end = min(sourceMax, max(0, position(source.upperBound, editor: sourceEditor) + sourceViewport / 2))
            let targetStart = min(targetMax, max(0, position(target.lowerBound, editor: targetEditor) - targetViewport / 2))
            let targetEnd = min(targetMax, max(0, position(target.upperBound, editor: targetEditor) + targetViewport / 2))
            // Nearby transitions share one interval; overlapping anchors would reverse the mapping.
            if let previous = transitions.last, start <= previous.sourceEnd || targetStart <= previous.targetEnd {
                transitions[transitions.count - 1].sourceEnd = max(previous.sourceEnd, end)
                transitions[transitions.count - 1].targetEnd = max(previous.targetEnd, targetEnd)
            } else {
                transitions.append((start, end, targetStart, targetEnd))
            }
        }

        var previousSource = 0.0
        var previousTarget = 0.0
        for transition in transitions {
            for (source, target) in [(transition.sourceStart, transition.targetStart),
                                     (transition.sourceEnd, transition.targetEnd)] {
                // Document edges use the shared (0, 0) and (sourceMax, targetMax) anchors.
                guard source > previousSource, target > previousTarget,
                      source < sourceMax, target < targetMax else { continue }
                if sourceY <= source {
                    let fraction = (sourceY - previousSource) / (source - previousSource)
                    return previousTarget + fraction * (target - previousTarget)
                }
                previousSource = source
                previousTarget = target
            }
        }
        let fraction = (sourceY - previousSource) / (sourceMax - previousSource)
        return previousTarget + fraction * (targetMax - previousTarget)
    }

    func scrollToProgress(_ progress: Double) {
        guard let scrollView = rightScrollView ?? leftScrollView else { return }
        let maxScroll = max(0, (scrollView.documentView?.bounds.height ?? 0) - scrollView.contentSize.height)
        var origin = scrollView.contentView.bounds.origin
        origin.y = maxScroll * max(0, min(1, progress))
        // The normal right-to-left synchronization keeps corresponding content aligned.
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
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
        point.y = max(0, ((scrollView.documentView as? DiffTextView)?.lineY(line) ?? (DiffTextView.verticalInset + Double(line) * DiffTextView.rowHeight)) - 80)
        scrollView.contentView.animator().setBoundsOrigin(point)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
