# Upstream pi-ai v0.87.1 runtime-candidate parity audit

Baseline: accepted runtime `v0.87.0` / `16787ad5b2dc748047f314ca1bfe7708f30f54f3` (Swift runtime `bc1f1e8f93cb8b8dfc9dbe753b86cc235ae4aacb`).
Target: official npm package `@earendil-works/pi-ai` `v0.87.1` / gitHead `f07218c4d4bbc12bef056a7058c3dd49dfe41abe`.

Verified npm artifact SHA-256: `35b4432f27cc2665f86beebb9af6a39b1251970883c3044bd8be4f4e8c731ca0`.

The bounded `packages/ai` delta is exactly 16 changed paths. Changed-path manifest hash: `2756fce613d0163b6eb5c47b599584589a229e5c7ed30a86b65380031e272eb6`. The changed-test full-path manifest covers 9 paths with hash `5b66a8cf9050b36a8dbae7a1b802c12037a2ec2332cf2e3f370953ea9ef9ac43`. The final upstream basename test corpus has 150 tests with hash `042cdfbc8cc089da71409e615fb54cfe7273a960f8e0d10e63e07584ae9f2e75`.

Runtime accepted: Swift commit `8a126fc8bb8429801905e502eb92ef2da6721d74`, CI `35794536991`, SBOM artifact `10723117599`. README/current-version/RELEASE metadata is updated by the post-runtime docs-only commit; durable release asset publication is handled by the guarded SBOM publisher.

## Exact changed-path disposition matrix

| # | Marker | Upstream path | Swift disposition |
| ---: | :---: | --- | --- |
| 1 | M | `packages/ai/CHANGELOG.md` | Release metadata/documentation reviewed; no Swift runtime behavior beyond internal v0.87.1 evidence/status updates during runtime-candidate phase. |
| 2 | M | `packages/ai/README.md` | Release metadata/documentation reviewed; no Swift runtime behavior beyond internal v0.87.1 evidence/status updates during runtime-candidate phase. |
| 3 | M | `packages/ai/package.json` | Release metadata/documentation reviewed; no Swift runtime behavior beyond internal v0.87.1 evidence/status updates during runtime-candidate phase. |
| 4 | M | `packages/ai/scripts/generate-models.ts` | Adapted by pinned v0.87.1 tarball export, regenerated Swift text/image snapshots, and strict full-record comparator updates. |
| 5 | M | `packages/ai/src/api/anthropic-messages.ts` | Ported Claude OAuth header identity: direct OAuth tokens use Bearer auth, `User-Agent: claude-cli/2.1.280`, and `x-app: cli`; covered by `testAnthropicBearerAuthEnvHeaders`. |
| 6 | M | `packages/ai/src/api/openai-completions.ts` | Ported zero-length multimodal text omission in OpenAI-compatible content parts while retaining whitespace-only text; covered by `testOpenAICompatibleImageOnlyUserMessageOmitsEmptyTextPart` plus existing tool-result replay gates. |
| 7 | M | `packages/ai/src/image-models.generated.ts` | Adapted by exact v0.87.1 generated image snapshot (`55/1/1`) from the verified npm tarball and embedded Swift image registry regeneration. |
| 8 | M | `packages/ai/test/cache-retention.test.ts` | Mapped in the v0.87.1 crosswalk to deterministic Swift runtime tests or exact generated catalog validators. |
| 9 | M | `packages/ai/test/github-copilot-anthropic.test.ts` | Mapped through generated Copilot Anthropic catalog aliases plus Anthropic/Copilot header/runtime metadata tests. |
| 10 | M | `packages/ai/test/max-thinking.test.ts` | Mapped in the v0.87.1 crosswalk to deterministic Swift runtime tests or exact generated catalog validators. |
| 11 | M | `packages/ai/test/model-catalog-types.test.ts` | Mapped through strict full-record text/image catalog comparators and generated registry metadata tests. |
| 12 | M | `packages/ai/test/openai-completions-tool-result-images.test.ts` | Mapped to focused OpenAI-compatible image-only/whitespace regression and existing tool-result image/empty-output Swift tests. |
| 13 | M | `packages/ai/test/openai-responses-compat.test.ts` | Mapped in the v0.87.1 crosswalk to deterministic Swift runtime tests or exact generated catalog validators. |
| 14 | M | `packages/ai/test/stream.test.ts` | Mapped in the v0.87.1 crosswalk to deterministic Swift runtime tests or exact generated catalog validators. |
| 15 | M | `packages/ai/test/supports-xhigh.test.ts` | Mapped through generated v0.87.1 model metadata and Swift supported-thinking-level tests for xhigh-capable models. |
| 16 | M | `packages/ai/test/xai-responses.test.ts` | Mapped through generated Grok 4.7 Responses catalog metadata and existing Responses reasoning/encrypted-content request tests. |

## Catalog parity evidence

Text catalog: `scripts/models.v0.87.1.json` equals `scripts/upstream-models.f07218c.json`; embedded registry equals normalized snapshot. Full records: `1495/1495`, providers `41`, APIs `10`, delta `+62/-12/35 changed` from accepted v0.87.0.

Image catalog: `scripts/image-models.v0.87.1.json` equals `scripts/upstream-image-models.f07218c.json`; embedded image registry equals snapshot. Full records: `55/55`, providers `1`, APIs `1`, delta `+1/-0/0 changed` from accepted v0.87.0.

## Focused runtime evidence

- `nice -n 10 swift test --filter 'SwiftAITests/(testOpenAICompatibleImageOnlyUserMessageOmitsEmptyTextPart|testOpenAIResponsesToolResultImagesStayInFunctionCallOutput|testOpenAIToolResultEmptyOutputPlaceholder|testOpenAIMultimodalAndToolResultReplay)' -j 2`: executed 4 tests, 0 failures.
- `nice -n 10 swift test --filter SwiftAITests/testAnthropicBearerAuthEnvHeaders -j 2`: executed 1 test, 0 failures.

## Runtime acceptance evidence

Accepted runtime commit: `8a126fc8bb8429801905e502eb92ef2da6721d74`; CI run `35794536991` completed successfully for `swift-test (ubuntu-latest)` and `static-check`. SHA-specific SBOM artifact `10723117599` has archive SHA-256 `fa7f65018406926f913360e6d9bbbb9c1e28ca2ad0e68ecb4ba789945ed4a435`, inner SBOM SHA-256 `3405700b03b751916446ff6b32190733de1845aa1486513730500a954495e3ac`, CycloneDX 1.5 root `swift-ai@0.87.1`, component count `2`, matching `git.revision`, `git.dirty=false`, and clean OSV/security/license scans.
