import Foundation

/// Only returns a replacement when the content can be formatted conservatively.
nonisolated enum PasteFormatter {
    static func format(_ text: String) -> String? {
        // Formatting runs before insertion; bound the work on the editor's main thread.
        guard text.utf8.count <= 1_000_000 else { return nil }
        let normalized = LineParser.normalize(text)
        let source = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }
        let formatted: String?
        switch source.first {
        case "{", "[": formatted = json(source)
        case "<": formatted = MarkupPasteFormatter.format(source)
        default: formatted = YAMLPasteFormatter.format(normalized)
        }
        guard let formatted else { return nil }
        return formatted + (normalized.hasSuffix("\n") && !formatted.hasSuffix("\n") ? "\n" : "")
    }

    private static func json(_ source: String) -> String? {
        // Validate, but format the original tokens: decoding and re-encoding can
        // round large numbers, reorder keys, or drop duplicate keys.
        guard (try? JSONSerialization.jsonObject(with: Data(source.utf8))) != nil else { return nil }
        var output = ""
        var depth = 0
        var inString = false
        var escaped = false
        var previous: Character?
        let characters = Array(source)
        func newline() { output += "\n" + String(repeating: "  ", count: depth) }
        for (index, character) in characters.enumerated() {
            if inString {
                output.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            guard !character.isWhitespace else { continue }
            switch character {
            case "\"":
                inString = true
                output.append(character)
            case "{", "[":
                output.append(character)
                depth += 1
                guard depth <= 128 else { return nil }
                if let next = characters[(index + 1)...].first(where: { !$0.isWhitespace }), next != "}", next != "]" {
                    newline()
                }
            case "}", "]":
                guard previous != "," else { return nil }
                depth -= 1
                if previous != "{", previous != "[" { newline() }
                output.append(character)
            case ",": output.append(character); newline()
            case ":": output += ": "
            default: output.append(character)
            }
            previous = character
        }
        return output
    }
}
