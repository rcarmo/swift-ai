import Foundation

public struct DurableRecoveryPlan: Sendable, Equatable {
    public var queuedSubmissions: [DurableSubmissionRecord]
    public var placedSubmissions: [DurableSubmissionRecord]
    public var runningTasks: [DurableTaskRecord]
    public var toolTasks: [DurableTaskRecord]
    public var waitingGenerations: [DurableTaskRecord]
    public init(queuedSubmissions: [DurableSubmissionRecord], placedSubmissions: [DurableSubmissionRecord], runningTasks: [DurableTaskRecord], toolTasks: [DurableTaskRecord] = [], waitingGenerations: [DurableTaskRecord] = []) {
        self.queuedSubmissions = queuedSubmissions
        self.placedSubmissions = placedSubmissions
        self.runningTasks = runningTasks
        self.toolTasks = toolTasks
        self.waitingGenerations = waitingGenerations
    }
}

public enum DurableRecovery {
    public static func plan(from snapshot: DurableSnapshot) -> DurableRecoveryPlan {
        DurableRecoveryPlan(
            queuedSubmissions: snapshot.submissions.values.filter { $0.status == .queued }.sorted { $0.id < $1.id },
            placedSubmissions: snapshot.submissions.values.filter { $0.status == .placed }.sorted { $0.id < $1.id },
            runningTasks: snapshot.tasks.values.filter { [.running, .waiting, .completing].contains($0.status) }.sorted { $0.id < $1.id },
            toolTasks: snapshot.tasks.values.filter { $0.kind == "tool" && [.pending, .running, .completing].contains($0.status) }.sorted { $0.id < $1.id },
            waitingGenerations: snapshot.tasks.values.filter { $0.kind == "generation" && $0.status == .waiting }.sorted { $0.id < $1.id }
        )
    }
}
