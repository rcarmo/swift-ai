# Swift durable S1a native foundation design

S1a adds the storage and mutation-line foundation for a later durable agent harness. It is not the useful durable harness: it does not run providers, tools, subagents, hooks, compaction, inbox steering or watches.

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

## Platform scope

The persistent journal backend is supported on Linux and macOS in S1a. Other platforms get a typed unsupported-storage error. macOS must still be verified on a real macOS host before claiming production persistence support there. No workflow is added for that proof in S1a.
