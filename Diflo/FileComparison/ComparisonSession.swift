import Foundation
import Observation

@MainActor
@Observable
final class ComparisonSession {
    let undoManager = UndoManager()
    private(set) var id = UUID()
    var isInteractionLocked = false
    var activeSide: ComparisonSide = .left
    var cursors: [ComparisonSide: CursorPosition] = [.left: .start, .right: .start]
    var protectionMessage: String?
    var onChange: (() -> Void)?
    private var draftTask: Task<Void, Never>?
    private var draftGeneration = Int(Date().timeIntervalSince1970 * 1_000_000)
    private var store: ComparisonStore?

    func enablePersistence(_ store: ComparisonStore) { self.store = store }
    func snapshot() -> ComparisonSnapshot {
        ComparisonSnapshot(id: id, updatedAt: Date(), left: BufferSnapshot(leftBuffer, cursor: cursors[.left] ?? .start), right: BufferSnapshot(rightBuffer, cursor: cursors[.right] ?? .start), options: options, activeSide: activeSide)
    }
    func restore(_ snapshot: ComparisonSnapshot) {
        startBlank()
        id = snapshot.id
        leftBuffer = snapshot.left.restored()
        rightBuffer = snapshot.right.restored()
        cursors = [.left: snapshot.left.cursor, .right: snapshot.right.cursor]
        activeSide = snapshot.activeSide
        options = snapshot.options
        scheduleComparison(debounced: false)
    }
    func discardDraft() async {
        draftTask?.cancel()
        draftGeneration += 1
        do { try await store?.deleteDraft(id: id, generation: draftGeneration, allowClaimed: true) }
        catch { protectionMessage = error.localizedDescription }
    }
    func flushDraft() async {
        draftTask?.cancel()
        guard isWorkspacePresented, let store else { return }
        if !hasUnsavedChanges { await discardDraft(); return }
        draftGeneration += 1
        let value = snapshot(), generation = draftGeneration
        do { _ = await store.claimDraft(id: value.id); try await store.saveDraft(value, generation: generation) }
        catch { protectionMessage = "草稿未能自动保存：\(error.localizedDescription)" }
    }
    private func scheduleDraft() {
        onChange?()
        guard store != nil else { return }
        draftTask?.cancel()
        draftTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await self?.flushDraft()
        }
    }
    func waitForSaves() async {
        for task in Array(saveTasks.values) { _ = await task.value }
    }
    func replace(file: ParsedTextFile, side: ComparisonSide) {
        setBuffer(EditorBuffer(file: file), for: side)
        selectedHunkID = nil
        scheduleComparison(debounced: false)
    }
    func recordRecent() async {
        do { try await store?.recordRecent(snapshot()) } catch { protectionMessage = error.localizedDescription }
    }
    func reportError(_ message: String) { errorMessage = message }
    func setReadOnly(_ value: Bool, side: ComparisonSide) {
        var buffer = buffer(for: side); buffer.isReadOnly = value; setBuffer(buffer, for: side)
    }
    func changeFormat(side: ComparisonSide, encoding: TextEncoding? = nil, lineEnding: LineEnding? = nil) {
        guard !isInteractionLocked, !buffer(for: side).isReadOnly else { return }
        let old = buffer(for: side)
        var updated = old
        if let encoding { updated.encoding = encoding }
        if let lineEnding {
            updated.lineEnding = lineEnding
            updated.originalSeparators = Array(repeating: lineEnding, count: updated.text.utf16.count { $0 == 10 })
        }
        guard old != updated else { return }
        updated.revision += 1; updated.isDirty = true
        setBuffer(updated, for: side)
        scheduleComparison(debounced: false)
        undoManager.registerUndo(withTarget: self) { target in target.restoreFormat(old, side: side) }
    }
    private func restoreFormat(_ snapshot: EditorBuffer, side: ComparisonSide) {
        guard buffer(for: side).documentID == snapshot.documentID else { return }
        let current = buffer(for: side)
        var updated = current
        updated.encoding = snapshot.encoding; updated.lineEnding = snapshot.lineEnding; updated.originalSeparators = snapshot.originalSeparators
        updated.isDirty = true; updated.revision += 1
        setBuffer(updated, for: side)
        scheduleComparison(debounced: false)
        undoManager.registerUndo(withTarget: self) { target in target.restoreFormat(current, side: side) }
    }
    private let worker: any ComparisonWorking
    private var comparisonTask: Task<Void, Never>?
    private var saveTasks: [UUID: Task<Bool, Never>] = [:]
    private(set) var savingDocuments: Set<UUID> = []
    private(set) var lastSaveError: TextFileWritingError?
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
        guard !isInteractionLocked else { return }
        draftTask?.cancel()
        id = UUID()
        undoManager.removeAllActions()
        comparisonTask?.cancel()
        invalidateLoads()
        result = nil
        leftBuffer = .blank(named: "左侧未命名")
        rightBuffer = .blank(named: "右侧未命名")
        selectedHunkID = nil
        errorMessage = nil
        isWorkspacePresented = true
        scheduleComparison(debounced: false)
    }

    func startSamples() {
        startBlank()
        leftBuffer = EditorBuffer.blank(named: "测试数据").updatingText(ComparisonSamples.left)
        rightBuffer = EditorBuffer.blank(named: "测试数据").updatingText(ComparisonSamples.right)
        scheduleComparison(debounced: false)
    }

    func start(leftURL: URL?, rightURL: URL?) async {
        startBlank()
        if let leftURL { await open(leftURL, for: .left) }
        if let rightURL { await open(rightURL, for: .right) }
    }

    func open(_ url: URL, for side: ComparisonSide, encodingOverride: TextEncoding? = nil) async {
        let original = buffer(for: side)
        let generation = (loadGenerations[side] ?? 0) + 1
        loadGenerations[side] = generation
        isWorking = true
        errorMessage = nil
        do {
            let file: ParsedTextFile
            if let encodingOverride {
                file = try await Task.detached { try TextFileLoader.load(from: url, encodingOverride: encodingOverride) }.value
            } else { file = try await worker.load(from: url) }
            guard loadGenerations[side] == generation else { return }
            guard buffer(for: side).documentID == original.documentID, buffer(for: side).revision == original.revision else {
                isWorking = false
                errorMessage = "加载期间内容已变化，已保留当前编辑，请重新打开文件。"
                return
            }
            setBuffer(EditorBuffer(file: file), for: side)
            result = nil
            selectedHunkID = nil
            scheduleComparison(debounced: false)
        } catch {
            guard loadGenerations[side] == generation else { return }
            errorMessage = error.localizedDescription
            isWorking = false
        }
        // Successful loading schedules comparison, which owns isWorking until its result arrives.
    }

    func edit(_ side: ComparisonSide, text: String) {
        guard !isInteractionLocked, !buffer(for: side).isReadOnly else { return }
        let updated = buffer(for: side).updatingText(text)
        guard updated != buffer(for: side) else { return }
        setBuffer(updated, for: side)
        scheduleComparison(debounced: true)
    }

    func edit(_ side: ComparisonSide, edit: TextEdit) {
        guard !isInteractionLocked, !buffer(for: side).isReadOnly else { return }
        do {
            let updated = try buffer(for: side).applying(edit)
            guard updated.revision != buffer(for: side).revision else { return }
            setBuffer(updated, for: side)
            scheduleComparison(debounced: true, edit: edit, side: side)
        } catch {
            errorMessage = "文本版本已变化，请重试编辑。"
        }
    }

    func swapBuffers() {
        guard !isInteractionLocked else { return }
        comparisonTask?.cancel()
        invalidateLoads()
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

    func save(_ side: ComparisonSide, to url: URL, force: Bool = false, confirmedModificationDate: Date? = nil) async -> Bool {
        let id = buffer(for: side).documentID
        while let pending = saveTasks[id] { _ = await pending.value; await Task.yield() }
        guard buffer(for: side).documentID == id else { return false }
        var snapshot = buffer(for: side)
        if let confirmedModificationDate { snapshot.lastKnownModificationDate = confirmedModificationDate }
        let task = Task { @MainActor [self] in
            savingDocuments.insert(id)
            defer { savingDocuments.remove(id) }
            lastSaveError = nil
            do {
                let date = try await worker.save(buffer: snapshot, to: url, force: force)
                guard let destination = ([ComparisonSide.left, .right].first { buffer(for: $0).documentID == id }) else { return true }
                var current = buffer(for: destination)
                let unchanged = current.revision == snapshot.revision
                current = current.markingSaved(to: url, modificationDate: date)
                current.isDirty = !unchanged
                setBuffer(current, for: destination)
                return true
            } catch {
                lastSaveError = error as? TextFileWritingError
                errorMessage = error.localizedDescription
                return false
            }
        }
        saveTasks[id] = task
        let success = await task.value
        saveTasks[id] = nil
        return success
    }

    @discardableResult
    func returnToLauncher(discardingChanges: Bool) -> Bool {
        guard discardingChanges || !hasUnsavedChanges else { return false }
        comparisonTask?.cancel()
        comparisonGeneration += 1
        invalidateLoads()
        isWorking = false
        isWorkspacePresented = false
        result = nil
        selectedHunkID = nil
        return true
    }

    func setOptions(_ newOptions: ComparisonOptions) {
        guard options != newOptions else { return }
        options = newOptions
        scheduleDraft()
        scheduleComparison(debounced: false)
    }

    func applyAllHunks(from source: ComparisonSide) {
        let sourceText = buffer(for: source).text
        edit(source == .left ? .right : .left, text: sourceText)
    }

    func dismissError() {
        errorMessage = nil
    }

    private func scheduleComparison(debounced: Bool, edit: TextEdit? = nil, side: ComparisonSide? = nil) {
        comparisonTask?.cancel()
        comparisonGeneration += 1
        let generation = comparisonGeneration
        let left = leftBuffer
        let right = rightBuffer
        let opts = options
        let worker = worker
        let previous = result
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
            do {
                let newResult: DiffResult
                if let previous, let edit, let side {
                    newResult = try await worker.compareIncrementally(previous: previous, left: left, right: right, edit: edit, side: side, options: opts)
                } else {
                    newResult = try await worker.compare(left: left, right: right, options: opts)
                }
                try Task.checkCancellation()
                guard let self, generation == self.comparisonGeneration, self.isWorkspacePresented else { return }
                self.result = newResult
                if !newResult.hunks.contains(where: { $0.id == self.selectedHunkID }) {
                    self.selectedHunkID = nil
                }
                self.isWorking = false
            } catch is CancellationError {
                // A newer request owns the state; cancelled work must not overwrite it.
            } catch {
                guard let self, generation == self.comparisonGeneration else { return }
                self.errorMessage = error.localizedDescription
                self.isWorking = false
            }
        }
    }

    private func invalidateLoads() {
        loadGenerations[.left, default: 0] += 1
        loadGenerations[.right, default: 0] += 1
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

    func buffer(for side: ComparisonSide) -> EditorBuffer {
        side == .left ? leftBuffer : rightBuffer
    }

    private func setBuffer(_ buffer: EditorBuffer, for side: ComparisonSide) {
        if side == .left { leftBuffer = buffer } else { rightBuffer = buffer }
        scheduleDraft()
    }
}
