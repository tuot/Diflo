import Foundation

nonisolated enum IntraLineDiffEngine {
    /// 计算两行文本之间的字符级差异范围 (NSRange)
    /// 结合公共前缀/后缀剥离与 LCS 动态规划算法
    static func diff(left: String, right: String) -> (leftRanges: [NSRange], rightRanges: [NSRange]) {
        guard left != right else { return ([], []) }
        guard !left.isEmpty else {
            return ([], [NSRange(location: 0, length: (right as NSString).length)])
        }
        guard !right.isEmpty else {
            return ([NSRange(location: 0, length: (left as NSString).length)], [])
        }

        let leftChars = Array(left.utf16)
        let rightChars = Array(right.utf16)
        let leftLen = leftChars.count
        let rightLen = rightChars.count

        // 1. 剥离公共前缀
        var prefixLen = 0
        while prefixLen < leftLen && prefixLen < rightLen && leftChars[prefixLen] == rightChars[prefixLen] {
            prefixLen += 1
        }

        // 2. 剥离公共后缀
        var suffixLen = 0
        while suffixLen < (leftLen - prefixLen) && suffixLen < (rightLen - prefixLen) &&
                leftChars[leftLen - 1 - suffixLen] == rightChars[rightLen - 1 - suffixLen] {
            suffixLen += 1
        }

        let midLeft = Array(leftChars[prefixLen..<(leftLen - suffixLen)])
        let midRight = Array(rightChars[prefixLen..<(rightLen - suffixLen)])

        if midLeft.isEmpty && midRight.isEmpty {
            return ([], [])
        }

        // Zero-width anchors belong to the presentation layer, not the changed text ranges.
        if midLeft.isEmpty {
            let rightRange = NSRange(location: prefixLen, length: midRight.count)
            return ([], [rightRange])
        }

        if midRight.isEmpty {
            let leftRange = NSRange(location: prefixLen, length: midLeft.count)
            return ([leftRange], [])
        }

        // 3. 计算中间差异部分的 LCS
        let midDiff = computeLCSDiff(left: midLeft, right: midRight)

        // 4. 偏置回原字符串并合并相邻区间
        let leftRanges = mergeRanges(midDiff.leftRanges.map {
            NSRange(location: $0.location + prefixLen, length: $0.length)
        })
        let rightRanges = mergeRanges(midDiff.rightRanges.map {
            NSRange(location: $0.location + prefixLen, length: $0.length)
        })

        return (leftRanges, rightRanges)
    }

    private static func computeLCSDiff(left: [UTF16Char], right: [UTF16Char]) -> (leftRanges: [NSRange], rightRanges: [NSRange]) {
        let n = left.count
        let m = right.count

        if n * m > 100_000 {
            return ([NSRange(location: 0, length: n)], [NSRange(location: 0, length: m)])
        }

        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0..<n {
            for j in 0..<m {
                if left[i] == right[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        var i = n
        var j = m
        var leftMatched = Array(repeating: false, count: n)
        var rightMatched = Array(repeating: false, count: m)

        while i > 0 && j > 0 {
            if left[i - 1] == right[j - 1] {
                leftMatched[i - 1] = true
                rightMatched[j - 1] = true
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        let leftRanges = extractUnmatchedRanges(leftMatched)
        let rightRanges = extractUnmatchedRanges(rightMatched)
        return (leftRanges, rightRanges)
    }

    private static func extractUnmatchedRanges(_ matched: [Bool]) -> [NSRange] {
        var ranges: [NSRange] = []
        var start: Int?

        for (idx, isMatch) in matched.enumerated() {
            if !isMatch {
                if start == nil {
                    start = idx
                }
            } else if let s = start {
                ranges.append(NSRange(location: s, length: idx - s))
                start = nil
            }
        }
        if let s = start {
            ranges.append(NSRange(location: s, length: matched.count - s))
        }
        return ranges
    }

    private static func mergeRanges(_ ranges: [NSRange]) -> [NSRange] {
        guard !ranges.isEmpty else { return [] }
        var merged: [NSRange] = [ranges[0]]

        for r in ranges.dropFirst() {
            let last = merged[merged.count - 1]
            if r.location <= last.location + last.length + 1 {
                let newLength = max(last.length, r.location + r.length - last.location)
                merged[merged.count - 1] = NSRange(location: last.location, length: newLength)
            } else {
                merged.append(r)
            }
        }
        return merged
    }
}
