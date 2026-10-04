# Swift durable S1a contract crosswalk

| Contract area | S1a disposition |
|---|---|
| Atomic session commit across records and documents | Implemented for storage batches in memory and journal backends; focused tests cover mixed record/document commits. |
| Commit-before-visibility | Implemented at the storage boundary: journal state advances only after append, file sync, directory sync and acknowledgement. No UI watcher exists yet. |
| Request ID deduplication | Implemented at storage level for conversation-scoped submissions. Incompatible reuse fails; duplicate initial indexes poison memory storage. |
| Strict record validation | Implemented for global IDs, immutable identities, task/submission transitions, references, owner cycles, document addresses, finite/bounded JSON, payload sizes and terminal immutability. |
| Persistent reopen | Implemented for the journal backend. Valid frames replay to a snapshot. |
| Torn final frame recovery | Implemented only for incomplete final EOF frames; interior or complete corruption fails closed. |
| Corruption fail-closed | Implemented for complete checksum/terminator/version/sequence/allocator damage. |
| Uncertain storage failure poison | Implemented as `DurableError.durabilityUncertain` on failed append/sync/ack seams followed by poisoned storage state. |
| Close versus abort | `close()` seals admission and drains admitted generation work. Observer cancellation detaches only the caller. Unexpected executor/storage failure seals the session, prevents queued provider effects and runs owned cleanup. Durable abort is later work. |
| Built-in generation/tool execution | S1b implements persistent no-tool provider generation through the public stream registry; tool execution remains S1c. |
| Tool replay policy | S1c pins declarations, implementation/schema identity and safe/unsafe policy. Pending work executes once; staged results finalize without effect; started safe work reuses the durable idempotency key with explicit billing uncertainty; started unsafe work settles interrupted without a second effect. Deferred terminals remain unsupported. |
| Ownership drain | S1c creates serial child tool tasks and executes them inline under the owned generation workflow. The parent remains waiting until ordered child settlement; abort and close retain model/tool effects and the journal writer through cleanup. |
| Persistent no-tool recovery | S1b open is zero-effect; explicit resume processes pinned pending/running/completing work through bounded batches and finalizes staged success, typed failure and context-limit checkpoints without rebilling. Journal SIGKILL tests cover admission and post-provider Completing acknowledgement loss. |
| Fork/reset/inbox/compaction/hooks/extensions | Later phases. |
| Watches/events/task graph | Later phases. |
| SQLite/JSONL alternative backends | Later optional phases. |
| Cross-language storage compatibility | Not claimed. |
## Official source inventory crosswalk

Fixed official v1.0.1 durable source inventory: 60 paths. S1a maps only the native storage and mutation-line foundation. Remaining paths stay planned for later phases.

| # | Official source path | Swift S1a disposition |
|---:|---|---|
| 1 | `packages/durable/src/documents.ts` | S1a record shape subset only; public typed definitions/tasks later. |
| 2 | `packages/durable/src/entries.ts` | S1a record shape subset only; public typed definitions/tasks later. |
| 3 | `packages/durable/src/env/index.ts` | Later environment phase. |
| 4 | `packages/durable/src/env/node.ts` | Later environment phase. |
| 5 | `packages/durable/src/errors.ts` | Native equivalents only where needed by S1a errors/limits; broader exports later. |
| 6 | `packages/durable/src/harness/agent.ts` | Later harness/provider/tool execution phase. |
| 7 | `packages/durable/src/harness/compaction.ts` | Later harness/provider/tool execution phase. |
| 8 | `packages/durable/src/harness/context.ts` | Later harness/provider/tool execution phase. |
| 9 | `packages/durable/src/harness/define.ts` | Later harness/provider/tool execution phase. |
| 10 | `packages/durable/src/harness/events.ts` | Later harness/provider/tool execution phase. |
| 11 | `packages/durable/src/harness/generation.ts` | Later harness/provider/tool execution phase. |
| 12 | `packages/durable/src/harness/harness.ts` | Later harness/provider/tool execution phase. |
| 13 | `packages/durable/src/harness/inbox.ts` | Later harness/provider/tool execution phase. |
| 14 | `packages/durable/src/harness/json.ts` | Later harness/provider/tool execution phase. |
| 15 | `packages/durable/src/harness/live.ts` | Later harness/provider/tool execution phase. |
| 16 | `packages/durable/src/harness/output.ts` | Later harness/provider/tool execution phase. |
| 17 | `packages/durable/src/harness/prompt.ts` | Later harness/provider/tool execution phase. |
| 18 | `packages/durable/src/harness/registry.ts` | Later harness/provider/tool execution phase. |
| 19 | `packages/durable/src/harness/scheduler.ts` | Later harness/provider/tool execution phase. |
| 20 | `packages/durable/src/harness/submissions.ts` | Later harness/provider/tool execution phase. |
| 21 | `packages/durable/src/harness/task-graph.ts` | Later harness/provider/tool execution phase. |
| 22 | `packages/durable/src/harness/tool.ts` | Later harness/provider/tool execution phase. |
| 23 | `packages/durable/src/harness/types.ts` | Later harness/provider/tool execution phase. |
| 24 | `packages/durable/src/harness/usage.ts` | Later harness/provider/tool execution phase. |
| 25 | `packages/durable/src/harness/util.ts` | Later harness/provider/tool execution phase. |
| 26 | `packages/durable/src/harness/view.ts` | Later harness/provider/tool execution phase. |
| 27 | `packages/durable/src/ids.ts` | S1a native foundation subset: records, validation, storage snapshots/commits, request-ID index. |
| 28 | `packages/durable/src/index.ts` | Native equivalents only where needed by S1a errors/limits; broader exports later. |
| 29 | `packages/durable/src/session/forks.ts` | Later session surface; S1a implements storage/gate foundations only. |
| 30 | `packages/durable/src/session/observation.ts` | Later session surface; S1a implements storage/gate foundations only. |
| 31 | `packages/durable/src/session/session.ts` | S1a native foundation subset: records, validation, storage snapshots/commits, request-ID index. |
| 32 | `packages/durable/src/session/transaction.ts` | S1a native foundation subset: records, validation, storage snapshots/commits, request-ID index. |
| 33 | `packages/durable/src/storage/jsonl/index.ts` | Later optional backend; S1a uses native framed journal, not JSONL/SQLite. |
| 34 | `packages/durable/src/storage/jsonl/node.ts` | Later optional backend; S1a uses native framed journal, not JSONL/SQLite. |
| 35 | `packages/durable/src/storage/jsonl/storage.ts` | Later optional backend; S1a uses native framed journal, not JSONL/SQLite. |
| 36 | `packages/durable/src/storage/memory.ts` | S1a native foundation subset: records, validation, storage snapshots/commits, request-ID index. |
| 37 | `packages/durable/src/storage/sqlite/database.ts` | Later optional backend; S1a uses native framed journal, not JSONL/SQLite. |
| 38 | `packages/durable/src/storage/sqlite/index.ts` | Later optional backend; S1a uses native framed journal, not JSONL/SQLite. |
| 39 | `packages/durable/src/storage/sqlite/migrations.ts` | Later optional backend; S1a uses native framed journal, not JSONL/SQLite. |
| 40 | `packages/durable/src/storage/sqlite/node.ts` | Later optional backend; S1a uses native framed journal, not JSONL/SQLite. |
| 41 | `packages/durable/src/storage/sqlite/storage.ts` | Later optional backend; S1a uses native framed journal, not JSONL/SQLite. |
| 42 | `packages/durable/src/tasks.ts` | S1a record shape subset only; public typed definitions/tasks later. |
| 43 | `packages/durable/src/testing/assertions.ts` | Adapted through Swift focused storage/gate tests, not a public testing module. |
| 44 | `packages/durable/src/testing/index.ts` | Adapted through Swift focused storage/gate tests, not a public testing module. |
| 45 | `packages/durable/src/testing/runner.ts` | Adapted through Swift focused storage/gate tests, not a public testing module. |
| 46 | `packages/durable/src/testing/storage-benchmark.ts` | Adapted through Swift focused storage/gate tests, not a public testing module. |
| 47 | `packages/durable/src/testing/storage-conformance.ts` | Adapted through Swift focused storage/gate tests, not a public testing module. |
| 48 | `packages/durable/src/testing/types.ts` | Adapted through Swift focused storage/gate tests, not a public testing module. |
| 49 | `packages/durable/src/tools/bash.ts` | Later built-in tools/environment phase. |
| 50 | `packages/durable/src/tools/edit-diff.ts` | Later built-in tools/environment phase. |
| 51 | `packages/durable/src/tools/edit.ts` | Later built-in tools/environment phase. |
| 52 | `packages/durable/src/tools/env.ts` | Later built-in tools/environment phase. |
| 53 | `packages/durable/src/tools/file-mutation-queue.ts` | Later built-in tools/environment phase. |
| 54 | `packages/durable/src/tools/image.ts` | Later built-in tools/environment phase. |
| 55 | `packages/durable/src/tools/index.ts` | Later built-in tools/environment phase. |
| 56 | `packages/durable/src/tools/path-utils.ts` | Later built-in tools/environment phase. |
| 57 | `packages/durable/src/tools/read.ts` | Later built-in tools/environment phase. |
| 58 | `packages/durable/src/tools/write.ts` | Later built-in tools/environment phase. |
| 59 | `packages/durable/src/truncate.ts` | Native equivalents only where needed by S1a errors/limits; broader exports later. |
| 60 | `packages/durable/src/types.ts` | S1a native foundation subset: records, validation, storage snapshots/commits, request-ID index. |
