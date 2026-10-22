import Foundation

nonisolated struct DiffHunk: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case leftOnly
        case rightOnly
        case modified
    }

    let id: String
    let kind: Kind
    let leftLineRange: Range<Int>
    let rightLineRange: Range<Int>
    let virtualRowRange: Range<Int>
    let leftRevision: Int
    let rightRevision: Int
    var isTrailingNewline: Bool = false
}
