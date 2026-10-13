import Foundation

nonisolated protocol ComparisonWorking: Sendable {
    func load(from url: URL) async throws -> ParsedTextFile
    func compare(left: EditorBuffer, right: EditorBuffer, options: ComparisonOptions) async throws -> DiffResult
    func compareIncrementally(previous: DiffResult, left: EditorBuffer, right: EditorBuffer, edit: TextEdit, side: ComparisonSide, options: ComparisonOptions) async throws -> DiffResult
    func save(buffer: EditorBuffer, to url: URL, force: Bool) async throws -> Date?
}

extension ComparisonWorking {
    nonisolated func compareIncrementally(previous: DiffResult, left: EditorBuffer, right: EditorBuffer, edit: TextEdit, side: ComparisonSide, options: ComparisonOptions) async throws -> DiffResult {
        try await compare(left: left, right: right, options: options)
    }
}
