import Foundation
import AppKit
import Testing
@testable import Diflo

struct ReleaseSafetyTests {
    @Test func utf8BOMRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("hello\r\n".utf8)
        try original.write(to: url)
        let buffer = EditorBuffer(file: try TextFileLoader.load(from: url))
        _ = try TextFileWriter.write(buffer: buffer, to: url, overwriteExternalChanges: false)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func mixedNewlinesRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("a\r\nb\nc\rd".utf8)
        try original.write(to: url)
        let buffer = EditorBuffer(file: try TextFileLoader.load(from: url)).updatingText("a\nb\nc\nchanged")
        _ = try TextFileWriter.write(buffer: buffer, to: url, overwriteExternalChanges: false)
        #expect(try Data(contentsOf: url) == Data("a\r\nb\nc\rchanged".utf8))
    }

    @Test @MainActor func ordinaryPastePreservesJSONWhitespace() {
        let view = DiffTextView.createStandard(side: .left)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let original = "{\"a\":  1}"
        pasteboard.setString(original, forType: .string)
        #expect(view.readSelection(from: pasteboard, type: .string))
        #expect(view.string == original)
    }

    @Test @MainActor func savingThenReplacingDoesNotRestoreOldDocument() async throws {
        let worker = PausedSaveWorker()
        let session = ComparisonSession(worker: worker)
        session.startBlank()
        let oldID = session.leftBuffer.documentID
        let task = Task { await session.save(.left, to: URL(fileURLWithPath: "/tmp/old.txt")) }
        await worker.waitUntilSaving()
        session.startBlank()
        let newID = session.leftBuffer.documentID
        await worker.finishSaving()
        _ = await task.value
        #expect(newID != oldID)
        #expect(session.leftBuffer.documentID == newID)
        #expect(session.leftBuffer.url == nil)
    }

    @Test @MainActor func editingDuringSaveKeepsNewTextDirtyAndSaveAsLocation() async {
        let worker = PausedSaveWorker()
        let session = ComparisonSession(worker: worker)
        session.startBlank()
        session.edit(.left, text: "first")
        let url = URL(fileURLWithPath: "/tmp/new-location.txt")
        let task = Task { await session.save(.left, to: url) }
        await worker.waitUntilSaving()
        session.edit(.left, text: "second")
        await worker.finishSaving()
        #expect(await task.value)
        #expect(session.leftBuffer.text == "second")
        #expect(session.leftBuffer.isDirty)
        #expect(session.leftBuffer.url == url)
    }

    @Test func twoWindowsCannotSilentlyOverwriteTheSameFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("original".utf8).write(to: url)
        let original = EditorBuffer(file: try TextFileLoader.load(from: url))
        let first = original.updatingText("first"), second = original.updatingText("second")
        let one = Task.detached { () -> Bool in
            do { _ = try TextFileWriter.write(buffer: first, to: url, overwriteExternalChanges: false); return true } catch { return false }
        }
        let two = Task.detached { () -> Bool in
            do { _ = try TextFileWriter.write(buffer: second, to: url, overwriteExternalChanges: false); return true } catch { return false }
        }
        let results = await [one.value, two.value]
        #expect(results.filter { $0 }.count == 1)
    }

    @Test @MainActor func openingFileCannotOverwriteEditsMadeWhileLoading() async {
        let worker = PausedLoadWorker()
        let session = ComparisonSession(worker: worker)
        session.startBlank()
        let task = Task { await session.open(URL(fileURLWithPath: "/tmp/slow.txt"), for: .left) }
        await worker.waitUntilLoading()
        session.edit(.left, text: "new typing")
        await worker.finishLoading()
        await task.value
        #expect(session.leftBuffer.text == "new typing")
        #expect(session.leftBuffer.isDirty)
    }
}

private actor PausedSaveWorker: ComparisonWorking {
    var continuation: CheckedContinuation<Date?, Never>?
    func waitUntilSaving() async { while continuation == nil { await Task.yield() } }
    func finishSaving() { continuation?.resume(returning: Date()); continuation = nil }
    func load(from url: URL) throws -> ParsedTextFile { try TextFileLoader.load(from: url) }
    func compare(left: EditorBuffer, right: EditorBuffer, options: ComparisonOptions) -> DiffResult {
        LineDiffEngine.compare(left: left.asParsedFile(), right: right.asParsedFile(), options: options)
    }
    func save(buffer: EditorBuffer, to url: URL, force: Bool) async -> Date? {
        await withCheckedContinuation { continuation = $0 }
    }
}

private actor PausedLoadWorker: ComparisonWorking {
    var continuation: CheckedContinuation<ParsedTextFile, Never>?
    func waitUntilLoading() async { while continuation == nil { await Task.yield() } }
    func finishLoading() {
        continuation?.resume(returning: LineParser.parse("disk", url: URL(fileURLWithPath: "/tmp/slow.txt"), encodingName: "UTF-8"))
        continuation = nil
    }
    func load(from url: URL) async -> ParsedTextFile { await withCheckedContinuation { continuation = $0 } }
    func compare(left: EditorBuffer, right: EditorBuffer, options: ComparisonOptions) -> DiffResult {
        LineDiffEngine.compare(left: left.asParsedFile(), right: right.asParsedFile(), options: options)
    }
    func save(buffer: EditorBuffer, to url: URL, force: Bool) throws -> Date? {
        try TextFileWriter.write(buffer: buffer, to: url, overwriteExternalChanges: force)
    }
}
