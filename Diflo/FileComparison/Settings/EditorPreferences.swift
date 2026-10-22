import Foundation
import Observation

@MainActor @Observable final class EditorPreferences {
    static let shared = EditorPreferences()
    private let defaults: UserDefaults
    private var storedFontSize: Double
    private var storedTabWidth: Int
    var fontSize: Double {
        get { storedFontSize }
        set { storedFontSize = min(28, max(10, newValue.isFinite ? newValue : 14)); defaults.set(storedFontSize, forKey: "editor.fontSize") }
    }
    var tabWidth: Int {
        get { storedTabWidth }
        set { storedTabWidth = [2, 4, 8].contains(newValue) ? newValue : 4; defaults.set(storedTabWidth, forKey: "editor.tabWidth") }
    }
    var wrapLines: Bool { didSet { defaults.set(wrapLines, forKey: "editor.wrapLines") } }
    var showWhitespace: Bool { didSet { defaults.set(showWhitespace, forKey: "editor.showWhitespace") } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let size = defaults.object(forKey: "editor.fontSize") as? Double ?? 14
        storedFontSize = min(28, max(10, size.isFinite ? size : 14))
        let tabs = defaults.object(forKey: "editor.tabWidth") as? Int ?? 4
        storedTabWidth = [2, 4, 8].contains(tabs) ? tabs : 4
        wrapLines = defaults.bool(forKey: "editor.wrapLines")
        showWhitespace = defaults.bool(forKey: "editor.showWhitespace")
    }
}
