# Upstream v1.0.1 audit

Runtime-candidate evidence only. No commit/push/tag/release has been authorised.

## Verified release inputs

- npm package: `@earendil-works/pi-ai@1.0.1`
- npm tarball SHA-256: `8a9e69b1309cf93405d87729fa123c8b11c6be7c646b16f34f8bef7b792f9138`
- upstream commit: `a7229ddc21810d6245105978033b7df645ecc2f7`
- Previous accepted upstream commit: `a13d35a742c6ef8462812a28fbe1d8c8b7431c32`
- Changed paths: `19`, diff `+546/-153`, manifest SHA-256 `ac9e4b76f7bb921a251ac5f5e14af48b1fa73f6e40d4d49e41ee11d5fb902278`
- Changed executable tests: `6`, manifest SHA-256 `fd49b5003edf22d18b5c4a4fa5b4998e5bad49136cc6d356527dd7c3d655a659`
- Final corpus manifest: `171` paths (`164` executable plus support entries), SHA-256 `9d24da3ede393a95a7131b1c9ac494f57d8165161d6eb581109c86809131abfc`
- Verified pinned tarball provider-data manifest: schema `6`, provider files `42`, changed provider JSON files `10`, structureHash `03d2e1aeeee6eb16959d4f727b47b9b187efaf863c688a47889fb90d200e6812`
- Baked schema-v6 counts: chat `1536/41/10`, image `59/1/1`, classifier `20/5/2`, total `1615`

## Changed-path disposition matrix

| # | Status | Path | Class | Swift disposition |
| --- | --- | --- | --- | --- |
| 1 | M | `packages/ai/CHANGELOG.md` | docs/package | Metadata only. |
| 2 | M | `packages/ai/README.md` | docs/package | Metadata/readme only. |
| 3 | M | `packages/ai/package.json` | package metadata | Version/provenance; `@anthropic-ai/sdk` 0.124.0 -> 0.129.0 has no Swift dependency effect. |
| 4 | M | `packages/ai/scripts/generate-models.ts` | tooling/catalog | Adapted through Swift generator/audit exact tarball snapshots. |
| 5 | A | `packages/ai/scripts/hydrate-model-catalog.ts` | tooling/catalog | Adapted through native offline provider-data validation; no JS dependency added. |
| 6 | M | `packages/ai/scripts/model-data.ts` | tooling/catalog | Adapted through provider-data manifest/schema/full-record audit. |
| 7 | M | `packages/ai/src/api/anthropic-messages.ts` | runtime | Ported inline tools beta/full tool definitions and fallback behavior. |
| 8 | M | `packages/ai/src/api/bedrock-converse-stream.ts` | runtime | Ported adaptive thinking block_binding/beta gating. |
| 9 | M | `packages/ai/src/api/cloudflare-workers-ai-system-one.ts` | runtime | Ported direct Cloudflare result envelope. |
| 10 | M | `packages/ai/src/auth/oauth/openai-chatgpt.ts` | runtime/OAuth | Adapted/N/A: Swift has primitives but no host callback listener; no server invented. |
| 11 | M | `packages/ai/src/types.ts` | metadata | Adapted by Codable full tool-delta metadata. |
| 12 | M | `packages/ai/src/utils/retry.ts` | runtime | Ported `model is at capacity` retry phrase. |
| 13 | M | `packages/ai/src/utils/transcript.ts` | runtime | Adapted by full tool-delta metadata preserving legacy `addedToolNames`. |
| 14 | M | `packages/ai/test/bedrock-thinking-payload.test.ts` | test | Ported focused deterministic Bedrock tests. |
| 15 | M | `packages/ai/test/cloudflare-workers-ai-system-one.test.ts` | test | Ported focused deterministic classifier tests. |
| 16 | M | `packages/ai/test/model-data-validation.test.ts` | test | Adapted to Swift audit/generator fault tests. |
| 17 | M | `packages/ai/test/stream.test.ts` | test | Adapted catalog/live-only drift; live credentials excluded. |
| 18 | M | `packages/ai/test/together-models.test.ts` | test | Adapted catalog comparator coverage. |
| 19 | M | `packages/ai/test/transcript-tool-changes.test.ts` | test | Ported focused Anthropic inline tool tests. |

## Catalog delta

- Chat: +17/-13/54 changed; 1536 records.
- Image: +2/-0/0 changed; 59 records.
- Classifier: +5/-0/0 changed; 20 records.

## Local implementation notes

- Durable/native durable work is separate and not included in this provider candidate.
- Swift has no `system` message role. The native initial-tool-state adaptation uses a first-message inert empty assistant metadata entry with `toolsAdded`; user/tool-result/non-empty assistant and later assistant metadata are not initial baselines. Tests cover no-initial fallback, timestamp collisions and canonical OAuth tool-name collisions.
- Actual typed Swift exports were independently compared against official raw snapshots with zero unexplained differences across all `1615` records. Accepted structural adaptations are implicit `type` for chat/image records and classifier `maxTokens = 0` default where official classifier records omit it.
- Image `inputLimits` and provider compat metadata are preserved as metadata. This lane does not add image preprocessing/resizing or broad non-Anthropic mid-conversation runtime consumption.
- Local full gates passed: warnings-as-errors build, `305` tests, deterministic repeats, `make check`, SBOM/security/licence, no `XCTSkip`, `git diff --check`, and clean-source snapshot. Hosted CI, commit/push and publication remain pending independent review and explicit authorization.


## Initial native and upstream publication receipt

Accepted runtime commit: `68e4052fde96cd9404aaddc56742c2ae5348664e` (`Port pi-ai v1.0.1 provider parity`). Parent: `daa9d9b07d13e5172f587b95918c6d9cedf43925`; tree: `eb8d04a07912ce175e101dba36b6ca087de0b790`.

Hosted CI for the accepted runtime passed on push run `37165556108` with jobs `111327607813` (`swift-test (ubuntu-latest)`) and `111327607944` (`static-check`). Hosted test evidence was `305` tests / `0` failures. Artifact `11289268006` had ZIP SHA-256 `7a2f41e16e1e575ae9262cca23db1f76f06e9c02f64949f76d83851d7e332162`; the inner SBOM SHA-256 was `352b5b40f7600b794d1acd956efbb05a3b565a263e2bd91da05270a55f71fd57`, root `swift-ai@1.0.1`, `git.revision=68e4052fde96cd9404aaddc56742c2ae5348664e`, `git.dirty=false`, `2` components and `3` dependency entries.

Native publication:

- Tag/release: `v1.0.1`.
- Annotated tag object: `f120f0c8976df20f82a55d1e5c9acfcceb02ff57`, tagger `Rui Carmo <rui.carmo@gmail.com>`, target `68e4052fde96cd9404aaddc56742c2ae5348664e`.
- Release database ID: `402757174`.
- Publisher workflow: `37165998133`, job `111328878306`, success.
- Assets: `608838456` (`sbom.cdx.json`, `sha256:352b5b40f7600b794d1acd956efbb05a3b565a263e2bd91da05270a55f71fd57`) and `608838457` (`sbom.cdx.json.sha256`, `sha256:438349ed2a330fe02a6d86208c2c8a0bcf6e2b0cb122477d35b3b39708d76d7a`).

Upstream alias publication:

- Tag/release: `upstream-v1.0.1`.
- Alias ref: lightweight `upstream-v1.0.1 -> 68e4052fde96cd9404aaddc56742c2ae5348664e`.
- Release database ID: `402759260`.
- Publisher workflow: `37166282241`, job `111329721226`, success.
- Assets: `608847003` (`sbom.cdx.json`, `sha256:352b5b40f7600b794d1acd956efbb05a3b565a263e2bd91da05270a55f71fd57`) and `608847004` (`sbom.cdx.json.sha256`, `sha256:438349ed2a330fe02a6d86208c2c8a0bcf6e2b0cb122477d35b3b39708d76d7a`).

Native and alias SBOM bytes match the accepted hosted runtime artifact. Older refs, releases and assets were preserved. A prior Git Data API call failed before mutation because `tagger` was encoded as a string; the successful call used an explicit JSON body with a nested `tagger` object. Durable implementation remains separate, and Rui's same-version `v1.0.1` durable replacement policy remains queued.
