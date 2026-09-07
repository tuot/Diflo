import Foundation

nonisolated struct DiffRow: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case unchanged
        case inserted
        case deleted
        case modified
    }

    let leftText: String?
    let rightText: String?
    let leftLineNumber: Int?
    let rightLineNumber: Int?
    let kind: Kind
}
