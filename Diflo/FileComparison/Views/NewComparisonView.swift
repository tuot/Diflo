import SwiftUI

struct NewComparisonView: View {
    let session: ComparisonSession
    var fileActions: ComparisonFileActions? = nil
    @State private var drafts: [ComparisonSnapshot] = []
    @State private var recent: [RecentComparison] = []
    @State private var isOpening = false

    @State private var leftURL: URL?
    @State private var rightURL: URL?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("新建对比")
                    .font(.largeTitle.weight(.semibold))
                Text("选择两个文本文件，或从空白内容开始")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                FileChoiceCard(side: .left, url: leftURL, choose: chooseLeft, onDropURL: { leftURL = $0 })
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                FileChoiceCard(side: .right, url: rightURL, choose: chooseRight, onDropURL: { rightURL = $0 })
            }
            HStack(spacing: 12) {
                Button("空白对比", systemImage: "doc.badge.plus", action: session.startBlank)
                    .controlSize(.large)
                Button("开始对比", systemImage: "arrow.right", action: startComparison)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(leftURL == nil && rightURL == nil)
            }
            Button("体验示例", action: session.startSamples)
                .buttonStyle(.link)
            if !drafts.isEmpty || !recent.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !drafts.isEmpty {
                            Text("恢复未保存的对比").font(.headline)
                            ForEach(drafts) { draft in
                                HStack {
                                    Button(draft.title) { Task { await restore(draft) } }
                                    draftSaveTime(draft.updatedAt)
                                    Spacer()
                                    Button("删除") { Task {
                                        do { try await ComparisonStore.shared.deleteDraft(id: draft.id, generation: Int.max); await refresh() }
                                        catch { session.reportError(error.localizedDescription) }
                                    } }
                                }
                            }
                        }
                        if !recent.isEmpty {
                            HStack {
                                Text("最近对比").font(.headline)
                                Spacer()
                                Button("清空记录") { Task {
                                    do { try await ComparisonStore.shared.removeRecent(id: nil); await refresh() }
                                    catch { session.reportError(error.localizedDescription) }
                                } }
                            }
                            ForEach(recent) { item in
                                HStack {
                                    Button(item.title) { Task { await reopen(item) } }
                                    Spacer()
                                    Button("移除") { Task {
                                        do { try await ComparisonStore.shared.removeRecent(id: item.id); await refresh() }
                                        catch { session.reportError(error.localizedDescription) }
                                    } }
                                }
                            }
                        }
                    }.frame(maxWidth: 650)
                }.frame(maxHeight: 200)
            }
            Spacer()
        }
        .disabled(isOpening)
        .task { await refresh() }
        .padding(40)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func draftSaveTime(_ date: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let elapsed = context.date.timeIntervalSince(date)
            if elapsed < 60 {
                Text("刚刚保存")
            } else if elapsed < 3_600 {
                Text("\(Int(elapsed / 60)) 分钟前保存")
            } else {
                Text("保存于 \(date.formatted(.dateTime.month().day().hour().minute()))")
            }
        }
        .foregroundStyle(.secondary)
    }

    private func refresh() async {
        do {
            drafts = try await ComparisonStore.shared.drafts()
            let warnings = await ComparisonStore.shared.draftWarnings()
            if !warnings.isEmpty { session.reportError(warnings.joined(separator: "\n")) }
            recent = try await ComparisonStore.shared.recentComparisons()
        } catch { session.reportError("无法读取本地记录：\(error.localizedDescription)") }
    }
    private func restore(_ snapshot: ComparisonSnapshot) async {
        guard await ComparisonStore.shared.claimDraft(id: snapshot.id) else { await refresh(); return }
        session.restore(snapshot)
        if let url = session.leftBuffer.url { fileActions?.retainAccess(url) }
        if let url = session.rightBuffer.url { fileActions?.retainAccess(url) }
        await fileActions?.checkExternalChanges()
    }
    private func reopen(_ recent: RecentComparison) async {
        var left = recent.left.resolve(), right = recent.right.resolve()
        if let url = left, !FileManager.default.fileExists(atPath: url.path) { left = FilePanel.openTextFile(); guard left != nil else { return } }
        if let url = right, !FileManager.default.fileExists(atPath: url.path) { right = FilePanel.openTextFile(); guard right != nil else { return } }
        if let left { fileActions?.retainAccess(left) }
        if let right { fileActions?.retainAccess(right) }
        await session.start(leftURL: left, rightURL: right)
        session.setOptions(recent.options)
        await session.recordRecent()
    }
    private func chooseLeft() { leftURL = FilePanel.openTextFile() }
    private func chooseRight() { rightURL = FilePanel.openTextFile() }

    private func startComparison() {
        let leftURL = leftURL
        let rightURL = rightURL
        if let leftURL { fileActions?.retainAccess(leftURL) }
        if let rightURL { fileActions?.retainAccess(rightURL) }
        Task {
            isOpening = true
            await session.start(leftURL: leftURL, rightURL: rightURL)
            await session.recordRecent()
            isOpening = false
        }
    }
}
