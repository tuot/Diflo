import SwiftUI

struct AppHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Diflo 使用帮助").font(.largeTitle)
                Text("选择两个文本文件，或创建空白对比后输入、粘贴文本。点击文件标题或将文件拖到标题上可替换该侧。")
                Text("比较与合并").font(.headline)
                Text("使用 ⌘↑ / ⌘↓ 跳转差异，点击中央箭头采纳一侧内容。末尾换行也是独立差异。粗略比较可能扩大合并范围，请先检查目标内容；⌘Z 可撤销。忽略规则只影响比较，不会修改文件。")
                Text("保存与恢复").font(.headline)
                Text("⌘S 保存最后聚焦的编辑侧；⇧⌘S 另存为。文件菜单提供全部保存、重新加载与编码操作。关闭或退出前会询问未保存修改。未保存内容在停止编辑约 1 秒后保存为本地草稿，下次启动可选择恢复。突然断电前尚未写入的内容可能无法恢复。")
                Text("编辑").font(.headline)
                Text("普通粘贴保留原文；⌥⇧⌘V 明确格式化后粘贴。⌘F 查找；⌘L 跳转到行；⌘+ / ⌘− 缩放字号。设置中可调整字号、Tab 宽度、自动换行和空白显示；比较菜单可将当前侧设为只读。")
                Text("文件格式与限制").font(.headline)
                Text("支持文本文件，导入上限 10 MiB、20,000 行。二进制和不能解码的文件会拒绝打开。内部统一使用 LF，保存时保留原编码、BOM 与混合换行；新增换行继承前一行的换行格式，首行采用文件默认格式。主动转换编码或换行会标为未保存。")
                Text("问题排查").font(.headline)
                Text("文件被其他应用修改时，请重新加载、另存为或明确覆盖；重新加载会替换当前编辑。权限失效时重新选择文件。如果草稿保存失败，提示栏会说明原因，请及时手动保存。")
            }.textSelection(.enabled).padding(28).frame(maxWidth: 680, alignment: .leading)
        }.frame(minWidth: 500, minHeight: 400)
    }
}
