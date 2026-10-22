import Foundation

actor ComparisonStore {
    static let shared: ComparisonStore = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-diflo-ui-testing"), let token = ProcessInfo.processInfo.environment["DIFLO_TEST_SESSION"], UUID(uuidString: token) != nil {
            return ComparisonStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("DifloUITests-\(token)", isDirectory: true))
        }
        #endif
        return ComparisonStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Diflo", isDirectory: true))
    }()
    let directory: URL
    private var generations: [UUID: Int] = [:]
    private var readWarnings: [String] = []
    private var claims: Set<UUID> = []
    init(directory: URL) { self.directory = directory }

    func saveDraft(_ snapshot: ComparisonSnapshot, generation: Int) throws {
        guard generation >= generations[snapshot.id, default: 0] else { return }
        let url = draftURL(snapshot.id)
        if FileManager.default.fileExists(atPath: url.path) {
            let old = try JSONDecoder().decode(ComparisonSnapshot.self, from: Data(contentsOf: url))
            guard old.version == 1 else { throw StoreError.unsupportedVersion }
        }
        generations[snapshot.id] = generation
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
    func deleteDraft(id: UUID, generation: Int, allowClaimed: Bool = false) throws {
        guard allowClaimed || !claims.contains(id) else { throw StoreError.draftInUse }
        guard generation >= generations[id, default: 0] else { return }
        generations[id] = generation
        let url = draftURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        claims.remove(id)
    }
    func drafts() throws -> [ComparisonSnapshot] {
        readWarnings = []
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        var values: [ComparisonSnapshot] = []
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.lastPathComponent.hasPrefix("draft-") && url.pathExtension == "json" {
            do {
                let value = try JSONDecoder().decode(ComparisonSnapshot.self, from: Data(contentsOf: url))
                guard value.version == 1 else { throw StoreError.unsupportedVersion }
                if !claims.contains(value.id) { values.append(value) }
            } catch { readWarnings.append("无法读取草稿 \(url.lastPathComponent)，原文件已保留。") }
        }
        return values.sorted { $0.updatedAt > $1.updatedAt }
    }
    func draftWarnings() -> [String] { readWarnings }
    func claimDraft(id: UUID) -> Bool { claims.insert(id).inserted }
    func releaseDraft(id: UUID) { claims.remove(id) }
    func recordRecent(_ snapshot: ComparisonSnapshot) throws {
        guard snapshot.left.url != nil || snapshot.right.url != nil else { return }
        var items = try recentComparisons()
        items.removeAll { $0.left.url == snapshot.left.url && $0.right.url == snapshot.right.url }
        // Recent records retain file access and options, never document contents.
        let record = RecentComparison(id: UUID(), left: RecentFile(snapshot.left), right: RecentFile(snapshot.right), options: snapshot.options)
        items.insert(record, at: 0)
        try writeRecent(Array(items.prefix(20)))
    }
    func recentComparisons() throws -> [RecentComparison] {
        let url = directory.appendingPathComponent("recent.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([RecentComparison].self, from: Data(contentsOf: url))
    }
    func removeRecent(id: UUID?) throws {
        try writeRecent(id == nil ? [] : recentComparisons().filter { $0.id != id })
    }
    private func writeRecent(_ values: [RecentComparison]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: directory.appendingPathComponent("recent.json"), options: .atomic)
    }
    private func draftURL(_ id: UUID) -> URL { directory.appendingPathComponent("draft-\(id.uuidString).json") }
    enum StoreError: LocalizedError {
        case unsupportedVersion, draftInUse
        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: "草稿版本无法读取，原文件已保留。"
            case .draftInUse: "此草稿正在其他窗口使用，无法删除。"
            }
        }
    }
}

nonisolated struct RecentComparison: Codable, Identifiable, Sendable {
    let id: UUID
    let left: RecentFile
    let right: RecentFile
    let options: ComparisonOptions
    var title: String { "\(left.displayName) ↔ \(right.displayName)" }
}
nonisolated struct RecentFile: Codable, Sendable {
    let url: URL?
    let displayName: String
    let bookmark: Data?
    init(_ buffer: BufferSnapshot) { url = buffer.url; displayName = buffer.displayName; bookmark = buffer.bookmark }
    func resolve() -> URL? {
        guard let bookmark else { return url }
        var stale = false
        return (try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)) ?? url
    }
}
