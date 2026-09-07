import Foundation

nonisolated enum IntraLineDiffEngine {
    /// Computes character ranges in both left and right strings that differ.
    /// Uses common prefix and suffix matching for O(N) fast diffing.
    static func diff(left: String, right: String) -> (leftRanges: [NSRange], rightRanges: [NSRange]) {
        guard left != right else { return ([], []) }
        let leftUtf16 = left as NSString
        let rightUtf16 = right as NSString
        let leftLen = leftUtf16.length
        let rightLen = rightUtf16.length

        var prefixLen = 0
        while prefixLen < leftLen && prefixLen < rightLen &&
                leftUtf16.character(at: prefixLen) == rightUtf16.character(at: prefixLen) {
            prefixLen += 1
        }

        var suffixLen = 0
        while suffixLen < (leftLen - prefixLen) && suffixLen < (rightLen - prefixLen) &&
                leftUtf16.character(at: leftLen - 1 - suffixLen) == rightUtf16.character(at: rightLen - 1 - suffixLen) {
            suffixLen += 1
        }

        let leftChangedLen = leftLen - prefixLen - suffixLen
        let rightChangedLen = rightLen - prefixLen - suffixLen

        let leftRanges = leftChangedLen > 0 ? [NSRange(location: prefixLen, length: leftChangedLen)] : []
        let rightRanges = rightChangedLen > 0 ? [NSRange(location: prefixLen, length: rightChangedLen)] : []
        return (leftRanges, rightRanges)
    }
}
