import Foundation

nonisolated enum DiffRowPresentation {
    enum Highlight: Equatable, Sendable {
        case none
        case insertion
        case deletion
        case modification
    }

    static func marker(for kind: DiffRow.Kind, side: ComparisonSide) -> String {
        switch (kind, side) {
        case (.inserted, .right):
            "+"
        case (.deleted, .left):
            "−"
        case (.modified, _):
            "~"
        default:
            ""
        }
    }

    static func highlight(for kind: DiffRow.Kind, side: ComparisonSide) -> Highlight {
        switch (kind, side) {
        case (.inserted, .right):
            .insertion
        case (.deleted, .left):
            .deletion
        case (.modified, _):
            .modification
        default:
            .none
        }
    }
}
