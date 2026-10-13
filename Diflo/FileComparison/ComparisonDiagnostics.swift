import os

nonisolated enum ComparisonDiagnostics {
    static let signposter = OSSignposter(subsystem: "Diflo", category: "FileComparison")

    static func measure<Value>(_ name: StaticString, _ operation: () throws -> Value) rethrows -> Value {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try operation()
    }
}
