import Foundation

/// Reads the one part of a workflow file Cleared cares about: whether it can be
/// started by hand, and with which inputs.
///
/// GitHub's API lists workflows but not their triggers, so the only way to know
/// a workflow accepts `workflow_dispatch` is to read the file. This is not a
/// YAML parser. It understands block mappings, block and flow sequences of
/// scalars, quoting and comments — the shapes an `on:` block is written in —
/// and it only ever looks inside `on:`, so nothing a job does can confuse it.
enum WorkflowFile {
    /// The inputs a manual run accepts, or nil when the workflow has no
    /// `workflow_dispatch` trigger and cannot be started by hand at all.
    static func dispatchInputs(in yaml: String) -> [WorkflowInput]? {
        let lines = significantLines(of: yaml)
        guard let onIndex = lines.firstIndex(where: { $0.indent == 0 && splitKey($0.text)?.key == "on" }),
              let inline = splitKey(lines[onIndex].text)?.value
        else { return nil }

        let trigger = "workflow_dispatch"

        // on: workflow_dispatch   /   on: [push, workflow_dispatch]   /   on: { workflow_dispatch: … }
        if !inline.isEmpty {
            if inline.hasPrefix("{") { return inline.contains(trigger) ? [] : nil }
            return flowItems(inline).contains(trigger) ? [] : nil
        }

        var index = onIndex + 1
        guard index < lines.count, lines[index].indent > 0 || lines[index].isSequenceItem else { return nil }

        switch parseValue(lines, &index) {
        case .list(let events):
            return events.contains(trigger) ? [] : nil
        case .scalar:
            return nil
        case .map(let events):
            guard let dispatch = events.first(where: { $0.key == trigger })?.value else { return nil }
            guard case .map(let settings) = dispatch,
                  case .map(let declared)? = settings.first(where: { $0.key == "inputs" })?.value
            else { return [] }
            return declared.map { input(named: $0.key, from: $0.value) }
        }
    }

    private static func input(named name: String, from node: Node) -> WorkflowInput {
        var fields: [String: Node] = [:]
        if case .map(let pairs) = node {
            for pair in pairs { fields[pair.key] = pair.value }
        }
        func text(_ key: String) -> String {
            if case .scalar(let value)? = fields[key] { return value }
            return ""
        }

        let kind: WorkflowInput.Kind
        switch text("type") {
        case "boolean": kind = .boolean
        case "number": kind = .number
        case "environment": kind = .environment
        case "choice":
            if case .list(let options)? = fields["options"] { kind = .choice(options) } else { kind = .string }
        default: kind = .string
        }

        return WorkflowInput(
            name: name,
            description: text("description"),
            kind: kind,
            isRequired: text("required").lowercased() == "true",
            defaultValue: text("default")
        )
    }

    // MARK: - A deliberately small reader

    private indirect enum Node {
        case scalar(String)
        case list([String])
        case map([(key: String, value: Node)])
    }

    private struct Line {
        let indent: Int
        let text: String
        var isSequenceItem: Bool { text == "-" || text.hasPrefix("- ") }
    }

    private static func significantLines(of yaml: String) -> [Line] {
        yaml.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).compactMap { raw in
            let uncommented = stripComment(String(raw))
            let text = uncommented.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return Line(indent: uncommented.prefix { $0 == " " }.count, text: text)
        }
    }

    /// Parses the block starting at `index`, leaving `index` on the first line
    /// that does not belong to it.
    private static func parseValue(_ lines: [Line], _ index: inout Int) -> Node {
        let indent = lines[index].indent

        if lines[index].isSequenceItem {
            var items: [String] = []
            while index < lines.count, lines[index].indent == indent, lines[index].isSequenceItem {
                items.append(unquote(String(lines[index].text.dropFirst()).trimmingCharacters(in: .whitespaces)))
                index += 1
                // An item that is itself a mapping spills onto deeper lines.
                while index < lines.count, lines[index].indent > indent { index += 1 }
            }
            return .list(items)
        }

        var pairs: [(key: String, value: Node)] = []
        while index < lines.count, lines[index].indent >= indent {
            guard lines[index].indent == indent, let (key, value) = splitKey(lines[index].text) else {
                index += 1
                continue
            }
            index += 1

            if value.isEmpty {
                // A sequence may sit at the same indent as the key that owns it.
                let hasChild = index < lines.count
                    && (lines[index].indent > indent || (lines[index].indent == indent && lines[index].isSequenceItem))
                pairs.append((key, hasChild ? parseValue(lines, &index) : .scalar("")))
            } else if value.hasPrefix("|") || value.hasPrefix(">") {
                var folded: [String] = []
                while index < lines.count, lines[index].indent > indent {
                    folded.append(lines[index].text)
                    index += 1
                }
                pairs.append((key, .scalar(folded.joined(separator: " "))))
            } else if value.hasPrefix("[") {
                pairs.append((key, .list(flowItems(value))))
            } else {
                pairs.append((key, .scalar(unquote(value))))
            }
        }
        return .map(pairs)
    }

    /// Splits `key: value` at the first colon that ends a key.
    private static func splitKey(_ text: String) -> (key: String, value: String)? {
        var quote: Character?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ":" {
                let next = text.index(after: index)
                if next == text.endIndex || text[next] == " " {
                    let key = unquote(String(text[..<index]).trimmingCharacters(in: .whitespaces))
                    let value = String(text[next...]).trimmingCharacters(in: .whitespaces)
                    return key.isEmpty ? nil : (key, value)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// `[a, "b", c]` or a bare scalar, as a list of unquoted strings.
    private static func flowItems(_ value: String) -> [String] {
        var inner = value
        if inner.hasPrefix("[") { inner.removeFirst() }
        if inner.hasSuffix("]") { inner.removeLast() }
        return inner.split(separator: ",")
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    /// Drops a trailing `# comment`. A `#` inside quotes, or one that is not
    /// preceded by whitespace, is part of the value.
    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        var previous: Character = " "
        for index in line.indices {
            let character = line[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#", previous == " " || previous == "\t" {
                return String(line[..<index])
            }
            previous = character
        }
        return line
    }
}
