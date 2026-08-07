# Upstream pi-ai v0.84.1 release parity audit

Baseline: accepted official release `v0.84.0` / `a5f43bf8aff3c55752432655f7334e3dafd1e256`.
Target: official release `v0.84.1` / `53fa77ccd8a279eb87e92294ef3687b03ff80112`.
Scope: release-only audit pinned to `53fa77c`; no commits beyond the tag were considered.

The bounded `packages/ai` delta is exactly 25 changed paths. The test delta is exactly 14 changed test paths total: 13 existing tests modified plus 1 new `generate-models-strict.test.ts`. The cumulative whole-corpus test crosswalk covers exactly 128 upstream `packages/ai/test/*.test.ts` files in [`upstream-v0.84.1-test-crosswalk.md`](upstream-v0.84.1-test-crosswalk.md), with disposition counts `ported: 98`, `adapted: 8`, `live-only: 7`, `adapted/live-remainder: 14`, `N/A/adapted-generator-policy: 1`, and open items `0`.

## Exact changed-path disposition matrix

| # | Upstream path | Swift disposition |
| ---: | --- | --- |
| 1 | `packages/ai/CHANGELOG.md` | Release metadata; recorded v0.84.1 scope/tag/counts in `RELEASE.md`, `PARITY.md`, `STATUS.json`, and this audit. |
| 2 | `packages/ai/README.md` | Package README/docs only; Swift public surface remains documented in root `README.md`, `PARITY.md`, `docs/USAGE.md`, and release ledger. |
| 3 | `packages/ai/package.json` | Package version metadata; SwiftPM analogue is unchanged `Package.swift`; static CI checks continue to validate package/workflow shape. |
| 4 | `packages/ai/scripts/generate-models.ts` | Ported by regenerating exact v0.84.1 Swift text catalog from the npm package artifact and adding the `qwen-token-plan-individual` provider enum/env/request behavior. Individual strict allowlist is asserted in deterministic Swift tests and comparator data. |
| 5 | `packages/ai/scripts/model-data.ts` | Upstream strict `assertExactModelIds` helper maps to Swift's exact full-record audit: `scripts/models.v0.84.1.json` must match `scripts/upstream-models.53fa77c.json`, the embedded registry must match the generator-normalized snapshot, and `audit-parity.py --self-test` fault-injects metadata to prove the comparator fails on value drift. |
| 6 | `packages/ai/src/env-api-keys.ts` | Added `Provider.qwenTokenPlanIndividual` and `QWEN_TOKEN_PLAN_API_KEY`/`DASHSCOPE_API_KEY` lookup parity via `ProviderEnvironment`; tests assert the shared international Token Plan key path. |
| 7 | `packages/ai/src/models.generated.ts` | Regenerated exact text catalog: `1220/1220` full records, `39` providers, `9` APIs. Audit enforces exact v0.84.0→v0.84.1 full-record delta `+70/-3/9 changed`. Image catalog remains `42/42` full records, `1` provider, `1` API. |
| 8 | `packages/ai/src/providers/all.ts` | Built-in provider registration is represented by generated models plus `ModelRuntime` fallback registration. The new provider is visible in `BuiltinModels.all()`, `AIRegistry`, and provider listing through generated metadata. |
| 9 | `packages/ai/src/providers/qwen-token-plan-individual.models.ts` | Ported as embedded generated model data for `qwen-token-plan-individual`; deterministic test asserts the exact seven documented text IDs and excludes image/retired preview IDs. |
| 10 | `packages/ai/src/providers/qwen-token-plan-individual.ts` | Ported provider behavior: OpenAI Completions API, Singapore Token Plan base URL, shared `QWEN_TOKEN_PLAN_API_KEY` auth, text-only Individual catalog, and Qwen thinking request payloads. |
| 11 | `packages/ai/src/types.ts` | Ported known-provider addition via `Provider.qwenTokenPlanIndividual`; generated catalog decoding fails if the Swift enum is not present, and `scripts/audit-parity.py` checks all raw values. |
| 12 | `packages/ai/test/abort.test.ts` | Existing adapted/live-remainder coverage retained; no new portable deterministic Swift behavior in this v0.84.1 slice beyond already-covered cancellation/abort tests. |
| 13 | `packages/ai/test/context-overflow.test.ts` | Reclassified `adapted/live-remainder`: deterministic generic overflow behavior is covered; newly added Individual live/provider case is credential-gated and unexecuted. |
| 14 | `packages/ai/test/cross-provider-handoff.test.ts` | Existing cross-provider handoff coverage retained through provider transform/message conversion tests; live/provider matrix remainder remains explicitly classified. |
| 15 | `packages/ai/test/empty.test.ts` | Existing empty-stream/empty-output tests retained; no new portable production delta in v0.84.1. |
| 16 | `packages/ai/test/generate-models-strict.test.ts` | Reclassified `N/A/adapted-generator-policy`: private TS atomic generator rollback policy is not an executable Swift port. Swift enforces full-record generated-catalog policy with `audit-parity.py` and the self-test fault-injection proof, but does not claim TS rollback coverage. |
| 17 | `packages/ai/test/image-tool-result.test.ts` | Existing image tool-result request-shape tests retained; v0.84.1 image catalog is unchanged at `42/42`. |
| 18 | `packages/ai/test/model-data-validation.test.ts` | Ported through `scripts/audit-parity.py` full-record source/comparator/embedded validation, enum raw-value checks, exact delta assertions, self-test metadata fault injection, and representative assertions including Individual models. |
| 19 | `packages/ai/test/openai-completions-tool-choice.test.ts` | Existing OpenAI Completions request-body tests retained; Qwen thinking payload behavior is additionally asserted for Individual high/xhigh reasoning. |
| 20 | `packages/ai/test/qwen-token-plan-models.test.ts` | Ported new Individual provider assertions: exact seven-model catalog, shared env key, Singapore endpoint, `thinkingFormat: qwen`, `supportsReasoningEffort`, qwen3.8 xhigh mapping, retired/image exclusions, and request payloads. |
| 21 | `packages/ai/test/stream.test.ts` | Existing stream parser/provider tests retained; no new provider-stream protocol in this slice. |
| 22 | `packages/ai/test/tokens.test.ts` | Reclassified `adapted/live-remainder`: deterministic generic token behavior is covered; newly added Individual live/provider case is credential-gated and unexecuted. |
| 23 | `packages/ai/test/tool-call-without-result.test.ts` | Existing tool-call handoff/replay tests retained; no new portable production delta in this slice. |
| 24 | `packages/ai/test/total-tokens.test.ts` | Reclassified `adapted/live-remainder`: deterministic generic total-token behavior is covered; newly added Individual live/provider case is credential-gated and unexecuted. |
| 25 | `packages/ai/test/unicode-surrogate.test.ts` | Reclassified `adapted/live-remainder`: deterministic generic Unicode behavior is covered; newly added Individual live/provider case is credential-gated and unexecuted. |

## Catalog parity evidence

Text catalog:

- Swift source snapshot: `scripts/models.v0.84.1.json`
- Exact upstream comparator source: `scripts/upstream-models.53fa77c.json`
- Embedded Swift registry: `Sources/SwiftAI/ModelsGenerated.swift`
- Full records: `1220/1220`
- Providers: `39`
- APIs: `9`
- Full-record delta vs committed v0.84.0 snapshot: `+70/-3/9 changed`

Image catalog:

- Swift source snapshot: `scripts/image-models.v0.84.1.json`
- Exact upstream comparator source: `scripts/upstream-image-models.53fa77c.json`
- Embedded Swift registry: `Sources/SwiftAI/ImageModelsGenerated.swift`
- Full records: `42/42`
- Providers: `1`
- APIs: `1`

## Validation requirements

- `scripts/audit-parity.py` enforces exact text and image full-record catalog parity against v0.84.1 source snapshots, embedded normalized text records, embedded image records, and the exact v0.84.0→v0.84.1 text delta `+70/-3/9 changed`; `--self-test` mutates metadata to prove the full-record comparator fails.
- Local gates must pass: `swift build -Xswiftc -warnings-as-errors`, `swift test`, deterministic `swift test` repeats, `make check`, `scripts/audit-parity.py`, `scripts/static-check.py`, and zero hidden `XCTSkip` matches.
- Acceptance requires GitHub Actions `static-check`, Ubuntu Swift tests, and macOS Swift tests all green for the pushed commit.
