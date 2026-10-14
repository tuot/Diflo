import Foundation

/// Immutable index shared by the editor and comparison snapshots.
/// Starts include the final empty display line, while `lines` follows LineParser semantics.
nonisolated struct TextLineIndex: Equatable, Sendable {
    let lines: [String]
    let utf16Starts: [Int]
    let utf16Count: Int
    let hasTrailingNewline: Bool

    init(normalizedText text: String) {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 10 { starts.append(offset) }
        }
        utf16Starts = starts
        utf16Count = offset
        hasTrailingNewline = text.hasSuffix("\n")
        if text.isEmpty {
            lines = []
        } else {
            let content = hasTrailingNewline ? text.dropLast() : Substring(text)
            lines = content.isEmpty ? [""] : content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
    }

    func line(containingUTF16Offset offset: Int) -> Int {
        let target = min(max(0, offset), utf16Count)
        var low = 0
        var high = utf16Starts.count
        while low < high {
            let middle = low + (high - low) / 2
            if utf16Starts[middle] <= target { low = middle + 1 } else { high = middle }
        }
        return max(0, low - 1)
    }
}
