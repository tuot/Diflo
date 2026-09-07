import Foundation

nonisolated enum TextFileWriter {
    static func write(
        buffer: EditorBuffer,
        to url: URL,
        overwriteExternalChanges: Bool
    ) throws -> Date? {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
        }

        if !overwriteExternalChanges,
           url == buffer.url,
           let expected = buffer.lastKnownModificationDate,
           let actual = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           abs(actual.timeIntervalSince(expected)) > 0.001 {
            throw TextFileWritingError.externallyModified
        }

        let output = buffer.lineEnding.apply(to: buffer.text)
        guard let data = buffer.encoding.encode(output) else {
            throw TextFileWritingError.cannotEncode
        }

        do {
            try data.write(to: url, options: .atomic)
            return try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        } catch let error as TextFileWritingError {
            throw error
        } catch {
            throw TextFileWritingError.cannotWrite
        }
    }
}
