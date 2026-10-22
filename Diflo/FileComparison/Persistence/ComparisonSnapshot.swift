import Foundation

nonisolated struct ComparisonSnapshot: Codable, Identifiable, Sendable {
    var version = 1
    let id: UUID
    let updatedAt: Date
    let left: BufferSnapshot
    let right: BufferSnapshot
    let options: ComparisonOptions
    let activeSide: ComparisonSide
    var title: String { "\(left.displayName) ↔ \(right.displayName)" }
}

nonisolated struct BufferSnapshot: Codable, Sendable {
    let text: String
    let displayName: String
    let url: URL?
    let bookmark: Data?
    let encoding: TextEncoding
    let lineEnding: LineEnding
    let separators: [LineEnding]
    let isDirty: Bool
    let isReadOnly: Bool
    let modificationDate: Date?
    let cursor: CursorPosition

    init(_ buffer: EditorBuffer, cursor: CursorPosition) {
        text = buffer.text
        displayName = buffer.displayName
        url = buffer.url
        if let url {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } else { bookmark = nil }
        encoding = buffer.encoding
        lineEnding = buffer.lineEnding
        separators = buffer.originalSeparators
        isDirty = buffer.isDirty
        isReadOnly = buffer.isReadOnly
        modificationDate = buffer.lastKnownModificationDate
        self.cursor = cursor
    }

    func restored() -> EditorBuffer {
        var resolved = url
        if let bookmark {
            var stale = false
            resolved = (try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)) ?? url
        }
        let parsed = LineParser.parse(text, url: resolved ?? URL(fileURLWithPath: "/tmp/\(displayName)"), encoding: encoding, lastKnownModificationDate: modificationDate)
        var buffer = EditorBuffer(file: parsed)
        buffer.url = resolved
        buffer.displayName = displayName
        buffer.lineEnding = lineEnding
        buffer.originalSeparators = separators
        buffer.isDirty = isDirty
        buffer.isReadOnly = isReadOnly
        return buffer
    }
}
