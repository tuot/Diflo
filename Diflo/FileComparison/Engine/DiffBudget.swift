import Foundation

nonisolated struct DiffBudget: Equatable, Sendable {
    let maximumSteps: Int
    let maximumTraceBytes: Int
    static let `default` = DiffBudget(maximumSteps: 4_000_000, maximumTraceBytes: 32 * 1024 * 1024)
}

nonisolated struct DiffStepCounter {
    enum Exhausted: Error { case budget }
    private var steps = 0
    private let maximum: Int
    init(maximum: Int) { self.maximum = max(0, maximum) }
    mutating func step() throws {
        if steps & 1023 == 0 { try Task.checkCancellation() }
        guard steps < maximum else { throw Exhausted.budget }
        steps += 1
    }
}
