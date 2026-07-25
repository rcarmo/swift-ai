# Upstream pi-ai v0.82.1 release parity audit

Baseline: accepted official release `v0.82.0` / `083e61621276bff9f6faefab87ce07fcd98734e2`.
Target: official release `v0.82.1` / `b4f293684bba718d59cc1157679bcf6157b3a7f5`.
Scope: release-only audit pinned to `b4f2936`; no commits beyond the tag were considered.

The final `packages/ai` delta is exactly 23 changed paths.

## Exact changed-path disposition matrix

| Upstream paths | Material delta | Swift disposition |
| --- | --- | --- |
| `CHANGELOG.md`, `package.json` | Release metadata and version bump. | Reflected in `STATUS.json`, `PARITY.md`, and this audit. |
| `scripts/generate-models.ts`, changed provider metadata tests | Catalog refresh and generated model-data metadata changes. | Regenerated exact-tag text/image Swift catalogs from v0.82.1 output: **1109/1109 text provider/id pairs**, **37 providers**, **9 APIs** and **40/40 image provider/id pairs**. `scripts/audit-parity.py` compares Swift source+embedded registries against `scripts/upstream-models.b4f2936.json` and `scripts/upstream-image-models.b4f2936.json`. |
| `src/models-store.ts`, `test/models-runtime.test.ts` | Store entries can carry ETags; model errors preserve cause details. | Added `StoredModelsEntry.etag`/`checkedAt`, propagated cached ETag into `ModelRefreshContext.currentETag`, added `ModelRefreshResponse` metadata, and construct `ModelsError` in real `ModelRuntime.refresh` failure paths with cause-preserving descriptions. Radius runtime refresh sends `If-None-Match`, persists response `ETag`, handles `304` by reusing cached models and preserving ETag while updating `checkedAt`. Tests cover real refresh failure cause text, ETag request headers, 304 cached reuse, and ETag persistence. |
| `src/api/bedrock-converse-stream.ts`, `test/bedrock-models.test.ts`, `test/bedrock-thinking-payload.test.ts`, `test/supports-xhigh.test.ts`, `test/xhigh.test.ts` | Claude Opus 5 Bedrock support for adaptive thinking, native xhigh effort, and prompt-cache eligibility. | Added `opus-5` to Swift Bedrock adaptive/native xhigh detection. Existing Bedrock request builders use the shared detection; tests cover Opus 5 adaptive/xhigh request fields. |
| `src/auth/oauth/radius.ts`, `test/radius-oauth.test.ts` | Radius OAuth token/device endpoints route through the gateway (`/v1/oauth/token`, `/v1/oauth/device`) with fixed client/scope defaults and reduced discovery requirements. | Added Radius OAuth constants/default endpoint helpers and relaxed config decode to fill token/device/scope/client defaults from the gateway. Tests cover minimal discovery, token endpoint, device endpoint, and field defaults. |
| `src/auth/resolve.ts`, auth/OAuth tests | `ModelsError` messages include formatted cause details. | Implemented Swift `ModelsError` with cause preservation in model-runtime, OAuth registry login/refresh/API-key lookup, and credential-store wrapper seams. Tests use real failing OAuth provider and credential-store paths to assert cause text is preserved. |
| `src/env-api-keys.ts`, `src/providers/anthropic.ts`, `test/anthropic-auth-token.test.ts`, `test/env-api-keys.test.ts`, `test/providers.test.ts` | Anthropic supports `ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_OAUTH_TOKEN` bearer auth distinctly from `ANTHROPIC_API_KEY` x-api-key auth. | Added `ANTHROPIC_AUTH_TOKEN` env lookup precedence and bearer-token header selection when the resolved key comes from auth-token env or already has `Bearer `. Tests cover env precedence and Authorization vs X-Api-Key headers. |
| `src/utils/error-body.ts`, `test/error-body.test.ts`, `test/provider-error-body-regression.test.ts` | Provider error body extraction ignores readable-stream-like `$response.body` values instead of serializing stream internals. | Updated Swift provider error normalization to ignore stream-like body dictionaries; tests cover no body extraction for stream-like response bodies. |
| `test/anthropic-adaptive-thinking-models.test.ts`, `test/openai-responses-reasoning-replay-e2e.test.ts` | Regression fixture updates around existing reasoning replay/adaptive thinking behavior. | Existing Swift reasoning replay/adaptive thinking coverage remains applicable; Opus 5-specific Bedrock behavior is added above. |

## Validation requirements

- `scripts/audit-parity.py` enforces exact text and image catalog parity against v0.82.1 source snapshots.
- Local gates must pass: `swift build -Xswiftc -warnings-as-errors`, `swift test`, deterministic `swift test` repeats, `make check`, `scripts/audit-parity.py`, `scripts/static-check.py`, and zero hidden `XCTSkip` matches.
- Acceptance requires GitHub Actions `static-check`, Ubuntu Swift tests, and macOS Swift tests all green for the pushed commit.
