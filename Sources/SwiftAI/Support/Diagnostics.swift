import Foundation

public enum Diagnostics {
    public static func formatThrownValue(_ value: Any?) -> String {
        guard let value else { return "<nil>" }
        if let error = value as? Error { return String(describing: error) }
        if let string = value as? String { return string }
        return String(describing: value)
    }

    public static func extractDiagnosticError(_ error: Error?) -> DiagnosticError {
        guard let error else { return DiagnosticError(message: "<nil>") }
        return DiagnosticError(message: String(describing: error), name: String(reflecting: type(of: error)), stack: Thread.callStackSymbols.joined(separator: "\n"), code: nil)
    }

    public static func createAssistantMessageDiagnostic(type: String, error: Error?, details: [String: JSONValue]? = nil) -> AssistantMessageDiagnostic {
        AssistantMessageDiagnostic(type: type, timestamp: Int64(Date().timeIntervalSince1970 * 1000), error: extractDiagnosticError(error), details: details)
    }

    public static func appendAssistantMessageDiagnostic(_ diagnostic: AssistantMessageDiagnostic, to message: inout Message) { message.diagnostics = (message.diagnostics ?? []) + [diagnostic] }
}
