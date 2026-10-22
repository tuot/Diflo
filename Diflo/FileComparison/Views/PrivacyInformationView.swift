import SwiftUI

struct PrivacyInformationView: View {
    @State private var confirming = false
    @State private var message: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("隐私说明").font(.largeTitle)
                Text("文本在本机处理").font(.headline)
                Text("Diflo 在本地读取、比较和编辑你选择的文件。当前版本没有账号、广告、跟踪或将文件上传到服务器的功能。")
                Text("本地保存的数据").font(.headline)
                Text("为恢复工作，应用会在沙盒的 Application Support/Diflo 目录保存未保存的左右文本、文件位置和授权书签、编码、比较选项及光标位置。草稿包含你输入的内容，请按文件本身的敏感程度管理。最近对比最多记录 20 组文件位置和授权书签，不保存正文；编辑偏好保存在应用自己的设置中。")
                Text("清除数据").font(.headline)
                Text("首页可单独删除草稿、移除或清空最近记录。关闭对比时明确丢弃，或保存后结束对比，都会删除对应草稿。下方操作仅清除未被窗口使用的恢复草稿与最近记录，当前窗口内容保留。")
                Button("清除恢复草稿与最近记录…", role: .destructive) { confirming = true }
                if let message { Text(message).font(.callout) }
                Text("文件授权").font(.headline)
                Text("应用仅通过你选择或拖入的文件获得访问权限。授权书签用于下次重新打开文件；文件移动或系统权限改变后，可能需要重新选择。")
            }.textSelection(.enabled).padding(28).frame(maxWidth: 680, alignment: .leading)
        }.frame(minWidth: 500, minHeight: 400)
        .confirmationDialog("清除本地恢复草稿与最近记录？", isPresented: $confirming) {
            Button("清除", role: .destructive) { Task {
                do {
                    let drafts = try await ComparisonStore.shared.drafts()
                    for draft in drafts { try await ComparisonStore.shared.deleteDraft(id: draft.id, generation: Int.max) }
                    try await ComparisonStore.shared.removeRecent(id: nil)
                    message = "本地恢复草稿与最近记录已清除。"
                } catch { message = "未能清除：\(error.localizedDescription)" }
            } }
            Button("取消", role: .cancel) {}
        }
    }
}

struct AppInformationCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Diflo 使用帮助") { openWindow(id: "help") }
            Button("隐私说明") { openWindow(id: "privacy") }
        }
    }
}
