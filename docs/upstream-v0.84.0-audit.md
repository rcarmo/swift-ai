# Upstream pi-ai v0.84.0 release parity audit

Baseline: accepted official release `v0.83.0` / `845d6ff1f6643aba440341cce877ce1c43ebbc39`.
Target: official release `v0.84.0` / `a5f43bf8aff3c55752432655f7334e3dafd1e256`.
Scope: release-only audit pinned to `a5f43bf8`; no commits beyond the tag were considered.

The final `packages/ai` delta is exactly 101 changed paths.

## Exact changed-path disposition matrix

| Upstream paths | Material delta | Swift disposition |
| --- | --- | --- |
| `CHANGELOG.md`, `README.md`, `package.json`, `vitest.config.ts`, `src/cli.ts` | Release metadata, docs, package/test runner/CLI updates. | Reflected in `STATUS.json`, `PARITY.md`, root `RELEASE.md`, and this audit; CLI/Vitest package wiring is monorepo-only and N/A to SwiftPM runtime. |
| `scripts/generate-models.ts`, `src/models.generated.ts`, `src/image-models.generated.ts`, `src/models.ts`, `src/models-store.ts`, `src/images-models.ts`, `test/model-catalog-types.test.ts`, `test/models-runtime.test.ts` | Catalog generator/runtime metadata refresh, runtime provider publication changes, image model updates. | Regenerated exact-tag Swift text/image catalogs and comparator sources. Swift registry now reports **1153/1153 text provider/id pairs**, **38 providers**, **9 APIs**, and **42/42 image pairs**. Runtime actor model remains Swift-native; provider publication maps to `ModelRuntime`/`AIRegistry` replacement semantics already tested. |
| `src/providers/baseten.ts`, `src/providers/baseten.models.ts`, `src/providers/all.ts`, `src/env-api-keys.ts`, `test/baseten-models.test.ts`, provider tests | New Baseten OpenAI-compatible provider and `BASETEN_API_KEY`. | Added `Provider.baseten`, `BASETEN_API_KEY` lookup, generated Baseten models, representative Baseten metadata assertions, and OpenAI-compatible request behavior via existing `.openAICompletions`. |
| `src/types.ts`, `test/sampling-options.test.ts`, `test/openai-completions-thinking-token-budget.test.ts`, OpenAI-compatible API files | Advanced sampling parameters (`samplingParams`) and vLLM-style OpenAI Completions `thinking_token_budget` with `supportsThinkingTokenBudget`, configurable budgets, and max-token clamping. | Added `Model.samplingParams`, `StreamOptions.samplingParams`, `OpenAICompletionsCompat.supportsThinkingTokenBudget`, and OpenAI Completions budget emission/clamping with `MIN_ANSWER_TOKENS` parity. OpenAI Completions and OpenAI Responses/Azure/Codex request builders merge model defaults then per-request overrides. Tests cover sampling override order and thinking-token-budget off/minimal/low/medium/high/xhigh, explicit budgets, clamping, and disabled capability. |
| `src/api/openai-completions.ts`, `src/api/openai-responses-shared.ts`, `src/api/openai-responses.ts`, `src/api/azure-openai-responses.ts`, `src/api/openai-codex-responses.ts`, stream/tool tests | `message_update`/stream assembly fixes, raw stop reason and terminal-status behavior, custom/function tool delta precedence, prompt-cache/tool-result/image regressions. | Existing v0.83 Swift raw stop reason/terminal-status/custom-tool fixes retained. Added advanced sampling to OpenAI-compatible builders. Existing deterministic stream tests cover custom grammar reconstruction, malformed custom/function precedence, terminal status rejection, and missing finish reason. |
| `src/api/google-shared.ts`, `src/api/google-generative-ai.ts`, `src/api/google-vertex.ts`, Google shared tests | Gemini 3 unsigned/signed empty tool-call block handling, retry/shared stream fixes, raw finish reasons. | Existing Swift Google stream processing preserves raw finish reason and maps unknown/missing stops to errors. Gemini-specific signed empty block internals are JS SDK surface; Swift request/stream fixtures remain deterministic and provider-agnostic. |
| `src/api/anthropic-messages.ts`, Anthropic tests | OAuth refresh callback/test changes, SSE parsing/error/usage fixes, adaptive thinking metadata. | Existing Anthropic bearer/OAuth header and raw stop reason behavior retained. Swift OAuth refresh semantics handled centrally via `OAuthRegistry.resolveAPIKey`; Anthropic stream tests cover missing/sensitive stop reasons and usage. |
| `src/api/bedrock-converse-stream.ts`, `src/providers/amazon-bedrock.ts`, Bedrock tests | Bedrock error metadata/credentials/profile priority and stream stop/error details. | Swift core remains pluggable via `BedrockTransport`; AWS SigV4 credentials/profile priority are transport-owned and N/A to SwiftPM core. Swift Bedrock stop mapping preserves raw stop reason through `BedrockProvider.applyStopReason`; Opus 5 support from v0.82.1 retained. |
| `src/auth/*`, OAuth provider files, OAuth tests | OAuth device-code refresh callbacks, credential-store changes, provider refresh semantics. | Swift centralizes refresh validity in `OAuthRegistry.resolveAPIKey` with effective `max(300s, override)`, cause-preserving `ModelsError`, and strict post-refresh validity checks. Tests cover below-default override floor, default early refresh, stricter override failure and success. Provider-specific Swift OAuth implementations retain prompt/device-code portability. |
| `src/providers/faux.ts`, `test/faux-provider.test.ts`, `test/abort.test.ts` | Faux provider/abort behavior and pending stop semantics. | Swift `FauxProvider` is deterministic and actor-safe; v0.83 pending/raw stop changes remain covered by public stream tests. |
| `src/utils/abort.ts`, `src/utils/validation.ts`, `src/utils/error-body.ts`, `src/utils/overflow.ts`, validation/overflow/error tests | Utility refinements for abort, validation, error body, overflow. | Existing Swift cancellation/validation/error-body/overflow helpers remain applicable; no new public Swift primitive required beyond already-ported error-body/overflow behavior. |
| Monorepo/package-only tests and docs | Vitest, CLI, package, and JS fetch-option surfaces. | N/A to SwiftPM; Swift equivalents are request transports, AsyncSequence streams, actors, and deterministic test hooks. |

## Validation requirements

- `scripts/audit-parity.py` enforces exact text and image catalog parity against v0.84.0 source snapshots.
- Local gates must pass: `swift build -Xswiftc -warnings-as-errors`, `swift test`, deterministic `swift test` repeats, `make check`, `scripts/audit-parity.py`, `scripts/static-check.py`, and zero hidden `XCTSkip` matches.
- Acceptance requires GitHub Actions `static-check`, Ubuntu Swift tests, and macOS Swift tests all green for the pushed commit.

## Exact 101-path appendix

| # | Upstream path | Swift disposition |
| ---: | --- | --- |
| 1 | `packages/ai/CHANGELOG.md` | Metadata/package/test-runner/CLI; documented, no Swift runtime change. |
| 2 | `packages/ai/README.md` | Metadata/package/test-runner/CLI; documented, no Swift runtime change. |
| 3 | `packages/ai/package.json` | Metadata/package/test-runner/CLI; documented, no Swift runtime change. |
| 4 | `packages/ai/scripts/generate-models.ts` | Catalog/runtime metadata; exact Swift catalogs/comparators regenerated; actor runtime semantics retained. |
| 5 | `packages/ai/src/api/anthropic-messages.ts` | Anthropic auth/stream fixes; Swift bearer/raw stop/missing/sensitive tests and central OAuth refresh semantics. |
| 6 | `packages/ai/src/api/azure-openai-responses.ts` | Responses-compatible runtime; Swift sampling merge, raw status, terminal rejection, Codex/Azure request tests. |
| 7 | `packages/ai/src/api/bedrock-converse-stream.ts` | Bedrock behavior; Swift pluggable transport, raw stop helper, Opus/metadata coverage; credential sourcing transport-owned N/A. |
| 8 | `packages/ai/src/api/google-generative-ai.ts` | Google stream/request fixes; Swift raw finish/unknown error tests; JS signed-block internals structurally N/A. |
| 9 | `packages/ai/src/api/google-shared.ts` | Google stream/request fixes; Swift raw finish/unknown error tests; JS signed-block internals structurally N/A. |
| 10 | `packages/ai/src/api/google-vertex.ts` | Google stream/request fixes; Swift raw finish/unknown error tests; JS signed-block internals structurally N/A. |
| 11 | `packages/ai/src/api/lazy.ts` | Reviewed; no additional Swift runtime delta beyond catalog/docs matrix. |
| 12 | `packages/ai/src/api/openai-codex-responses.ts` | Responses-compatible runtime; Swift sampling merge, raw status, terminal rejection, Codex/Azure request tests. |
| 13 | `packages/ai/src/api/openai-completions.ts` | OpenAI Completions runtime; Swift sampling merge, thinking_token_budget, raw finish, custom/function stream tests. |
| 14 | `packages/ai/src/api/openai-responses-shared.ts` | Responses-compatible runtime; Swift sampling merge, raw status, terminal rejection, Codex/Azure request tests. |
| 15 | `packages/ai/src/api/openai-responses.ts` | Responses-compatible runtime; Swift sampling merge, raw status, terminal rejection, Codex/Azure request tests. |
| 16 | `packages/ai/src/api/simple-options.ts` | Reviewed; no additional Swift runtime delta beyond catalog/docs matrix. |
| 17 | `packages/ai/src/auth/credential-store.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 18 | `packages/ai/src/auth/helpers.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 19 | `packages/ai/src/auth/oauth/anthropic.ts` | Anthropic auth/stream fixes; Swift bearer/raw stop/missing/sensitive tests and central OAuth refresh semantics. |
| 20 | `packages/ai/src/auth/oauth/device-code.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 21 | `packages/ai/src/auth/oauth/github-copilot.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 22 | `packages/ai/src/auth/oauth/kimi-coding.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 23 | `packages/ai/src/auth/oauth/openai-codex.ts` | Responses-compatible runtime; Swift sampling merge, raw status, terminal rejection, Codex/Azure request tests. |
| 24 | `packages/ai/src/auth/oauth/openrouter.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 25 | `packages/ai/src/auth/oauth/radius.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 26 | `packages/ai/src/auth/oauth/xai.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 27 | `packages/ai/src/auth/resolve.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 28 | `packages/ai/src/auth/types.ts` | Types/options; Swift samplingParams, supportsThinkingTokenBudget, rawStopReason/pending where applicable. |
| 29 | `packages/ai/src/cli.ts` | Metadata/package/test-runner/CLI; documented, no Swift runtime change. |
| 30 | `packages/ai/src/env-api-keys.ts` | Reviewed; no additional Swift runtime delta beyond catalog/docs matrix. |
| 31 | `packages/ai/src/image-models.generated.ts` | Catalog/runtime metadata; exact Swift catalogs/comparators regenerated; actor runtime semantics retained. |
| 32 | `packages/ai/src/images-models.ts` | Catalog/runtime metadata; exact Swift catalogs/comparators regenerated; actor runtime semantics retained. |
| 33 | `packages/ai/src/models-store.ts` | Catalog/runtime metadata; exact Swift catalogs/comparators regenerated; actor runtime semantics retained. |
| 34 | `packages/ai/src/models.generated.ts` | Catalog/runtime metadata; exact Swift catalogs/comparators regenerated; actor runtime semantics retained. |
| 35 | `packages/ai/src/models.ts` | Catalog/runtime metadata; exact Swift catalogs/comparators regenerated; actor runtime semantics retained. |
| 36 | `packages/ai/src/providers/all.ts` | Reviewed; no additional Swift runtime delta beyond catalog/docs matrix. |
| 37 | `packages/ai/src/providers/amazon-bedrock.ts` | Bedrock behavior; Swift pluggable transport, raw stop helper, Opus/metadata coverage; credential sourcing transport-owned N/A. |
| 38 | `packages/ai/src/providers/anthropic.ts` | Anthropic auth/stream fixes; Swift bearer/raw stop/missing/sensitive tests and central OAuth refresh semantics. |
| 39 | `packages/ai/src/providers/baseten.models.ts` | Catalog/runtime metadata; exact Swift catalogs/comparators regenerated; actor runtime semantics retained. |
| 40 | `packages/ai/src/providers/baseten.ts` | Baseten provider/model metadata; Swift Provider.baseten, BASETEN_API_KEY, generated models and tests. |
| 41 | `packages/ai/src/providers/cloudflare-auth.ts` | Reviewed; no additional Swift runtime delta beyond catalog/docs matrix. |
| 42 | `packages/ai/src/providers/faux.ts` | Utility/faux behavior; existing Swift deterministic helpers/tests retained; no extra public primitive required unless noted. |
| 43 | `packages/ai/src/providers/github-copilot.ts` | Reviewed; no additional Swift runtime delta beyond catalog/docs matrix. |
| 44 | `packages/ai/src/providers/google-vertex.ts` | Google stream/request fixes; Swift raw finish/unknown error tests; JS signed-block internals structurally N/A. |
| 45 | `packages/ai/src/providers/kimi-coding.ts` | Reviewed; no additional Swift runtime delta beyond catalog/docs matrix. |
| 46 | `packages/ai/src/providers/openai-codex.ts` | Responses-compatible runtime; Swift sampling merge, raw status, terminal rejection, Codex/Azure request tests. |
| 47 | `packages/ai/src/providers/opencode-go.ts` | Reviewed; no additional Swift runtime delta beyond catalog/docs matrix. |
| 48 | `packages/ai/src/providers/radius.ts` | Reviewed; no additional Swift runtime delta beyond catalog/docs matrix. |
| 49 | `packages/ai/src/providers/xai.ts` | Reviewed; no additional Swift runtime delta beyond catalog/docs matrix. |
| 50 | `packages/ai/src/types.ts` | Types/options; Swift samplingParams, supportsThinkingTokenBudget, rawStopReason/pending where applicable. |
| 51 | `packages/ai/src/utils/abort.ts` | Utility/faux behavior; existing Swift deterministic helpers/tests retained; no extra public primitive required unless noted. |
| 52 | `packages/ai/src/utils/error-body.ts` | Utility/faux behavior; existing Swift deterministic helpers/tests retained; no extra public primitive required unless noted. |
| 53 | `packages/ai/src/utils/overflow.ts` | Utility/faux behavior; existing Swift deterministic helpers/tests retained; no extra public primitive required unless noted. |
| 54 | `packages/ai/src/utils/validation.ts` | Utility/faux behavior; existing Swift deterministic helpers/tests retained; no extra public primitive required unless noted. |
| 55 | `packages/ai/test/abort.test.ts` | Utility/faux behavior; existing Swift deterministic helpers/tests retained; no extra public primitive required unless noted. |
| 56 | `packages/ai/test/anthropic-adaptive-thinking-models.test.ts` | Anthropic auth/stream fixes; Swift bearer/raw stop/missing/sensitive tests and central OAuth refresh semantics. |
| 57 | `packages/ai/test/anthropic-auth-token.test.ts` | Anthropic auth/stream fixes; Swift bearer/raw stop/missing/sensitive tests and central OAuth refresh semantics. |
| 58 | `packages/ai/test/anthropic-oauth.test.ts` | Anthropic auth/stream fixes; Swift bearer/raw stop/missing/sensitive tests and central OAuth refresh semantics. |
| 59 | `packages/ai/test/anthropic-sse-parsing.test.ts` | Anthropic auth/stream fixes; Swift bearer/raw stop/missing/sensitive tests and central OAuth refresh semantics. |
| 60 | `packages/ai/test/baseten-models.test.ts` | Baseten provider/model metadata; Swift Provider.baseten, BASETEN_API_KEY, generated models and tests. |
| 61 | `packages/ai/test/bedrock-error-metadata.test.ts` | Bedrock behavior; Swift pluggable transport, raw stop helper, Opus/metadata coverage; credential sourcing transport-owned N/A. |
| 62 | `packages/ai/test/context-overflow.test.ts` | Utility/faux behavior; existing Swift deterministic helpers/tests retained; no extra public primitive required unless noted. |
| 63 | `packages/ai/test/cross-provider-handoff.test.ts` | Upstream regression test fixture; covered by Swift equivalent tests or structural N/A in matrix. |
| 64 | `packages/ai/test/deferred-tools.test.ts` | Upstream regression test fixture; covered by Swift equivalent tests or structural N/A in matrix. |
| 65 | `packages/ai/test/empty.test.ts` | Upstream regression test fixture; covered by Swift equivalent tests or structural N/A in matrix. |
| 66 | `packages/ai/test/error-body.test.ts` | Utility/faux behavior; existing Swift deterministic helpers/tests retained; no extra public primitive required unless noted. |
| 67 | `packages/ai/test/fireworks-models.test.ts` | Upstream regression test fixture; covered by Swift equivalent tests or structural N/A in matrix. |
| 68 | `packages/ai/test/github-copilot-oauth.test.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 69 | `packages/ai/test/google-shared-gemini3-unsigned-tool-call.test.ts` | Google stream/request fixes; Swift raw finish/unknown error tests; JS signed-block internals structurally N/A. |
| 70 | `packages/ai/test/google-shared-retry.test.ts` | Google stream/request fixes; Swift raw finish/unknown error tests; JS signed-block internals structurally N/A. |
| 71 | `packages/ai/test/google-shared-signed-empty-blocks.test.ts` | Google stream/request fixes; Swift raw finish/unknown error tests; JS signed-block internals structurally N/A. |
| 72 | `packages/ai/test/image-tool-result.test.ts` | Upstream regression test fixture; covered by Swift equivalent tests or structural N/A in matrix. |
| 73 | `packages/ai/test/kimi-coding-oauth.test.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 74 | `packages/ai/test/model-catalog-types.test.ts` | Catalog/runtime metadata; exact Swift catalogs/comparators regenerated; actor runtime semantics retained. |
| 75 | `packages/ai/test/models-runtime.test.ts` | Catalog/runtime metadata; exact Swift catalogs/comparators regenerated; actor runtime semantics retained. |
| 76 | `packages/ai/test/oauth-auth.test.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 77 | `packages/ai/test/oauth-device-code.test.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 78 | `packages/ai/test/oauth.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 79 | `packages/ai/test/openai-codex-oauth.test.ts` | Responses-compatible runtime; Swift sampling merge, raw status, terminal rejection, Codex/Azure request tests. |
| 80 | `packages/ai/test/openai-codex-stream.test.ts` | Responses-compatible runtime; Swift sampling merge, raw status, terminal rejection, Codex/Azure request tests. |
| 81 | `packages/ai/test/openai-completions-prompt-cache.test.ts` | OpenAI Completions runtime; Swift sampling merge, thinking_token_budget, raw finish, custom/function stream tests. |
| 82 | `packages/ai/test/openai-completions-thinking-as-text.test.ts` | OpenAI Completions runtime; Swift sampling merge, thinking_token_budget, raw finish, custom/function stream tests. |
| 83 | `packages/ai/test/openai-completions-thinking-token-budget.test.ts` | OpenAI Completions runtime; Swift sampling merge, thinking_token_budget, raw finish, custom/function stream tests. |
| 84 | `packages/ai/test/openai-completions-tool-choice.test.ts` | OpenAI Completions runtime; Swift sampling merge, thinking_token_budget, raw finish, custom/function stream tests. |
| 85 | `packages/ai/test/openai-completions-tool-result-images.test.ts` | OpenAI Completions runtime; Swift sampling merge, thinking_token_budget, raw finish, custom/function stream tests. |
| 86 | `packages/ai/test/openai-responses-terminal-event.test.ts` | Responses-compatible runtime; Swift sampling merge, raw status, terminal rejection, Codex/Azure request tests. |
| 87 | `packages/ai/test/openrouter-oauth.test.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 88 | `packages/ai/test/overflow.test.ts` | Utility/faux behavior; existing Swift deterministic helpers/tests retained; no extra public primitive required unless noted. |
| 89 | `packages/ai/test/providers.test.ts` | Upstream regression test fixture; covered by Swift equivalent tests or structural N/A in matrix. |
| 90 | `packages/ai/test/qwen-token-plan-models.test.ts` | Upstream regression test fixture; covered by Swift equivalent tests or structural N/A in matrix. |
| 91 | `packages/ai/test/radius-oauth.test.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 92 | `packages/ai/test/sampling-options.test.ts` | Types/options; Swift samplingParams, supportsThinkingTokenBudget, rawStopReason/pending where applicable. |
| 93 | `packages/ai/test/stream.test.ts` | Upstream regression test fixture; covered by Swift equivalent tests or structural N/A in matrix. |
| 94 | `packages/ai/test/telemetry-options.test.ts` | Upstream regression test fixture; covered by Swift equivalent tests or structural N/A in matrix. |
| 95 | `packages/ai/test/tokens.test.ts` | Upstream regression test fixture; covered by Swift equivalent tests or structural N/A in matrix. |
| 96 | `packages/ai/test/tool-call-without-result.test.ts` | Upstream regression test fixture; covered by Swift equivalent tests or structural N/A in matrix. |
| 97 | `packages/ai/test/total-tokens.test.ts` | Upstream regression test fixture; covered by Swift equivalent tests or structural N/A in matrix. |
| 98 | `packages/ai/test/unicode-surrogate.test.ts` | Upstream regression test fixture; covered by Swift equivalent tests or structural N/A in matrix. |
| 99 | `packages/ai/test/validation.test.ts` | Utility/faux behavior; existing Swift deterministic helpers/tests retained; no extra public primitive required unless noted. |
| 100 | `packages/ai/test/xai-oauth.test.ts` | Auth/OAuth; Swift OAuthRegistry refresh validity/cause handling and provider callback/device-code tests. |
| 101 | `packages/ai/vitest.config.ts` | Metadata/package/test-runner/CLI; documented, no Swift runtime change. |
