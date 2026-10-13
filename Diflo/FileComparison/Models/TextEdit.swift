import Foundation

nonisolated struct TextEdit: Equatable, Sendable {
    let range: NSRange
    let replacement: String
    let baseRevision: Int
}

nonisolated enum TextEditError: Error, Equatable {
    case staleRevision
    case invalidRange
}
