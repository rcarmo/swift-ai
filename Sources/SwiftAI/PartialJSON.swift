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
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: JSONValue].self, from: data)
    }
}
