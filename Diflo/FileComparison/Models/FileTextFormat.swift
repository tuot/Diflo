import Foundation

nonisolated enum FileTextFormat {
    static func separators(in text: String) -> [LineEnding] {
        var result: [LineEnding] = []
        var iterator = text.unicodeScalars.makeIterator()
        var pending = iterator.next()
        while let scalar = pending {
            pending = iterator.next()
            if scalar.value == 13 {
                if pending?.value == 10 { result.append(.crlf); pending = iterator.next() }
                else { result.append(.cr) }
            } else if scalar.value == 10 { result.append(.lf) }
        }
        return result
    }

    static func render(_ text: String, separators: [LineEnding], fallback: LineEnding) -> String {
        var index = 0
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { part in
            defer { index += 1 }
            guard index > 0 else { return String(part) }
            return (index - 1 < separators.count ? separators[index - 1] : fallback).separator + part
        }.joined()
    }

    static func updating(separators: [LineEnding], old: String, new: String, fallback: LineEnding) -> [LineEnding] {
        let before = Array(old.utf16), after = Array(new.utf16)
        var prefix = 0, suffix = 0
        while prefix < min(before.count, after.count), before[prefix] == after[prefix] { prefix += 1 }
        while suffix < min(before.count, after.count) - prefix,
              before[before.count - 1 - suffix] == after[after.count - 1 - suffix] { suffix += 1 }
        let prefixCount = before.prefix(prefix).count { $0 == 10 }
        let suffixCount = before.suffix(suffix).count { $0 == 10 }
        let total = after.count { $0 == 10 }
        let oldCount = before.count { $0 == 10 }
        let existing = (0..<oldCount).map { $0 < separators.count ? separators[$0] : fallback }
        let inherited = prefixCount > 0 ? existing[prefixCount - 1] : (existing.first ?? fallback)
        return Array(existing.prefix(prefixCount))
            + Array(repeating: inherited, count: max(0, total - prefixCount - suffixCount))
            + Array(existing.suffix(suffixCount))
    }
}
