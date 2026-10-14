import AppKit
import SwiftUI

struct ComparisonFindCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .textEditing) {
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
