import SwiftUI

@main
struct DifloApp: App {
    @NSApplicationDelegateAdaptor(ComparisonApplicationDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Diflo", id: "comparison") {
            ContentView()
        }
        .defaultSize(width: 1_080, height: 720)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            ComparisonUndoCommands()
            ComparisonFindCommands()
            ComparisonWorkspaceCommands()
            AppInformationCommands()
        }
        Settings { EditorSettingsView() }
        Window("Diflo 使用帮助", id: "help") { AppHelpView() }.defaultSize(width: 650, height: 620)
        Window("隐私说明", id: "privacy") { PrivacyInformationView() }.defaultSize(width: 650, height: 560)
    }
}
