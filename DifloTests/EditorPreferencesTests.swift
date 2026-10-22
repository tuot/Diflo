import AppKit
import Testing
@testable import Diflo

@MainActor struct EditorPreferencesTests {
    @Test func fontSizeClampsAndPreferencesPersist() {
        let name = "DifloTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = EditorPreferences(defaults: defaults)
        preferences.fontSize = 100
        #expect(preferences.fontSize == 28)
        preferences.fontSize = 1
        #expect(preferences.fontSize == 10)
        preferences.tabWidth = 8
        preferences.wrapLines = true
        #expect(EditorPreferences(defaults: defaults).wrapLines)
        #expect(EditorPreferences(defaults: defaults).tabWidth == 8)
    }
    @Test func wrappedLongLineMovesNextLogicalLineDown() throws {
        let editor = DiffTextView.createStandard(side: .left)
        editor.configure(text: String(repeating: "你好🌟", count: 50) + "\nnext", lineCount: 2, hunks: [], side: .left, selectedHunkID: nil)
        editor.applyPreferences(fontSize: 18, tabWidth: 4, wrapLines: true, showWhitespace: true)
        editor.resizeDocument(minimumSize: NSSize(width: 200, height: 200))
        let first = try #require(editor.lineRect(at: 0))
        let second = try #require(editor.lineRect(at: 1))
        #expect(first.height > editor.effectiveRowHeight)
        #expect(second.minY >= first.maxY - 1)
    }
}
