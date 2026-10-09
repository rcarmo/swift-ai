# pi-durable v1.1.0 candidate audit

Pinned official tag `abe508e1b89912adde45528136c3221eb69acdd7`, compared with v1.0.1 `a7229ddc21810d6245105978033b7df645ecc2f7`.

Exact scope: 59 changed paths, 21 changed test paths, 90 whole-corpus paths. This one-hour candidate is not accepted release parity. Rows marked `pending` still need individual production/test disposition.

| # | Changed path | Disposition |
|---|---|---|
| 1 | `M packages/durable/CHANGELOG.md` | reference -- native version/docs updated; JS packaging excluded |
| 2 | `M packages/durable/README.md` | reference -- native version/docs updated; JS packaging excluded |
| 3 | `M packages/durable/docs/spec.md` | pending -- exact behaviour/test audit required |
| 4 | `M packages/durable/package.json` | reference -- native version/docs updated; JS packaging excluded |
| 5 | `A packages/durable/src/env/decode.ts` | pending -- exact behaviour/test audit required |
| 6 | `M packages/durable/src/env/index.ts` | pending -- exact behaviour/test audit required |
| 7 | `A packages/durable/src/env/line-scan.ts` | pending -- exact behaviour/test audit required |
| 8 | `A packages/durable/src/env/node-watch.ts` | pending -- exact behaviour/test audit required |
| 9 | `M packages/durable/src/env/node.ts` | pending -- exact behaviour/test audit required |
| 10 | `M packages/durable/src/harness/agent.ts` | pending -- exact behaviour/test audit required |
| 11 | `M packages/durable/src/harness/compaction.ts` | pending -- exact behaviour/test audit required |
| 12 | `M packages/durable/src/harness/context.ts` | pending -- exact behaviour/test audit required |
| 13 | `M packages/durable/src/harness/generation.ts` | pending -- exact behaviour/test audit required |
| 14 | `M packages/durable/src/harness/harness.ts` | pending -- exact behaviour/test audit required |
| 15 | `M packages/durable/src/harness/output.ts` | pending -- exact behaviour/test audit required |
| 16 | `A packages/durable/src/harness/provider.ts` | adapted candidate -- native ordered snapshot scans / persisted pi.provider session ID; DurableV110Tests; fork inheritance not implemented |
| 17 | `M packages/durable/src/harness/scheduler.ts` | pending -- exact behaviour/test audit required |
| 18 | `M packages/durable/src/harness/tool.ts` | pending -- exact behaviour/test audit required |
| 19 | `M packages/durable/src/harness/types.ts` | pending -- exact behaviour/test audit required |
| 20 | `M packages/durable/src/harness/view.ts` | pending -- exact behaviour/test audit required |
| 21 | `M packages/durable/src/index.ts` | pending -- exact behaviour/test audit required |
| 22 | `M packages/durable/src/session/session.ts` | pending -- exact behaviour/test audit required |
| 23 | `M packages/durable/src/session/transaction.ts` | pending -- exact behaviour/test audit required |
| 24 | `M packages/durable/src/storage/memory.ts` | pending -- exact behaviour/test audit required |
| 25 | `A packages/durable/src/storage/scan.ts` | adapted candidate -- native ordered snapshot scans / persisted pi.provider session ID; DurableV110Tests; fork inheritance not implemented |
| 26 | `A packages/durable/src/storage/sqlite/cloudflare.ts` | pending -- exact behaviour/test audit required |
| 27 | `M packages/durable/src/storage/sqlite/storage.ts` | pending -- exact behaviour/test audit required |
| 28 | `A packages/durable/src/testing/env-conformance.ts` | pending -- exact behaviour/test audit required |
| 29 | `M packages/durable/src/testing/index.ts` | pending -- exact behaviour/test audit required |
| 30 | `M packages/durable/src/testing/runner.ts` | pending -- exact behaviour/test audit required |
| 31 | `M packages/durable/src/testing/storage-conformance.ts` | pending -- exact behaviour/test audit required |
| 32 | `M packages/durable/src/testing/types.ts` | pending -- exact behaviour/test audit required |
| 33 | `M packages/durable/src/tools/bash.ts` | pending -- exact behaviour/test audit required |
| 34 | `M packages/durable/src/tools/image.ts` | pending -- exact behaviour/test audit required |
| 35 | `M packages/durable/src/tools/index.ts` | pending -- exact behaviour/test audit required |
| 36 | `M packages/durable/src/tools/read.ts` | pending -- exact behaviour/test audit required |
| 37 | `M packages/durable/src/truncate.ts` | pending -- exact behaviour/test audit required |
| 38 | `M packages/durable/src/types.ts` | pending -- exact behaviour/test audit required |
| 39 | `A packages/durable/test/env-line-scan.test.ts` | pending -- exact behaviour/test audit required |
| 40 | `A packages/durable/test/env-node-conformance.test.ts` | pending -- exact behaviour/test audit required |
| 41 | `M packages/durable/test/env-node.test.ts` | pending -- exact behaviour/test audit required |
| 42 | `M packages/durable/test/harness-compaction.test.ts` | pending -- exact behaviour/test audit required |
| 43 | `M packages/durable/test/harness-context.test.ts` | pending -- exact behaviour/test audit required |
| 44 | `M packages/durable/test/harness-conversations.test.ts` | pending -- exact behaviour/test audit required |
| 45 | `M packages/durable/test/harness-generation-recovery.test.ts` | pending -- exact behaviour/test audit required |
| 46 | `M packages/durable/test/harness-generation.test.ts` | pending -- exact behaviour/test audit required |
| 47 | `M packages/durable/test/harness-inbox.test.ts` | pending -- exact behaviour/test audit required |
| 48 | `A packages/durable/test/harness-output-skip.test.ts` | pending -- exact behaviour/test audit required |
| 49 | `M packages/durable/test/harness-output.test.ts` | pending -- exact behaviour/test audit required |
| 50 | `M packages/durable/test/harness-registry.test.ts` | pending -- exact behaviour/test audit required |
| 51 | `M packages/durable/test/harness-tasks-recovery.test.ts` | pending -- exact behaviour/test audit required |
| 52 | `M packages/durable/test/harness-tasks.test.ts` | pending -- exact behaviour/test audit required |
| 53 | `M packages/durable/test/harness-tools.test.ts` | pending -- exact behaviour/test audit required |
| 54 | `M packages/durable/test/harness-view.test.ts` | pending -- exact behaviour/test audit required |
| 55 | `A packages/durable/test/provider-session-cache-e2e.test.ts` | pending -- exact behaviour/test audit required |
| 56 | `A packages/durable/test/sqlite-cloudflare.test.ts` | pending -- exact behaviour/test audit required |
| 57 | `A packages/durable/test/system-order-cache-e2e.test.ts` | pending -- exact behaviour/test audit required |
| 58 | `A packages/durable/test/tools-read-differential.test.ts` | pending -- exact behaviour/test audit required |
| 59 | `M packages/durable/test/tools.test.ts` | pending -- exact behaviour/test audit required |
