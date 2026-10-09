import Foundation

public struct DurableGenerationRequest: Sendable {
    public var conversationID: Int64
    public var model: Model
    public var systemPrompt: String?
    public var transcript: [Message]
    public var requestID: String?
    public var payloadHash: String?
    public var options: StreamOptions?
    var offeredTools: [DurableToolBinding] = []

    public init(conversationID: Int64, model: Model, systemPrompt: String? = nil, transcript: [Message], requestID: String? = nil, payloadHash: String? = nil, options: StreamOptions? = nil) {
        self.conversationID = conversationID
        self.model = model
        self.systemPrompt = systemPrompt
        self.transcript = transcript
        self.requestID = requestID
        self.payloadHash = payloadHash
        self.options = options
    }

    public func sanitizedOptions() -> StreamOptions {
        var options = options ?? StreamOptions()
        options.apiKey = nil
        options.bearerToken = nil
        options.headers = nil
        options.env = nil
        options.onPayload = nil
        options.onResponse = nil
        options.onProviderStreamEvent = nil
        options.requestMetadata = nil
        options.transport = nil
        options.deferred = nil
        options.wait = nil
        options.maxRetries = 0
        options.retryConfig = RetryConfig(maxRetries: 0, maxDelayMs: options.retryConfig?.maxDelayMs)
        return options
    }

    public func context() -> AIContext { AIContext(systemPrompt: systemPrompt, messages: transcript) }
}

public struct DurableGenerationResult: Sendable, Equatable {
    public var task: DurableTaskRecord
    public var submission: DurableSubmissionRecord?
    public var entry: DurableEntryRecord?
    public init(task: DurableTaskRecord, submission: DurableSubmissionRecord?, entry: DurableEntryRecord?) {
        self.task = task
        self.submission = submission
        self.entry = entry
    }
}

struct DurableGenerationAdmission: Sendable {
    var taskID: Int64
    var inputEntryID: Int64
    var submissionID: Int64?
    var duplicate: DurableGenerationResult?
    var request: DurableGenerationRequest?
    var batch: DurableCommitBatch
}

struct DurablePinnedOptions: Codable, Equatable, Sendable {
    var temperature: Double?
    var maxTokens: Int?
    var samplingParams: [String: JSONValue]?
    var cacheRetention: CacheRetention?
    var maxRetryDelayMs: Int?
    var retryConfig: RetryConfig?
    var metadata: [String: JSONValue]?
    var region: String?
    var profile: String?
    var project: String?
    var location: String?
    var textVerbosity: String?
    var timeoutMs: Int?
    var reasoning: ThinkingLevel?
    var thinkingBudgets: ThinkingBudgets?
    var reasoningSummary: String?
    var serviceTier: String?
    var toolChoice: JSONValue?
    var sessionId: String?
    var azureApiVersion: String?
    var azureResourceName: String?
    var azureDeploymentName: String?

    init(_ options: StreamOptions) {
        temperature = options.temperature
        maxTokens = options.maxTokens
        samplingParams = options.samplingParams
        cacheRetention = options.cacheRetention
        maxRetryDelayMs = options.maxRetryDelayMs
        retryConfig = options.retryConfig
        metadata = options.metadata
        region = options.region
        profile = options.profile
        project = options.project
        location = options.location
        textVerbosity = options.textVerbosity
        timeoutMs = options.timeoutMs
        reasoning = options.reasoning
        thinkingBudgets = options.thinkingBudgets
        reasoningSummary = options.reasoningSummary
        serviceTier = options.serviceTier
        toolChoice = options.toolChoice
        sessionId = options.sessionId
        azureApiVersion = options.azureApiVersion
        azureResourceName = options.azureResourceName
        azureDeploymentName = options.azureDeploymentName
    }

    func streamOptions() -> StreamOptions {
        var options = StreamOptions()
        options.temperature = temperature
        options.maxTokens = maxTokens
        options.samplingParams = samplingParams
        options.cacheRetention = cacheRetention
        options.maxRetryDelayMs = maxRetryDelayMs
        options.retryConfig = retryConfig ?? RetryConfig(maxRetries: 0, maxDelayMs: nil)
        options.maxRetries = 0
        options.metadata = metadata
        options.region = region
        options.profile = profile
        options.project = project
        options.location = location
        options.textVerbosity = textVerbosity
        options.timeoutMs = timeoutMs
        options.reasoning = reasoning
        options.thinkingBudgets = thinkingBudgets
        options.reasoningSummary = reasoningSummary
        options.serviceTier = serviceTier
        options.toolChoice = toolChoice
        options.sessionId = sessionId
        options.azureApiVersion = azureApiVersion
        options.azureResourceName = azureResourceName
        options.azureDeploymentName = azureDeploymentName
        options.azureBaseUrl = nil
        options.deferred = nil
        options.wait = nil
        return options
    }
}

struct DurableGenerationIntent: Codable, Equatable, Sendable {
    var conversationID: Int64
    var inputEntryID: Int64
    var model: Model
    var systemPrompt: String?
    var transcript: [Message]
    var preparedTranscript: [Message]?
    var requestID: String?
    var payloadHash: String?
    var options: DurablePinnedOptions
    var attempt: Int
    var offeredTools: [DurableToolBinding]?
    var roundMessages: [Message]?
    var round: Int?

    init(request: DurableGenerationRequest, inputEntryID: Int64) {
        conversationID = request.conversationID
        self.inputEntryID = inputEntryID
        var model = request.model
        model.baseUrl = ""
        model.headers = nil
        self.model = model
        systemPrompt = request.systemPrompt
        transcript = request.transcript
        preparedTranscript = nil
        requestID = request.requestID
        payloadHash = request.payloadHash
        options = DurablePinnedOptions(request.sanitizedOptions())
        attempt = 1
        offeredTools = request.offeredTools
        roundMessages = []
        round = 1
    }

    var request: DurableGenerationRequest { DurableGenerationRequest(conversationID: conversationID, model: model, systemPrompt: systemPrompt, transcript: transcript, requestID: requestID, payloadHash: payloadHash, options: options.streamOptions()) }
    var dispatchContext: AIContext { AIContext(systemPrompt: systemPrompt, messages: preparedTranscript ?? transcript) }

    func semanticallyMatches(_ other: DurableGenerationIntent) -> Bool {
        conversationID == other.conversationID &&
        model == other.model &&
        systemPrompt == other.systemPrompt && transcript == other.transcript &&
        requestID == other.requestID && payloadHash == other.payloadHash && options == other.options &&
        (offeredTools ?? []) == (other.offeredTools ?? [])
    }
}

struct DurableStreamTerminal: Codable, Equatable, Sendable {
    var message: Message
    var usage: Usage?
    var diagnostics: [AssistantMessageDiagnostic]?
    var stopReason: StopReason
}

struct DurableFailureInfo: Codable, Equatable, Sendable {
    var code: String
    var usage: Usage?
    var diagnostics: [AssistantMessageDiagnostic]?
}

struct DurableGenerationPlanner {
    static func admitBatch(snapshot: DurableSnapshot, request: DurableGenerationRequest) throws -> DurableGenerationAdmission {
        if let requestID = request.requestID, let existing = DurableSubmissionPlanner.existing(conversationID: request.conversationID, requestID: requestID, in: snapshot) {
            guard existing.payloadHash == request.payloadHash else { throw DurableError.requestIDConflict(requestID) }
            guard let task = taskForSubmission(existing, in: snapshot) else { throw DurableError.corruptStorage("requestID has no generation task") }
            let existingIntent = try intent(for: task, in: snapshot)
            let requestedIntent = DurableGenerationIntent(request: request, inputEntryID: existing.entryID ?? existingIntent.inputEntryID)
            guard existingIntent.semanticallyMatches(requestedIntent) else { throw DurableError.requestIDConflict(requestID) }
            let answer = existing.answerID.flatMap { snapshot.entries[$0] }
            return DurableGenerationAdmission(taskID: task.id, inputEntryID: existing.entryID ?? existingIntent.inputEntryID, submissionID: existing.id, duplicate: DurableGenerationResult(task: task, submission: existing, entry: answer), request: nil, batch: DurableCommitBatch())
        }

        let existingQueue = document(scope: "conversation", ownerID: request.conversationID, kind: "durable.queue", in: snapshot)
        let required = 3 + (request.requestID == nil ? 0 : 1) + (existingQueue == nil ? 1 : 0)
        var ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: required)
        func takeID() -> Int64 { ids.removeFirst() }
        let inputEntryID = takeID()
        let taskID = takeID()
        let intentDocumentID = takeID()
        let submissionID = request.requestID == nil ? nil : takeID()
        let queueDocumentID = existingQueue?.id ?? takeID()
        let intent = DurableGenerationIntent(request: request, inputEntryID: inputEntryID)
        try preflightIntent(intent)
        let input = DurableEntryRecord(id: inputEntryID, conversationID: request.conversationID, kind: "input", messages: request.transcript, byTaskID: taskID)
        let task = DurableTaskRecord(id: taskID, conversationID: request.conversationID, kind: "generation", status: .pending, checkpoint: checkpoint(intent: intent, phase: "pending"))
        let submission = submissionID.map { DurableSubmissionRecord(id: $0, conversationID: request.conversationID, requestID: request.requestID, type: .input, payloadHash: request.payloadHash, status: .placed, entryID: inputEntryID) }
        let intentDocument = DurableDocumentRecord(id: intentDocumentID, scope: "task", ownerID: taskID, kind: "generation.intent", value: try encodeJSON(intent))
        let queue = queueDocument(id: queueDocumentID, conversationID: request.conversationID, existing: existingQueue, adding: taskID, removing: nil)
        let batch = DurableCommitBatch(entries: [input], tasks: [task], submissions: submission.map { [$0] } ?? [], documents: [intentDocument, queue])
        return DurableGenerationAdmission(taskID: taskID, inputEntryID: inputEntryID, submissionID: submissionID, duplicate: nil, request: request, batch: batch)
    }

    static func runningBatch(snapshot: DurableSnapshot, task: DurableTaskRecord, intent: DurableGenerationIntent) throws -> DurableCommitBatch {
        var prepared = intent
        prepared.preparedTranscript = preparedContextMessages(for: intent, in: snapshot)
        try preflightMessages(prepared.preparedTranscript ?? [], label: "generation.preparedContext")
        let intentDocument = try document(scope: "task", ownerID: task.id, kind: "generation.intent", in: snapshot).map { existing in
            DurableDocumentRecord(id: existing.id, scope: existing.scope, ownerID: existing.ownerID, kind: existing.kind, value: try encodeJSON(prepared), createdSeq: existing.createdSeq)
        }
        let running = DurableTaskRecord(id: task.id, conversationID: task.conversationID, ownerTaskID: task.ownerTaskID, kind: task.kind, status: .running, checkpoint: checkpoint(intent: prepared, phase: "running"), abortRequested: task.abortRequested, background: task.background, outcome: task.outcome, createdSeq: task.createdSeq)
        return DurableCommitBatch(tasks: [running], documents: intentDocument.map { [$0] } ?? [])
    }

    static func runningContextFailureBatch(task: DurableTaskRecord, failure: DurableFailureInfo) throws -> DurableCommitBatch {
        let checkpoint: JSONValue = .object(["phase": .string("running_context_failure"), "failure": try encodeJSON(boundedFailureInfo(failure), maxBytes: DurableLimits.maxCheckpointBytes)])
        let running = DurableTaskRecord(id: task.id, conversationID: task.conversationID, ownerTaskID: task.ownerTaskID, kind: task.kind, status: .running, checkpoint: checkpoint, abortRequested: task.abortRequested, background: task.background, outcome: .object(["errorCode": .string("context_limit")]), createdSeq: task.createdSeq)
        return DurableCommitBatch(tasks: [running])
    }

    static func completingBatch(task: DurableTaskRecord, intent: DurableGenerationIntent, terminal: DurableStreamTerminal) throws -> DurableCommitBatch {
        do {
            try preflightMessages([terminal.message], label: "generation.terminal")
            let completing = DurableTaskRecord(id: task.id, conversationID: task.conversationID, ownerTaskID: task.ownerTaskID, kind: task.kind, status: .completing, checkpoint: try stagedTerminalCheckpoint(intent: intent, terminal: terminal), abortRequested: task.abortRequested, background: task.background, outcome: .object(["phase": .string("terminal-staged")]), createdSeq: task.createdSeq)
            return DurableCommitBatch(tasks: [completing])
        } catch {
            throw DurableGenerationFailure.outputLimit(DurableFailureInfo(code: "output_limit", usage: validUsageOrNil(terminal.usage ?? terminal.message.usage), diagnostics: boundedDiagnostics(terminal.diagnostics ?? terminal.message.diagnostics)))
        }
    }

    static func finalSuccessBatch(snapshot: DurableSnapshot, task: DurableTaskRecord, submission: DurableSubmissionRecord?, inputEntryID: Int64, terminal: DurableStreamTerminal) throws -> DurableCommitBatch {
        let intent = try intent(for: task, in: snapshot)
        let usageKind = (intent.offeredTools ?? []).isEmpty ? "generation.usage" : "generation.usage.round.\(intent.round ?? 1)"
        let existingUsage = document(scope: "task", ownerID: task.id, kind: usageKind, in: snapshot)
        let existingAggregate = document(scope: "conversation", ownerID: task.conversationID, kind: "durable.usage", in: snapshot)
        let existingLive = document(scope: "conversation", ownerID: task.conversationID, kind: "durable.live", in: snapshot)
        let existingQueue = document(scope: "conversation", ownerID: task.conversationID, kind: "durable.queue", in: snapshot)
        let required = 1 + (existingUsage == nil ? 1 : 0) + (existingAggregate == nil ? 1 : 0) + (existingLive == nil ? 1 : 0) + (existingQueue == nil ? 1 : 0)
        var ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: required)
        func takeID() -> Int64 { ids.removeFirst() }
        let assistantEntryID = takeID()
        let usageDocumentID = existingUsage?.id ?? takeID()
        let aggregateDocumentID = existingAggregate?.id ?? takeID()
        let liveDocumentID = existingLive?.id ?? takeID()
        let queueDocumentID = existingQueue?.id ?? takeID()
        let entry = DurableEntryRecord(id: assistantEntryID, conversationID: task.conversationID, kind: "assistant", messages: [terminal.message], byTaskID: task.id)
        let completed = DurableTaskRecord(id: task.id, conversationID: task.conversationID, ownerTaskID: task.ownerTaskID, kind: task.kind, status: .completed, checkpoint: task.checkpoint, abortRequested: task.abortRequested, background: task.background, outcome: .object(["phase": .string("completed")]), createdSeq: task.createdSeq)
        let settled = submission.map { DurableSubmissionRecord(id: $0.id, conversationID: $0.conversationID, requestID: $0.requestID, type: $0.type, payloadHash: $0.payloadHash, status: .done, entryID: inputEntryID, answerID: assistantEntryID, createdSeq: $0.createdSeq) }
        let usage = terminal.usage ?? terminal.message.usage
        let modelKey = try pinnedModelIdentity(task: task, in: snapshot)
        let usageDoc = DurableDocumentRecord(id: usageDocumentID, scope: "task", ownerID: task.id, kind: usageKind, value: usageValue(usage, model: modelKey))
        let aggregate = DurableDocumentRecord(id: aggregateDocumentID, scope: "conversation", ownerID: task.conversationID, kind: "durable.usage", value: try aggregateUsageValue(existing: existingAggregate?.value, adding: usage, model: modelKey))
        let live = DurableDocumentRecord(id: liveDocumentID, scope: "conversation", ownerID: task.conversationID, kind: "durable.live", value: .object(["lastTaskID": .number(Double(task.id)), "lastEntryID": .number(Double(assistantEntryID))]))
        let queue = queueDocument(id: queueDocumentID, conversationID: task.conversationID, existing: existingQueue, adding: nil, removing: task.id)
        return DurableCommitBatch(entries: [entry], tasks: [completed], submissions: settled.map { [$0] } ?? [], documents: [usageDoc, aggregate, live, queue])
    }

    static func aggregateFailureFinalBatch(snapshot: DurableSnapshot, task: DurableTaskRecord, submission: DurableSubmissionRecord?, inputEntryID: Int64?, failure: DurableFailureInfo) throws -> DurableCommitBatch {
        let intent = try intent(for: task, in: snapshot)
        let usageKind = (intent.offeredTools ?? []).isEmpty ? "generation.usage" : "generation.usage.round.\(intent.round ?? 1)"
        let existingUsage = document(scope: "task", ownerID: task.id, kind: usageKind, in: snapshot)
        let existingQueue = document(scope: "conversation", ownerID: task.conversationID, kind: "durable.queue", in: snapshot)
        let required = (existingUsage == nil ? 1 : 0) + (existingQueue == nil ? 1 : 0) + 1
        var ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: required)
        func takeID() -> Int64 { ids.removeFirst() }
        let usageID = existingUsage?.id ?? takeID()
        let queueID = existingQueue?.id ?? takeID()
        let incompleteID = takeID()
        let failed = DurableTaskRecord(id: task.id, conversationID: task.conversationID, ownerTaskID: task.ownerTaskID, kind: task.kind, status: .failed, checkpoint: try stagedFailureCheckpoint(failure), abortRequested: task.abortRequested, background: task.background, outcome: .object(["errorCode": .string(failure.code), "aggregateIncomplete": .bool(true)]), createdSeq: task.createdSeq)
        let settled = submission.map { DurableSubmissionRecord(id: $0.id, conversationID: $0.conversationID, requestID: $0.requestID, type: $0.type, payloadHash: $0.payloadHash, status: .unanswered, entryID: inputEntryID ?? $0.entryID, reason: failure.code, createdSeq: $0.createdSeq) }
        let modelKey = try pinnedModelIdentity(task: task, in: snapshot)
        let usage = DurableDocumentRecord(id: usageID, scope: "task", ownerID: task.id, kind: usageKind, value: usageValue(failure.usage, model: modelKey))
        let queue = queueDocument(id: queueID, conversationID: task.conversationID, existing: existingQueue, adding: nil, removing: task.id)
        let incomplete = DurableDocumentRecord(id: incompleteID, scope: "task", ownerID: task.id, kind: "generation.aggregate-incomplete", value: .object(["code": .string(failure.code), "aggregatePreserved": .bool(true)]))
        return DurableCommitBatch(tasks: [failed], submissions: settled.map { [$0] } ?? [], documents: [usage, queue, incomplete])
    }

    static func failureBatches(snapshot: DurableSnapshot, task: DurableTaskRecord, submission: DurableSubmissionRecord?, inputEntryID: Int64?, failure: DurableFailureInfo) throws -> (DurableCommitBatch, DurableCommitBatch) {
        let failure = boundedFailureInfo(failure)
        let intent = try intent(for: task, in: snapshot)
        let usageKind = (intent.offeredTools ?? []).isEmpty ? "generation.usage" : "generation.usage.round.\(intent.round ?? 1)"
        let existingQueue = document(scope: "conversation", ownerID: task.conversationID, kind: "durable.queue", in: snapshot)
        let existingUsage = document(scope: "task", ownerID: task.id, kind: usageKind, in: snapshot)
        let existingAggregate = document(scope: "conversation", ownerID: task.conversationID, kind: "durable.usage", in: snapshot)
        var ids = try DurableSubmissionPlanner.nextID(from: snapshot, reserving: (existingQueue == nil ? 1 : 0) + (existingUsage == nil ? 1 : 0) + (existingAggregate == nil ? 1 : 0) + 1)
        func takeID() -> Int64 { ids.removeFirst() }
        let queueID = existingQueue?.id ?? takeID()
        let usageID = existingUsage?.id ?? takeID()
        let aggregateID = existingAggregate?.id ?? takeID()
        let incompleteID = takeID()
        let completing = DurableTaskRecord(id: task.id, conversationID: task.conversationID, ownerTaskID: task.ownerTaskID, kind: task.kind, status: .completing, checkpoint: try stagedFailureCheckpoint(failure), abortRequested: task.abortRequested, background: task.background, outcome: .object(["errorCode": .string(failure.code)]), createdSeq: task.createdSeq)
        let failed = DurableTaskRecord(id: task.id, conversationID: task.conversationID, ownerTaskID: task.ownerTaskID, kind: task.kind, status: .failed, checkpoint: completing.checkpoint, abortRequested: task.abortRequested, background: task.background, outcome: .object(["errorCode": .string(failure.code)]), createdSeq: task.createdSeq)
        let settled = submission.map { DurableSubmissionRecord(id: $0.id, conversationID: $0.conversationID, requestID: $0.requestID, type: $0.type, payloadHash: $0.payloadHash, status: .unanswered, entryID: inputEntryID ?? $0.entryID, reason: failure.code, createdSeq: $0.createdSeq) }
        let queue = queueDocument(id: queueID, conversationID: task.conversationID, existing: existingQueue, adding: nil, removing: task.id)
        let modelKey = try pinnedModelIdentity(task: task, in: snapshot)
        let usage = DurableDocumentRecord(id: usageID, scope: "task", ownerID: task.id, kind: usageKind, value: usageValue(failure.usage, model: modelKey))
        var documents = [queue, usage]
        do {
            let aggregateValue = try aggregateUsageValue(existing: existingAggregate?.value, adding: failure.usage, model: modelKey)
            documents.append(DurableDocumentRecord(id: aggregateID, scope: "conversation", ownerID: task.conversationID, kind: "durable.usage", value: aggregateValue))
        } catch {
            documents.append(DurableDocumentRecord(id: incompleteID, scope: "task", ownerID: task.id, kind: "generation.aggregate-incomplete", value: .object(["code": .string("usage_overflow"), "aggregatePreserved": .bool(true)])))
        }
        return (DurableCommitBatch(tasks: [completing]), DurableCommitBatch(tasks: [failed], submissions: settled.map { [$0] } ?? [], documents: documents))
    }

    static func collectTerminal(model: Model, context: AIContext, options: StreamOptions) async throws -> DurableStreamTerminal {
        let events = await SwiftAI.stream(model: model, context: context, options: options)
        var terminal: DurableStreamTerminal?
        var failure: DurableFailureInfo?
        for await event in events {
            switch event {
            case .done(let reason, let message):
                guard terminal == nil, failure == nil else { throw DurableError.invalidRecord("duplicate_terminal") }
                terminal = try validatedTerminal(message: message, reason: reason, pinned: model)
            case .error(_, let message, _):
                guard terminal == nil, failure == nil else { throw DurableError.invalidRecord("duplicate_terminal") }
                failure = failureInfo(from: message, defaultCode: "provider_error")
            default: break
            }
        }
        if let failure { throw DurableGenerationFailure.failure(failure) }
        guard let terminal else { throw DurableError.invalidRecord("missing_terminal") }
        return terminal
    }

    static func intent(for task: DurableTaskRecord, in snapshot: DurableSnapshot) throws -> DurableGenerationIntent {
        guard let document = document(scope: "task", ownerID: task.id, kind: "generation.intent", in: snapshot) else { throw DurableError.corruptStorage("missing generation intent") }
        return try decodeJSON(DurableGenerationIntent.self, from: document.value)
    }

    static func stagedTerminal(for task: DurableTaskRecord) throws -> DurableStreamTerminal? {
        guard task.status == .completing, let checkpoint = task.checkpoint, checkpoint.objectValue?["terminal"] != nil else { return nil }
        return try decodeJSON(DurableStreamTerminal.self, from: checkpoint.objectValue!["terminal"]!)
    }

    static func stagedFailure(for task: DurableTaskRecord) throws -> DurableFailureInfo? {
        guard [.running, .completing].contains(task.status), let checkpoint = task.checkpoint, checkpoint.objectValue?["failure"] != nil else { return nil }
        return try decodeJSON(DurableFailureInfo.self, from: checkpoint.objectValue!["failure"]!)
    }

    static func taskForSubmission(_ submission: DurableSubmissionRecord, in snapshot: DurableSnapshot) -> DurableTaskRecord? {
        if let entryID = submission.entryID, let entry = snapshot.entries[entryID], let taskID = entry.byTaskID, let task = snapshot.tasks[taskID] { return task }
        return snapshot.tasks.values.first { task in
            task.conversationID == submission.conversationID && document(scope: "task", ownerID: task.id, kind: "generation.intent", in: snapshot) != nil && (try? intent(for: task, in: snapshot).inputEntryID) == submission.entryID
        }
    }

    static func taskForRequestID(_ requestID: String, conversationID: Int64, in snapshot: DurableSnapshot) -> DurableTaskRecord? {
        snapshot.tasks.values.first { task in
            task.conversationID == conversationID && (try? intent(for: task, in: snapshot).requestID) == requestID
        }
    }

    static func context(for intent: DurableGenerationIntent, in snapshot: DurableSnapshot) -> AIContext {
        let messages = (intent.preparedTranscript ?? preparedContextMessages(for: intent, in: snapshot)) + (intent.roundMessages ?? [])
        return AIContext(systemPrompt: intent.systemPrompt, messages: messages, tools: (intent.offeredTools ?? []).map(\.definition))
    }

    static func preparedContextMessages(for intent: DurableGenerationIntent, in snapshot: DurableSnapshot) -> [Message] {
        var entryIDs = Set<Int64>()
        for task in snapshot.tasks.values where task.conversationID == intent.conversationID && task.status == .completed {
            guard let completedIntent = try? self.intent(for: task, in: snapshot), completedIntent.inputEntryID != intent.inputEntryID else { continue }
            entryIDs.insert(completedIntent.inputEntryID)
            for entry in snapshot.entries.values where entry.conversationID == intent.conversationID && entry.byTaskID == task.id { entryIDs.insert(entry.id) }
            let childIDs = Set(snapshot.tasks.values.filter { $0.ownerTaskID == task.id }.map(\.id))
            for entry in snapshot.entries.values where entry.conversationID == intent.conversationID && entry.byTaskID.map(childIDs.contains) == true { entryIDs.insert(entry.id) }
        }
        for submission in snapshot.submissions.values where submission.conversationID == intent.conversationID && submission.answerID != nil {
            if let inputID = submission.entryID, inputID != intent.inputEntryID { entryIDs.insert(inputID) }
            if let answerID = submission.answerID { entryIDs.insert(answerID) }
        }
        for entry in snapshot.entries.values where entry.conversationID == intent.conversationID && entry.byTaskID == nil && entry.id != intent.inputEntryID {
            if !snapshot.submissions.values.contains(where: { $0.entryID == entry.id }) { entryIDs.insert(entry.id) }
        }
        // The current input fixes this request's range. Later queued inputs must not leak in.
        guard let view = try? DurableContext.derive(snapshot: snapshot, conversationID: intent.conversationID, at: intent.inputEntryID) else { return intent.transcript }
        var messages: [Message] = []
        for (entry, contribution) in zip(view.entries, view.contributions) {
            if entry.conversationID != intent.conversationID || entryIDs.contains(entry.id) || entry.id == intent.inputEntryID || entry.head != nil {
                messages.append(contentsOf: contribution)
            }
        }
        return DurableContext.orderToolResults(messages)
    }

    static func checkpoint(intent: DurableGenerationIntent, phase: String) -> JSONValue {
        var object: [String: JSONValue] = ["model": .string(intent.model.id), "provider": .string(intent.model.provider.rawValue), "api": .string(intent.model.api.rawValue), "inputEntryID": .number(Double(intent.inputEntryID)), "phase": .string(phase), "attempt": .number(Double(intent.attempt))]
        if let requestID = intent.requestID { object["requestID"] = .string(requestID) }
        return .object(object)
    }

    static func stagedTerminalCheckpoint(intent: DurableGenerationIntent, terminal: DurableStreamTerminal) throws -> JSONValue {
        let requestID: JSONValue = intent.requestID.map { .string($0) } ?? .null
        return .object(["phase": .string("completing"), "inputEntryID": .number(Double(intent.inputEntryID)), "requestID": requestID, "terminal": try encodeJSON(terminal, maxBytes: DurableLimits.maxCheckpointBytes)])
    }

    static func stagedFailureCheckpoint(_ failure: DurableFailureInfo) throws -> JSONValue {
        .object(["phase": .string("completing"), "failure": try encodeJSON(failure, maxBytes: DurableLimits.maxCheckpointBytes)])
    }

    static func validatedTerminal(message: Message, reason: StopReason, pinned: Model) throws -> DurableStreamTerminal {
        guard message.role == .assistant else { throw DurableGenerationFailure.failure(failureInfo(from: message, defaultCode: "invalid_terminal_role")) }
        if let api = message.api, api != pinned.api { throw DurableGenerationFailure.failure(failureInfo(from: message, defaultCode: "invalid_terminal_api")) }
        if let provider = message.provider, provider != pinned.provider { throw DurableGenerationFailure.failure(failureInfo(from: message, defaultCode: "invalid_terminal_provider")) }
        if let model = message.model, model != pinned.id { throw DurableGenerationFailure.failure(failureInfo(from: message, defaultCode: "invalid_terminal_model")) }
        if let stopReason = message.stopReason, stopReason != reason { throw DurableGenerationFailure.failure(failureInfo(from: message, defaultCode: "invalid_terminal_stop_reason")) }
        if message.deferred != nil { throw DurableGenerationFailure.failure(failureInfo(from: message, defaultCode: "deferred_unsupported")) }
        let calls = message.content.filter { $0.type == "toolCall" }
        if reason == .toolUse {
            guard !calls.isEmpty else { throw DurableGenerationFailure.failure(failureInfo(from: message, defaultCode: "invalid_tool_terminal")) }
        } else {
            guard calls.isEmpty, reason == .stop || reason == .length else { throw DurableGenerationFailure.failure(failureInfo(from: message, defaultCode: errorCode(reason.rawValue))) }
        }
        try validateUsage(message.usage)
        return DurableStreamTerminal(message: message, usage: message.usage, diagnostics: message.diagnostics, stopReason: reason)
    }

    static func failureInfo(from message: Message?, defaultCode: String) -> DurableFailureInfo {
        boundedFailureInfo(DurableFailureInfo(code: message?.errorMessage.map(errorCode) ?? defaultCode, usage: validUsageOrNil(message?.usage), diagnostics: message?.diagnostics))
    }

    static func boundedFailureInfo(_ failure: DurableFailureInfo) -> DurableFailureInfo {
        DurableFailureInfo(code: String(failure.code.prefix(128)), usage: validUsageOrNil(failure.usage), diagnostics: boundedDiagnostics(failure.diagnostics))
    }

    static func boundedDiagnostics(_ diagnostics: [AssistantMessageDiagnostic]?) -> [AssistantMessageDiagnostic]? {
        guard let diagnostics else { return nil }
        do { try DurableNativePreflight.validate(diagnostics, maxBytes: DurableLimits.maxCheckpointBytes / 2); return diagnostics }
        catch { return nil }
    }

    static func validUsageOrNil(_ usage: Usage?) -> Usage? {
        do { try validateUsage(usage); return usage }
        catch { return nil }
    }

    static func validateUsage(_ usage: Usage?) throws {
        guard let usage else { return }
        for value in [usage.input, usage.output, usage.cacheRead, usage.cacheWrite, usage.cacheWrite1h ?? 0, usage.reasoning, usage.totalTokens] {
            guard value >= 0, Int64(value) <= DurableLimits.maxExactInteger else { throw DurableGenerationFailure.failure(DurableFailureInfo(code: "invalid_usage", usage: nil, diagnostics: usageDiagnostics("invalid_counter"))) }
        }
        for value in [usage.cost.input, usage.cost.output, usage.cost.cacheRead, usage.cost.cacheWrite, usage.cost.total] {
            guard value.isFinite, value >= 0 else { throw DurableGenerationFailure.failure(DurableFailureInfo(code: "invalid_usage", usage: nil, diagnostics: usageDiagnostics("non_finite_cost"))) }
        }
    }

    static func usageDiagnostics(_ code: String) -> [AssistantMessageDiagnostic] {
        [AssistantMessageDiagnostic(type: "durable_usage_validation", timestamp: 0, error: DiagnosticError(message: code))]
    }

    static func usageValue(_ usage: Usage?, model: String) -> JSONValue {
        guard let usage else { return .object(["model": .string(model)]) }
        var object: [String: JSONValue] = ["model": .string(model), "input": .number(Double(usage.input)), "output": .number(Double(usage.output)), "cacheRead": .number(Double(usage.cacheRead)), "cacheWrite": .number(Double(usage.cacheWrite)), "reasoning": .number(Double(usage.reasoning)), "totalTokens": .number(Double(usage.totalTokens)), "cost": .object(["input": .number(usage.cost.input), "output": .number(usage.cost.output), "cacheRead": .number(usage.cost.cacheRead), "cacheWrite": .number(usage.cost.cacheWrite), "total": .number(usage.cost.total)])]
        if let cacheWrite1h = usage.cacheWrite1h { object["cacheWrite1h"] = .number(Double(cacheWrite1h)) }
        return .object(object)
    }

    static func aggregateUsageValue(existing: JSONValue?, adding usage: Usage?, model: String) throws -> JSONValue {
        func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
            let (value, overflow) = lhs.addingReportingOverflow(rhs)
            if overflow || value < 0 || Int64(value) > DurableLimits.maxExactInteger { throw DurableGenerationFailure.failure(DurableFailureInfo(code: "usage_overflow", usage: usage, diagnostics: usageDiagnostics("overflow"))) }
            return value
        }
        func checkedCost(_ lhs: Double, _ rhs: Double) throws -> Double {
            let value = lhs + rhs
            if !value.isFinite || value < 0 { throw DurableGenerationFailure.failure(DurableFailureInfo(code: "usage_overflow", usage: usage, diagnostics: usageDiagnostics("cost_overflow"))) }
            return value
        }
        func exactInt(_ value: JSONValue?) throws -> Int {
            guard let number = value?.doubleValue else { return 0 }
            guard number.isFinite, number >= 0, number.rounded(.towardZero) == number, number <= Double(DurableLimits.maxExactInteger) else { throw DurableGenerationFailure.failure(DurableFailureInfo(code: "usage_overflow", usage: usage, diagnostics: usageDiagnostics("invalid_existing_counter"))) }
            return Int(number)
        }
        var input = try exactInt(existing?.objectValue?["input"])
        var output = try exactInt(existing?.objectValue?["output"])
        var cacheRead = try exactInt(existing?.objectValue?["cacheRead"])
        var cacheWrite = try exactInt(existing?.objectValue?["cacheWrite"])
        var cacheWrite1h = try exactInt(existing?.objectValue?["cacheWrite1h"])
        var reasoning = try exactInt(existing?.objectValue?["reasoning"])
        var total = try exactInt(existing?.objectValue?["totalTokens"])
        var costInput = existing?.objectValue?["cost"]?.objectValue?["input"]?.doubleValue ?? 0
        var costOutput = existing?.objectValue?["cost"]?.objectValue?["output"]?.doubleValue ?? 0
        var costCacheRead = existing?.objectValue?["cost"]?.objectValue?["cacheRead"]?.doubleValue ?? 0
        var costCacheWrite = existing?.objectValue?["cost"]?.objectValue?["cacheWrite"]?.doubleValue ?? 0
        var cost = existing?.objectValue?["cost"]?.objectValue?["total"]?.doubleValue ?? 0
        var perModel = existing?.objectValue?["perModel"]?.objectValue ?? [:]
        var perTool = existing?.objectValue?["perTool"]?.objectValue ?? [:]
        let isTool = model.hasPrefix("tool:")
        var modelUsage = (isTool ? perTool[model] : perModel[model])?.objectValue ?? [:]
        if let usage {
            input = try checkedAdd(input, usage.input); output = try checkedAdd(output, usage.output); cacheRead = try checkedAdd(cacheRead, usage.cacheRead); cacheWrite = try checkedAdd(cacheWrite, usage.cacheWrite); cacheWrite1h = try checkedAdd(cacheWrite1h, usage.cacheWrite1h ?? 0); reasoning = try checkedAdd(reasoning, usage.reasoning); total = try checkedAdd(total, usage.totalTokens)
            costInput = try checkedCost(costInput, usage.cost.input); costOutput = try checkedCost(costOutput, usage.cost.output); costCacheRead = try checkedCost(costCacheRead, usage.cost.cacheRead); costCacheWrite = try checkedCost(costCacheWrite, usage.cost.cacheWrite); cost = try checkedCost(cost, usage.cost.total)
            modelUsage = try usageSummaryValue(existing: .object(modelUsage), adding: usage).objectValue ?? modelUsage
        }
        if isTool { perTool[model] = .object(modelUsage) } else { perModel[model] = .object(modelUsage) }
        return .object(["perModel": .object(perModel), "perTool": .object(perTool), "input": .number(Double(input)), "output": .number(Double(output)), "cacheRead": .number(Double(cacheRead)), "cacheWrite": .number(Double(cacheWrite)), "cacheWrite1h": .number(Double(cacheWrite1h)), "reasoning": .number(Double(reasoning)), "totalTokens": .number(Double(total)), "cost": .object(["input": .number(costInput), "output": .number(costOutput), "cacheRead": .number(costCacheRead), "cacheWrite": .number(costCacheWrite), "total": .number(cost)])])
    }

    static func usageSummaryValue(existing: JSONValue?, adding usage: Usage) throws -> JSONValue {
        func exactInt(_ key: String) throws -> Int {
            guard let number = existing?.objectValue?[key]?.doubleValue else { return 0 }
            guard number.isFinite, number >= 0, number.rounded(.towardZero) == number, number <= Double(DurableLimits.maxExactInteger) else { throw DurableGenerationFailure.failure(DurableFailureInfo(code: "usage_overflow", usage: usage, diagnostics: usageDiagnostics("invalid_existing_counter"))) }
            return Int(number)
        }
        func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
            let (value, overflow) = lhs.addingReportingOverflow(rhs)
            if overflow || value < 0 || Int64(value) > DurableLimits.maxExactInteger { throw DurableGenerationFailure.failure(DurableFailureInfo(code: "usage_overflow", usage: usage, diagnostics: usageDiagnostics("overflow"))) }
            return value
        }
        func checkedCost(_ key: String, _ value: Double) throws -> Double {
            let existingValue = existing?.objectValue?["cost"]?.objectValue?[key]?.doubleValue ?? 0
            let result = existingValue + value
            guard existingValue.isFinite, existingValue >= 0, result.isFinite, result >= 0 else { throw DurableGenerationFailure.failure(DurableFailureInfo(code: "usage_overflow", usage: usage, diagnostics: usageDiagnostics("cost_overflow"))) }
            return result
        }
        let input = try checkedAdd(exactInt("input"), usage.input)
        let output = try checkedAdd(exactInt("output"), usage.output)
        let cacheRead = try checkedAdd(exactInt("cacheRead"), usage.cacheRead)
        let cacheWrite = try checkedAdd(exactInt("cacheWrite"), usage.cacheWrite)
        let cacheWrite1h = try checkedAdd(exactInt("cacheWrite1h"), usage.cacheWrite1h ?? 0)
        let reasoning = try checkedAdd(exactInt("reasoning"), usage.reasoning)
        let total = try checkedAdd(exactInt("totalTokens"), usage.totalTokens)
        let costInput = try checkedCost("input", usage.cost.input)
        let costOutput = try checkedCost("output", usage.cost.output)
        let costCacheRead = try checkedCost("cacheRead", usage.cost.cacheRead)
        let costCacheWrite = try checkedCost("cacheWrite", usage.cost.cacheWrite)
        let costTotal = try checkedCost("total", usage.cost.total)
        return .object(["input": .number(Double(input)), "output": .number(Double(output)), "cacheRead": .number(Double(cacheRead)), "cacheWrite": .number(Double(cacheWrite)), "cacheWrite1h": .number(Double(cacheWrite1h)), "reasoning": .number(Double(reasoning)), "totalTokens": .number(Double(total)), "cost": .object(["input": .number(costInput), "output": .number(costOutput), "cacheRead": .number(costCacheRead), "cacheWrite": .number(costCacheWrite), "total": .number(costTotal)])])
    }

    static func pinnedModelIdentity(task: DurableTaskRecord, in snapshot: DurableSnapshot) throws -> String {
        let intent = try intent(for: task, in: snapshot)
        return "\(intent.model.provider.rawValue)/\(intent.model.api.rawValue)/\(intent.model.id)"
    }

    static func document(scope: String, ownerID: Int64, kind: String, in snapshot: DurableSnapshot) -> DurableDocumentRecord? {
        snapshot.documents.values.first { $0.scope == scope && $0.ownerID == ownerID && $0.kind == kind }
    }

    static func queueDocument(id: Int64, conversationID: Int64, existing: DurableDocumentRecord?, adding: Int64?, removing: Int64?) -> DurableDocumentRecord {
        var ids = Set<Int64>()
        if let array = existing?.value.objectValue?["pendingTaskIDs"]?.arrayValue {
            for value in array { if let number = value.doubleValue { ids.insert(Int64(number)) } }
        }
        if let adding { ids.insert(adding) }
        if let removing { ids.remove(removing) }
        return DurableDocumentRecord(id: id, scope: "conversation", ownerID: conversationID, kind: "durable.queue", value: .object(["pendingTaskIDs": .array(ids.sorted().map { .number(Double($0)) })]), createdSeq: existing?.createdSeq ?? 0)
    }

    static func preflightIntent(_ intent: DurableGenerationIntent) throws {
        try preflightMessages(intent.transcript, label: "generation.intent.transcript")
        if let prepared = intent.preparedTranscript { try preflightMessages(prepared, label: "generation.intent.preparedTranscript") }
        var model: [String: JSONValue] = [
            "id": .string(intent.model.id), "name": .string(intent.model.name), "api": .string(intent.model.api.rawValue), "provider": .string(intent.model.provider.rawValue),
            "baseUrl": .string(intent.model.baseUrl), "input": .array(intent.model.input.map { .string($0) }), "contextWindow": .number(Double(intent.model.contextWindow)), "maxTokens": .number(Double(intent.model.maxTokens))
        ]
        if let sampling = intent.model.samplingParams { model["samplingParams"] = .object(sampling) }
        if let levels = intent.model.samplingParamsByThinkingLevel { model["samplingParamsByThinkingLevel"] = .object(Dictionary(uniqueKeysWithValues: levels.map { ($0.key.rawValue, JSONValue.object($0.value)) })) }
        if let limits = intent.model.inputLimits { model["inputLimits"] = .object(limits) }
        if let cache = intent.model.promptCache { model["promptCache"] = .object(cache) }
        if let providers = intent.model.providers { model["providers"] = .array(providers) }
        var options: [String: JSONValue] = [:]
        if let temperature = intent.options.temperature { options["temperature"] = .number(temperature) }
        if let maxTokens = intent.options.maxTokens { options["maxTokens"] = .number(Double(maxTokens)) }
        if let sampling = intent.options.samplingParams { options["samplingParams"] = .object(sampling) }
        if let metadata = intent.options.metadata { options["metadata"] = .object(metadata) }
        for (key, value) in [("region", intent.options.region), ("profile", intent.options.profile), ("project", intent.options.project), ("location", intent.options.location), ("textVerbosity", intent.options.textVerbosity), ("sessionId", intent.options.sessionId), ("azureApiVersion", intent.options.azureApiVersion), ("azureResourceName", intent.options.azureResourceName), ("azureDeploymentName", intent.options.azureDeploymentName)] where value != nil { options[key] = .string(value!) }
        var value: [String: JSONValue] = ["conversationID": .number(Double(intent.conversationID)), "inputEntryID": .number(Double(intent.inputEntryID)), "model": .object(model), "transcriptCount": .number(Double(intent.transcript.count)), "options": .object(options), "attempt": .number(Double(intent.attempt)), "toolCount": .number(Double((intent.offeredTools ?? []).count)), "round": .number(Double(intent.round ?? 1))]
        if let prompt = intent.systemPrompt { value["systemPrompt"] = .string(prompt) }
        if let requestID = intent.requestID { value["requestID"] = .string(requestID) }
        if let payloadHash = intent.payloadHash { value["payloadHash"] = .string(payloadHash) }
        try preflightJSON(.object(value), label: "generation.intent")
    }

    static func preflightMessages(_ messages: [Message], label: String) throws {
        let snapshot = DurableSnapshot(seq: 1, highWaterID: 1, conversations: [1: DurableConversationRecord(id: 1, createdSeq: 1)])
        _ = try DurableValidation.validate(batch: DurableCommitBatch(entries: [DurableEntryRecord(id: 2, conversationID: 1, kind: label, messages: messages)]), against: snapshot)
    }

    static func preflightJSON(_ value: JSONValue, label: String) throws {
        let snapshot = DurableSnapshot(seq: 1, highWaterID: 1, conversations: [1: DurableConversationRecord(id: 1, createdSeq: 1)])
        _ = try DurableValidation.validate(batch: DurableCommitBatch(documents: [DurableDocumentRecord(id: 2, scope: "conversation", ownerID: 1, kind: label, value: value)]), against: snapshot)
    }

    static func encodeJSON<T: Encodable>(_ value: T, maxBytes: Int = DurableLimits.maxDocumentBytes) throws -> JSONValue {
        try DurableNativePreflight.validate(value, maxBytes: maxBytes)
        return try JSONDecoder().decode(JSONValue.self, from: DurableValidation.encoder.encode(value))
    }

    static func decodeJSON<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        try JSONDecoder().decode(T.self, from: DurableValidation.encoder.encode(value))
    }

    static func errorCode(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("timeout") { return "timeout" }
        if lower.contains("rate") { return "rate_limited" }
        if lower.contains("auth") || lower.contains("key") || lower.contains("token") { return "auth_error" }
        if lower.contains("tool") { return "tool_use_unsupported" }
        if lower.contains("deferred") { return "deferred_unsupported" }
        return "provider_error"
    }
}

enum DurableGenerationFailure: Error, Sendable {
    case failure(DurableFailureInfo)
    case outputLimit(DurableFailureInfo)
}
