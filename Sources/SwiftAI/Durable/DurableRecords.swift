import Foundation

public enum DurableError: Error, Equatable, Sendable, CustomStringConvertible {
    case closed
    case queueFull
    case cancelledBeforeAdmission
    case invalidRecord(String)
    case requestIDConflict(String)
    case corruptStorage(String)
    case poisoned(String)
    case durabilityUncertain(String)
    case unsupportedPlatform(String)
    case storageBusy(String)

    public var description: String {
        switch self {
        case .closed: return "durable storage is closed"
        case .queueFull: return "durable mutation queue is full"
        case .cancelledBeforeAdmission: return "durable mutation cancelled before admission"
        case .invalidRecord(let message): return "invalid durable record: \(message)"
        case .requestIDConflict(let requestID): return "request ID conflict: \(requestID)"
        case .corruptStorage(let message): return "corrupt durable storage: \(message)"
        case .poisoned(let message): return "durable storage poisoned: \(message)"
        case .durabilityUncertain(let message): return "durable durability uncertain: \(message)"
        case .unsupportedPlatform(let message): return "unsupported durable platform: \(message)"
        case .storageBusy(let message): return "durable storage busy: \(message)"
        }
    }
}

public enum DurableLimits {
    public static let maxExactInteger: Int64 = 9_007_199_254_740_991
    public static let maxPublicQueue = 1_024
    public static let maxRequestIDBytes = 512
    public static let maxArgumentsBytes = 256 * 1024
    public static let maxRecordBytes = 1 * 1024 * 1024
    public static let maxCheckpointBytes = 1 * 1024 * 1024
    public static let maxEntryBytes = 4 * 1024 * 1024
    public static let maxDocumentBytes = 4 * 1024 * 1024
    public static let maxBatchBytes = 16 * 1024 * 1024
    public static let maxPageLimit = 1_000
    public static let maxJSONDepth = 128
    public static let maxJSONNodes = 10_000
    public static let maxStringBytes = 1 * 1024 * 1024
    public static let maxJournalBytes = 256 * 1024 * 1024
    public static let maxJournalFrames = 1_000_000
}

public struct DurableConversationRecord: Codable, Equatable, Sendable {
    public var id: Int64
    public var parentConversationID: Int64?
    public var parentEntryID: Int64?
    public var ownerTaskID: Int64?
    public var createdSeq: Int64
    public init(id: Int64, parentConversationID: Int64? = nil, parentEntryID: Int64? = nil, ownerTaskID: Int64? = nil, createdSeq: Int64 = 0) { self.id = id; self.parentConversationID = parentConversationID; self.parentEntryID = parentEntryID; self.ownerTaskID = ownerTaskID; self.createdSeq = createdSeq }
}

public struct DurableEntryRecord: Codable, Equatable, Sendable {
    public var id: Int64
    public var conversationID: Int64
    public var kind: String
    public var messages: [Message]?
    public var data: JSONValue?
    public var byTaskID: Int64?
    public var createdSeq: Int64
    public init(id: Int64, conversationID: Int64, kind: String, messages: [Message]? = nil, data: JSONValue? = nil, byTaskID: Int64? = nil, createdSeq: Int64 = 0) { self.id = id; self.conversationID = conversationID; self.kind = kind; self.messages = messages; self.data = data; self.byTaskID = byTaskID; self.createdSeq = createdSeq }
}

public enum DurableTaskStatus: String, Codable, Sendable { case pending, running, waiting, completing, completed, failed, aborted }

public struct DurableTaskRecord: Codable, Equatable, Sendable {
    public var id: Int64
    public var conversationID: Int64
    public var ownerTaskID: Int64?
    public var kind: String
    public var status: DurableTaskStatus
    public var checkpoint: JSONValue?
    public var abortRequested: Bool
    public var background: Bool
    public var outcome: JSONValue?
    public var createdSeq: Int64
    public init(id: Int64, conversationID: Int64, ownerTaskID: Int64? = nil, kind: String, status: DurableTaskStatus = .pending, checkpoint: JSONValue? = nil, abortRequested: Bool = false, background: Bool = false, outcome: JSONValue? = nil, createdSeq: Int64 = 0) { self.id = id; self.conversationID = conversationID; self.ownerTaskID = ownerTaskID; self.kind = kind; self.status = status; self.checkpoint = checkpoint; self.abortRequested = abortRequested; self.background = background; self.outcome = outcome; self.createdSeq = createdSeq }
}

public enum DurableSubmissionType: String, Codable, Sendable { case input, write }
public enum DurableSubmissionStatus: String, Codable, Sendable { case queued, placed, done, unanswered, withdrawn }

public struct DurableSubmissionRecord: Codable, Equatable, Sendable {
    public var id: Int64
    public var conversationID: Int64
    public var requestID: String?
    public var type: DurableSubmissionType
    public var payloadHash: String?
    public var status: DurableSubmissionStatus
    public var entryID: Int64?
    public var answerID: Int64?
    public var reason: String?
    public var createdSeq: Int64
    public init(id: Int64, conversationID: Int64, requestID: String? = nil, type: DurableSubmissionType, payloadHash: String? = nil, status: DurableSubmissionStatus = .queued, entryID: Int64? = nil, answerID: Int64? = nil, reason: String? = nil, createdSeq: Int64 = 0) { self.id = id; self.conversationID = conversationID; self.requestID = requestID; self.type = type; self.payloadHash = payloadHash; self.status = status; self.entryID = entryID; self.answerID = answerID; self.reason = reason; self.createdSeq = createdSeq }
}

public struct DurableDocumentRecord: Codable, Equatable, Sendable {
    public var id: Int64
    public var scope: String
    public var ownerID: Int64
    public var kind: String
    public var value: JSONValue
    public var createdSeq: Int64
    public init(id: Int64, scope: String, ownerID: Int64, kind: String, value: JSONValue, createdSeq: Int64 = 0) { self.id = id; self.scope = scope; self.ownerID = ownerID; self.kind = kind; self.value = value; self.createdSeq = createdSeq }
}

public struct DurableSnapshot: Codable, Equatable, Sendable {
    public var seq: Int64
    public var highWaterID: Int64
    public var conversations: [Int64: DurableConversationRecord]
    public var entries: [Int64: DurableEntryRecord]
    public var tasks: [Int64: DurableTaskRecord]
    public var submissions: [Int64: DurableSubmissionRecord]
    public var documents: [Int64: DurableDocumentRecord]
    public init(seq: Int64 = 0, highWaterID: Int64 = 0, conversations: [Int64: DurableConversationRecord] = [:], entries: [Int64: DurableEntryRecord] = [:], tasks: [Int64: DurableTaskRecord] = [:], submissions: [Int64: DurableSubmissionRecord] = [:], documents: [Int64: DurableDocumentRecord] = [:]) { self.seq = seq; self.highWaterID = highWaterID; self.conversations = conversations; self.entries = entries; self.tasks = tasks; self.submissions = submissions; self.documents = documents }
}

public struct DurableCommitBatch: Codable, Equatable, Sendable {
    public var conversations: [DurableConversationRecord]
    public var entries: [DurableEntryRecord]
    public var tasks: [DurableTaskRecord]
    public var submissions: [DurableSubmissionRecord]
    public var documents: [DurableDocumentRecord]
    public init(conversations: [DurableConversationRecord] = [], entries: [DurableEntryRecord] = [], tasks: [DurableTaskRecord] = [], submissions: [DurableSubmissionRecord] = [], documents: [DurableDocumentRecord] = []) { self.conversations = conversations; self.entries = entries; self.tasks = tasks; self.submissions = submissions; self.documents = documents }
}

struct DurableJournalPayload: Codable, Equatable {
    var seq: Int64
    var highWaterID: Int64
    var batch: DurableCommitBatch
}
