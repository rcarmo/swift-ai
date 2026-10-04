import Foundation
#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

public final class DurableJournalLock: @unchecked Sendable {
    private var fileDescriptor: Int32 = -1
    public let url: URL

    public init(directory: URL) throws {
        #if os(Linux) || os(macOS)
        self.url = directory.appendingPathComponent("session.lock")
        fileDescriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else { throw DurableError.storageBusy("cannot open lock file") }
        if flock(fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            let fd = fileDescriptor
            fileDescriptor = -1
            Self.posixClose(fd)
            throw DurableError.storageBusy("storage lock is held: \(url.path)")
        }
        #else
        self.url = directory.appendingPathComponent("session.lock")
        throw DurableError.unsupportedPlatform("DurableJournalStorage is supported on Linux and macOS only")
        #endif
    }

    public func release() {
        #if os(Linux) || os(macOS)
        guard fileDescriptor >= 0 else { return }
        let fd = fileDescriptor
        fileDescriptor = -1
        flock(fd, LOCK_UN)
        Self.posixClose(fd)
        #endif
    }

    private static func posixClose(_ fd: Int32) {
        #if os(Linux)
        Glibc.close(fd)
        #elseif os(macOS)
        Darwin.close(fd)
        #endif
    }

    deinit { release() }
}
