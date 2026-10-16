import Foundation

/// A deliberately small, lossless subset of YAML block mappings and scalar lists.
/// Multiline scalars, flow collections, tags and anchors are left untouched.
nonisolated enum YAMLPasteFormatter {
    static func format(_ source: String) -> String? {
        var indents = [0]
        var kinds = [Bool?](repeating: nil, count: 1)
        var keys = [Set<String>()]
        var canNest = false
        var entries = 0
        var output: [String] = []
        for line in source.components(separatedBy: "\n") {
            let body = String(line.drop(while: { $0 == " " }))
            guard !body.contains("\t") else { return nil }
            if body.isEmpty || body.hasPrefix("#") {
                output.append(line)
                continue
            }
            if body == "---", entries == 0 { output.append(body); continue }
            let indent = line.count - body.count
            if indent > indents.last! {
                guard canNest, indents.count < 128 else { return nil }
                indents.append(indent)
                kinds.append(nil)
                keys.append([])
            } else {
                while indents.count > 1, indent < indents.last! {
                    indents.removeLast(); kinds.removeLast(); keys.removeLast()
                }
                guard indent == indents.last! else { return nil }
            }
            let level = indents.count - 1
            let isList = body.hasPrefix("- ")
            if let kind = kinds[level], kind != isList { return nil }
            kinds[level] = isList
            let formatted: String
            if isList {
                let value = String(body.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard scalar(value), !value.isEmpty else { return nil }
                formatted = "- " + value
                canNest = false
            } else {
                guard let colon = body.firstIndex(of: ":") else { return nil }
                let key = String(body[..<colon])
                guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil,
                      keys[level].insert(key).inserted else { return nil }
                let remainder = body[body.index(after: colon)...]
                guard remainder.isEmpty || remainder.first == " " else { return nil }
                let value = remainder.trimmingCharacters(in: .whitespaces)
                guard scalar(value) else { return nil }
                formatted = key + ":" + (value.isEmpty ? "" : " " + value)
                canNest = value.isEmpty
            }
            entries += 1
            output.append(String(repeating: "  ", count: level) + formatted)
        }
        // One prose line with a colon is not enough evidence of YAML.
        guard entries >= 2 else { return nil }
        return output.joined(separator: "\n")
    }

    private static func scalar(_ value: String) -> Bool {
        guard let first = value.first else { return true }
        if first == "\"" {
            return (try? JSONSerialization.jsonObject(with: Data(value.utf8), options: .fragmentsAllowed)) is String
        }
        if first == "'" {
            return value.range(of: #"^'(?:[^']|'')*'$"#, options: .regularExpression) != nil
        }
        guard !"[]{}|>&*!%@`#?:,-".contains(first),
              !value.contains(": "), !value.hasSuffix(":"),
              !value.contains("["), !value.contains("]"),
              !value.contains("{"), !value.contains("}") else { return false }
        return true
    }
}
