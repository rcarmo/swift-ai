import Foundation
import XCTest
@testable import SwiftAI

private final class GateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var releaseReady = false
    private var releaseReadyContinuation: CheckedContinuation<Void, Never>?
    private var values: [String] = []
    private var queuedIDs = Set<Int64>()
    private var queuedContinuations: [Int64: CheckedContinuation<Void, Never>] = [:]
    private var closeSealed = false
    private var closeSealedContinuation: CheckedContinuation<Void, Never>?
    private var closeWaiterIDs = Set<Int64>()
    private var closeWaiterContinuations: [Int64: CheckedContinuation<Void, Never>] = [:]
    private var cancelledCloseWaiterIDs = Set<Int64>()
    private var cancelledCloseWaiterContinuations: [Int64: CheckedContinuation<Void, Never>] = [:]

    func append(_ value: String) { lock.lock(); values.append(value); lock.unlock() }
    func setRelease(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        self.continuation = continuation
        releaseReady = true
        let readyContinuation = releaseReadyContinuation
        releaseReadyContinuation = nil
        lock.unlock()
        readyContinuation?.resume()
    }
    func waitReleaseReady() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if releaseReady { lock.unlock(); continuation.resume(); return }
            releaseReadyContinuation = continuation
            lock.unlock()
        }
    }
    func release() { lock.lock(); let continuation = self.continuation; self.continuation = nil; lock.unlock(); continuation?.resume() }
    func effects() -> [String] { lock.lock(); defer { lock.unlock() }; return values }
    func markQueued(_ id: Int64) {
        lock.lock()
        queuedIDs.insert(id)
        let continuation = queuedContinuations.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume()
    }
    func waitQueued(_ id: Int64) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if queuedIDs.contains(id) { lock.unlock(); continuation.resume(); return }
            queuedContinuations[id] = continuation
            lock.unlock()
        }
    }
    func markCloseSealed() {
        lock.lock()
        closeSealed = true
        let continuation = closeSealedContinuation
        closeSealedContinuation = nil
        lock.unlock()
        continuation?.resume()
    }
    func waitCloseSealed() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if closeSealed { lock.unlock(); continuation.resume(); return }
            closeSealedContinuation = continuation
            lock.unlock()
        }
    }
    func markCloseWaiter(_ id: Int64) {
        lock.lock()
        closeWaiterIDs.insert(id)
        let continuation = closeWaiterContinuations.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume()
    }
    func waitCloseWaiter(_ id: Int64) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if closeWaiterIDs.contains(id) { lock.unlock(); continuation.resume(); return }
            closeWaiterContinuations[id] = continuation
            lock.unlock()
        }
    }
    func markCancelledCloseWaiter(_ id: Int64) {
        lock.lock()
        cancelledCloseWaiterIDs.insert(id)
        let continuation = cancelledCloseWaiterContinuations.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume()
    }
    func waitCancelledCloseWaiter(_ id: Int64) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if cancelledCloseWaiterIDs.contains(id) { lock.unlock(); continuation.resume(); return }
            cancelledCloseWaiterContinuations[id] = continuation
            lock.unlock()
        }
    }
}

final class DurableMutationGateTests: XCTestCase {
    func testCloseWaitsAdmittedAndRejectsQueuedAndPostClose() async throws {
        let box = GateBox()
        let gate = DurableMutationGate(testingHooks: DurableMutationGateTestingHooks(onQueued: { box.markQueued($0) }, onCloseSealed: { box.markCloseSealed() }))
        let first = Task { try await gate.submit { () async throws -> String in box.append("first-start"); await withCheckedContinuation { box.setRelease($0) }; box.append("first-end"); return "first" } }
        await box.waitReleaseReady()
        let second = Task { try await gate.submit { () async throws -> String in box.append("second"); return "second" } }
        await box.waitQueued(2)
        let closed = Task { try await gate.close() }
        await box.waitCloseSealed()
        XCTAssertEqual(box.effects(), ["first-start"])
        box.release()
        let firstValue = try await first.value
        XCTAssertEqual(firstValue, "first")
        await XCTAssertThrowsAsyncError(try await second.value)
        try await closed.value
        await XCTAssertThrowsAsyncError(try await gate.submit { "late" })
        XCTAssertEqual(box.effects(), ["first-start", "first-end"])
    }

    func testAfterAdmissionCallerCancellationDoesNotCancelEffect() async throws {
        let box = GateBox()
        let gate = DurableMutationGate(testingHooks: DurableMutationGateTestingHooks(onQueued: { box.markQueued($0) }))
        let admitted = Task { try await gate.submit { () async throws -> String in box.append("start"); await withCheckedContinuation { box.setRelease($0) }; box.append("end"); return "done" } }
        await box.waitQueued(1)
        await box.waitReleaseReady()
        admitted.cancel()
        XCTAssertEqual(box.effects(), ["start"])
        box.release()
        let value = try await admitted.value
        XCTAssertEqual(value, "done")
        XCTAssertEqual(box.effects(), ["start", "end"])
    }

    func testConcurrentCancelledCloseObserverDoesNotCancelCommonClose() async throws {
        let box = GateBox()
        let gate = DurableMutationGate(testingHooks: DurableMutationGateTestingHooks(onQueued: { box.markQueued($0) }, onCloseWaiter: { box.markCloseWaiter($0) }, onCloseWaiterCancelled: { box.markCancelledCloseWaiter($0) }))
        let first = Task { try await gate.submit { () async throws -> String in box.append("start"); await withCheckedContinuation { box.setRelease($0) }; box.append("end"); return "done" } }
        await box.waitQueued(1)
        await box.waitReleaseReady()
        let closeA = Task { try await gate.close() }
        await box.waitCloseWaiter(1)
        let closeB = Task { try await gate.close() }
        await box.waitCloseWaiter(2)
        closeB.cancel()
        await box.waitCancelledCloseWaiter(2)
        box.release()
        let firstValue = try await first.value
        XCTAssertEqual(firstValue, "done")
        try await closeA.value
        await XCTAssertThrowsAsyncError(try await closeB.value)
        await XCTAssertThrowsAsyncError(try await gate.submit { "late" })
        XCTAssertEqual(box.effects(), ["start", "end"])
    }

    func testUncertainDurabilitySealsGateAndPreservesFailedClose() async throws {
        let gate = DurableMutationGate()
        let box = GateBox()
        let first = Task { try await gate.submit { () async throws -> String in throw DurableError.durabilityUncertain("injected uncertain ACK") } }
        await XCTAssertThrowsAsyncError(try await first.value) { error in
            XCTAssertTrue(String(describing: error).contains("uncertain"))
        }
        await XCTAssertThrowsAsyncError(try await gate.submit { () async throws -> String in box.append("late-effect"); return "late" }) { error in
            XCTAssertTrue(String(describing: error).contains("uncertain"))
        }
        await XCTAssertThrowsAsyncError(try await gate.close()) { error in
            XCTAssertTrue(String(describing: error).contains("uncertain"))
        }
        XCTAssertEqual(box.effects(), [])
    }

    func testCancellationBeforeDequeuePreventsEffectAndPoisonWaitsAdmitted() async throws {
        let box = GateBox()
        let gate = DurableMutationGate(testingHooks: DurableMutationGateTestingHooks(onQueued: { box.markQueued($0) }, onCloseSealed: { box.markCloseSealed() }))
        let first = Task { try await gate.submit { () async throws -> String in box.append("first-start"); await withCheckedContinuation { box.setRelease($0) }; box.append("first-end"); return "first" } }
        await box.waitReleaseReady()
        let cancelled = Task { try await gate.submit { () async throws -> String in box.append("cancelled"); return "cancelled" } }
        await box.waitQueued(2)
        cancelled.cancel()
        await gate.poison("boom")
        let close = Task { try await gate.close() }
        await box.waitCloseSealed()
        XCTAssertEqual(box.effects(), ["first-start"])
        box.release()
        let firstValue = try await first.value
        XCTAssertEqual(firstValue, "first")
        await XCTAssertThrowsAsyncError(try await cancelled.value)
        await XCTAssertThrowsAsyncError(try await close.value) { error in XCTAssertTrue(String(describing: error).contains("boom")) }
        XCTAssertEqual(box.effects(), ["first-start", "first-end"])
        await XCTAssertThrowsAsyncError(try await gate.submit { "late" })
    }
}
