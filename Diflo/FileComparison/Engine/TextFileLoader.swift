import Foundation

nonisolated enum TextFileLoader {
    private static let maximumByteCount = 10 * 1_024 * 1_024
    private static let maximumLineCount = 20_000

    static func load(from url: URL, encodingOverride: TextEncoding? = nil) throws -> ParsedTextFile {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            var metadataURL = url
            metadataURL.removeAllCachedResourceValues()
            let values = try metadataURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile != false else {
                throw TextFileLoadingError.unreadable
            }
            if let fileSize = values.fileSize, fileSize > maximumByteCount {
                throw TextFileLoadingError.fileTooLarge
            }

            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= maximumByteCount else {
                throw TextFileLoadingError.fileTooLarge
            }

            let decoded: (text: String, encoding: TextEncoding)
            if let encodingOverride {
                let body = data.starts(with: encodingOverride.byteOrderMark) ? data.dropFirst(encodingOverride.byteOrderMark.count) : data[...]
                guard let text = String(data: body, encoding: String.Encoding(rawValue: encodingOverride.rawValue)) else {
                    throw TextFileLoadingError.unsupportedEncoding
                }
                decoded = (text, encodingOverride)
            } else { decoded = try decode(data) }
            let file = LineParser.parse(
                decoded.text,
                url: url,
                encoding: decoded.encoding,
                lastKnownModificationDate: values.contentModificationDate
            )
            guard file.lines.count <= maximumLineCount else {
                throw TextFileLoadingError.tooManyLines
            }
            return file
        } catch let error as TextFileLoadingError {
            throw error
        } catch {
            throw TextFileLoadingError.unreadable
        }
    }

    private static func decode(_ data: Data) throws -> (text: String, encoding: TextEncoding) {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            guard let text = String(data: Data(data.dropFirst(3)), encoding: .utf8) else {
                throw TextFileLoadingError.unsupportedEncoding
            }
            return (text, .utf8BOM)
        }

        if data.starts(with: [0xFF, 0xFE]) {
            guard let text = String(data: Data(data.dropFirst(2)), encoding: .utf16LittleEndian) else {
                throw TextFileLoadingError.unsupportedEncoding
            }
            return (text, .utf16LittleEndian)
        }

        if data.starts(with: [0xFE, 0xFF]) {
            guard let text = String(data: Data(data.dropFirst(2)), encoding: .utf16BigEndian) else {
                throw TextFileLoadingError.unsupportedEncoding
            }
            return (text, .utf16BigEndian)
        }

        guard !data.contains(0) else {
            throw TextFileLoadingError.binaryFile
        }

        if let text = String(data: data, encoding: .utf8) {
            return (text, .utf8)
        }

        var convertedString: NSString?
        var usedLossyConversion = ObjCBool(false)
        let rawEncoding = NSString.stringEncoding(
            for: data,
            encodingOptions: [.allowLossyKey: false],
            convertedString: &convertedString,
            usedLossyConversion: &usedLossyConversion
        )

        guard
            rawEncoding != 0,
            !usedLossyConversion.boolValue,
            let convertedString
        else {
            throw TextFileLoadingError.unsupportedEncoding
        }

        return (
            convertedString as String,
            TextEncoding(rawValue: rawEncoding, displayName: NSString.localizedName(of: rawEncoding))
        )
    }
}
