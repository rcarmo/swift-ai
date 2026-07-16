# Upstream pi-ai v0.80.9 release parity audit

Baseline: prior pinned upstream `2be9efa19cd64aed40ca63f92c0c0f9a6bac7c9d`.
Target: official release tag `v0.80.9` / `2d16f92973230a7e095aa984f150ba8702784f50`.
Scope: release-only audit; no commits beyond `v0.80.9` were considered.

## Exact material-delta disposition matrix

| Upstream path | Material delta | Swift disposition |
| --- | --- | --- |
| `CHANGELOG.md`, `README.md`, `package.json` | Release metadata/changelog and package version updates. | Documented in this audit/`STATUS.json`; no runtime code required. |
| `scripts/generate-models.ts`, `src/models.ts`, provider model files | Registry refresh with Kimi K3/Kimi high-speed entries, Kimi/Moonshot output-limit corrections, OpenRouter/Vercel catalog refreshes, xAI OAuth/provider label/model-list adjustments. | Regenerated `scripts/models.v0.80.9.json`, `scripts/upstream-models.2d16f92.json`, `scripts/image-models.v0.80.9.json`, `Sources/SwiftAI/ModelsGenerated.swift`, and `Sources/SwiftAI/ImageModelsGenerated.swift` directly from the exact tag; `BuiltinModels.upstreamVersion == 0.80.9`. Counts are 1075 text / 35 image models, with `scripts/audit-parity.py` comparing Swift's snapshot and embedded registry to the exact-tag upstream catalog. |
| `src/types.ts` | Adds `OpenAICompletionsCompat.deferredToolsMode?: "kimi"`. | Implemented as `OpenAICompletionsCompat.deferredToolsMode`. |
| `src/api/openai-completions.ts` | Kimi deferred-tools behavior: remove newly added tools from top-level active tool list and serialize deferred tool declarations in a content-less system message after tool results. | Implemented in `OpenAICompletionsProvider.buildRequestBody`/message conversion; covered by `testOpenAICompletionsKimiDeferredTools`. |
| `test/deferred-tools.test.ts` | New upstream regression tests for deferred tool loading. | Swift regression added for OpenAI/Kimi serialization. Existing Swift tests already cover Anthropic/Responses deferred tool plans. |
| `src/auth/helpers.ts`, `src/auth/oauth/load.ts`, `src/auth/oauth/xai.ts`, `src/auth/types.ts`, `src/bun-oauth.ts`, `src/providers/xai.ts`, `test/xai-oauth.test.ts` | OAuth UX/runtime changes: Bun-binary OAuth loading, xAI prefilled device link/SuperGrok label/trimmed available model list. | Production behavior already represented by portable Swift OAuth abstractions where applicable; Bun binary bundling is Node packaging-only and not applicable to SwiftPM. Registry/provider label changes captured by regenerated registries where they affect model metadata. |
| Upstream existing test fixtures touched for import renames | Context overflow, streaming, token, empty, unicode, total-token, thinking-as-text, and tool-image tests had import/package path churn or expected registry metadata adjustments. | Existing Swift regression suite continues to cover equivalent behavior; no semantic code change beyond registry/deferred-tools required. |
| `packages/coding-agent/*` changes outside `packages/ai` | Catalog refresh CLI flag, clone-failure messaging, bundled OAuth in Bun binaries, docs/examples/package-lock churn. | Out of scope for SwiftAI runtime except generated model catalog inputs; catalog data refreshed. |

## Validation

- `scripts/audit-parity.py` enforces exact-tag text catalog parity against `scripts/upstream-models.2d16f92.json` (1075/1075 provider/id pairs) plus representative Kimi K3, OpenRouter Muse, Vercel fast Opus/K3/Inkling entries.
- Local Swift compile/test gates and GitHub Actions are required before acceptance.
