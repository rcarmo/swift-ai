# Upstream pi-ai v0.84.2 release parity audit

Baseline: accepted official release `v0.84.1` / `53fa77ccd8a279eb87e92294ef3687b03ff80112`.
Target: official release `v0.84.2` / `914cf1472e715297caa30db4b9535d534a9eb718`.
Scope: release-only audit pinned to `914cf147`; no commits beyond the tag were considered.

Verified npm artifact SHA-256: `0262785a76b0eb2eec596cd8a7ab2ee23eef89d2ef1bb1211c4f0a1944dacf41`.

The bounded `packages/ai` delta is exactly 42 changed paths: 18 source, 21 tests, and 3 package/docs/generated metadata paths. The test delta is exactly 21 changed test paths total: 18 existing tests modified plus 3 new tests. The cumulative whole-corpus test crosswalk covers exactly 131 upstream `packages/ai/test/*.test.ts` files in [`upstream-v0.84.2-test-crosswalk.md`](upstream-v0.84.2-test-crosswalk.md).

## Exact changed-path disposition matrix

| # | Upstream path | Swift disposition |
| ---: | --- | --- |
| 1 | `packages/ai/CHANGELOG.md` | Package/release metadata; recorded in STATUS/PARITY/RELEASE/audit docs. |
| 2 | `packages/ai/package.json` | Package/release metadata; recorded in STATUS/PARITY/RELEASE/audit docs. |
| 3 | `packages/ai/scripts/generate-models.ts` | Ported via exact generated text catalog and Swift compat structs/enums; audit enforces 1267 full records and +71/-24/85 delta. |
| 4 | `packages/ai/src/api/anthropic-messages.ts` | Runtime change: Kimi runtime `User-Agent` and strict tool schema handling; covered by `testUpstream0842UserAgentAndRetryClassifier` and strict schema tests. |
| 5 | `packages/ai/src/api/bedrock-converse-stream.ts` | Ported: Bedrock strict schema and empty-key replay sanitization covered; no live AWS transport bundled. |
| 6 | `packages/ai/src/api/cloudflare-gateway-binding.ts` | N/A/adapted transport: Cloudflare Workers gateway binding is JS Workers object semantics; Swift already exposes request-transport injection and Cloudflare gateway URL/env routing, with tokenless binding object intentionally not shipped. |
| 7 | `packages/ai/src/api/constrained-sampling.ts` | Ported: strict JSON-schema conversion and optional non-nullable null omission covered by focused tests. |
| 8 | `packages/ai/src/api/google-generative-ai.ts` | Ported: Google/Vertex STOP/MAX_TOKENS/raw reason behavior covered by existing raw stop tests. |
| 9 | `packages/ai/src/api/google-shared.ts` | Ported: Google/Vertex STOP/MAX_TOKENS/raw reason behavior covered by existing raw stop tests. |
| 10 | `packages/ai/src/api/google-vertex.ts` | Ported: Google/Vertex STOP/MAX_TOKENS/raw reason behavior covered by existing raw stop tests. |
| 11 | `packages/ai/src/api/mistral-conversations.ts` | Ported/adapted: Swift uses an incremental delegate-based URLSession streaming transport by default, also exposes an injectable raw stream seam, sends `x-affinity`, bounds non-2xx bodies, maps cancellation to aborted, and covers production first-event-before-completion plus UTF-8 split bytes, abort, timeout, headers/status/body, cached usage, request/replay/tool/thinking behavior. |
| 12 | `packages/ai/src/api/openai-codex-responses.ts` | Ported: Responses/Codex additional_tools, namespace/endTurn, User-Agent, stream/replay behavior covered by focused tests and exact catalog compat. |
| 13 | `packages/ai/src/api/openai-completions.ts` | Runtime change: strict JSON-schema conversion plus case-insensitive DeepSeek hostname detection and `max_tokens`; covered by `testUpstream0842StrictSchemaAndNullableNullOmission` and `testUpstream0842DeepSeekMixedCaseMaxTokensCompat`. |
| 14 | `packages/ai/src/api/openai-responses-shared.ts` | Ported: Responses/Codex additional_tools, namespace/endTurn, User-Agent, stream/replay behavior covered by focused tests and exact catalog compat. |
| 15 | `packages/ai/src/api/openai-responses.ts` | Ported: Responses/Codex additional_tools, namespace/endTurn, User-Agent, stream/replay behavior covered by focused tests and exact catalog compat. |
| 16 | `packages/ai/src/auth/oauth/github-copilot.ts` | Ported/adapted: policy updates are capped at 4 concurrent structured tasks with cancellation checks; `testUpstream0842CopilotPolicyUpdateConcurrencyCap` verifies max in-flight. |
| 17 | `packages/ai/src/image-models.generated.ts` | Ported: image catalog regenerated exactly to 45 full records with +3/0/0 delta. |
| 18 | `packages/ai/src/types.ts` | Ported via exact generated text catalog and Swift compat structs/enums; audit enforces 1267 full records and +71/-24/85 delta. |
| 19 | `packages/ai/src/utils/pi-user-agent.ts` | Runtime change: shared pi runtime `User-Agent` for Kimi/Codex paths; covered by `testUpstream0842UserAgentAndRetryClassifier` and Codex header tests. |
| 20 | `packages/ai/src/utils/retry.ts` | Ported: retry classifier includes upstream buffer-limit phrase. |
| 21 | `packages/ai/src/utils/validation.ts` | Ported: strict JSON-schema conversion and optional non-nullable null omission covered by focused tests. |
| 22 | `packages/ai/test/anthropic-auth-token.test.ts` | Covered in the exact 131-file crosswalk with live/N/A separation. |
| 23 | `packages/ai/test/anthropic-eager-tool-input-compat.test.ts` | Covered in the exact 131-file crosswalk with live/N/A separation. |
| 24 | `packages/ai/test/bedrock-convert-messages.test.ts` | Ported: Bedrock strict schema and empty-key replay sanitization covered; no live AWS transport bundled. |
| 25 | `packages/ai/test/cloudflare-gateway-binding.test.ts` | N/A/workers-binding-transport; separated in test crosswalk from Swift transport injection. |
| 26 | `packages/ai/test/constrained-sampling.test.ts` | Ported: strict JSON-schema conversion and optional non-nullable null omission covered by focused tests. |
| 27 | `packages/ai/test/context-overflow.test.ts` | Covered in the exact 131-file crosswalk with live/N/A separation. |
| 28 | `packages/ai/test/deferred-tools.test.ts` | Covered in the exact 131-file crosswalk with live/N/A separation. |
| 29 | `packages/ai/test/github-copilot-oauth.test.ts` | Adapted: bounded policy update/task behavior and model filtering covered; live Copilot endpoint remains mocked/adapted. |
| 30 | `packages/ai/test/google-raw-stop-reason.test.ts` | Ported: Google/Vertex STOP/MAX_TOKENS/raw reason behavior covered by existing raw stop tests. |
| 31 | `packages/ai/test/lazy-module-load.test.ts` | Covered in the exact 131-file crosswalk with live/N/A separation. |
| 32 | `packages/ai/test/mistral-http-transport.test.ts` | Ported/adapted: focused Swift wire tests cover raw streaming seam, UTF-8 split bytes, x-affinity, non-2xx body, timeout, and abort. |
| 33 | `packages/ai/test/mistral-raw-stop-reason.test.ts` | Ported/adapted: raw stop reason and usage behavior retained in Mistral parser/request tests. |
| 34 | `packages/ai/test/openai-codex-stream.test.ts` | Ported: Responses/Codex additional_tools, namespace/endTurn, User-Agent, stream/replay behavior covered by focused tests and exact catalog compat. |
| 35 | `packages/ai/test/openai-completions-tool-choice.test.ts` | Covered in the exact 131-file crosswalk with live/N/A separation. |
| 36 | `packages/ai/test/openai-responses-compat.test.ts` | Ported: Responses/Codex additional_tools, namespace/endTurn, User-Agent, stream/replay behavior covered by focused tests and exact catalog compat. |
| 37 | `packages/ai/test/openai-responses-namespace.test.ts` | Ported: Responses/Codex additional_tools, namespace/endTurn, User-Agent, stream/replay behavior covered by focused tests and exact catalog compat. |
| 38 | `packages/ai/test/retry.test.ts` | Ported: retry classifier includes upstream buffer-limit phrase. |
| 39 | `packages/ai/test/stream.test.ts` | Covered in the exact 131-file crosswalk with live/N/A separation. |
| 40 | `packages/ai/test/supports-xhigh.test.ts` | Covered in the exact 131-file crosswalk with live/N/A separation. |
| 41 | `packages/ai/test/total-tokens.test.ts` | Covered in the exact 131-file crosswalk with live/N/A separation. |
| 42 | `packages/ai/test/validation.test.ts` | Ported: strict JSON-schema conversion and optional non-nullable null omission covered by focused tests. |

## Catalog parity evidence

Text catalog:

- Swift source snapshot: `scripts/models.v0.84.2.json`
- Exact upstream comparator source: `scripts/upstream-models.914cf14.json`
- Embedded Swift registry: `Sources/SwiftAI/Models/Generated/ModelsGenerated.swift`
- Full records: `1267/1267`
- Providers: `39`
- APIs: `9`
- Full-record delta vs committed v0.84.1 snapshot: `+71/-24/85 changed`

Image catalog:

- Swift source snapshot: `scripts/image-models.v0.84.2.json`
- Exact upstream comparator source: `scripts/upstream-image-models.914cf14.json`
- Embedded Swift registry: `Sources/SwiftAI/Models/Generated/ImageModelsGenerated.swift`
- Full records: `45/45`
- Providers: `1`
- APIs: `1`
- Full-record delta vs committed v0.84.1 snapshot: `+3/0/0 changed`

## Portable behavior evidence

Implemented/adapted in Swift:

- Strict JSON-schema tool conversion and optional non-nullable null omission.
- Kimi/Codex runtime `User-Agent` handling.
- Responses/Codex message-anchored `additional_tools`, tool-search fallback, namespace preservation, and `AssistantMessage.endTurn`.
- Mistral incremental default URLSession streaming transport, injectable raw streaming seam, `x-affinity`, bounded non-2xx response bodies, timeout/abort handling, cancellation-to-aborted mapping, cached-token usage, request/replay behavior, raw stop/error behavior, and UTF-8-safe SSE chunk framing.
- Copilot policy/model update is capped at 4 concurrent structured tasks and remains cancellation-safe.
- Retry classifier includes `exceeded request buffer limit while retrying upstream`.
- Case-insensitive DeepSeek detection/max-token compatibility is represented in generated catalog compat and request builders.
- Google/Vertex STOP/MAX_TOKENS/raw reason behavior is covered by existing parser tests.
- Bedrock replay sanitizes empty argument keys without mutating streamed/original arguments.
- Streaming usage preservation remains covered by provider parser tests and exact usage assertions.

Cloudflare `createGatewayBindingFetch` assessment: N/A to Swift runtime as written because it is a Cloudflare Workers AI Gateway binding object adapter. Swift preserves the portable routing seam through model base URLs, env overlay, and pluggable request transports; no Workers binding object exists in SwiftPM core.

## Validation requirements

- `scripts/audit-parity.py` enforces exact text/image full-record parity, embedded registry equality, exact text delta `+71/-24/85`, exact image delta `+3/0/0`, and `--self-test` metadata fault injection.
- Local gates must pass: `swift build -Xswiftc -warnings-as-errors`, `swift test`, deterministic `swift test` repeats, `make check`, `scripts/audit-parity.py`, `scripts/static-check.py`, and zero hidden `XCTSkip` matches.
- Acceptance requires GitHub Actions `static-check`, Ubuntu Swift tests, and macOS Swift tests all green for the pushed commit.
