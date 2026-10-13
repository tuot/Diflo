import Foundation

nonisolated enum TextFileWritingError: LocalizedError, Equatable {
    case cannotEncode
    case externallyModified
    case cannotWrite

    var errorDescription: String? {
        switch self {
        case .cannotEncode: "当前内容无法使用原文件编码无损保存"
        case .externallyModified: "文件已被其他应用修改"
        case .cannotWrite: "无法写入文件"
        }
    }
}
