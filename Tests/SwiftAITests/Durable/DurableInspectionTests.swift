import XCTest
@testable import SwiftAI

final class DurableInspectionTests: XCTestCase {
    func testPagesFilterAndBoundAllTables() throws {
        let snapshot = DurableSnapshot(
            seq: 1,
            highWaterID: 5,
            conversations: [1: DurableConversationRecord(id: 1, createdSeq: 1)],
            entries: [2: DurableEntryRecord(id: 2, conversationID: 1, kind: "input", createdSeq: 1)],
            tasks: [3: DurableTaskRecord(id: 3, conversationID: 1, kind: "generation", createdSeq: 1)],
            submissions: [4: DurableSubmissionRecord(id: 4, conversationID: 1, type: .input, createdSeq: 1)],
            documents: [5: DurableDocumentRecord(id: 5, scope: "conversation", ownerID: 1, kind: "doc", value: .object([:]), createdSeq: 1)]
        )
        let inspection = DurableInspection(snapshot: snapshot)
        XCTAssertEqual(try inspection.entries(conversationID: 1, limit: 1).values.map(\.id), [2])
        XCTAssertEqual(try inspection.tasks(conversationID: 1).values.map(\.id), [3])
        XCTAssertEqual(try inspection.submissions(conversationID: 1).values.map(\.id), [4])
        XCTAssertEqual(try inspection.documents(scope: "conversation", ownerID: 1).values.map(\.id), [5])
        XCTAssertThrowsError(try inspection.entries(offset: -1))
    }

    func testRecoveryPlanIsPassiveAndTruthful() {
        let snapshot = DurableSnapshot(seq: 1, highWaterID: 4, conversations: [1: DurableConversationRecord(id: 1, createdSeq: 1)], entries: [4: DurableEntryRecord(id: 4, conversationID: 1, kind: "input", createdSeq: 1)], tasks: [2: DurableTaskRecord(id: 2, conversationID: 1, kind: "generation", status: .running, createdSeq: 1)], submissions: [3: DurableSubmissionRecord(id: 3, conversationID: 1, type: .input, status: .placed, entryID: 4, createdSeq: 1)])
        let plan = DurableRecovery.plan(from: snapshot)
        XCTAssertEqual(plan.runningTasks.map(\.id), [2])
        XCTAssertEqual(plan.placedSubmissions.map(\.id), [3])
    }
}
