import Foundation

enum SwiftAITestScratch {
    private static let environmentKey = "SWIFT_AI_TEST_RUN_ROOT"

    static func directory(_ label: String = "test") -> URL {
        let root = configuredRoot()
        let safeLabel = label.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
        }
        let name = String(safeLabel) + "-" + UUID().uuidString
        let directory = root.appendingPathComponent(name, isDirectory: true).standardizedFileURL
        precondition(directory.path.hasPrefix(root.path + "/"), "test scratch escaped its configured root")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        } catch {
            preconditionFailure("cannot create isolated test scratch directory: \(error)")
        }
        return directory
    }

    static func file(_ label: String, extension suffix: String? = nil) -> URL {
        let directory = self.directory(label)
        let filename = suffix.map { "fixture.\($0)" } ?? "fixture"
        return directory.appendingPathComponent(filename, isDirectory: false)
    }

    private static func configuredRoot() -> URL {
        guard let raw = ProcessInfo.processInfo.environment[environmentKey], !raw.isEmpty else {
            preconditionFailure("\(environmentKey) must identify project-owned test scratch")
        }
        let root = URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
        let path = root.path
        guard let projectRaw = ProcessInfo.processInfo.environment["SWIFT_AI_TMP_ROOT"], !projectRaw.isEmpty else {
            preconditionFailure("SWIFT_AI_TMP_ROOT must identify the resolved project root")
        }
        let projectRoot = URL(fileURLWithPath: projectRaw, isDirectory: true).standardizedFileURL
        precondition(projectRoot.lastPathComponent == "swift-ai", "project scratch root must end in swift-ai")
        let runsRoot = projectRoot.appendingPathComponent("runs", isDirectory: true).standardizedFileURL
        precondition(path.hasPrefix(runsRoot.path + "/"), "test scratch must use the resolved swift-ai runs hierarchy")

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        if exists {
            precondition(isDirectory.boolValue, "test scratch root is not a directory")
            do {
                let values = try root.resourceValues(forKeys: [.isSymbolicLinkKey])
                precondition(values.isSymbolicLink != true, "test scratch root must not be a symlink")
            } catch {
                preconditionFailure("cannot inspect test scratch root: \(error)")
            }
        } else {
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            } catch {
                preconditionFailure("cannot create test scratch root: \(error)")
            }
        }
        return root
    }
}
