import AppKit
import Testing
@testable import Diflo

@MainActor
struct PasteFormattingTests {
    private func paste(_ text: String, into editor: DiffTextView) -> Bool {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString(text, forType: .string)
        return editor.readSelection(from: board, type: .string)
    }

    @Test func wholeDocumentPasteFormatsAndUndoRestoresSelection() {
        for side in [ComparisonSide.left, .right] {
            let editor = DiffTextView.createStandard(side: side)
            let original = "原文🌟"
            editor.configure(text: original, lineCount: 1, hunks: [], side: side, selectedHunkID: nil)
            editor.selectAll(nil)
            let selection = editor.selectedRange()
            let history = editor.undoManager!
            history.groupsByEvent = false
            history.beginUndoGrouping()
            #expect(paste(#"{"value":9007199254740993,"nested":[true,null]}"#, into: editor))
            history.endUndoGrouping()
            #expect(editor.string == "{\n  \"value\": 9007199254740993,\n  \"nested\": [\n    true,\n    null\n  ]\n}")
            let formatted = editor.string
            history.undo()
            #expect(editor.string == original)
            #expect(editor.selectedRange() == selection)
            #expect(!history.canUndo)
            history.redo()
            #expect(editor.string == formatted)
        }
    }

    @Test func partialPasteDoesNotFormat() {
        let editor = DiffTextView.createStandard(side: .left)
        editor.string = "prefix: "
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        #expect(paste(#"{"a":1}"#, into: editor))
        #expect(editor.string == #"prefix: {"a":1}"#)
    }

    @Test func nativePasteboardDispatchFormatsPlainText() {
        let editor = DiffTextView.createStandard(side: .left)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString(#"{"text":"你好🌟"}"#, forType: .string)
        #expect(editor.readSelection(from: board))
        #expect(editor.string == "{\n  \"text\": \"你好🌟\"\n}")
    }

    @Test func formattingPreservesTokensAndSensitiveMarkup() {
        let fixtures = [
            (#"{"z":1e30,"a":[],"z":{},"text":"a,\"b"}"#,
             "{\n  \"z\": 1e30,\n  \"a\": [],\n  \"z\": {},\n  \"text\": \"a,\\\"b\"\n}"),
            ("<div><p title=\"a > b\">Hi</p><script>if (a < b) { x++; }</script></div>",
             "<div>\n  <p title=\"a > b\">Hi</p>\n  <script>if (a < b) { x++; }</script>\n</div>"),
            ("{\r\n\"a\":true\r\n}\r\n", "{\n  \"a\": true\n}\n")
        ]
        for (input, expected) in fixtures {
            #expect(PasteFormatter.format(input) == expected)
        }
    }

    @Test func emptyEditorPasteFormatsMarkupAndYAML() {
        let fixtures = [
            ("<div><p>Hello</p><p>World</p></div>", "<div>\n  <p>Hello</p>\n  <p>World</p>\n</div>"),
            ("<root><item id=\"1\"/><item>value</item></root>", "<root>\n  <item id=\"1\"/>\n  <item>value</item>\n</root>"),
            ("app:\n    name: Diflo\n    ports:\n        - 80\n        - 443\n", "app:\n  name: Diflo\n  ports:\n    - 80\n    - 443\n")
        ]
        for (input, expected) in fixtures {
            let editor = DiffTextView.createStandard(side: .left)
            #expect(paste(input, into: editor))
            #expect(editor.string == expected)
        }
    }

    @Test func uncertainOrSensitiveContentIsPreserved() {
        let inputs = [
            "plain text", "Note: ordinary text", "https://example.com", "{broken}",
            "{\"a\":1,}", "[1, ]", "<root><item></root>",
            "<p>Hello <b>world</b>!</p>",
            "<div><span>Hello</span><span>world</span></div>",
            "<button><span>Hello</span><span>world</span></button>",
            "<custom-element><span>Hello</span><span>world</span></custom-element>",
            "<div><p style=\"display:inline\">Hello</p><p style=\"display:inline\">world</p></div>",
            "<html><head><style>p { display:inline }</style></head><body><p>Hello</p><p>world</p></body></html>",
            "<xmp><div><p>A</p><p>B</p></div></xmp>",
            "<plaintext><div><p>A</p><p>B</p></div></plaintext>",
            "<svg><text><tspan>Hello</tspan><tspan>world</tspan></text></svg>",
            "<pre>  keep\n    spaces</pre>",
            "message: |\n    keep\n      indentation\n",
            "text: \"a multiline\n    quoted value\"\n",
            "a:\n    b: 1\n  c: 2", "value: [broken", "a: 1\na: 2",
            String(repeating: " ", count: 1_000_001) + "{\"a\":1}"
        ]
        for input in inputs {
            let editor = DiffTextView.createStandard(side: .left)
            #expect(paste(input, into: editor))
            #expect(editor.string == input)
        }
    }
}
