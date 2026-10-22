import Foundation

nonisolated struct ParsedTextFile: Equatable, Sendable {
    let url: URL
    let displayName: String
    let lines: [String]
    let hasTrailingNewline: Bool
    let encodingName: String
    var normalizedText: String = ""
    var encoding: TextEncoding = .utf8
    var lineEnding: LineEnding = .lf
    var originalSeparators: [LineEnding] = []
    var lastKnownModificationDate: Date? = nil
}
