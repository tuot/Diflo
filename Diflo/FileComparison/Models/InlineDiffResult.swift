import Foundation

nonisolated struct InlineDiffResult: Equatable, Sendable {
    let leftRanges: [NSRange]
    let rightRanges: [NSRange]
    let precision: DiffPrecision
}
