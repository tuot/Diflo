import Foundation

nonisolated protocol ComparisonWorking: Sendable {
    func load(from url: URL) async throws -> ParsedTextFile
    func compare(left: EditorBuffer, right: EditorBuffer) async -> DiffResult
    func save(buffer: EditorBuffer, to url: URL, force: Bool) async throws -> Date?
}
