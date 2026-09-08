import Foundation

actor ComparisonWorker: ComparisonWorking {
    func load(from url: URL) async throws -> ParsedTextFile {
        try TextFileLoader.load(from: url)
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
