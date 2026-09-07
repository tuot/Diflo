import Foundation

nonisolated struct EditorBuffer: Equatable, Sendable {
    var text: String
    var url: URL?
    var displayName: String
    var encoding: TextEncoding
    var lineEnding: LineEnding
    var isDirty: Bool
    var revision: Int
    var lastKnownModificationDate: Date?

    var hasTrailingNewline: Bool { text.hasSuffix("\n") }
    var lines: [String] { LineParser.splitNormalized(text).lines }
    var lineCount: Int { lines.count }

    static func blank(named name: String) -> EditorBuffer {
        EditorBuffer(
            text: "",
            url: nil,
            displayName: name,
            encoding: .utf8,
            lineEnding: .lf,
            isDirty: false,
            revision: 0,
            lastKnownModificationDate: nil
        )
    }

    init(file: ParsedTextFile) {
        if file.normalizedText.isEmpty, !file.lines.isEmpty {
            text = file.lines.joined(separator: "\n") + (file.hasTrailingNewline ? "\n" : "")
        } else {
            text = file.normalizedText
        }
        url = file.url
        displayName = file.displayName
        encoding = file.encoding
        lineEnding = file.lineEnding
        isDirty = false
        revision = 0
        lastKnownModificationDate = file.lastKnownModificationDate
    }

    private init(
        text: String,
        url: URL?,
        displayName: String,
        encoding: TextEncoding,
        lineEnding: LineEnding,
        isDirty: Bool,
        revision: Int,
        lastKnownModificationDate: Date?
    ) {
        self.text = text
        self.url = url
        self.displayName = displayName
        self.encoding = encoding
        self.lineEnding = lineEnding
        self.isDirty = isDirty
        self.revision = revision
        self.lastKnownModificationDate = lastKnownModificationDate
    }

    func updatingText(_ newText: String) -> EditorBuffer {
        let normalized = LineParser.normalize(newText)
        guard normalized != text else { return self }
        var copy = self
        copy.text = normalized
        copy.revision += 1
        copy.isDirty = true
        return copy
    }

    func asParsedFile() -> ParsedTextFile {
        let parts = LineParser.splitNormalized(text)
        return ParsedTextFile(
            url: url ?? URL(fileURLWithPath: "/tmp/\(displayName)"),
            displayName: displayName,
            lines: parts.lines,
            hasTrailingNewline: parts.hasTrailingNewline,
            encodingName: encoding.displayName,
            normalizedText: text,
            encoding: encoding,
            lineEnding: lineEnding,
            lastKnownModificationDate: lastKnownModificationDate
        )
    }

    func markingSaved(to savedURL: URL, modificationDate: Date?) -> EditorBuffer {
        var copy = self
        copy.url = savedURL
        copy.displayName = savedURL.lastPathComponent
        copy.lastKnownModificationDate = modificationDate
        copy.isDirty = false
        return copy
    }
}
