import Foundation
#if os(Linux)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public struct DurableTextRead: Sendable {
    public var text: String
    public var totalLines: Int
    public var truncated: Bool
}
public struct DurableTextEdit: Sendable { public var oldText: String; public var newText: String; public init(oldText: String, newText: String) { self.oldText = oldText; self.newText = newText } }
public struct DurableExecutionResult: Sendable {
    public var output: String
    public var exitCode: Int32
    public var truncated: Bool
    public var spillPath: String?
}

public protocol DurableExecutionEnvironment: Sendable {
    func read(path: String, offset: Int, limit: Int?, cancellation: DurableCancellationSignal) async throws -> DurableTextRead
    func write(path: String, content: String, cancellation: DurableCancellationSignal) async throws
    func edit(path: String, edits: [DurableTextEdit], cancellation: DurableCancellationSignal) async throws
    func execute(command: String, timeoutSeconds: Double?, cancellation: DurableCancellationSignal) async throws -> DurableExecutionResult
}

/// Filesystem methods stay within an explicitly owned root; bash executes trusted scripts and is not sandboxed.
public actor DurableLocalEnvironment: DurableExecutionEnvironment {
    public let root: URL
    public let scratch: URL
    public static let maxOutputBytes = 50 * 1024
    public static let maxOutputLines = 2000

    public init(root: URL, scratch: URL) throws {
        let root = root.standardizedFileURL, scratch = scratch.standardizedFileURL
        guard root.path.hasPrefix("/"), scratch.path.hasPrefix("/"), FileManager.default.fileExists(atPath: root.path) else { throw DurableError.invalidRecord("environment requires an existing absolute root") }
        for path in [root, scratch] {
            var component = path
            while component.path != "/" {
                if component.path != "/workspace", let values = try? component.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true { throw DurableError.invalidRecord("environment root/scratch must not traverse symlinks") }
                component.deleteLastPathComponent()
            }
        }
        let canonicalRoot = root.resolvingSymlinksInPath(), canonicalScratch = scratch.resolvingSymlinksInPath()
        guard scratch.path.contains("/swift-ai/runs/"), scratch.path != root.path else { throw DurableError.invalidRecord("environment scratch must use swift-ai runs") }
        for path in [root, scratch] {
            if FileManager.default.fileExists(atPath: path.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory, (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw DurableError.invalidRecord("environment root/scratch must be owned directories") }
            }
        }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        self.root = canonicalRoot; self.scratch = canonicalScratch
    }

    private func path(_ raw: String) throws -> URL {
        let url = raw.hasPrefix("/") ? URL(fileURLWithPath: raw).standardizedFileURL : root.appendingPathComponent(raw).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw DurableError.invalidRecord("path escapes environment root") }
        var component = url
        while component.path != root.path {
            if let values = try? component.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true { throw DurableError.invalidRecord("environment paths must not traverse symlinks") }
            component.deleteLastPathComponent()
        }
        return url
    }

    private func check(_ cancellation: DurableCancellationSignal) throws {
        if cancellation.isCancelled || Task.isCancelled { throw CancellationError() }
    }

    public func read(path raw: String, offset: Int = 1, limit: Int? = nil, cancellation: DurableCancellationSignal = DurableCancellationSignal()) async throws -> DurableTextRead {
        try check(cancellation)
        if let limit { guard limit >= 0 else { throw DurableError.invalidRecord("read limit must be nonnegative") } }
        let url = try path(raw)
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw DurableError.invalidRecord("read path is not a regular file") }
        var newlines = 0
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty { try check(cancellation); newlines += chunk.reduce(0) { $0 + ($1 == 10 ? 1 : 0) } }
        let totalLines = newlines + 1
        let start = offset <= 0 ? max(0, totalLines + offset - 1) : offset - 1
        guard start < totalLines else { throw DurableError.invalidRecord("Offset \(offset) is beyond end of file (\(totalLines) lines total)") }
        try handle.seek(toOffset: 0)
        let end = limit.map { min(totalLines, start + min($0, totalLines)) } ?? totalLines
        var line = 0, prefix = Data(), selectedLines = 0, truncated = false
        let maxBytes = Self.maxOutputBytes, maxLines = Self.maxOutputLines
        var current = Data()
        func finishLine() {
            if line >= start && line < end {
                let separator = selectedLines > 0 ? 1 : 0
                if selectedLines < maxLines && prefix.count + separator + current.count <= maxBytes && !truncated {
                    if separator > 0 { prefix.append(10) }; prefix.append(current); selectedLines += 1
                } else { truncated = true }
            }
            current.removeAll(keepingCapacity: true); line += 1
        }
        var firstBytes = true
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try check(cancellation)
            var bytes = chunk
            if firstBytes { firstBytes = false; if bytes.starts(with: [0xef, 0xbb, 0xbf]) { bytes.removeFirst(3) } }
            for byte in bytes {
                if byte == 10 { finishLine() }
                else if line >= start && line < end { if current.count <= maxBytes { current.append(byte) } }
            }
        }
        finishLine()
        let after = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber) == (after[.size] as? NSNumber), (attributes[.modificationDate] as? Date) == (after[.modificationDate] as? Date) else { throw DurableError.invalidRecord("file changed while read") }
        return DurableTextRead(text: String(decoding: prefix, as: UTF8.self), totalLines: totalLines, truncated: truncated)
    }

    public func write(path raw: String, content: String, cancellation: DurableCancellationSignal = DurableCancellationSignal()) async throws {
        try check(cancellation); let url = try path(raw)
        guard content.utf8.count <= DurableLimits.maxEntryBytes else { throw DurableError.invalidRecord("file mutation exceeds native limit") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try check(cancellation); _ = try path(raw)
        try Data(content.utf8).write(to: url, options: .atomic)
    }

    public func edit(path raw: String, edits: [DurableTextEdit], cancellation: DurableCancellationSignal = DurableCancellationSignal()) async throws {
        try check(cancellation); let url = try path(raw)
        guard !edits.isEmpty, edits.count <= 1000 else { throw DurableError.invalidRecord("invalid edit count") }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= DurableLimits.maxEntryBytes else { throw DurableError.invalidRecord("edit file exceeds native limit") }
        let bytes = try Data(contentsOf: url)
        guard String(data: bytes, encoding: .utf8) != nil else { throw DurableError.invalidRecord("edit requires UTF-8 text") }
        var original = String(decoding: bytes, as: UTF8.self)
        let bom = original.hasPrefix("\u{feff}") ? "\u{feff}" : ""
        if !bom.isEmpty { original.removeFirst() }
        let crlf = original.contains("\r\n"); original = original.replacingOccurrences(of: "\r\n", with: "\n")
        var regions: [(Range<String.Index>, String)] = []
        for edit in edits {
            let old = edit.oldText.replacingOccurrences(of: "\r\n", with: "\n")
            guard !old.isEmpty, let region = original.range(of: old), original.range(of: old, range: region.upperBound..<original.endIndex) == nil else { throw DurableError.invalidRecord("edit oldText must match one unique region") }
            guard !regions.contains(where: { $0.0.overlaps(region) }) else { throw DurableError.invalidRecord("overlapping edits") }
            regions.append((region, edit.newText.replacingOccurrences(of: "\r\n", with: "\n")))
        }
        var changed = original
        for (region, text) in regions.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) { changed.replaceSubrange(region, with: text) }
        if crlf { changed = changed.replacingOccurrences(of: "\n", with: "\r\n") }
        try await write(path: raw, content: bom + changed, cancellation: cancellation)
    }

    public nonisolated func execute(command: String, timeoutSeconds: Double? = nil, cancellation: DurableCancellationSignal = DurableCancellationSignal()) async throws -> DurableExecutionResult {
        if let timeoutSeconds { guard timeoutSeconds.isFinite, timeoutSeconds > 0, timeoutSeconds <= 2_147_483.647 else { throw DurableError.invalidRecord("invalid command timeout") } }
        if cancellation.isCancelled || Task.isCancelled { throw CancellationError() }
        let process = Process(), pipe = Pipe()
        let groupFile = scratch.appendingPathComponent("process-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: groupFile) }
        #if os(Linux)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/setsid")
        process.arguments = ["--fork", "--wait", "/bin/bash", "-c", "printf '%s' \"$$\" > \"$1\"; exec /bin/bash -lc \"$2\"", "swift-ai", groupFile.path, command]
        #else
        process.executableURL = URL(fileURLWithPath: "/bin/bash"); process.arguments = ["-lc", command]
        #endif
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["TMPDIR"] = scratch.path; environment["TMP"] = scratch.path; environment["TEMP"] = scratch.path
        process.environment = environment; process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        try pipe.fileHandleForWriting.close()
        let spill = scratch.appendingPathComponent("output-\(UUID().uuidString).log")
        let reader = Task.detached { () throws -> (Data, Bool, String?) in
            defer { try? pipe.fileHandleForReading.close() }
            var tail = Data(), total = 0; var file: FileHandle?
            defer { try? file?.close() }
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
                total += chunk.count
                if file == nil, total > Self.maxOutputBytes {
                    _ = FileManager.default.createFile(atPath: spill.path, contents: tail)
                    file = try FileHandle(forWritingTo: spill); try file?.seekToEnd()
                }
                try file?.write(contentsOf: chunk)
                tail.append(chunk)
                if tail.count > Self.maxOutputBytes { tail.removeFirst(tail.count - Self.maxOutputBytes) }
            }
            return (tail, total > Self.maxOutputBytes, file == nil ? nil : spill.path)
        }
        let start = DispatchTime.now().uptimeNanoseconds
        var stopped: String?
        while process.isRunning {
            let timedOut = timeoutSeconds.map { Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9 >= $0 } ?? false
            if cancellation.isCancelled || Task.isCancelled || timedOut {
                stopped = timedOut ? "timeout" : "aborted"
                #if os(Linux)
                if let text = try? String(contentsOf: groupFile, encoding: .utf8), let group = Int32(text), group > 1 { _ = kill(-group, SIGKILL) }
                #endif
                process.terminate(); break
            }
            do { try await Task.sleep(nanoseconds: 5_000_000) }
            catch {
                stopped = "aborted"
                if let text = try? String(contentsOf: groupFile, encoding: .utf8), let group = Int32(text), group > 1 { _ = kill(-group, SIGKILL) }
                process.terminate(); break
            }
        }
        process.waitUntilExit()
        let captured = try await reader.value
        let lines = String(decoding: captured.0, as: UTF8.self).components(separatedBy: "\n")
        let output = lines.suffix(Self.maxOutputLines).joined(separator: "\n")
        if let stopped { throw DurableError.invalidRecord("Command \(stopped); retained output: \(output); spill: \(captured.2 ?? "none")") }
        return DurableExecutionResult(output: output, exitCode: process.terminationStatus, truncated: captured.1 || lines.count > Self.maxOutputLines, spillPath: captured.2)
    }
}
