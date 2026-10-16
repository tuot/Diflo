import Foundation

nonisolated enum MarkupPasteFormatter {
    private static let htmlNames: Set<String> = [
        "html", "head", "body", "div", "p", "section", "article", "main", "nav", "header", "footer",
        "ul", "ol", "li", "table", "thead", "tbody", "tr", "td", "th", "form", "h1", "h2", "h3",
        "span", "a", "b", "i", "strong", "em", "br", "hr", "img", "input", "meta", "link",
        "script", "style", "pre", "textarea", "title", "code", "button", "label", "select", "option",
        "a", "abbr", "address", "area", "aside", "audio", "base", "bdi", "bdo", "blockquote",
        "caption", "cite", "col", "colgroup", "data", "datalist", "dd", "del", "details", "dfn",
        "dialog", "dl", "dt", "embed", "fieldset", "figcaption", "figure", "h4", "h5", "h6",
        "hgroup", "iframe", "ins", "kbd", "legend", "map", "mark", "menu", "meter", "noscript",
        "object", "optgroup", "output", "picture", "progress", "q", "rp", "rt", "ruby", "s",
        "samp", "search", "slot", "small", "source", "sub", "summary", "sup", "template", "tfoot",
        "time", "track", "u", "var", "video", "wbr", "xmp", "noembed", "noframes", "plaintext"
    ]
    private static let blockNames: Set<String> = [
        "html", "head", "body", "div", "p", "section", "article", "main", "nav", "header", "footer",
        "ul", "ol", "li", "table", "thead", "tbody", "tr", "td", "th", "form", "h1", "h2", "h3",
        "hr", "meta", "link", "script", "style", "pre"
    ]
    private static let voidNames: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"
    ]
    private static let preservedNames: Set<String> = [
        "script", "style", "pre", "textarea", "title", "code", "xmp", "iframe", "noembed", "noframes", "noscript",
        "plaintext", "listing", "svg", "text", "tspan"
    ]

    static func format(_ source: String) -> String? {
        // CSS can make otherwise block-level whitespace significant.
        guard source.range(of: #"<style(?:\s|>)|\sstyle\s*="#,
                           options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        let pattern = #"<([A-Za-z][A-Za-z0-9:_.-]*)(?:\s|/?>)"#
        guard let match = source.range(of: pattern, options: .regularExpression) else { return nil }
        let firstTag = source[match].dropFirst().prefix(while: { !$0.isWhitespace && $0 != ">" && $0 != "/" })
        let html = htmlNames.contains(firstTag.lowercased()) && !source.hasPrefix("<?xml")
        if !html {
            // DTDs can define entities; avoid parsing or expanding them entirely.
            guard !source.contains("<!DOCTYPE") else { return nil }
            let parser = XMLParser(data: Data(source.utf8))
            parser.shouldResolveExternalEntities = false
            parser.externalEntityResolvingPolicy = .never
            guard parser.parse() else { return nil }
        }
        var cursor = source.startIndex
        var parts: [String] = []
        var roots = 0
        while cursor < source.endIndex {
            if source[cursor].isWhitespace { cursor = source.index(after: cursor); continue }
            guard let result = node(source, cursor: &cursor, depth: 0, html: html) else { return nil }
            parts.append(result.rendered)
            if result.name != nil { roots += 1 }
        }
        guard roots > 0 else { return nil }
        return parts.joined(separator: "\n")
    }

    private static func node(_ source: String, cursor: inout String.Index, depth: Int, html: Bool)
        -> (rendered: String, name: String?)? {
        guard depth < 128, source[cursor] == "<" else { return nil }
        let start = cursor
        let tail = source[cursor...]
        let indent = String(repeating: "  ", count: depth)
        for (opening, closing) in [("<!--", "-->"), ("<![CDATA[", "]]>"), ("<?", "?>")] {
            if tail.hasPrefix(opening) {
                guard let end = source.range(of: closing, range: cursor..<source.endIndex)?.upperBound else { return nil }
                cursor = end
                return (indent + source[start..<end], nil)
            }
        }
        guard let opening = tag(source, cursor: &cursor) else { return nil }
        if opening.lowercased() == "<!doctype html>" { return (indent + opening, nil) }
        guard let nameRange = opening.range(of: #"^<[A-Za-z][A-Za-z0-9:_.-]*"#, options: .regularExpression) else { return nil }
        let originalName = String(opening[nameRange].dropFirst())
        let name = html ? originalName.lowercased() : originalName
        if opening.hasSuffix("/>") || (html && voidNames.contains(name)) {
            return (indent + opening, name)
        }
        if html && preservedNames.contains(name) {
            guard let closing = source.range(of: "</\(name)>", options: .caseInsensitive, range: cursor..<source.endIndex) else { return nil }
            cursor = closing.upperBound
            return (indent + source[start..<cursor], name)
        }
        var children: [String] = []
        var preserve = opening.contains("xml:space") || (!html && preservedNames.contains(name))
        while cursor < source.endIndex {
            if source[cursor...].hasPrefix("</") {
                guard let closing = tag(source, cursor: &cursor) else { return nil }
                let closeName = closing.dropFirst(2).dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
                guard (html ? closeName.lowercased() : closeName) == name else { return nil }
                if preserve || children.isEmpty { return (indent + source[start..<cursor], name) }
                return (indent + opening + "\n" + children.joined(separator: "\n") + "\n" + indent + closing, name)
            }
            if source[cursor] == "<" {
                let isCDATA = source[cursor...].hasPrefix("<![CDATA[")
                guard let child = node(source, cursor: &cursor, depth: depth + 1, html: html) else { return nil }
                children.append(child.rendered)
                if isCDATA || child.name.map({
                    !blockNames.contains($0.lowercased()) && (html || htmlNames.contains($0.lowercased()))
                }) == true { preserve = true }
            } else {
                let end = source[cursor...].firstIndex(of: "<") ?? source.endIndex
                if !source[cursor..<end].allSatisfy(\.isWhitespace) { preserve = true }
                cursor = end
            }
        }
        return nil
    }

    /// Finds a tag boundary without treating a quoted '>' as its end.
    private static func tag(_ source: String, cursor: inout String.Index) -> String? {
        let start = cursor
        var quote: Character?
        while cursor < source.endIndex {
            let character = source[cursor]
            cursor = source.index(after: cursor)
            if let current = quote {
                if character == current { quote = nil }
            } else if character == "\"" || character == "'" { quote = character }
            else if character == ">" { return String(source[start..<cursor]) }
        }
        return nil
    }
}
