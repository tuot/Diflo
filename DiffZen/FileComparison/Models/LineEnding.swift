import Foundation

nonisolated enum LineEnding: String, Equatable, Sendable, CaseIterable {
    case lf
    case crlf
    case cr

    var displayName: String { rawValue.uppercased() }

    var separator: String {
        switch self {
        case .lf: "\n"
        case .crlf: "\r\n"
        case .cr: "\r"
        }
    }

    static func detect(in text: String) -> LineEnding {
        let scalars = text.unicodeScalars
        var index = scalars.startIndex

        while index < scalars.endIndex {
            if scalars[index].value == 13 {
                let next = scalars.index(after: index)
                if next < scalars.endIndex, scalars[next].value == 10 {
                    return .crlf
                }
                return .cr
            }
            if scalars[index].value == 10 { return .lf }
            index = scalars.index(after: index)
        }
        return .lf
    }

    func apply(to normalizedText: String) -> String {
        guard self != .lf else { return normalizedText }
        return normalizedText.replacing("\n", with: separator)
    }
}
