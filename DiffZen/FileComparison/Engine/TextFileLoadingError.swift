import Foundation

nonisolated enum TextFileLoadingError: LocalizedError, Equatable {
    case fileTooLarge
    case tooManyLines
    case binaryFile
    case unsupportedEncoding
    case unreadable

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "文件超过 10 MB，MVP 暂不支持。"
        case .tooManyLines:
            "文件超过 20,000 行，MVP 暂不支持。"
        case .binaryFile:
            "该文件看起来是二进制文件。"
        case .unsupportedEncoding:
            "无法无损识别文件编码。"
        case .unreadable:
            "无法读取该文件，请检查权限后重试。"
        }
    }
}
