import AppKit
import Testing
@testable import Diflo

@MainActor
struct DiffOverviewInteractionTests {
    @Test func clickingTheTrackAndDraggingTheThumbScrollWithoutSelectingAHunk() throws {
        let view = DiffOverviewView(frame: NSRect(x: 0, y: 0, width: 12, height: 200))
        let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        var selected = false
        var progress: Double?
        view.configure(hunks: [], totalRows: 100, selectedHunkID: nil, select: { _ in selected = true })
        view.updateViewport(progress: 0, visibleFraction: 0.25)
        view.onScrollToProgress = { progress = $0 }
        try send(.leftMouseDown, to: view, y: 175)
        #expect(progress == 1)
        #expect(!selected)
        view.updateViewport(progress: 0.5, visibleFraction: 0.25)
        progress = nil
        try send(.leftMouseDown, to: view, y: 85)
        #expect(progress == nil)
        try send(.leftMouseDragged, to: view, y: 10)
        #expect(progress == 0)
    }

    @Test func viewportDoesNotTravelWhenTheWholeDocumentFits() {
        let view = DiffOverviewView(frame: NSRect(x: 0, y: 0, width: 12, height: 100))
        view.updateViewport(progress: 1, visibleFraction: 1)
        #expect(view.viewportRect.minY == 0)
        #expect(view.viewportRect.height == 100)
    }

    private func send(_ type: NSEvent.EventType, to view: NSView, y: CGFloat) throws {
        let event = try #require(NSEvent.mouseEvent(with: type, location: view.convert(NSPoint(x: 6, y: y), to: nil), modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        if type == .leftMouseDown { view.mouseDown(with: event) }
        else { view.mouseDragged(with: event) }
    }
}
