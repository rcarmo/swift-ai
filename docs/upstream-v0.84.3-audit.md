# Upstream pi-ai v0.84.3 release parity audit

Baseline: accepted official release `v0.84.2` / `914cf1472e715297caa30db4b9535d534a9eb718`.
Target: official release `v0.84.3` / `4e58f324fae8ebfa98a3d45181fb248072a2afac`.
Scope: release-only audit pinned to `4e58f32`; no commits beyond the tag were considered.

Verified npm artifact SHA-256: `9c40af2f43950f8e94e7bbcd0c1b3548f000972da00c4fb9c0d0529d4d7d5431`.

The bounded `packages/ai` delta is exactly 48 changed paths: 19 source, 25 tests, and 4 package/docs/generated metadata paths. The cumulative whole-corpus test crosswalk covers exactly 136 upstream `packages/ai/test/*.test.ts` files in [`upstream-v0.84.3-test-crosswalk.md`](upstream-v0.84.3-test-crosswalk.md).

## Exact changed-path disposition matrix

| # | Upstream path | Swift disposition |
| ---: | --- | --- |
| 1 | `packages/ai/CHANGELOG.md` | Package/docs/generated metadata recorded in STATUS/PARITY/RELEASE/audit. |
| 2 | `packages/ai/README.md` | Package/docs/generated metadata recorded in STATUS/PARITY/RELEASE/audit. |
| 3 | `packages/ai/package.json` | Package/docs/generated metadata recorded in STATUS/PARITY/RELEASE/audit. |
| 4 | `packages/ai/scripts/generate-models.ts` | Package/docs/generated metadata recorded in STATUS/PARITY/RELEASE/audit. |
| 5 | `packages/ai/src/api/anthropic-messages.ts` | Ported: default Pi User-Agent, server-side fallback body/beta metadata, and fallback pricing metadata decoded. |
| 6 | `packages/ai/src/api/azure-openai-responses.ts` | Ported: provider-neutral toolChoice, User-Agent, Responses/Codex/xAI replay behavior. |
| 7 | `packages/ai/src/api/bedrock-converse-stream.ts` | Adapted/ported: redacted reasoning/replay and response-header transport surfaces covered, including fake production-transport streaming; live AWS headers remain transport-owned. |
| 8 | `packages/ai/src/api/google-generative-ai.ts` | Ported: Google thinking level mapping, custom budgets, raw stop/Vertex behavior, and Pi User-Agent covered by focused tests. |
| 9 | `packages/ai/src/api/google-shared.ts` | Ported: Google thinking level mapping, custom budgets, raw stop/Vertex behavior, and Pi User-Agent covered by focused tests. |
| 10 | `packages/ai/src/api/google-vertex.ts` | Ported: Google thinking level mapping, custom budgets, raw stop/Vertex behavior, and Pi User-Agent covered by focused tests. |
| 11 | `packages/ai/src/api/mistral-conversations.ts` | Package/docs/generated metadata recorded in STATUS/PARITY/RELEASE/audit. |
| 12 | `packages/ai/src/api/openai-codex-responses.ts` | Ported: provider-neutral toolChoice, User-Agent, Responses/Codex/xAI replay behavior. |
| 13 | `packages/ai/src/api/openai-completions.ts` | Ported: toolChoice, reasoningDetails preservation, strict schemas, configurable thinking budgets. |
| 14 | `packages/ai/src/api/openai-responses.ts` | Ported: provider-neutral toolChoice, User-Agent, Responses/Codex/xAI replay behavior. |
| 15 | `packages/ai/src/api/pi-messages.ts` | Package/docs/generated metadata recorded in STATUS/PARITY/RELEASE/audit. |
| 16 | `packages/ai/src/api/simple-options.ts` | Package/docs/generated metadata recorded in STATUS/PARITY/RELEASE/audit. |
| 17 | `packages/ai/src/auth/oauth/device-code.ts` | Ported/adapted: cancellation-aware retry sleep and Copilot throttling/retry/policy/login budget/persistence behavior via structured concurrency tests. |
| 18 | `packages/ai/src/auth/oauth/github-copilot.ts` | Ported/adapted: cancellation-aware retry sleep and Copilot throttling/retry/policy/login budget/persistence behavior via structured concurrency tests. |
| 19 | `packages/ai/src/auth/oauth/kimi-coding.ts` | Ported/adapted: cancellation-aware retry sleep and Copilot throttling/retry/policy/login budget/persistence behavior via structured concurrency tests. |
| 20 | `packages/ai/src/index.ts` | Package/docs/generated metadata recorded in STATUS/PARITY/RELEASE/audit. |
| 21 | `packages/ai/src/providers/xai.ts` | Ported: built-in xAI Responses migration, Grok 4.6/default endpoint/reasoning/UA via exact catalog and actual transport request tests. |
| 22 | `packages/ai/src/types.ts` | Package/docs/generated metadata recorded in STATUS/PARITY/RELEASE/audit. |
| 23 | `packages/ai/src/utils/sleep.ts` | Ported/adapted: cancellation-aware retry sleep and Copilot throttling/retry/policy/login budget/persistence behavior via structured concurrency tests. |
| 24 | `packages/ai/test/anthropic-auth-token.test.ts` | Ported: default Pi User-Agent, server-side fallback body/beta metadata, and fallback pricing metadata decoded. |
| 25 | `packages/ai/test/azure-openai-base-url.test.ts` | Ported: provider-neutral toolChoice, User-Agent, Responses/Codex/xAI replay behavior. |
| 26 | `packages/ai/test/azure-openai-tool-choice.test.ts` | Ported: provider-neutral toolChoice, User-Agent, Responses/Codex/xAI replay behavior. |
| 27 | `packages/ai/test/baseten-models.test.ts` | Covered in exact 136-file crosswalk with live/N/A separation. |
| 28 | `packages/ai/test/bedrock-redacted-reasoning.test.ts` | Adapted/ported: redacted reasoning/replay and response-header transport surfaces covered, including fake production-transport streaming; live AWS headers remain transport-owned. |
| 29 | `packages/ai/test/bedrock-response-headers.test.ts` | Adapted/ported: redacted reasoning/replay and response-header transport surfaces covered, including fake production-transport streaming; live AWS headers remain transport-owned. |
| 30 | `packages/ai/test/generate-models-strict.test.ts` | Covered in exact 136-file crosswalk with live/N/A separation. |
| 31 | `packages/ai/test/github-copilot-oauth.test.ts` | Ported/adapted: cancellation-aware retry sleep and Copilot throttling/retry/policy/login budget/persistence behavior via structured concurrency tests, including policy POST retry/failure continuation. |
| 32 | `packages/ai/test/google-raw-stop-reason.test.ts` | Ported: Google thinking level mapping, custom budgets, raw stop/Vertex behavior, and Pi User-Agent covered by focused tests. |
| 33 | `packages/ai/test/google-thinking-level-map.test.ts` | Ported: Google thinking level mapping, custom budgets, raw stop/Vertex behavior, and Pi User-Agent covered by focused tests. |
| 34 | `packages/ai/test/google-vertex-api-key-resolution.test.ts` | Ported: Google thinking level mapping, custom budgets, raw stop/Vertex behavior, and Pi User-Agent covered by focused tests. |
| 35 | `packages/ai/test/mistral-http-transport.test.ts` | Covered in exact 136-file crosswalk with live/N/A separation. |
| 36 | `packages/ai/test/model-catalog-types.test.ts` | Covered in exact 136-file crosswalk with live/N/A separation. |
| 37 | `packages/ai/test/openai-completions-reasoning-details.test.ts` | Ported: toolChoice, reasoningDetails preservation, strict schemas, configurable thinking budgets. |
| 38 | `packages/ai/test/openai-completions-thinking-as-text.test.ts` | Ported: toolChoice, reasoningDetails preservation, strict schemas, configurable thinking budgets. |
| 39 | `packages/ai/test/openai-completions-thinking-token-budget.test.ts` | Ported: toolChoice, reasoningDetails preservation, strict schemas, configurable thinking budgets. |
| 40 | `packages/ai/test/openai-completions-tool-choice.test.ts` | Ported: toolChoice, reasoningDetails preservation, strict schemas, configurable thinking budgets. |
| 41 | `packages/ai/test/openai-completions-tool-result-images.test.ts` | Ported: toolChoice, reasoningDetails preservation, strict schemas, configurable thinking budgets. |
| 42 | `packages/ai/test/pi-messages.test.ts` | Covered in exact 136-file crosswalk with live/N/A separation. |
| 43 | `packages/ai/test/qwen-token-plan-models.test.ts` | Covered in exact 136-file crosswalk with live/N/A separation. |
| 44 | `packages/ai/test/stream.test.ts` | Covered in exact 136-file crosswalk with live/N/A separation. |
| 45 | `packages/ai/test/supports-xhigh.test.ts` | Covered in exact 136-file crosswalk with live/N/A separation. |
| 46 | `packages/ai/test/xai-responses.test.ts` | Ported: built-in xAI Responses migration, Grok 4.6/default endpoint/reasoning/UA via exact catalog and actual transport request tests. |
| 47 | `packages/ai/test/xiaomi-models.test.ts` | Covered in exact 136-file crosswalk with live/N/A separation. |
| 48 | `packages/ai/test/zai-coding-plan-models.test.ts` | Ported: ZAI Coding Plan global/CN and DeepSeek V4 Pro 0813 via exact catalog/tests. |

## Catalog parity evidence

Text catalog: `scripts/models.v0.84.3.json` equals `scripts/upstream-models.4e58f32.json`; embedded registry equals normalized snapshot. Full records: `1312/1312`, providers `39`, APIs `9`, delta `+81/-36/88 changed`.

Image catalog: `scripts/image-models.v0.84.3.json` equals `scripts/upstream-image-models.4e58f32.json`; embedded registry equals snapshot. Full records: `45/45`, delta `+0/0/0 changed`.

## Portable behavior evidence

Implemented/adapted in Swift:

- Provider-neutral `toolChoice` through OpenAI Responses/Azure/Pi/OpenAI-compatible requests.
- Default Pi `User-Agent` with explicit override via provider headers across HTTP adapters.
- Anthropic server-side fallbacks/refusal metadata and fallback pricing compatibility metadata.
- Bedrock redacted reasoning/replay and raw response header/onResponse transport surfaces, including fake production-transport streaming; live AWS transport remains pluggable.
- Google thinking-level resolved mapping and configurable token budgets.
- Configurable OpenAI-compatible thinking budgets and reasoning-details preservation.
- xAI built-in migration to Responses, Grok 4.6/default/endpoint/reasoning/UA and encrypted reasoning replay through actual transport assertions.
- Copilot throttling/retry/policy-update/login budget/persistence fixes through bounded structured concurrency and cancellation-aware sleep/retry, including policy POST retry/failure continuation.
- ZAI Coding Plan China/global and DeepSeek V4 Pro 0813 generated compatibility.

JS-only/N/A decisions are limited to package docs/exports/lazy module mechanics and live/provider credential matrices captured in the crosswalk.

## Validation requirements

- `scripts/audit-parity.py` enforces exact text/image full-record parity, embedded registry equality, exact text delta `+81/-36/88`, exact image delta `+0/0/0`, and `--self-test` metadata fault injection.
- Local gates must pass: `swift build -Xswiftc -warnings-as-errors`, `swift test`, deterministic repeats, `make check`, parity/static checks, and zero hidden `XCTSkip` matches.
- Acceptance requires GitHub Actions `static-check`, Ubuntu Swift tests, and macOS Swift tests all green for the pushed commit.
