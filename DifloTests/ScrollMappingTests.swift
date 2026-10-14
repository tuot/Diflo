import AppKit
import CoreGraphics
import Testing
@testable import Diflo

@MainActor
struct DualScrollSynchronizationTests {
    private func panes(hunks: [DiffHunk]) -> (DualScrollCoordinator, NSScrollView, NSScrollView) {
        let coordinator = DualScrollCoordinator()
        func pane(height: CGFloat) -> NSScrollView {
            let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
            scroll.documentView = DiffTextView.createStandard(side: .left)
            scroll.documentView?.frame = CGRect(x: 0, y: 0, width: 400, height: height)
            scroll.verticalScrollElasticity = .none
            return scroll
        }
        let left = pane(height: 300 * DiffTextView.rowHeight + 16)
        let right = pane(height: 360 * DiffTextView.rowHeight + 16)
        coordinator.register(scrollView: left, for: .left)
        coordinator.register(scrollView: right, for: .right)
        coordinator.updateHunks(hunks)
        return (coordinator, left, right)
    }

    private func insertion(at line: Int) -> DiffHunk {
        DiffHunk(id: "insert", kind: .rightOnly, leftLineRange: line..<line,
                 rightLineRange: line..<(line + 60), virtualRowRange: line..<(line + 60),
                 leftRevision: 0, rightRevision: 0)
    }

    @Test func crossingInsertionDoesNotJumpByTheInsertedBlock() {
        let (coordinator, left, right) = panes(hunks: [insertion(at: 100)])
        let boundary = DiffTextView.verticalInset + 100 * DiffTextView.rowHeight
        left.contentView.scroll(to: CGPoint(x: 0, y: boundary - 1))
        let before = right.contentView.bounds.minY
        left.contentView.scroll(to: CGPoint(x: 0, y: boundary + 1))
        #expect(right.contentView.bounds.minY - before < 40)
        #expect(right.contentView.bounds.minY >= before)
        #expect(left.contentView.bounds.minY == boundary + 1)
        withExtendedLifetime(coordinator) {}
    }

    @Test func mappingIsContinuousAtDocumentEdgesAndReversible() {
        for line in [0, 100, 300] {
            let (coordinator, left, right) = panes(hunks: [insertion(at: line)])
            let maxY = left.documentView!.bounds.height - left.contentSize.height
            var previous: CGFloat = 0
            for y in stride(from: CGFloat(0), through: maxY, by: 1) {
                left.contentView.scroll(to: CGPoint(x: 0, y: y))
                let mapped = right.contentView.bounds.minY
                #expect(mapped >= previous - 0.01)
                #expect(mapped - previous < 40)
                previous = mapped
            }
            left.contentView.scroll(to: CGPoint(x: 0, y: maxY))
            #expect(abs(right.contentView.bounds.maxY - right.documentView!.bounds.height) < 0.01)
            left.contentView.scroll(to: CGPoint(x: 0, y: maxY / 2))
            let mapped = right.contentView.bounds.minY
            right.contentView.scroll(to: CGPoint(x: 0, y: mapped + 1))
            #expect(abs(left.contentView.bounds.minY - maxY / 2) < 2)
            withExtendedLifetime(coordinator) {}
        }
    }

    @Test func nearbyInsertionsAndDeletionsStayMonotonicInBothDirections() {
        let hunks = [
            DiffHunk(id: "insert", kind: .rightOnly, leftLineRange: 100..<100,
                     rightLineRange: 100..<180, virtualRowRange: 100..<180, leftRevision: 0, rightRevision: 0),
            DiffHunk(id: "delete", kind: .leftOnly, leftLineRange: 105..<125,
                     rightLineRange: 185..<185, virtualRowRange: 185..<205, leftRevision: 0, rightRevision: 0)
        ]
        let (coordinator, left, right) = panes(hunks: hunks)
        for (source, target) in [(left, right), (right, left)] {
            source.contentView.scroll(to: .zero)
            let maxY = source.documentView!.bounds.height - source.contentSize.height
            var previous: CGFloat = 0
            for y in stride(from: CGFloat(0), through: maxY, by: 1) {
                source.contentView.scroll(to: CGPoint(x: 0, y: y))
                let mapped = target.contentView.bounds.minY
                #expect(mapped >= previous - 0.01)
                #expect(mapped - previous < 40)
                previous = mapped
            }
        }
        left.contentView.scroll(to: CGPoint(x: 0, y: 200 * DiffTextView.rowHeight + 8))
        #expect(abs(right.contentView.bounds.minY - (260 * DiffTextView.rowHeight + 8)) < 0.01)
        withExtendedLifetime(coordinator) {}
    }
}
