import Foundation

public enum PartialJSONParser {
    public static func parseObject(_ partial: String) -> [String: JSONValue]? {
        let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let object = decodeObject(trimmed) { return object }
        return decodeObject(closeJSON(trimmed))
    }

    public static func closeJSON(_ input: String) -> String {
        var output = input
        var stack: [Character] = []
        var inString = false
        var escaped = false
        for ch in input {
            if escaped { escaped = false; continue }
            if ch == "\\", inString { escaped = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }
            switch ch {
            case "{": stack.append("}")
            case "[": stack.append("]")
            case "}", "]": if !stack.isEmpty { _ = stack.removeLast() }
            default: break
            }
        }
        if inString { output.append("\"") }
        for ch in stack.reversed() { output.append(ch) }
        return output
    }

    private static func decodeObject(_ text: String) -> [String: JSONValue]? {
        if let data = text.data(using: .utf8), let object = try? JSONDecoder().decode([String: JSONValue].self, from: data) { return object }
        let repaired = repairMalformedJSONStrings(text)
        guard repaired != text, let data = repaired.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    private static func repairMalformedJSONStrings(_ text: String) -> String {
        var out = ""
        var inString = false
        var escaping = false
        for scalar in text.unicodeScalars {
            if escaping {
                if "\\\"/bfnrtu".unicodeScalars.contains(scalar) { out.unicodeScalars.append(scalar) }
                else { out += "\\\\"; out.unicodeScalars.append(scalar) }
                escaping = false
                continue
            }
            if scalar.value == 34 {
                inString.toggle()
                out.unicodeScalars.append(scalar)
            } else if scalar.value == 92, inString {
                out += "\\"
                escaping = true
            } else if inString && scalar.value == 9 {
                out += "\\t"
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        if escaping { out += "\\\\" }
        return out
    }
}
