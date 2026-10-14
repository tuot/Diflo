import Foundation

nonisolated enum DiffRowPresentation {
    enum Highlight: Equatable, Sendable {
        case none
        case insertion
        case deletion
        case modification
    }
}
