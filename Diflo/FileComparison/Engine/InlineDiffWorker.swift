import Foundation

/// Separate serial executor from line comparison; queued identical inputs hit the cache.
actor InlineDiffWorker {
    private struct Key: Hashable { let left: String; let right: String }
    private struct Entry { let result: InlineDiffResult; let bytes: Int; var access: UInt64 }
    private var cache: [Key: Entry] = [:]
    private var access: UInt64 = 0
    private let maximumEntries: Int
    private let maximumBytes: Int
    private(set) var cacheBytes = 0
    var cacheEntryCount: Int { cache.count }

    init(maximumEntries: Int = 256, maximumBytes: Int = 16 * 1024 * 1024) {
        self.maximumEntries = max(0, maximumEntries)
        self.maximumBytes = max(0, maximumBytes)
    }

    func compare(left: String, right: String) async throws -> InlineDiffResult {
        try Task.checkCancellation()
        let key = Key(left: left, right: right)
        access &+= 1
        if var entry = cache[key] {
            entry.access = access; cache[key] = entry
            return entry.result
        }
        let result = try Self.calculate(left: left, right: right)
        try Task.checkCancellation()
        let bytes = (left.utf8.count + right.utf8.count) * 2 + (result.leftRanges.count + result.rightRanges.count) * MemoryLayout<NSRange>.stride + 128
        if maximumEntries > 0 && bytes <= maximumBytes {
            while cache.count >= maximumEntries || cacheBytes + bytes > maximumBytes {
                guard let oldest = cache.min(by: { $0.value.access < $1.value.access }) else { break }
                cacheBytes -= oldest.value.bytes
                cache.removeValue(forKey: oldest.key)
            }
            cache[key] = Entry(result: result, bytes: bytes, access: access)
            cacheBytes += bytes
        }
        return result
    }


    private nonisolated static func calculate(left: String, right: String) throws -> InlineDiffResult {
        var scalars = 0
        for text in [left, right] {
            for _ in text.unicodeScalars {
                if scalars & 1023 == 0 { try Task.checkCancellation() }
                scalars += 1
                if scalars > 20_000 { return coarse(left: left, right: right) }
            }
        }
        if left == right { return .init(leftRanges: [], rightRanges: [], precision: .exact) }
        let l = try tokens(left), r = try tokens(right)
        var pool: [String: Int] = [:]
        func ids(_ tokens: [Token]) -> [Int] {
            tokens.map { token in
                if let id = pool[token.text] { return id }
                let id = pool.count; pool[token.text] = id; return id
            }
        }
        let tokenDiff = try SequenceDiff.compare(left: ids(l), right: ids(r))
        var leftRanges: [NSRange] = [], rightRanges: [NSRange] = []
        var precision = tokenDiff.precision
        for block in tokenDiff.blocks where block.kind != .equal {
            try Task.checkCancellation()
            let leftRange = range(block.left, tokens: l, end: left.utf16.count)
            let rightRange = range(block.right, tokens: r, end: right.utf16.count)
            if block.kind == .replace && tokenDiff.precision == .exact {
                // Refine changed words using grapheme clusters so UTF-16 spans never split them.
                let leftText = (left as NSString).substring(with: leftRange)
                let rightText = (right as NSString).substring(with: rightRange)
                let lc = try characters(leftText), rc = try characters(rightText)
                let refined = try SequenceDiff.compare(left: ids(lc), right: ids(rc), budget: .init(maximumSteps: 200_000, maximumTraceBytes: 2 * 1024 * 1024))
                if refined.precision == .coarse { precision = .coarse }
                for change in refined.blocks where change.kind != .equal {
                    let lr = range(change.left, tokens: lc, end: leftText.utf16.count)
                    let rr = range(change.right, tokens: rc, end: rightText.utf16.count)
                    if lr.length > 0 { leftRanges.append(.init(location: leftRange.location + lr.location, length: lr.length)) }
                    if rr.length > 0 { rightRanges.append(.init(location: rightRange.location + rr.location, length: rr.length)) }
                }
            } else {
                if leftRange.length > 0 { leftRanges.append(leftRange) }
                if rightRange.length > 0 { rightRanges.append(rightRange) }
            }
        }
        return .init(leftRanges: merge(leftRanges), rightRanges: merge(rightRanges), precision: precision)
    }

    private nonisolated struct Token { let text: String; let range: NSRange }

    private nonisolated static func characters(_ text: String) throws -> [Token] {
        var result: [Token] = [], offset = 0
        for (index, character) in text.enumerated() {
            if index & 1023 == 0 { try Task.checkCancellation() }
            let string = String(character), length = string.utf16.count
            result.append(.init(text: string, range: .init(location: offset, length: length)))
            offset += length
        }
        return result
    }

    private nonisolated static func tokens(_ text: String) throws -> [Token] {
        var result: [Token] = [], word = "", start = 0, offset = 0
        for (index, character) in text.enumerated() {
            if index & 1023 == 0 { try Task.checkCancellation() }
            let isWord = character.isLetter || character.isNumber
            if !isWord && !word.isEmpty {
                result.append(.init(text: word, range: .init(location: start, length: offset - start)))
                word = ""
            }
            let length = String(character).utf16.count
            if isWord {
                if word.isEmpty { start = offset }
                word.append(character)
            } else { result.append(.init(text: String(character), range: .init(location: offset, length: length))) }
            offset += length
        }
        if !word.isEmpty { result.append(.init(text: word, range: .init(location: start, length: offset - start))) }
        return result
    }

    private nonisolated static func range(_ indices: Range<Int>, tokens: [Token], end: Int) -> NSRange {
        let start = indices.lowerBound < tokens.count ? tokens[indices.lowerBound].range.location : end
        let finish = indices.upperBound < tokens.count ? tokens[indices.upperBound].range.location : end
        return .init(location: start, length: finish - start)
    }

    private nonisolated static func merge(_ ranges: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges {
            if let last = result.last, NSMaxRange(last) == range.location {
                result[result.count - 1] = .init(location: last.location, length: last.length + range.length)
            } else { result.append(range) }
        }
        return result
    }

    private nonisolated static func coarse(left: String, right: String) -> InlineDiffResult {
        .init(leftRanges: left.isEmpty ? [] : [.init(location: 0, length: left.utf16.count)], rightRanges: right.isEmpty ? [] : [.init(location: 0, length: right.utf16.count)], precision: .coarse)
    }
}
