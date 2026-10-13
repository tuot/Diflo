import SwiftUI

private struct ComparisonUndoManagerKey: FocusedValueKey {
    typealias Value = UndoManager
}

extension FocusedValues {
    var comparisonUndoManager: UndoManager? {
        get { self[ComparisonUndoManagerKey.self] }
        set { self[ComparisonUndoManagerKey.self] = newValue }
    }
}

struct ComparisonUndoCommands: Commands {
    @FocusedValue(\.comparisonUndoManager) private var undoManager

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("撤销") { undoManager?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(undoManager == nil)
            Button("重做") { undoManager?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(undoManager == nil)
        }
    }
}
