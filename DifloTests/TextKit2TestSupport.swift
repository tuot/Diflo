import AppKit
@testable import Diflo

@MainActor
final class TextKit2FragmentCounter: NSObject, NSTextLayoutManagerDelegate {
    var fragments = 0

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        fragments += 1
        return NSTextLayoutFragment(textElement: textElement, range: nil)
    }
}

@MainActor
func inlineBackground(in editor: DiffTextView, at offset: Int) -> NSColor? {
    guard let manager = editor.textLayoutManager,
          let content = manager.textContentManager,
          let location = content.location(content.documentRange.location, offsetBy: offset) else { return nil }
    var color: NSColor?
    manager.enumerateRenderingAttributes(from: location, reverse: false) { _, attributes, range in
        let start = content.offset(from: content.documentRange.location, to: range.location)
        let end = content.offset(from: content.documentRange.location, to: range.endLocation)
        if start <= offset, offset < end { color = attributes[.backgroundColor] as? NSColor }
        return false
    }
    return color
}
