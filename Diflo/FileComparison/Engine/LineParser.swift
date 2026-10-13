import Foundation

nonisolated enum LineParser {
    static func parse(_ text: String, url: URL, encodingName: String) -> ParsedTextFile {
        parse(
            text,
            url: url,
            encoding: TextEncoding(rawValue: String.Encoding.utf8.rawValue, displayName: encodingName)
        )
    }

    static func parse(
        _ text: String,
        url: URL,
        encoding: TextEncoding,
        lastKnownModificationDate: Date? = nil
    ) -> ParsedTextFile {
        let normalized = normalize(text)
        let parts = splitNormalized(normalized)

        return ParsedTextFile(
            url: url,
            displayName: url.lastPathComponent,
            lines: parts.lines,
            hasTrailingNewline: parts.hasTrailingNewline,
            encodingName: encoding.displayName,
            normalizedText: normalized,
            encoding: encoding,
            lineEnding: LineEnding.detect(in: text),
            lastKnownModificationDate: lastKnownModificationDate
        )
    }

    static func normalize(_ text: String) -> String {
        text.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
    }

    static func splitNormalized(_ text: String) -> (lines: [String], hasTrailingNewline: Bool) {
        guard !text.isEmpty else { return ([], false) }
        let hasTrailingNewline = text.hasSuffix("\n")
        let content = hasTrailingNewline ? text.dropLast() : Substring(text)
        let lines = content.isEmpty
            ? [""]
            : content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return (lines, hasTrailingNewline)
    }
}
