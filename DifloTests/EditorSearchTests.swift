import AppKit
import Testing
@testable import Diflo

@MainActor
struct EditorSearchTests {
    @Test func nativeFindBarNavigatesMatchesInEachEditorWithoutChangingText() async throws {
        let pasteboard = NSPasteboard(name: .find)
        let savedItems = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        defer {
            pasteboard.clearContents()
            pasteboard.writeObjects(savedItems)
        }

        for side in [ComparisonSide.left, .right] {
            let scroll = DiffOverlayScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
            let editor = DiffTextView.createStandard(side: side)
            scroll.documentView = editor
            let text = "🐾 目标\n其他\n目标"
            editor.configure(text: text, lineCount: 3, hunks: [], side: side, selectedHunkID: nil)
            let window = NSWindow(contentRect: scroll.bounds, styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = scroll
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(editor)
            defer { window.orderOut(nil) }
            await Task.yield()
            let first = (text as NSString).range(of: "目标")
            let last = (text as NSString).range(of: "目标", options: .backwards)
            editor.setSelectedRange(first)
            func perform(_ action: NSTextFinder.Action) {
                let item = NSMenuItem()
                item.action = #selector(NSTextView.performTextFinderAction(_:))
                item.tag = action.rawValue
                editor.performTextFinderAction(item)
            }
            perform(.showFindInterface)
            #expect(scroll.isFindBarVisible)
            #expect(scroll.findBarView != nil)
            func searchField(in view: NSView) -> NSSearchField? {
                if let field = view as? NSSearchField { return field }
                for child in view.subviews {
                    if let field = searchField(in: child) { return field }
                }
                return nil
            }
            let bar = try #require(scroll.findBarView)
            let field = try #require(searchField(in: bar))
            field.stringValue = "目标"
            field.sendAction(field.action, to: field.target)
            // The native incremental finder updates its query on the next run-loop turn.
            try await Task.sleep(for: .milliseconds(100))
            window.makeFirstResponder(editor)
            editor.setSelectedRange(NSRange(location: 0, length: 0))
            perform(.nextMatch)
            #expect(editor.selectedRange() == first)
            perform(.nextMatch)
            #expect(editor.selectedRange() == last)
            perform(.previousMatch)
            #expect(editor.selectedRange() == first)
            #expect(editor.string == text)
            #expect(editor.textLayoutManager != nil)
            perform(.hideFindInterface)
            #expect(!scroll.isFindBarVisible)
        }
    }

    @Test func findBarReservesSpaceAndOverlayScrollersStayInsideTheEditor() throws {
        let scroll = DiffOverlayScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        scroll.borderType = .noBorder
        scroll.documentView = DiffTextView.createStandard(side: .left)
        scroll.findBarPosition = .aboveContent
        scroll.tile()
        let originalFrame = scroll.contentView.frame
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 32))
        scroll.findBarView = bar
        scroll.isFindBarVisible = true
        scroll.tile()

        // AppKit may reserve the bar's space with either a smaller frame or content insets.
        let reservedHeight = originalFrame.height - scroll.contentView.frame.height + scroll.contentView.contentInsets.top
        #expect(reservedHeight >= bar.frame.height)
        #expect(scroll.contentView.frame.contains(scroll.verticalOverlayScroller.frame))
        #expect(scroll.contentView.frame.contains(scroll.horizontalOverlayScroller.frame))
        #expect(!scroll.verticalOverlayScroller.frame.intersects(bar.frame))
        #expect(!scroll.horizontalOverlayScroller.frame.intersects(bar.frame))

        scroll.frame.size.height = 450
        scroll.tile()
        #expect(!scroll.verticalOverlayScroller.frame.intersects(bar.frame))
        #expect(scroll.contentView.frame.contains(scroll.verticalOverlayScroller.frame))

        scroll.isFindBarVisible = false
        scroll.tile()
        #expect(scroll.contentView.frame == scroll.bounds)
    }

    @Test func draggingTheThumbReachesTheTopAndBottomWithFindBarInsets() {
        let scroll = DiffOverlayScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        let editor = DiffTextView.createStandard(side: .left)
        scroll.documentView = editor
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 32, left: 0, bottom: 6, right: 0)
        scroll.tile()
        scroll.verticalOverlayScroller.doubleValue = 0
        scroll.scrollOverlayScroller(scroll.verticalOverlayScroller, part: .knob)
        #expect(scroll.contentView.bounds.minY == -32)
        scroll.verticalOverlayScroller.doubleValue = 1
        scroll.scrollOverlayScroller(scroll.verticalOverlayScroller, part: .knob)
        #expect(scroll.contentView.bounds.maxY == editor.bounds.maxY + 6)
    }
}
