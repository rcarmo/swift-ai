# Swift durable S1a native foundation design

S1a adds the storage and mutation-line foundation. S1b adds a persistent no-tool generation/session vertical on top of it. S1b is still not the useful tool-capable durable harness: tools, subagents, hooks, compaction, inbox steering and watches remain later work.

## Scope

S1a adds six runtime files under `Sources/SwiftAI/Durable`:

- `DurableRecords.swift` defines typed records, writes, snapshots, errors and fixed limits.
- `DurableStorage.swift` defines the storage protocol and shared validation.
- `DurableMemoryStorage.swift` implements an in-memory reference backend.
- `DurableJournalLock.swift` implements a Linux/macOS POSIX lock.
- `DurableJournalStorage.swift` implements a single-owner framed journal backend.
- `DurableMutationGate.swift` implements a bounded owned mutation queue.

The tests live under `Tests/SwiftAITests/Durable`. SwiftPM discovers these files without a package manifest edit.

## Storage model

Storage commits batches of conversation, entry, task, submission and document records. Each commit receives a strictly increasing sequence. IDs are signed 64-bit integers but are admitted only in the exact JSON range `1...(2^53 - 1)`. The allocator high-water mark is part of the committed journal frame. `metadata.json` is not used as authority in S1a.

Records are strict Codable values. `JSONValue.number` must be finite. JSON depth, node count and string/key size are bounded before encoding, then encoded sizes gate storage admission. Record IDs share one global namespace across conversations, entries, tasks, submissions and documents. Task/submission/document identity is immutable after creation and task owner chains must stay acyclic within one conversation.

## Journal format

Each journal frame stores:

- magic and frame version;
- sequence and allocator high-water;
- payload length;
- payload SHA-256;
- JSON payload;
- terminator with sequence and a header hash.

A complete bad checksum, bad terminator, sequence gap, sequence duplicate, allocator rollback or unknown version fails closed with `DurableError.corruptStorage`. Only an incomplete final EOF frame may be ignored and truncated before the next append. The implementation does not scan for later magic bytes. Append, file-sync, directory-sync and acknowledgement seams are classified as uncertain durability failures; storage is poisoned after such a failure.

## Mutation gate

`DurableMutationGate` is independent of Swift actor reentrancy. Public submissions are queued. Cancelling before admission removes the queued job. Once a job is admitted, the write/settle/adopt-or-poison/publication step is owned by the gate and is not cancelled by a dropped caller. `close()` seals public admission and waits for admitted work to drain.

## S1b no-tool generation

`DurableSession` owns a FIFO executor and mutation gate. Admission persists an input entry, pending task, request-scoped submission, queue document and full pinned intent before provider effects. The pinned intent strips auth, callback, telemetry, transport and endpoint fields; at dispatch, the runtime overlays only the current registry endpoint/headers while preserving pinned behavior fields.

Provider streams must produce exactly one terminal. Stop/length assistant terminals settle as answers. Error, deferred, tool-use and invalid terminal identity/usage settle as typed durable failures. Usage documents retain complete counters/cost and conversation aggregates by pinned provider/API/model identity.

Before JSON encoding, S1b walks complete native intent/terminal/failure DTOs with shared depth/node/string/total-byte budgets. The native estimator deliberately uses conservative container/key/enum overhead, so its accepted payload headroom can be smaller than the encoded byte ceiling; fixed public limits are not widened to compensate.

Open is zero-effect. Explicit resume scans durable pending/running/completing tasks and feeds them through the bounded owned FIFO in successive batches. Running recovery reuses the persisted prepared transcript; staged success/failure recovery finalizes without another provider call. Public admission and observer waiters reserve bounded capacity before commit. Cancelling an observer removes only that waiter; committed work continues under session ownership.

Close seals new admission, drains admitted work, closes storage exactly once and preserves its common result. An unexpected executor or uncertain storage error seals the session, fails queued observers without starting their provider effects, and runs the same owned close workflow. Typed provider terminals settle as durable task failures and do not stop later queued generations.

## S1c owned tools

S1c snapshots bounded tool declarations, implementation identity, schema identity and replay policy into each generation intent. The runtime validates the declared schema subset without coercion, commits assistant tool calls and serial child intents before effects, then executes children inline under the owned generation workflow and commits ordered native tool-result messages before the successor model round. This serial design is bounded and does not claim parallel child scheduling or worker-slot yielding. Later generation context reconstructs prior assistant calls and child results in entry order, including submissions without request IDs.

A child progresses through pending, started, completing and terminal checkpoints. Safe started recovery uses the same durable idempotency key and records physical-invocation billing uncertainty until durable evidence resolves it. Unsafe started recovery performs no second effect and returns an interrupted result. Staged results finalize without another effect. Tool and model receipts use round/attempt-specific kinds and checked conversation aggregates.

Tool application writes are data, not escaping storage closures. The runtime constructs `tool.application.<tool>.<suffix>` kinds, restricts scope to the parent conversation or current child, allocates IDs itself and proves the original child creator on updates. Invalid or mixed document sets commit no application writes while retaining valid billed usage.

Explicit abort is separate from observer cancellation. Parent abort propagates to non-terminal children; child-only abort returns an ordered error result. Close retains the journal writer while model or tool effects remain owned. Live endpoint/auth resolution returns only a process-local connection DTO and cannot change pinned behaviour; resolver values and errors are absent from durable bytes.

## Platform scope

The persistent journal backend is supported on Linux and macOS in S1a. Other platforms get a typed unsupported-storage error. macOS must still be verified on a real macOS host before claiming production persistence support there. No workflow is added for that proof in S1a.
