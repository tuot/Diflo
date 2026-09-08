import Foundation
import AppKit
import Testing
@testable import DiffZen

struct LineParserTests {
    @Test func emptyFileHasNoLines() {
        let file = LineParser.parse("", url: fixtureURL("empty.txt"), encodingName: "UTF-8")

        #expect(file.lines.isEmpty)
        #expect(file.hasTrailingNewline == false)
    }

    @Test func normalizesLineEndingsAndPreservesTrailingNewline() {
        let file = LineParser.parse("first\r\nsecond\rthird\n", url: fixtureURL("mixed.txt"), encodingName: "UTF-8")

        #expect(file.lines == ["first", "second", "third"])
        #expect(file.hasTrailingNewline)
    }

    @Test func singleNewlineIsOneEmptyLine() {
        let file = LineParser.parse("\n", url: fixtureURL("newline.txt"), encodingName: "UTF-8")

        #expect(file.lines == [""])
        #expect(file.hasTrailingNewline)
    }
}

struct IntraLineDiffEngineTests {
    @Test func identicalLinesProduceNoRanges() {
        let (left, right) = IntraLineDiffEngine.diff(left: "hello world", right: "hello world")
        #expect(left.isEmpty)
        #expect(right.isEmpty)
    }

    @Test func identifiesChangedWordInMiddle() {
        let (left, right) = IntraLineDiffEngine.diff(left: "let count = foo", right: "let count = bar")
        #expect(left == [NSRange(location: 12, length: 3)])
        #expect(right == [NSRange(location: 12, length: 3)])
    }

    @Test func identifiesSingleCharacterChange() {
        let (left, right) = IntraLineDiffEngine.diff(left: "let count = 10", right: "let count = 20")
        #expect(left == [NSRange(location: 12, length: 1)])
        #expect(right == [NSRange(location: 12, length: 1)])
    }

    @Test func identifiesAdditionAtEnd() {
        let (left, right) = IntraLineDiffEngine.diff(left: "hello", right: "hello world")
        #expect(left.isEmpty)
        #expect(right == [NSRange(location: 5, length: 6)])
    }

    @Test func identifiesMultipleDiscreteChangesInSingleLine() {
        let (left, right) = IntraLineDiffEngine.diff(left: "func foo(a: Int, b: String)", right: "func bar(a: Double, b: String)")
        // "foo" -> "bar" (location 5, length 3)
        // "Int" -> "Double" (location 13, length 3 vs location 13, length 6)
        #expect(left.count == 2)
        #expect(right.count == 2)
        #expect(left[0] == NSRange(location: 5, length: 3))
        #expect(right[0] == NSRange(location: 5, length: 3))
    }
}

struct ComparisonOptionsTests {
    @Test func ignoreCaseTreatsDifferentCasedLinesAsUnchanged() {
        let left = LineParser.parse("Hello WORLD\n", url: fixtureURL("1.txt"), encodingName: "UTF-8")
        let right = LineParser.parse("hello world\n", url: fixtureURL("2.txt"), encodingName: "UTF-8")

        var options = ComparisonOptions.default
        let diffDefault = LineDiffEngine.compare(left: left, right: right, options: options)
        #expect(diffDefault.differenceCount == 1)

        options.ignoreCase = true
        let diffIgnored = LineDiffEngine.compare(left: left, right: right, options: options)
        #expect(diffIgnored.differenceCount == 0)
    }

    @Test func ignoreWhitespaceTreatsSpacesAsUnchanged() {
        let left = LineParser.parse("let a = 1;\n", url: fixtureURL("1.txt"), encodingName: "UTF-8")
        let right = LineParser.parse("let   a   =   1;\n", url: fixtureURL("2.txt"), encodingName: "UTF-8")

        var options = ComparisonOptions.default
        let diffDefault = LineDiffEngine.compare(left: left, right: right, options: options)
        #expect(diffDefault.differenceCount == 1)

        options.ignoreWhitespace = true
        let diffIgnored = LineDiffEngine.compare(left: left, right: right, options: options)
        #expect(diffIgnored.differenceCount == 0)
    }

    @Test func ignoreTrailingWhitespaceTreatsEndSpacesAsUnchanged() {
        let left = LineParser.parse("let a = 1\n", url: fixtureURL("1.txt"), encodingName: "UTF-8")
        let right = LineParser.parse("let a = 1   \n", url: fixtureURL("2.txt"), encodingName: "UTF-8")

        var options = ComparisonOptions.default
        options.ignoreTrailingWhitespace = true
        let diff = LineDiffEngine.compare(left: left, right: right, options: options)
        #expect(diff.differenceCount == 0)
    }
}

struct EditorBufferTests {
    @Test func blankBufferUsesUTF8AndLF() {
        let buffer = EditorBuffer.blank(named: "未命名")

        #expect(buffer.text.isEmpty)
        #expect(buffer.encoding == .utf8)
        #expect(buffer.lineEnding == .lf)
        #expect(buffer.revision == 0)
        #expect(buffer.isDirty == false)
    }

    @Test func loadedCRLFFileRetainsFormatAndNormalizesText() {
        let file = LineParser.parse(
            "one\r\ntwo\r\n",
            url: fixtureURL("windows.txt"),
            encoding: .utf8
        )
        let buffer = EditorBuffer(file: file)

        #expect(buffer.text == "one\ntwo\n")
        #expect(buffer.lineEnding == .crlf)
        #expect(buffer.hasTrailingNewline)
        #expect(buffer.isDirty == false)
    }

    @Test func editingMarksBufferDirtyAndIncrementsRevision() {
        let original = EditorBuffer.blank(named: "左侧")
        let edited = original.updatingText("hello\r\nworld")

        #expect(edited.text == "hello\nworld")
        #expect(edited.revision == 1)
        #expect(edited.isDirty)
    }
}

struct DiffTextViewRenderingTests {
    @Test @MainActor func laysOutTypedGlyphsInsideTheVisibleEditorFrame() throws {
        let editor = DiffTextView.createStandard(side: .left)
        editor.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let left = EditorBuffer.blank(named: "左侧").updatingText("left")
        let right = EditorBuffer.blank(named: "右侧").updatingText("right")
        let result = LineDiffEngine.compare(left: left.asParsedFile(), right: right.asParsedFile())

        editor.configure(
            text: left.text,
            lineCount: left.lineCount,
            hunks: result.hunks,
            side: .left,
            selectedHunkID: nil,
            oppositeLines: right.lines
        )
        editor.resizeDocument(minimumSize: NSSize(width: 600, height: 400))

        let layoutManager = try #require(editor.layoutManager)
        let textContainer = try #require(editor.textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        #expect(editor.frame.width > 0)
        #expect(editor.frame.height > 0)
        #expect(usedRect.width > 0)
        #expect(usedRect.height > 0)
        #expect(darkPixelCount(in: editor) > 20)
    }

    private func darkPixelCount(in view: NSView) -> Int {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let luminance = 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                if color.alphaComponent > 0.5, luminance < 0.75 {
                    count += 1
                }
            }
        }
        return count
    }
}

struct LineDiffEngineTests {
    @Test func identicalFilesKeepOriginalLineNumbers() {
        let result = LineDiffEngine.compare(
            left: makeFile("left.txt", lines: ["one", "two"]),
            right: makeFile("right.txt", lines: ["one", "two"])
        )

        #expect(result.rows.map(\.kind) == [.unchanged, .unchanged])
        #expect(result.rows.map(\.leftLineNumber) == [1, 2])
        #expect(result.rows.map(\.rightLineNumber) == [1, 2])
        #expect(result.differenceCount == 0)
    }

    @Test func alignsUnevenReplacementBlock() {
        let result = LineDiffEngine.compare(
            left: makeFile("left.txt", lines: ["A", "B", "C"]),
            right: makeFile("right.txt", lines: ["A", "X", "Y", "C"])
        )

        #expect(result.rows.map(\.kind) == [.unchanged, .modified, .inserted, .unchanged])
        #expect(result.rows[1].leftText == "B")
        #expect(result.rows[1].rightText == "X")
        #expect(result.rows[2].leftText == nil)
        #expect(result.rows[2].rightText == "Y")
        #expect(result.rows[2].leftLineNumber == nil)
        #expect(result.rows[2].rightLineNumber == 3)
    }

    @Test func alignsInsertionAndDeletionAtFileEdges() {
        let result = LineDiffEngine.compare(
            left: makeFile("left.txt", lines: ["removed", "shared"]),
            right: makeFile("right.txt", lines: ["shared", "inserted"])
        )

        #expect(result.rows.map(\.kind) == [.deleted, .unchanged, .inserted])
        #expect(result.rows.map(\.leftLineNumber) == [1, 2, nil])
        #expect(result.rows.map(\.rightLineNumber) == [nil, 1, 2])
    }

    @Test func repeatedLinesStillAnchorTheChangedOccurrence() {
        let result = LineDiffEngine.compare(
            left: makeFile("left.txt", lines: ["head", "same", "same", "tail"]),
            right: makeFile("right.txt", lines: ["head", "same", "changed", "tail"])
        )

        #expect(result.rows.map(\.kind) == [.unchanged, .unchanged, .modified, .unchanged])
        #expect(result.rows[2].leftText == "same")
        #expect(result.rows[2].rightText == "changed")
    }

    @Test func reportsTrailingNewlineDifferenceWithoutInventingRows() {
        let result = LineDiffEngine.compare(
            left: makeFile("left.txt", lines: ["same"], hasTrailingNewline: true),
            right: makeFile("right.txt", lines: ["same"], hasTrailingNewline: false)
        )

        #expect(result.rows.map(\.kind) == [.unchanged])
        #expect(result.hasTrailingNewlineDifference)
        #expect(result.differenceCount == 1)
    }
}

struct DiffHunkTests {
    @Test func groupsConsecutiveChangesAndKeepsUnevenSourceRanges() throws {
        let left = EditorBuffer(file: makeFile("left.txt", lines: ["A", "B", "C"]))
        let right = EditorBuffer(file: makeFile("right.txt", lines: ["A", "X", "Y", "C"]))
        let result = LineDiffEngine.compare(left: left.asParsedFile(), right: right.asParsedFile())
        let hunk = try #require(result.hunks.first)

        #expect(result.hunks.count == 1)
        #expect(hunk.kind == .modified)
        #expect(hunk.leftLineRange == 1..<2)
        #expect(hunk.rightLineRange == 1..<3)
    }

    @Test func classifiesLeftAndRightOnlyHunks() throws {
        let result = LineDiffEngine.compare(
            left: makeFile("left.txt", lines: ["left", "same"]),
            right: makeFile("right.txt", lines: ["same", "right"])
        )

        #expect(result.hunks.map(\.kind) == [.leftOnly, .rightOnly])
    }

    @Test func appliesAChangeInEitherDirection() throws {
        let left = EditorBuffer(file: makeFile("left.txt", lines: ["A", "B", "C"]))
        let right = EditorBuffer(file: makeFile("right.txt", lines: ["A", "X", "Y", "C"]))
        let result = LineDiffEngine.compare(left: left.asParsedFile(), right: right.asParsedFile())
        let hunk = try #require(result.hunks.first)

        #expect(try ApplyHunkCommand.apply(hunk, from: .left, left: left, right: right) == "A\nB\nC")
        #expect(try ApplyHunkCommand.apply(hunk, from: .right, left: left, right: right) == "A\nX\nY\nC")
    }

    @Test func rejectsAStaleHunk() throws {
        var left = EditorBuffer(file: makeFile("left.txt", lines: ["old"]))
        let right = EditorBuffer(file: makeFile("right.txt", lines: ["new"]))
        let hunk = try #require(LineDiffEngine.compare(left: left.asParsedFile(), right: right.asParsedFile()).hunks.first)
        left = left.updatingText("changed again")

        #expect(throws: HunkApplicationError.staleRevision) {
            try ApplyHunkCommand.apply(hunk, from: .left, left: left, right: right)
        }
    }
}

struct TextFileLoaderTests {
    @Test func loadsUTF8ChineseText() throws {
        let url = try temporaryFile(data: Data("你好\r\nDiffZen\n".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try TextFileLoader.load(from: url)

        #expect(file.lines == ["你好", "DiffZen"])
        #expect(file.hasTrailingNewline)
        #expect(file.encodingName == "UTF-8")
    }

    @Test func loadsUTF16TextWithByteOrderMark() throws {
        let data = try #require("你好\n".data(using: .utf16))
        let url = try temporaryFile(data: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try TextFileLoader.load(from: url)

        #expect(file.lines == ["你好"])
        #expect(file.hasTrailingNewline)
        #expect(file.encodingName.contains("UTF-16"))
    }

    @Test func rejectsBinaryDataContainingNul() throws {
        let url = try temporaryFile(data: Data([0x41, 0x00, 0x42, 0x01]))
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try TextFileLoader.load(from: url)
            Issue.record("包含 NUL 的二进制文件不应加载成功")
        } catch let error as TextFileLoadingError {
            #expect(error == .binaryFile)
        }
    }

    @Test func rejectsFilesLargerThanTenMegabytes() throws {
        let url = try temporaryFile(data: Data(repeating: 0x61, count: 10 * 1_024 * 1_024 + 1))
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try TextFileLoader.load(from: url)
            Issue.record("超过 10 MB 的文件不应加载成功")
        } catch let error as TextFileLoadingError {
            #expect(error == .fileTooLarge)
        }
    }

    @Test func rejectsFilesWithMoreThanTwentyThousandLines() throws {
        let text = Array(repeating: "line", count: 20_001).joined(separator: "\n")
        let url = try temporaryFile(data: Data(text.utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try TextFileLoader.load(from: url)
            Issue.record("超过 20,000 行的文件不应加载成功")
        } catch let error as TextFileLoadingError {
            #expect(error == .tooManyLines)
        }
    }
}

struct TextFileWriterTests {
    @Test func preservesCRLFAndTrailingNewline() throws {
        let url = try temporaryFile(data: Data())
        defer { try? FileManager.default.removeItem(at: url) }
        var buffer = EditorBuffer.blank(named: "test.txt")
        buffer = buffer.updatingText("one\ntwo\n")
        buffer.lineEnding = .crlf

        _ = try TextFileWriter.write(buffer: buffer, to: url, overwriteExternalChanges: true)

        #expect(try Data(contentsOf: url) == Data("one\r\ntwo\r\n".utf8))
    }

    @Test func refusesLossyEncoding() throws {
        let url = try temporaryFile(data: Data())
        defer { try? FileManager.default.removeItem(at: url) }
        var buffer = EditorBuffer.blank(named: "ascii.txt").updatingText("你好")
        buffer.encoding = .ascii

        #expect(throws: TextFileWritingError.cannotEncode) {
            try TextFileWriter.write(buffer: buffer, to: url, overwriteExternalChanges: true)
        }
    }
}

struct ComparisonSessionTests {
    @Test @MainActor func startsAnEditableBlankComparison() async throws {
        let session = ComparisonSession(worker: TestComparisonWorker(files: [:]))

        session.startBlank()
        try await waitUntil { session.result != nil }

        #expect(session.isWorkspacePresented)
        #expect(session.leftBuffer.text.isEmpty)
        #expect(session.rightBuffer.text.isEmpty)
        #expect(session.result?.differenceCount == 0)
    }

    @Test @MainActor func editingRecomputesDiffAndNavigationWraps() async throws {
        let session = ComparisonSession(worker: TestComparisonWorker(files: [:]))
        session.startBlank()
        session.edit(.left, text: "one\ntwo")
        session.edit(.right, text: "one\nchanged\nextra")
        try await waitUntil { session.result?.hunks.count == 1 }

        #expect(session.result?.hunks.count == 1)
        session.selectNextHunk()
        let selected = session.selectedHunkID
        session.selectNextHunk()
        #expect(session.selectedHunkID == selected)
    }

    @Test @MainActor func appliesSelectedHunkAndMarksTargetDirty() async throws {
        let session = ComparisonSession(worker: TestComparisonWorker(files: [:]))
        session.startBlank()
        session.edit(.left, text: "left")
        session.edit(.right, text: "right")
        try await waitUntil { session.result?.hunks.count == 1 }
        let hunk = try #require(session.result?.hunks.first)

        session.applyHunk(hunk, from: .left)

        #expect(session.rightBuffer.text == "left")
        #expect(session.rightBuffer.isDirty)
    }

    @Test @MainActor func dirtyBuffersBlockReturningToLauncher() {
        let session = ComparisonSession(worker: TestComparisonWorker(files: [:]))
        session.startBlank()
        session.edit(.left, text: "unsaved")

        #expect(session.returnToLauncher(discardingChanges: false) == false)
        #expect(session.returnToLauncher(discardingChanges: true))
        #expect(session.isWorkspacePresented == false)
    }
}

struct DiffRowPresentationTests {
    @Test func deletionAppearsOnlyInTheLeftPane() {
        #expect(DiffRowPresentation.marker(for: .deleted, side: .left) == "−")
        #expect(DiffRowPresentation.marker(for: .deleted, side: .right) == "")
        #expect(DiffRowPresentation.highlight(for: .deleted, side: .left) == .deletion)
        #expect(DiffRowPresentation.highlight(for: .deleted, side: .right) == .none)
    }

    @Test func insertionAppearsOnlyInTheRightPane() {
        #expect(DiffRowPresentation.marker(for: .inserted, side: .left) == "")
        #expect(DiffRowPresentation.marker(for: .inserted, side: .right) == "+")
        #expect(DiffRowPresentation.highlight(for: .inserted, side: .left) == .none)
        #expect(DiffRowPresentation.highlight(for: .inserted, side: .right) == .insertion)
    }

    @Test func modificationHighlightsBothPanesWithoutRelyingOnColorAlone() {
        #expect(DiffRowPresentation.marker(for: .modified, side: .left) == "~")
        #expect(DiffRowPresentation.marker(for: .modified, side: .right) == "~")
        #expect(DiffRowPresentation.highlight(for: .modified, side: .left) == .modification)
        #expect(DiffRowPresentation.highlight(for: .modified, side: .right) == .modification)
    }

    @Test func unchangedRowsHaveNoMarkerOrHighlight() {
        #expect(DiffRowPresentation.marker(for: .unchanged, side: .left) == "")
        #expect(DiffRowPresentation.highlight(for: .unchanged, side: .left) == .none)
    }
}

struct EditableDiffContainerTests {
    @Test @MainActor func standardFactoryRetainsTextSystemAndAcceptsTyping() throws {
        let textView = DiffTextView.createStandard(side: .left)
        #expect(textView.textStorage != nil)
        #expect(textView.layoutManager != nil)
        #expect(textView.textContainer != nil)
        #expect(textView.isEditable)
        #expect(textView.isSelectable)
        #expect(textView.acceptsFirstResponder)

        textView.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
        #expect(textView.string == "hello")
    }

    @Test @MainActor func blankLeftPaneAcceptsKeyboardInput() throws {
        let textView = DiffTextView.createStandard(side: .left)
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        textView.configure(
            text: "",
            lineCount: 0,
            hunks: [],
            side: ComparisonSide.left,
            selectedHunkID: nil
        )
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)

        #expect(textView.isEditable)
        #expect(window.firstResponder === textView)

        textView.insertText("hello", replacementRange: NSRange(location: 0, length: 0))

        #expect(textView.string == "hello")
    }

    @Test @MainActor func customDiffEditorViewRendersEmptyStateAndAcceptsInput() throws {
        let editor = CustomDiffEditorView(side: .left)
        editor.configure(text: "", hunks: [], selectedHunkID: nil)

        #expect(editor.lines.isEmpty)
        #expect(editor.caretLine == 0)
        #expect(editor.caretColumn == 0)
        #expect(!editor.placeholderString.isEmpty)

        // 测试文字输入
        editor.insertText("first line", replacementRange: NSRange(location: 0, length: 0))
        #expect(editor.text == "first line")
        #expect(editor.lines == ["first line"])
        #expect(editor.caretColumn == 10)

        // 测试换行
        editor.insertNewline(nil)
        #expect(editor.lines == ["first line", ""])
        #expect(editor.caretLine == 1)
        #expect(editor.caretColumn == 0)

        // 测试第二行录入
        editor.insertText("second", replacementRange: NSRange(location: 0, length: 0))
        #expect(editor.lines == ["first line", "second"])
        #expect(editor.caretColumn == 6)

        // 测试退格删除与跨行合并
        for _ in 0..<6 {
            editor.deleteBackward(nil)
        }
        #expect(editor.lines == ["first line", ""])
        editor.deleteBackward(nil) // 合并回上一行
        #expect(editor.lines == ["first line"])
        #expect(editor.caretLine == 0)
        #expect(editor.caretColumn == 10)
    }

    @Test @MainActor func scrollViewWithDiffTextViewRendersTextCorrectly() throws {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        let textView = DiffTextView.createStandard(side: .left)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)

        textView.configure(
            text: "Hello World\nLine 2",
            lineCount: 2,
            hunks: [],
            side: .left,
            selectedHunkID: nil
        )
        textView.resizeDocument(minimumSize: scrollView.contentSize)

        let lm = try #require(textView.layoutManager)
        let tc = try #require(textView.textContainer)
        let glyphCount = lm.numberOfGlyphs
        let usedRect = lm.usedRect(for: tc)

        let rep = scrollView.bitmapImageRepForCachingDisplay(in: scrollView.bounds)!
        scrollView.cacheDisplay(in: scrollView.bounds, to: rep)
        var darkCount = 0
        for y in 0..<rep.pixelsHigh {
            for x in 10..<rep.pixelsWide {
                let color = rep.colorAt(x: x, y: y)!
                if color.redComponent < 0.5 && color.greenComponent < 0.5 && color.blueComponent < 0.5 {
                    darkCount += 1
                }
            }
        }
        #expect(glyphCount > 0)
        #expect(usedRect.height > 0)
        #expect(darkCount > 10, "Text must be drawn onto the scroll view!")
    }
}

private func fixtureURL(_ name: String) -> URL {
    URL(fileURLWithPath: "/tmp/\(name)")
}

private func makeFile(
    _ name: String,
    lines: [String],
    hasTrailingNewline: Bool = false
) -> ParsedTextFile {
    ParsedTextFile(
        url: fixtureURL(name),
        displayName: name,
        lines: lines,
        hasTrailingNewline: hasTrailingNewline,
        encodingName: "UTF-8"
    )
}

private func temporaryFile(data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "DiffZenTests-\(UUID().uuidString)")
    try data.write(to: url, options: .atomic)
    return url
}

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<100 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("等待条件在 1 秒内未满足")
}

private actor TestComparisonWorker: ComparisonWorking {
    private let files: [URL: ParsedTextFile]

    init(files: [URL: ParsedTextFile]) {
        self.files = files
    }

    func load(from url: URL) async throws -> ParsedTextFile {
        guard let file = files[url] else {
            throw TextFileLoadingError.unreadable
        }
        return file
    }

    func compare(left: EditorBuffer, right: EditorBuffer, options: ComparisonOptions = .default) async -> DiffResult {
        LineDiffEngine.compare(
            left: left.asParsedFile(),
            right: right.asParsedFile(),
            leftRevision: left.revision,
            rightRevision: right.revision,
            options: options
        )
    }

    func save(buffer: EditorBuffer, to url: URL, force: Bool) async throws -> Date? {
        try TextFileWriter.write(buffer: buffer, to: url, overwriteExternalChanges: force)
    }
}

@MainActor
private extension NSView {
    func descendants<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { view in
            (view as? T).map { [$0] } ?? view.descendants(of: type)
        }
    }
}

