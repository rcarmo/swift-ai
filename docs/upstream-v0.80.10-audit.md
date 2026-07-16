# Upstream pi-ai v0.80.10 release parity audit

Baseline: prior official release `v0.80.9` / `2d16f92973230a7e095aa984f150ba8702784f50`.
Target: official release `v0.80.10` / `8dc78834cde4e329284cf505f9e3f99763df5529`.
Scope: release-only audit; no commits beyond `8dc78834` were considered.

## Exact changed-path disposition matrix

| Upstream path | Material delta | Swift disposition |
| --- | --- | --- |
| `packages/ai/CHANGELOG.md`, `packages/ai/README.md`, `packages/ai/package.json` | Release metadata and package version updates. | Reflected in `STATUS.json`, `SwiftAIStatus`, `PARITY.md`, and this audit; no runtime behavior required. |
| `packages/ai/scripts/generate-models.ts` | Generator now compares exact provider/id pairs and selected metadata, not only aggregate counts; xAI removed-model regeneration bug fixed. | `scripts/audit-parity.py` now targets the exact v0.80.10 upstream export `scripts/upstream-models.8dc78834.json`, compares the embedded Swift registry to that exact source, and keeps representative metadata assertions. |
| `packages/ai/src/providers/kimi-coding.models.ts` | Adds Kimi adaptive-thinking compatibility; `kimi-k3` also permits empty thinking signatures and maps `max` thinking to `max` while disabling lower levels. | Regenerated into `scripts/models.v0.80.10.json` and `Sources/SwiftAI/ModelsGenerated.swift`; covered by `testUpstream08010KimiAndMoonshotCatalogMetadata`. Existing Anthropic request builder already honors `forceAdaptiveThinking` and `allowEmptySignature`. |
| `packages/ai/src/providers/moonshotai.models.ts`, `packages/ai/src/providers/moonshotai-cn.models.ts` | Corrects official Kimi K3 pricing to input 3 / output 15 / cache read 0.3 / cache write 0. | Regenerated catalog; covered by `testUpstream08010KimiAndMoonshotCatalogMetadata`. |
| `packages/ai/src/providers/opencode-go.models.ts` | Adds OpenCode Go catalog entries. | Regenerated catalog; covered by `testUpstream08010XAIAndOpenCodeCatalogDisposition`. |
| `packages/ai/src/providers/openrouter.models.ts` | Catalog metadata refresh. | Regenerated catalog and exact-source comparator enforce provider/id and embedded metadata parity. |
| `packages/ai/src/providers/xai.models.ts` | Removes stale xAI models so regeneration no longer preserves removed entries. | Regenerated catalog now exposes only the three upstream xAI models; covered by `testUpstream08010XAIAndOpenCodeCatalogDisposition`. |
| `packages/ai/test/anthropic-adaptive-thinking-models.test.ts`, `packages/ai/test/anthropic-empty-thinking-signature-compat.test.ts`, `packages/ai/test/anthropic-force-adaptive-thinking.test.ts` | Adds/adjusts Anthropic/Kimi adaptive-thinking and empty-signature compatibility expectations. | Existing production builder behavior already matched these flags; Kimi catalog flags are now regenerated and asserted. |
| `packages/ai/test/supports-xhigh.test.ts` | Adds `max`/Kimi thinking support coverage. | Swift `thinkingLevelMap` preserves `max` and null lower-level entries; covered by new Kimi catalog test plus existing xhigh tests. |
| `packages/ai/test/providers.test.ts` | Adds official Kimi K3 pricing regression. | Covered by `testUpstream08010KimiAndMoonshotCatalogMetadata`. |
| `packages/ai/test/xai-responses.test.ts` | Adds xAI removed-model regeneration regression. | Covered by exact catalog comparator and explicit xAI provider-id set test. |
| `packages/ai/test/context-overflow.test.ts`, `packages/ai/test/cross-provider-handoff.test.ts`, `packages/ai/test/stream.test.ts`, `packages/ai/test/total-tokens.test.ts` | Expected fixture/model adjustments associated with the refreshed catalog and thinking metadata. | Existing Swift utility/provider tests still cover equivalent behavior; no additional production code required beyond catalog regeneration. |

## Validation

- `python3 scripts/static-check.py`
- `python3 scripts/audit-parity.py`
- `git diff --check`
- `swift test` could not run in this Linux container because `swift` is not installed (`swift: command not found`). Ubuntu/macOS Swift CI remains required once GitHub Actions recovers from the reported API 503.
