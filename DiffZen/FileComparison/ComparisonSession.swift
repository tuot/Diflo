import Foundation
import Observation

@MainActor
@Observable
final class ComparisonSession {
    private let worker: any ComparisonWorking
    private var comparisonTask: Task<Void, Never>?
    private var comparisonGeneration = 0
    private var loadGenerations: [ComparisonSide: Int] = [.left: 0, .right: 0]

    private(set) var leftBuffer = EditorBuffer.blank(named: "左侧未命名")
    private(set) var rightBuffer = EditorBuffer.blank(named: "右侧未命名")
    private(set) var result: DiffResult?
    private(set) var isWorkspacePresented = false
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    private(set) var selectedHunkID: DiffHunk.ID?
    private(set) var options = ComparisonOptions.default

    var hasUnsavedChanges: Bool { leftBuffer.isDirty || rightBuffer.isDirty }
    var selectedHunk: DiffHunk? { result?.hunks.first { $0.id == selectedHunkID } }

    init(worker: any ComparisonWorking = ComparisonWorker()) {
        self.worker = worker
    }

    func startBlank() {
        comparisonTask?.cancel()
        leftBuffer = .blank(named: "左侧未命名")
        rightBuffer = .blank(named: "右侧未命名")
        selectedHunkID = nil
        errorMessage = nil
        isWorkspacePresented = true
        scheduleComparison(debounced: false)
    }

    func start(leftURL: URL?, rightURL: URL?) async {
        startBlank()
        if let leftURL { await open(leftURL, for: .left) }
        if let rightURL { await open(rightURL, for: .right) }
    }

    func open(_ url: URL, for side: ComparisonSide) async {
        let generation = (loadGenerations[side] ?? 0) + 1
        loadGenerations[side] = generation
        isWorking = true
        errorMessage = nil
        do {
            let file = try await worker.load(from: url)
            guard loadGenerations[side] == generation else { return }
            setBuffer(EditorBuffer(file: file), for: side)
            scheduleComparison(debounced: false)
        } catch {
            guard loadGenerations[side] == generation else { return }
            errorMessage = error.localizedDescription
        }
        if loadGenerations[side] == generation { isWorking = false }
    }

    func edit(_ side: ComparisonSide, text: String) {
        let updated = buffer(for: side).updatingText(text)
        guard updated != buffer(for: side) else { return }
        setBuffer(updated, for: side)
        scheduleComparison(debounced: true)
    }

    func editLine(_ side: ComparisonSide, at lineIndex: Int, text: String) {
        var lines = buffer(for: side).lines
        guard lineIndex >= 0 && lineIndex < lines.count else { return }
        lines[lineIndex] = text
        let hasTrailing = buffer(for: side).hasTrailingNewline
        let joined = lines.joined(separator: "\n") + (hasTrailing ? "\n" : "")
        edit(side, text: joined)
    }

    func swapBuffers() {
        comparisonTask?.cancel()
        (leftBuffer, rightBuffer) = (rightBuffer, leftBuffer)
        leftBuffer.revision += 1
        rightBuffer.revision += 1
        selectedHunkID = nil
        scheduleComparison(debounced: false)
    }

    func selectNextHunk() {
        selectHunk(offset: 1)
    }

    func selectPreviousHunk() {
        selectHunk(offset: -1)
    }

    func selectHunk(_ id: DiffHunk.ID?) {
        selectedHunkID = id
    }

    func applyHunk(_ hunk: DiffHunk, from source: ComparisonSide) {
        do {
            let updatedText = try ApplyHunkCommand.apply(
                hunk,
                from: source,
                left: leftBuffer,
                right: rightBuffer
            )
            edit(source == .left ? .right : .left, text: updatedText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteHunk(_ hunk: DiffHunk, from side: ComparisonSide) {
        guard hunk.leftRevision == leftBuffer.revision,
              hunk.rightRevision == rightBuffer.revision else {
            errorMessage = "差异已过期，请等待重新计算"
            return
        }
        var lines = buffer(for: side).lines
        let range = side == .left ? hunk.leftLineRange : hunk.rightLineRange
        guard range.upperBound <= lines.count else { return }
        lines.removeSubrange(range)
        let trailing = buffer(for: side).hasTrailingNewline && !lines.isEmpty
        edit(side, text: lines.joined(separator: "\n") + (trailing ? "\n" : ""))
    }

    func save(_ side: ComparisonSide, to url: URL, force: Bool = false) async -> Bool {
        let snapshot = buffer(for: side)
        isWorking = true
        defer { isWorking = false }
        do {
            let date = try await worker.save(buffer: snapshot, to: url, force: force)
            guard buffer(for: side).revision == snapshot.revision else { return true }
            setBuffer(snapshot.markingSaved(to: url, modificationDate: date), for: side)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func returnToLauncher(discardingChanges: Bool) -> Bool {
        guard discardingChanges || !hasUnsavedChanges else { return false }
        comparisonTask?.cancel()
        isWorkspacePresented = false
        result = nil
        selectedHunkID = nil
        return true
    }

    func setOptions(_ newOptions: ComparisonOptions) {
        guard options != newOptions else { return }
        options = newOptions
        scheduleComparison(debounced: false)
    }

    func applyAllHunks(from source: ComparisonSide) {
        let sourceText = buffer(for: source).text
        edit(source == .left ? .right : .left, text: sourceText)
    }

    func dismissError() {
        errorMessage = nil
    }

    private func scheduleComparison(debounced: Bool) {
        comparisonTask?.cancel()
        comparisonGeneration += 1
        let generation = comparisonGeneration
        let left = leftBuffer
        let right = rightBuffer
        let opts = options
        let worker = worker
        isWorking = true

        comparisonTask = Task { [weak self] in
            if debounced {
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            let newResult = await worker.compare(left: left, right: right, options: opts)
            guard let self, generation == self.comparisonGeneration else { return }
            self.result = newResult
            if !newResult.hunks.contains(where: { $0.id == self.selectedHunkID }) {
                self.selectedHunkID = nil
            }
            self.isWorking = false
        }
    }

    private func selectHunk(offset: Int) {
        guard let hunks = result?.hunks, !hunks.isEmpty else {
            selectedHunkID = nil
            return
        }
        guard let selectedHunkID,
              let current = hunks.firstIndex(where: { $0.id == selectedHunkID }) else {
            self.selectedHunkID = offset > 0 ? hunks.first?.id : hunks.last?.id
            return
        }
        self.selectedHunkID = hunks[(current + offset + hunks.count) % hunks.count].id
    }

    private func buffer(for side: ComparisonSide) -> EditorBuffer {
        side == .left ? leftBuffer : rightBuffer
    }

    private func setBuffer(_ buffer: EditorBuffer, for side: ComparisonSide) {
        if side == .left { leftBuffer = buffer } else { rightBuffer = buffer }
    }
}
