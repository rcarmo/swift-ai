# Swift durable S1a test crosswalk

The official durable package has 42 test suites. S1a covers storage/mutation foundations; S1b adds the persistent no-tool session/generation/recovery subset.

| # | Upstream suite | S1a disposition |
|---:|---|---|
| 1 | `chord-guide.test.ts` | Later: Chord-style document operations. |
| 2 | `env-node-spill.test.ts` | Later: environment spill files. |
| 3 | `env-node.test.ts` | Later: local tool environment. |
| 4 | `env-truncate.test.ts` | Later: tool output spill/truncation. |
| 5 | `harness-compaction.test.ts` | Later: compaction tasks. |
| 6 | `harness-context.test.ts` | Later: provider context assembly. |
| 7 | `harness-conversations.test.ts` | S1a covers root conversation records only. |
| 8 | `harness-events.test.ts` | Later: committed event stream. |
| 9 | `harness-generation-recovery.test.ts` | S1b covers bounded explicit resume, pinned-intent recovery, staged success/failure recovery and journal SIGKILL at admission and Completing acknowledgement seams. |
| 10 | `harness-generation.test.ts` | S1b covers persistent no-tool provider streaming and terminal settlement. |
| 11 | `harness-inbox.test.ts` | Later: inbox steering/follow-up. |
| 12 | `harness-inspect.test.ts` | Later: inspection API. |
| 13 | `harness-lifecycle.test.ts` | S1a covers storage/gate lifecycle; S1b covers cancellation-aware session observers, owned drain and fail-stop cleanup. |
| 14 | `harness-live-deltas.test.ts` | Later: live deltas. |
| 15 | `harness-output.test.ts` | Later: tool output commits. |
| 16 | `harness-ownership.test.ts` | S1a covers record owner validation; S1b keeps committed generation and close workflows alive after observer cancellation. |
| 17 | `harness-prompt.test.ts` | Later: prompt/section replay. |
| 18 | `harness-registry.test.ts` | Later: extension registry. |
| 19 | `harness-structured.test.ts` | Later: structured provider requests. |
| 20 | `harness-submissions.test.ts` | S1a covers records/request IDs; S1b covers durable placed/done/unanswered generation submissions and semantic idempotency. |
| 21 | `harness-task-graph.test.ts` | Later: graph view. |
| 22 | `harness-tasks-recovery.test.ts` | S1a covers checkpoint validation; S1b recovers Running prepared context, Running context failure and Completing success/failure checkpoints. |
| 23 | `harness-tasks.test.ts` | S1a covers task records only. |
| 24 | `harness-tools-recovery.test.ts` | Later: replay-safe tools. |
| 25 | `harness-tools.test.ts` | Later: durable tools. |
| 26 | `harness-view.test.ts` | Later: conversation view. |
| 27 | `jsonl-storage.test.ts` | Later optional backend. |
| 28 | `memory-storage.test.ts` | Covered by `DurableMemoryStorageTests`. |
| 29 | `session-checkpoints-migrations.test.ts` | S1a covers schema/version corruption checks. |
| 30 | `session-definitions.test.ts` | Later typed definitions. |
| 31 | `session-documents.test.ts` | S1a covers full JSON document records. |
| 32 | `session-forks.test.ts` | Later forks. |
| 33 | `session-states.test.ts` | S1a covers snapshots and close/poison states. |
| 34 | `session-tables.test.ts` | S1a covers record tables through storage snapshots. |
| 35 | `session-watches.test.ts` | Later watches. |
| 36 | `spec-usage.test.ts` | Later usage documents. |
| 37 | `sqlite-facade.test.ts` | Later optional SQLite. |
| 38 | `sqlite-migrations.test.ts` | Later optional SQLite. |
| 39 | `sqlite-storage.test.ts` | Later optional SQLite. |
| 40 | `storage-runtime-boundary.test.ts` | Covered by memory/journal close and validation tests. |
| 41 | `tools.test.ts` | Later built-in tools. |
| 42 | `types.test.ts` | S1a covers Codable/Sendable durable records and errors. |
