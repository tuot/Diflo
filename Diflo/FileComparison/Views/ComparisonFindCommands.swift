import AppKit
import SwiftUI

struct ComparisonFindCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("跳转到行…") { NSApp.sendAction(#selector(DiffTextView.goToLine(_:)), to: nil, from: nil) }
                .keyboardShortcut("l", modifiers: .command)
            Button("放大文字") { EditorPreferences.shared.fontSize += 1 }.keyboardShortcut("+", modifiers: .command)
            Button("缩小文字") { EditorPreferences.shared.fontSize -= 1 }.keyboardShortcut("-", modifiers: .command)
            Button("恢复默认字号") { EditorPreferences.shared.fontSize = 14 }.keyboardShortcut("0", modifiers: .command)
            Button("格式化后粘贴") {
                NSApp.sendAction(#selector(DiffTextView.pasteFormatted(_:)), to: nil, from: nil)
            }.keyboardShortcut("v", modifiers: [.command, .option, .shift])
            Menu {
                Button { perform(.showFindInterface) } label: {
                    Text(.editorFindOpen)
                }
                .keyboardShortcut("f", modifiers: .command)
                Button { perform(.nextMatch) } label: {
                    Text(.editorFindNext)
                }
                .keyboardShortcut("g", modifiers: .command)
                Button { perform(.previousMatch) } label: {
                    Text(.editorFindPrevious)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            } label: {
                Text(.editorFindMenu)
            }
        }
    }

    private func perform(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.action = #selector(NSTextView.performTextFinderAction(_:))
        item.tag = action.rawValue
        NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: item)
    }
}
