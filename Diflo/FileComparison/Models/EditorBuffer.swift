import Foundation

nonisolated struct EditorBuffer: Equatable, Sendable {
    let documentID = UUID()
    private(set) var text: String
    private(set) var lineIndex: TextLineIndex
    var url: URL?
    var displayName: String
    var encoding: TextEncoding
    var lineEnding: LineEnding
    var isDirty: Bool
    var revision: Int
    var lastKnownModificationDate: Date?

    var hasTrailingNewline: Bool { lineIndex.hasTrailingNewline }
    var lines: [String] { lineIndex.lines }
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
        lineIndex = TextLineIndex(normalizedText: text)
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
        self.lineIndex = TextLineIndex(normalizedText: text)
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
        copy.lineIndex = TextLineIndex(normalizedText: normalized)
        copy.revision += 1
        copy.isDirty = true
        return copy
    }

    func asParsedFile() -> ParsedTextFile {
        return ParsedTextFile(
            url: url ?? URL(fileURLWithPath: "/tmp/\(displayName)"),
            displayName: displayName,
            lines: lines,
            hasTrailingNewline: hasTrailingNewline,
            encodingName: encoding.displayName,
            normalizedText: text,
            encoding: encoding,
            lineEnding: lineEnding,
            lastKnownModificationDate: lastKnownModificationDate
        )
    }

    func applying(_ edit: TextEdit) throws -> EditorBuffer {
        guard edit.baseRevision == revision else { throw TextEditError.staleRevision }
        guard edit.range.location >= 0, edit.range.length >= 0,
              edit.range.location <= lineIndex.utf16Count,
              edit.range.length <= lineIndex.utf16Count - edit.range.location else {
            throw TextEditError.invalidRange
        }
        let utf16 = text.utf16
        let lowerUTF16 = utf16.index(utf16.startIndex, offsetBy: edit.range.location)
        let upperUTF16 = utf16.index(lowerUTF16, offsetBy: edit.range.length)
        guard let lowerBound = String.Index(lowerUTF16, within: text),
              let upperBound = String.Index(upperUTF16, within: text) else {
            throw TextEditError.invalidRange
        }
        let range = lowerBound..<upperBound
        var updated = text
        updated.replaceSubrange(range, with: LineParser.normalize(edit.replacement))
        return updatingText(updated)
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
