import Foundation

actor ComparisonWorker: ComparisonWorking {
    func load(from url: URL) async throws -> ParsedTextFile {
        try Task.checkCancellation()
        return try ComparisonDiagnostics.measure("Load") { try TextFileLoader.load(from: url) }
    }

    func compare(left: EditorBuffer, right: EditorBuffer, options: ComparisonOptions = .default) async throws -> DiffResult {
        try Task.checkCancellation()
        return try ComparisonDiagnostics.measure("LineDiff") { try LineDiffEngine.compareCancellable(
            left: left.asParsedFile(),
            right: right.asParsedFile(),
            leftRevision: left.revision,
            rightRevision: right.revision,
            options: options
        ) }
    }

    func compareIncrementally(previous: DiffResult, left: EditorBuffer, right: EditorBuffer, edit: TextEdit, side: ComparisonSide, options: ComparisonOptions) async throws -> DiffResult {
        try Task.checkCancellation()
        return try ComparisonDiagnostics.measure("LineDiff") {
            try IncrementalDiffEngine.compare(previous: previous, left: left, right: right, edit: edit, side: side, options: options)
        }
    }

    func save(buffer: EditorBuffer, to url: URL, force: Bool) async throws -> Date? {
        try TextFileWriter.write(buffer: buffer, to: url, overwriteExternalChanges: force)
    }
}
