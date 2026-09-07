import Foundation

nonisolated struct CursorPosition: Equatable, Sendable {
    let line: Int
    let column: Int

    static let start = CursorPosition(line: 1, column: 1)
}
