import SwiftUI

final class NativeChangeGutterView: NSView {
    weak var coordinator: DualScrollCoordinator?
    var hunks: [DiffHunk] = []
    var selected: DiffHunk.ID?
    var select: ((DiffHunk.ID?) -> Void)?
    var apply: ((DiffHunk, ComparisonSide) -> Void)?
    private var hitRegions: [(CGRect, DiffHunk, ComparisonSide)] = []
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()
        hitRegions.removeAll(keepingCapacity: true)
        guard let coordinator, let left = coordinator.editor(for: .left), let right = coordinator.editor(for: .right) else { return }
        var visibleIDs: Set<DiffHunk.ID> = []
        let visibleHunks = candidates(in: left.geometry.visibleLines, side: .left) + candidates(in: right.geometry.visibleLines, side: .right)
        for hunk in visibleHunks where visibleIDs.insert(hunk.id).inserted {
            let l = left.geometry.rect(for: hunk.leftLineRange).map { $0.offsetBy(dx: 0, dy: -left.visibleRect.minY) }
            let r = right.geometry.rect(for: hunk.rightLineRange).map { $0.offsetBy(dx: 0, dy: -right.visibleRect.minY) }
            guard l != nil || r != nil else { continue }
            // Missing distant layout is not represented by a fictitious zero coordinate.
            guard let l, let r else { continue }
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: l.minY))
            path.curve(to: NSPoint(x: bounds.width, y: r.minY), controlPoint1: NSPoint(x: bounds.midX, y: l.minY), controlPoint2: NSPoint(x: bounds.midX, y: r.minY))
            path.line(to: NSPoint(x: bounds.width, y: r.maxY))
            path.curve(to: NSPoint(x: 0, y: l.maxY), controlPoint1: NSPoint(x: bounds.midX, y: r.maxY), controlPoint2: NSPoint(x: bounds.midX, y: l.maxY))
            path.close()
            let color: NSColor = hunk.kind == .modified ? .systemBlue : (hunk.kind == .leftOnly ? .systemRed : .systemGreen)
            color.withAlphaComponent(selected == hunk.id ? 0.35 : 0.16).setFill()
            path.fill()
            for (x, y, side, label) in [(CGFloat(2), l.midY, ComparisonSide.left, "→"), (CGFloat(28), r.midY, ComparisonSide.right, "←")] {
                let rect = CGRect(x: x, y: y - 9, width: 22, height: 18)
                guard rect.intersects(bounds) else { continue }
                NSColor.controlBackgroundColor.withAlphaComponent(0.9).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
                (label as NSString).draw(at: NSPoint(x: x + 4, y: y - 8), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color])
                hitRegions.append((rect, hunk, side))
            }
        }
    }
    private func candidates(in visible: Range<Int>, side: ComparisonSide) -> ArraySlice<DiffHunk> {
        var low = 0, high = hunks.count
        while low < high {
            let mid = (low + high) / 2
            let range = side == .left ? hunks[mid].leftLineRange : hunks[mid].rightLineRange
            if range.upperBound < visible.lowerBound { low = mid + 1 } else { high = mid }
        }
        let start = low
        while low < hunks.count {
            let range = side == .left ? hunks[low].leftLineRange : hunks[low].rightLineRange
            if range.lowerBound > visible.upperBound { break }
            low += 1
        }
        return hunks[start..<low]
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let (_, hunk, side) = hitRegions.first(where: { $0.0.contains(point) }) {
            select?(hunk.id)
            apply?(hunk, side)
        }
    }
}

struct NativeChangeGutterRepresentable: NSViewRepresentable {
    let session: ComparisonSession
    let coordinator: DualScrollCoordinator
    func makeNSView(context: Context) -> NativeChangeGutterView {
        let view = NativeChangeGutterView()
        view.coordinator = coordinator
        coordinator.nativeGutterView = view
        return view
    }
    func updateNSView(_ view: NativeChangeGutterView, context: Context) {
        view.hunks = session.result?.hunks ?? []
        view.selected = session.selectedHunkID
        view.select = { session.selectHunk($0) }
        view.apply = { session.applyHunk($0, from: $1) }
        view.needsDisplay = true
    }
}
