import Foundation

nonisolated struct ComparisonOptions: Equatable, Sendable, Codable {
    var ignoreTrailingWhitespace: Bool = false
    var ignoreWhitespace: Bool = false
    var ignoreCase: Bool = false

    nonisolated static let `default` = ComparisonOptions()
}
