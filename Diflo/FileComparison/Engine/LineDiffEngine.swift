import Foundation

nonisolated enum LineDiffEngine {
    /// Compatibility for synchronous callers. Background production work uses compareCancellable.
    static func compare(left: ParsedTextFile, right: ParsedTextFile, leftRevision: Int = 0, rightRevision: Int = 0, options: ComparisonOptions = .default) -> DiffResult {
        do {
            return try compareCancellable(left: left, right: right, leftRevision: leftRevision, rightRevision: rightRevision, options: options)
        } catch {
            // The legacy signature cannot propagate cancellation. It never restarts expensive work.
            return assemble(left: left, right: right, leftRevision: leftRevision, rightRevision: rightRevision, options: options, blocks: coarseBlocks(left: left, right: right), precision: .coarse)
        }
    }

    static func compareCancellable(left: ParsedTextFile, right: ParsedTextFile, leftRevision: Int = 0, rightRevision: Int = 0, options: ComparisonOptions = .default, budget: DiffBudget = .default) throws -> DiffResult {
        try Task.checkCancellation()
        var pool: [String: Int] = [:]
        var counter = DiffStepCounter(maximum: budget.maximumSteps)
        func intern(_ lines: [String]) throws -> [Int] {
            var ids: [Int] = []
            ids.reserveCapacity(lines.count)
            for line in lines {
                try counter.step()
                let normalized = try normalizeLine(line, options: options, counter: &counter)
                if let id = pool[normalized] { ids.append(id) }
                else { let id = pool.count; pool[normalized] = id; ids.append(id) }
            }
            return ids
        }
        let sequence: SequenceDiffResult
        do {
            let leftIDs = try intern(left.lines)
            let rightIDs = try intern(right.lines)
            sequence = try SequenceDiff.compare(left: leftIDs, right: rightIDs, budget: budget)
        } catch is DiffStepCounter.Exhausted {
            sequence = .init(blocks: coarseBlocks(left: left, right: right), precision: .coarse)
        }
        let rows = try makeRows(left: left.lines, right: right.lines, blocks: sequence.blocks, cancellable: true)
        try Task.checkCancellation()
        return result(left: left, right: right, leftRevision: leftRevision, rightRevision: rightRevision, options: options, rows: rows, precision: sequence.precision)
    }

    static func makeRows(left: [String], right: [String], blocks: [DiffBlock], cancellable: Bool = true) throws -> [DiffRow] {
        var rows: [DiffRow] = []
        rows.reserveCapacity(max(left.count, right.count))
        for block in blocks {
            for offset in 0..<max(block.left.count, block.right.count) {
                if cancellable && rows.count & 1023 == 0 { try Task.checkCancellation() }
                let l: Int? = offset < block.left.count ? block.left.lowerBound + offset : nil
                let r: Int? = offset < block.right.count ? block.right.lowerBound + offset : nil
                rows.append(.init(leftText: l.map { left[$0] }, rightText: r.map { right[$0] }, leftLineNumber: l.map { $0 + 1 }, rightLineNumber: r.map { $0 + 1 }, kind: block.kind == .equal ? .unchanged : (l == nil ? .inserted : (r == nil ? .deleted : .modified))))
            }
        }
        return rows
    }

    static func result(left: ParsedTextFile, right: ParsedTextFile, leftRevision: Int, rightRevision: Int, options: ComparisonOptions, rows: [DiffRow], precision: DiffPrecision) -> DiffResult {
        DiffResult(leftFile: left, rightFile: right, rows: rows, hasTrailingNewlineDifference: left.hasTrailingNewline != right.hasTrailingNewline, hunks: DiffHunkBuilder.build(rows: rows, leftRevision: leftRevision, rightRevision: rightRevision), precision: precision, options: options, leftRevision: leftRevision, rightRevision: rightRevision)
    }

    private static func assemble(left: ParsedTextFile, right: ParsedTextFile, leftRevision: Int, rightRevision: Int, options: ComparisonOptions, blocks: [DiffBlock], precision: DiffPrecision) -> DiffResult {
        // cancellable:false has no throwing branches.
        let rows = (try? makeRows(left: left.lines, right: right.lines, blocks: blocks, cancellable: false)) ?? []
        return result(left: left, right: right, leftRevision: leftRevision, rightRevision: rightRevision, options: options, rows: rows, precision: precision)
    }

    private static func coarseBlocks(left: ParsedTextFile, right: ParsedTextFile) -> [DiffBlock] {
        guard !left.lines.isEmpty || !right.lines.isEmpty else { return [] }
        return [.init(kind: left.lines.isEmpty ? .insert : (right.lines.isEmpty ? .delete : .replace), left: 0..<left.lines.count, right: 0..<right.lines.count)]
    }

    private static func normalizeLine(_ line: String, options: ComparisonOptions, counter: inout DiffStepCounter) throws -> String {
        guard options.ignoreCase || options.ignoreWhitespace || options.ignoreTrailingWhitespace else { return line }
        var characters: [Character] = []
        characters.reserveCapacity(min(line.utf8.count, 4096))
        for character in line {
            try counter.step()
            if !options.ignoreWhitespace || !character.isWhitespace { characters.append(character) }
        }
        if options.ignoreTrailingWhitespace && !options.ignoreWhitespace {
            while characters.last?.isWhitespace == true { try counter.step(); characters.removeLast() }
        }
        let text = String(characters)
        return options.ignoreCase ? text.lowercased() : text
    }
}
