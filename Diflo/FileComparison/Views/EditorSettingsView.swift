import SwiftUI

struct EditorSettingsView: View {
    @Bindable var preferences = EditorPreferences.shared
    var body: some View {
        Form {
            Slider(value: $preferences.fontSize, in: 10...28, step: 1) {
                Text("字号：\(Int(preferences.fontSize))")
            }
            Picker("Tab 宽度", selection: $preferences.tabWidth) {
                ForEach([2, 4, 8], id: \.self) { Text("\($0) 个空格").tag($0) }
            }
            Toggle("自动换行", isOn: $preferences.wrapLines)
            Toggle("显示空白字符", isOn: $preferences.showWhitespace)
            Text("设置自动保存，并应用到所有对比窗口。")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).frame(width: 420).padding()
    }
}
