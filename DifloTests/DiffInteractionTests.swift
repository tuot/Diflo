import AppKit
import Testing
@testable import Diflo

@MainActor
struct DiffInteractionTests {
    @Test func horizontalScrollingSynchronizesBothDirectionsWithoutMovingVertically() {
        let left = scrollView(width: 1400, y: 80)
        let right = scrollView(width: 600, y: 120)
        let coordinator = DualScrollCoordinator()
        coordinator.register(scrollView: left, for: .left)
        coordinator.register(scrollView: right, for: .right)

        scroll(left, to: NSPoint(x: 250, y: 80))
        #expect(right.contentView.bounds.origin == NSPoint(x: 250, y: 120))
        scroll(right, to: NSPoint(x: 100, y: 120))
        #expect(left.contentView.bounds.origin == NSPoint(x: 100, y: 80))
    }

    @Test func horizontalScrollingClampsAtTheShorterDocumentAndVerticalScrollingKeepsX() {
        let left = scrollView(width: 1400, y: 80)
        let right = scrollView(width: 600, y: 120)
        let coordinator = DualScrollCoordinator()
        coordinator.register(scrollView: left, for: .left)
        coordinator.register(scrollView: right, for: .right)

        scroll(left, to: NSPoint(x: 700, y: 80))
        #expect(right.contentView.bounds.minX == 300)
        #expect(left.contentView.bounds.minX == 700)
        scroll(right, to: NSPoint(x: 300, y: 200))
        #expect(left.contentView.bounds.minX == 700)
        #expect(left.contentView.bounds.minY == 200)
    }

    @Test func mergeArrowsCopyFromTheirAdjacentSourcePane() throws {
        let gutter = ChangeGutterView(frame: NSRect(x: 0, y: 0, width: 64, height: 400))
        let window = NSWindow(contentRect: gutter.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = gutter
        let hunk = DiffHunk(id: "test", kind: .modified, leftLineRange: 1..<5, rightLineRange: 3..<6, virtualRowRange: 1..<6, leftRevision: 0, rightRevision: 0)
        var source: ComparisonSide?
        var navigated = false
        gutter.configure(hunks: [hunk], selectedHunkID: nil, leftOffset: 0, rightOffset: 0, select: { _ in navigated = true }, apply: { _, side in source = side })
        try click(gutter, at: NSPoint(x: 8, y: DiffTextView.verticalInset + 1.5 * DiffTextView.rowHeight))
        #expect(source == .left)
        try click(gutter, at: NSPoint(x: 56, y: DiffTextView.verticalInset + 3.5 * DiffTextView.rowHeight))
        #expect(source == .right)
        #expect(!navigated)
    }

    @Test(arguments: [DiffHunk.Kind.leftOnly, .rightOnly])
    func oneSidedBlocksOnlyOfferMergingFromTheNonemptySide(kind: DiffHunk.Kind) throws {
        let gutter = ChangeGutterView(frame: NSRect(x: 0, y: 0, width: 64, height: 400))
        let window = NSWindow(contentRect: gutter.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = gutter
        let leftOnly = kind == .leftOnly
        let hunk = DiffHunk(id: "test", kind: kind, leftLineRange: leftOnly ? 1..<5 : 1..<1, rightLineRange: leftOnly ? 3..<3 : 3..<6, virtualRowRange: 1..<6, leftRevision: 0, rightRevision: 0)
        var source: ComparisonSide?
        gutter.configure(hunks: [hunk], selectedHunkID: nil, leftOffset: 0, rightOffset: 0, select: { _ in }, apply: { _, side in source = side })
        try click(gutter, at: NSPoint(x: leftOnly ? 56 : 8, y: DiffTextView.verticalInset + (leftOnly ? 3 : 1) * DiffTextView.rowHeight))
        #expect(source == nil)
        try click(gutter, at: NSPoint(x: leftOnly ? 8 : 56, y: DiffTextView.verticalInset + (leftOnly ? 1.5 : 3.5) * DiffTextView.rowHeight))
        #expect(source == (leftOnly ? .left : .right))
    }

    @Test func accessibleMergeArrowIsEnabledAndCopiesFromItsSource() throws {
        let gutter = ChangeGutterView(frame: NSRect(x: 0, y: 0, width: 64, height: 400))
        let hunk = DiffHunk(id: "accessible", kind: .leftOnly, leftLineRange: 0..<2, rightLineRange: 0..<0, virtualRowRange: 0..<2, leftRevision: 0, rightRevision: 0)
        var source: ComparisonSide?
        gutter.configure(hunks: [hunk], selectedHunkID: nil, leftOffset: 0, rightOffset: 0, select: { _ in }, apply: { _, side in source = side })
        let children = try #require(gutter.accessibilityChildren() as? [NSAccessibilityElement])
        #expect(children.count == 1)
        let arrow = try #require(children.first)
        #expect(arrow.isAccessibilityEnabled())
        #expect(arrow.accessibilityPerformPress())
        #expect(source == .left)
    }

    @Test func connectorsFollowLiveFractionalOffsetsDespiteStaleConfiguration() {
        let left = scrollView(width: 1400, y: 0)
        let right = scrollView(width: 1400, y: 0)
        let gutter = ChangeGutterView(frame: NSRect(x: 0, y: 0, width: ChangeGutterView.preferredWidth, height: 400))
        let hunk = DiffHunk(id: "scroll", kind: .modified, leftLineRange: 20..<23, rightLineRange: 18..<22, virtualRowRange: 18..<23, leftRevision: 0, rightRevision: 0)
        gutter.configure(hunks: [hunk], selectedHunkID: nil, leftOffset: 0, rightOffset: 0, select: { _ in }, apply: { _, _ in })
        gutter.scrollOffsets = { (left.contentView.bounds.minY, right.contentView.bounds.minY) }
        for offset in [0.25, 19.75, 220.5, 130.25, 700.5, 0] {
            left.contentView.setBoundsOrigin(NSPoint(x: 100, y: offset))
            right.contentView.setBoundsOrigin(NSPoint(x: 100, y: offset + 7.25))
            #expect(gutter.connectionBand(for: hunk, side: .left).minY == DiffTextView.verticalInset + 20 * DiffTextView.rowHeight - left.contentView.bounds.minY)
            #expect(gutter.connectionBand(for: hunk, side: .right).minY == DiffTextView.verticalInset + 18 * DiffTextView.rowHeight - right.contentView.bounds.minY)
        }
    }

    private func scrollView(width: CGFloat, y: CGFloat) -> NSScrollView {
        let view = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.documentView = DiffScrollTestDocument(frame: NSRect(x: 0, y: 0, width: width, height: 1000))
        view.contentView.scroll(to: NSPoint(x: 0, y: y))
        return view
    }

    private func scroll(_ view: NSScrollView, to point: NSPoint) {
        view.contentView.scroll(to: point)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: view.contentView)
    }

    private func click(_ view: NSView, at point: NSPoint) throws {
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        view.mouseDown(with: event)
    }
}

private final class DiffScrollTestDocument: NSView {
    override var isFlipped: Bool { true }
}
