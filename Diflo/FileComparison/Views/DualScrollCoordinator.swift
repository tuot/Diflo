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

    var alignment = DiffAlignment(rows: [])
    weak var nativeGutterView: NativeChangeGutterView?
    var onViewportChanged: (() -> Void)?
    private var isSynchronizing = false
    private var leftHorizontalOffset: CGFloat = 0
    private var rightHorizontalOffset: CGFloat = 0

    func geometryChanged() {
        if let scroll = rightScrollView, let document = scroll.documentView {
            let height = max(1, document.bounds.height)
            let travel = max(0, height - scroll.contentSize.height)
            viewportProgress = travel > 0 ? scroll.contentView.bounds.minY / travel : 0
            visibleFraction = min(1, scroll.contentSize.height / height)
            overviewView?.updateViewport(progress: viewportProgress, visibleFraction: visibleFraction)
        }
        nativeGutterView?.needsDisplay = true
        onViewportChanged?()
    }

    func editor(for side: ComparisonSide) -> NativeDiffTextView? {
        (side == .left ? leftScrollView : rightScrollView)?.documentView as? NativeDiffTextView
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
        } else if let sourceEditor = source.documentView as? NativeDiffTextView,
           let targetEditor = target.documentView as? NativeDiffTextView {
            sourceEditor.refreshGeometry()
            let center = source.contentView.bounds.midY
            if let anchor = sourceEditor.geometry.linePosition(at: center) {
                let mapped = alignment.mappedLine(anchor, from: sourceIsLeft ? .left : .right)
                if targetEditor.geometry.y(for: mapped) == nil { targetEditor.navigate(to: Int(mapped)) }
                targetY = min(targetMax, max(0, (targetEditor.geometry.y(for: mapped) ?? target.contentView.bounds.midY) - target.contentSize.height / 2))
            } else { targetY = target.contentView.bounds.minY }
        } else {
            targetY = mapScrollPosition(sourceY: sourceY, sourceIsLeft: sourceIsLeft, sourceMax: sourceMax, targetMax: targetMax)
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

        (target.documentView as? NativeDiffTextView)?.refreshGeometry()
        geometryChanged()
        gutterView?.updateOffsets(left: leftOffset, right: rightOffset)
        overviewView?.updateViewport(progress: viewportProgress, visibleFraction: visibleFraction)
    }

    /// Piecewise Hunk-Aware Scroll Sync: Maps source Y coordinate to target Y so matching lines align horizontally.
    private func mapScrollPosition(sourceY: Double, sourceIsLeft: Bool, sourceMax: Double, targetMax: Double) -> Double {
        guard targetMax > 0 else { return 0 }
        if sourceY <= 0 {
            return sourceY
        }
        if sourceMax > 0, sourceY >= sourceMax {
            return targetMax + (sourceY - sourceMax)
        }
        guard !hunks.isEmpty, sourceMax > 0 else {
            let progress = sourceMax > 0 ? sourceY / sourceMax : 0
            return min(max(0, progress * targetMax), targetMax)
        }

        let rowHeight = DiffTextView.rowHeight
        let inset = DiffTextView.verticalInset
        let sourceLine = max(0, (sourceY - inset) / rowHeight)

        let targetLine = mapLine(sourceLine: sourceLine, sourceIsLeft: sourceIsLeft)
        let calculatedY = inset + targetLine * rowHeight

        // Smoothly clamp to document bounds
        return min(max(0, calculatedY), targetMax)
    }

    private func mapLine(sourceLine: Double, sourceIsLeft: Bool) -> Double {
        var prevSourceEnd = 0.0
        var prevTargetEnd = 0.0

        for hunk in hunks {
            let srcStart = Double(sourceIsLeft ? hunk.leftLineRange.lowerBound : hunk.rightLineRange.lowerBound)
            let srcEnd = Double(sourceIsLeft ? hunk.leftLineRange.upperBound : hunk.rightLineRange.upperBound)
            let tgtStart = Double(sourceIsLeft ? hunk.rightLineRange.lowerBound : hunk.leftLineRange.lowerBound)
            let tgtEnd = Double(sourceIsLeft ? hunk.rightLineRange.upperBound : hunk.leftLineRange.upperBound)

            // Before this hunk (in matching lines)
            if sourceLine < srcStart {
                return prevTargetEnd + (sourceLine - prevSourceEnd)
            }

            // Inside this hunk
            if sourceLine <= srcEnd {
                let srcLen = srcEnd - srcStart
                let tgtLen = tgtEnd - tgtStart
                if srcLen <= 0 {
                    return tgtStart
                }
                let fraction = (sourceLine - srcStart) / srcLen
                return tgtStart + fraction * tgtLen
            }

            prevSourceEnd = srcEnd
            prevTargetEnd = tgtEnd
        }

        // After all hunks (trailing matching lines)
        return prevTargetEnd + (sourceLine - prevSourceEnd)
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
        if let editor = scrollView.documentView as? NativeDiffTextView {
            editor.navigate(to: line)
            return
        }
        var point = scrollView.contentView.bounds.origin
        point.y = max(0, DiffTextView.verticalInset + Double(line) * DiffTextView.rowHeight - 80)
        scrollView.contentView.animator().setBoundsOrigin(point)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
