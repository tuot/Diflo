import Foundation

nonisolated struct DiffBlock: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case equal, replace, delete, insert }
    let kind: Kind
    let left: Range<Int>
    let right: Range<Int>
}
