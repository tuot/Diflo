import SwiftUI

@main
struct DifloApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1_080, height: 720)
        .commands {
            ComparisonUndoCommands()
            ComparisonFindCommands()
        }
    }
}
