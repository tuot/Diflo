import Foundation

nonisolated enum TextFileWriter {
    private static let coordinationLock = NSLock()
    static func write(
        buffer: EditorBuffer,
        to url: URL,
        overwriteExternalChanges: Bool
    ) throws -> Date? {
        coordinationLock.lock()
        defer { coordinationLock.unlock() }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
        }

        var metadataURL = url
        metadataURL.removeAllCachedResourceValues()
        if !overwriteExternalChanges, url == buffer.url, let expected = buffer.lastKnownModificationDate {
            guard let actual = try? metadataURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  actual == expected else { throw TextFileWritingError.externallyModified }
        }

        let output = FileTextFormat.render(buffer.text, separators: buffer.originalSeparators, fallback: buffer.lineEnding)
        guard let data = buffer.encoding.encode(output) else {
            throw TextFileWritingError.cannotEncode
        }

        do {
            try data.write(to: url, options: .atomic)
            metadataURL.removeAllCachedResourceValues()
            return try metadataURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        } catch let error as TextFileWritingError {
            throw error
        } catch {
            throw TextFileWritingError.cannotWrite
        }
    }
}
