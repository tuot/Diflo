# DiffZen 本地 CodeMirror Meld 式对比设计

## 文档状态

本设计取代 `2026-08-18-meld-style-comparison-design.md` 中基于双 `NSTextView`、自绘行号与独立滚动同步的编辑器实现。产品范围仍是单窗口、单会话、双向文本对比；文件读写继续使用原生 macOS API，编辑与 Diff 展示改由 App 内本地 CodeMirror 6 `MergeView` 负责。

## 目标与原则

第一版提供接近 Meld 的核心文件对比体验：左右文本可编辑，差异块垂直对齐，中间展示连接关系并允许双向应用，右侧总览展示全文差异分布。

实现遵循以下原则：

- SwiftUI/AppKit 负责窗口、工具栏、文件面板、菜单、保存确认与错误提示。
- `WKWebView` 只承载编辑器、差异布局、中央操作带和差异总览。
- HTML、JavaScript、CSS 与字体配置全部打包进 App，不访问网络或加载远程代码。
- CodeMirror 是编辑文本、Undo、选区与 Diff chunk 的唯一事实来源；Swift 不重复计算用于渲染的 Diff。
- 跨 Swift/JavaScript 边界传递命令、增量状态和按需快照，不在每次按键后复制完整文档。

## 第一版范围

包含：

- 从两个文件、单个文件加空白侧，或两个空白缓冲区创建对比。
- 左右两侧打开、替换、编辑、保存和另存为。
- 行号、固定行高、关闭自动换行、独立水平滚动和统一垂直滚动。
- 整行及行内差异高亮，未变化内容垂直对齐。
- 中央差异连接带、左右双向应用按钮和删除当前侧差异块。
- 上一个、下一个差异块导航。
- 右侧差异总览及点击定位。
- 每侧 Undo/Redo、dirty 状态、编码、换行符和光标行列显示。
- 返回、替换、关闭前的未保存确认，以及外部文件修改检测。

不包含目录对比、三方合并、Git 集成、多标签、语法高亮、文本过滤器、自动换行和远程资源。

## 总体架构

```text
SwiftUI / AppKit
  ├─ ComparisonSession：页面状态、文件元数据、dirty、错误与命令入口
  ├─ TextFileLoader / TextFileWriter：编码、换行符、安全范围和原子保存
  └─ WebComparisonView：WKWebView 生命周期与 Codable 消息桥
             ⇅ 本地消息协议
Bundled Web Editor
  ├─ CodeMirror MergeView：文本、选区、Undo、Diff chunks 与垂直对齐
  ├─ MergeOperations：双向应用、删除与导航
  ├─ ConnectorOverlay：可见 chunk 的 SVG 连接形状和操作按钮
  └─ DiffOverview：全文差异分布与点击定位
```

旧的 `DualDiffContainerView`、`DiffTextView`、`LineNumberRulerView`、`ChangeGutterView`、`DiffOverviewView`、原生渲染用 `DiffRow` 和 `LineDiffEngine` 不再参与产品路径。若旧类型没有独立测试价值或文件读写依赖，随新实现删除，避免同时维护两套 Diff 事实来源。

## Web 资源与依赖

Web 源码放在 `WebEditor/`，使用 TypeScript、CSS、CodeMirror 6 和轻量打包器生成单个 JavaScript bundle。依赖版本由 lockfile 固定。生成后的 `editor.html`、`editor.js` 和 `editor.css` 作为 Xcode 资源随 App 打包，正常 Xcode Build 不运行 npm，也不需要网络。

`WKWebView` 通过 `loadFileURL(_:allowingReadAccessTo:)` 只读取编辑器资源目录。导航代理拒绝离开本地入口页；页面设置 Content Security Policy，禁止网络、iframe、插件及非 bundle 脚本。

## 编辑器布局

编辑区使用三列结构：左编辑器、中央操作带、右编辑器。CodeMirror `MergeView` 负责两个编辑器及 spacer 对齐；中央操作带覆盖在 MergeView 的两栏之间，不建立第三套滚动模型。

中央操作带根据 `MergeView.chunks` 和两个 `EditorView.lineBlockAt` 的可见几何信息绘制 SVG 贝塞尔连接形状。只创建当前 viewport 附近的连接元素；编辑、滚动、窗口缩放和字体变化后，在 `requestAnimationFrame` 测量阶段统一更新。

每个可见差异块同时显示：

- `→`：把左侧 chunk 应用到右侧。
- `←`：把右侧 chunk 应用到左侧。
- 更多菜单：删除左侧块或删除右侧块。

连接形状只表达对应关系，按钮具有独立点击区域、键盘焦点和无障碍标签。颜色不作为唯一信息来源；左右 gutter 继续显示差异标记。

右侧差异总览按 chunk 在文档位置中的比例绘制。点击标记选择该 chunk，并调用 CodeMirror 导航和滚动 API。总览不自行解析文本。

## 差异块操作

CodeMirror `Chunk` 的 `fromA/toA/fromB/toB` 是所有合并操作的范围来源。应用操作直接向目标 `EditorView` dispatch 一次 transaction：

- 两侧均有内容时替换目标范围。
- 源侧有内容、目标侧为空时插入。
- 源侧为空、目标侧有内容时删除。

transaction 使用明确的 `userEvent`，进入目标编辑器的 Undo 历史。操作后目标侧获得焦点并选中修改范围；新的 chunks 产生后选择最接近原位置的剩余差异块。任何操作都不使用 Swift 保存的旧行号反推范围。

## Swift 与 JavaScript 消息协议

所有消息包含 `type` 和单调递增的 `revision`，负载使用可验证的字典结构。未知类型、缺少字段或过期 revision 被忽略并记录诊断信息。

Swift 发往 Web：

- `loadSession`：首次传入左右文本、显示名和初始 revision。
- `replaceDocument`：用户重新打开某一侧文件时替换该侧文档并重置 Undo。
- `navigateChunk`：上一个、下一个或指定 chunk。
- `applyChunk` / `deleteChunk`：来自原生菜单或工具栏的操作。
- `requestSnapshot`：保存时按 request ID 请求某侧完整文本和当前 revision。
- `markSaved`：仅当 revision 仍匹配保存快照时清除 dirty。
- `setAppearance`：浅色/深色、强调色和文字缩放变化。

Web 发往 Swift：

- `ready`：编辑器资源加载完成。
- `documentChanged`：侧别、revision、dirty；不附带完整文本。
- `selectionChanged`：侧别、行、列和是否处于 IME 组合输入。
- `chunksChanged`：chunk 数量、当前索引和可导航状态。
- `snapshot`：request ID、侧别、revision 和完整文本。
- `command`：保存、另存为等需要原生界面处理的快捷键。
- `error`：可恢复的 Web 初始化或命令错误。

Swift 只在加载、替换和保存快照时跨桥传递完整文本。关闭确认依赖 dirty 状态，不为确认动作请求文本。

## 会话与文件保存

`ComparisonSession` 保存两侧文件元数据、当前 revision、dirty、加载/保存状态和当前差异索引，不再为每次输入维护完整 Swift 文本副本。

保存流程：

1. Swift 请求目标侧快照。
2. Web 返回文本和 revision。
3. Swift 按记录的换行符和编码进行无损编码。
4. `TextFileWriter` 检查外部修改并原子写入。
5. 成功后向 Web 发送带 revision 的 `markSaved`；若保存期间又发生编辑，写入成功但编辑器继续保持 dirty。

打开的文件继续保留 UTF-8、UTF-16、ASCII 等已识别编码和 LF、CRLF、CR。无法无损编码时提示改用 UTF-8，不静默替换字符。

## 性能策略

- 保持单侧 10 MB、20,000 行上限。
- 默认纯文本、不加载语言包、不启用语法树和自动换行。
- 使用 CodeMirror viewport 虚拟渲染和增量 chunk 更新。
- 中央 SVG 与总览只处理可见 chunk 或预计算的轻量位置比例。
- 不在 `documentChanged` 中序列化完整文档。
- 一次加载整份新文本时重建对应 EditorState，不用数万个小 transaction 拼接。
- 对几乎完全不同或含超长行的文档允许 Diff 算法使用扫描上限；界面必须保持可编辑，并显示“差异结果已采用快速模式”。

性能验收在当前开发 Mac 上使用 Release 构建执行：

- 两侧各 20,000 行、约 5 MB 的典型文本，从发送 `loadSession` 到首屏可交互不超过 2 秒。
- 上述文档完成首次加载后，单行输入到差异高亮更新的 P95 不超过 100 毫秒。
- 连续输入、快速滚动和连续应用 20 个 chunk 时无明显空白帧或滚动跳跃。
- 两侧各 10 MB 的上限文件不得崩溃；若首次 Diff 超过 3 秒，显示进度并允许取消或进入快速模式。

## macOS 契合

窗口、工具栏、文件面板、确认对话框、菜单和状态栏保持原生。编辑器使用系统字体栈与 `ui-monospace`，从 Swift 同步浅色/深色、强调色和 Reduce Motion。

CodeMirror 启用 macOS 标准快捷键和 Emacs 风格移动键。Swift 菜单的保存、另存为、查找、Undo 和 Redo 转发到当前聚焦的 Web 编辑器；复制、剪切、粘贴和全选由 WebKit 文本输入系统处理。

专项验证中文拼音组合输入、Emoji、死键、Option/Cmd 光标移动、触控板滚动、窗口缩放、VoiceOver 标签和键盘遍历。系统拼写、智能引号和 macOS Services 不作为第一版验收要求。

## 错误与恢复

- Web 资源加载失败时显示原生错误页，可重新加载编辑器，不清除已加载的文件元数据。
- Bridge 消息解析失败不执行操作，并在 Debug 日志记录类型和 revision，不记录文档正文。
- 保存失败保留 dirty，原文件不被部分覆盖。
- Web content process 终止后重建 WKWebView；若存在未保存编辑且没有可用快照，明确告知用户无法自动恢复，不伪造已保存状态。
- 用户取消打开、保存或关闭确认时保持当前会话不变。

## 测试策略

遵循红—绿—重构：

- JavaScript 单元测试覆盖 chunk 双向替换、插入、删除、尾换行、revision 和消息校验。
- Swift 单元测试覆盖消息 Codable、会话 revision、快照保存竞态、编码、换行符与外部修改。
- WKWebView 集成测试加载真实 bundle，覆盖 ready、加载两侧文本、编辑回调、chunk 数量、导航、双向应用、Undo 和快照。
- UI 烟测覆盖空白对比、文件对比、编辑、中央按钮、保存和未保存关闭确认。
- 性能测试使用固定生成器构造相同、局部不同、完全不同和超长行四组数据。
- 人工验收中文 IME、VoiceOver、键盘菜单和深浅色，因为这些行为不适合只依赖自动化断言。

## 验收标准

- 左右编辑器在插入、删除和不等长替换块中保持对应未变化内容垂直对齐。
- 中央连接形状与实际 chunk 一致，双向按钮修改正确目标且可以 Undo。
- 行号、高亮、连接带、导航和差异总览全部消费同一组 CodeMirror chunks。
- 快速编辑时旧 revision 不覆盖新状态，保存期间继续编辑不会错误清除 dirty。
- App 完全离线工作，编辑器页面不能导航或请求远程资源。
- 文件编码、换行符、尾部换行和外部修改保护符合原有产品要求。
- 达到性能策略中的可交互、输入延迟和上限文件指标。

