# Upstream pi-ai v0.84.0 release parity audit

Baseline: accepted official release `v0.83.0` / `845d6ff1f6643aba440341cce877ce1c43ebbc39`.
Target: official release `v0.84.0` / `a5f43bf8aff3c55752432655f7334e3dafd1e256`.
Scope: release-only audit pinned to `a5f43bf8`; no commits beyond the tag were considered.

The final `packages/ai` delta is exactly 101 changed paths. The cumulative whole-corpus test crosswalk covers exactly 127 upstream `packages/ai/test/*.test.ts` files in [`upstream-v0.84.0-test-crosswalk.md`](upstream-v0.84.0-test-crosswalk.md), with disposition counts `ported: 102`, `adapted: 8`, `live-only: 7`, `adapted/live-remainder: 10`, and open items `0`.

## Exact changed-path disposition matrix

| Upstream paths | Material delta | Swift disposition |
| --- | --- | --- |
| `CHANGELOG.md`, `README.md`, `package.json`, `vitest.config.ts`, `src/cli.ts` | Release metadata, docs, package/test runner/CLI updates. | Reflected in `STATUS.json`, `PARITY.md`, root `RELEASE.md`, and this audit; CLI/Vitest package wiring is monorepo-only and N/A to SwiftPM runtime. |
| `scripts/generate-models.ts`, `src/models.generated.ts`, `src/image-models.generated.ts`, `src/models.ts`, `src/models-store.ts`, `src/images-models.ts`, `test/model-catalog-types.test.ts`, `test/models-runtime.test.ts` | Catalog generator/runtime metadata refresh, runtime provider publication changes, image model updates, deferred lifecycle provider capabilities. | Regenerated exact-tag Swift text/image catalogs and comparator sources. Swift registry now reports **1153/1153 text provider/id pairs**, **38 providers**, **9 APIs**, and **42/42 image pairs**. Runtime actor model remains Swift-native; provider publication maps to `ModelRuntime`/`AIRegistry` replacement semantics. Deferred `fetchDeferred`/`cancelDeferred` capabilities and `StopReason.deferred` are now public Swift APIs with Faux lifecycle tests. |
| `src/providers/baseten.ts`, `src/providers/baseten.models.ts`, `src/providers/all.ts`, `src/env-api-keys.ts`, `test/baseten-models.test.ts`, provider tests | New Baseten OpenAI-compatible provider and `BASETEN_API_KEY`. | Added `Provider.baseten`, `BASETEN_API_KEY` lookup, generated Baseten models, representative Baseten metadata assertions, and OpenAI-compatible request behavior via existing `.openAICompletions`. |
| `src/types.ts`, `test/sampling-options.test.ts`, `test/openai-completions-thinking-token-budget.test.ts`, OpenAI-compatible API files | Advanced sampling parameters (`samplingParams`) and vLLM-style OpenAI Completions `thinking_token_budget` with `supportsThinkingTokenBudget`, configurable budgets, and max-token clamping. | Added `Model.samplingParams`, `StreamOptions.samplingParams`, `OpenAICompletionsCompat.supportsThinkingTokenBudget`, and OpenAI Completions budget emission/clamping with `MIN_ANSWER_TOKENS` parity. OpenAI Completions and OpenAI Responses/Azure/Codex request builders merge model defaults then per-request overrides. Tests cover sampling override order and thinking-token-budget off/minimal/low/medium/high/xhigh, explicit budgets, clamping, and disabled capability. |
| `src/api/openai-completions.ts`, `src/api/openai-responses-shared.ts`, `src/api/openai-responses.ts`, `src/api/azure-openai-responses.ts`, `src/api/openai-codex-responses.ts`, stream/tool tests | `message_update`/stream assembly fixes, raw stop reason and terminal-status behavior, custom/function tool delta precedence, prompt-cache/tool-result/image regressions, provider header null deletion, deferred Responses lifecycle hooks. | Existing v0.83 Swift raw stop reason/terminal-status/custom-tool fixes retained. Added advanced sampling to OpenAI-compatible builders. Existing deterministic stream tests cover custom grammar reconstruction, malformed custom/function precedence, terminal status rejection, and missing finish reason. `AIUtilities.mergeProviderHeaders` ports null header deletion. Deferred public contract is implemented at registry/provider level. |
| `src/api/google-shared.ts`, `src/api/google-generative-ai.ts`, `src/api/google-vertex.ts`, Google shared tests | Gemini 3 unsigned/signed empty tool-call block handling, retry/shared stream fixes, raw finish reasons. | Existing Swift Google stream processing preserves raw finish reason and maps unknown/missing stops to errors. Gemini-specific signed empty block internals are JS SDK surface; Swift request/stream fixtures remain deterministic and provider-agnostic. |
| `src/api/anthropic-messages.ts`, Anthropic tests | OAuth refresh callback/test changes, SSE parsing/error/usage fixes, adaptive thinking metadata. | Existing Anthropic bearer/OAuth header and raw stop reason behavior retained. Swift OAuth refresh semantics handled centrally via `OAuthRegistry.resolveAPIKey`; Anthropic stream tests cover missing/sensitive stop reasons and usage. |
| `src/api/bedrock-converse-stream.ts`, `src/providers/amazon-bedrock.ts`, Bedrock tests | Bedrock error metadata/credentials/profile priority and stream stop/error details. | Swift core remains pluggable via `BedrockTransport`; AWS SigV4 credentials/profile priority are transport-owned by the transport layer. Core now exposes a bounded `BedrockFailureMetadata` diagnostic surface (`bedrock_response_failure`) and tests modeled send errors, modeled/unmodeled mid-stream errors, non-AWS transport-name filtering, abort suppression, overlong value dropping, and `Unknown` placeholder omission. Swift Bedrock stop mapping preserves raw stop reason through `BedrockProvider.applyStopReason`; Opus 5 support from v0.82.1 retained. |
| `src/auth/*`, OAuth provider files, OAuth tests | OAuth device-code refresh callbacks, credential-store changes, provider refresh semantics. | Swift centralizes refresh validity in `OAuthRegistry.resolveAPIKey` with effective `max(300s, override)`, cause-preserving `ModelsError`, and strict post-refresh validity checks. Tests cover below-default override floor, default early refresh, stricter override failure and success. Provider-specific Swift OAuth implementations retain prompt/device-code portability. |
| `src/providers/faux.ts`, `test/faux-provider.test.ts`, `test/abort.test.ts` | Faux provider/abort behavior, pending/deferred stop semantics, background response lifecycle. | Swift `FauxProvider` is deterministic and actor-safe and now supports deferred submit → pending → ready, failed fetch, cancel/cancelled, `pollAfterMs`, deferred state counters, and capability dispatch tests. |
| `src/utils/abort.ts`, `src/utils/validation.ts`, `src/utils/error-body.ts`, `src/utils/overflow.ts`, validation/overflow/error tests | Utility refinements for abort, validation, error body, overflow. | Swift cancellation/error-body/overflow helpers remain applicable. `ContextUtilities.validateAndCoerce` now ports v0.84 nullable union handling: it preserves values already matching `type` union, `anyOf`, or `oneOf` arms and coerces through union arms when no arm initially matches; tests cover null TypeBox-style unions, null plain `oneOf`, and `"42"` through `anyOf` number/null. |
| Monorepo/package-only tests and docs | Vitest, CLI, package, and JS fetch-option surfaces. | N/A to SwiftPM; Swift equivalents are request transports, AsyncSequence streams, actors, and deterministic test hooks. |

## Validation requirements

- `scripts/audit-parity.py` enforces exact text and image catalog parity against v0.84.0 source snapshots.
- Local gates must pass: `swift build -Xswiftc -warnings-as-errors`, `swift test`, deterministic `swift test` repeats, `make check`, `scripts/audit-parity.py`, `scripts/static-check.py`, and zero hidden `XCTSkip` matches.
- Acceptance requires GitHub Actions `static-check`, Ubuntu Swift tests, and macOS Swift tests all green for the pushed commit.

## Deferred lifecycle and reopened public-contract audit

The upstream `382aa641` public contract is now represented in Swift rather than treated as structural:

- `StopReason.deferred`, `DeferredHandle`, and `DeferredRequestOptions` are public `Codable & Sendable` types.
- `Message.deferred` carries the assistant deferred handle.
- `APIProvider` exposes optional `fetchDeferred` and `cancelDeferred` capabilities.
- `SwiftAI.fetchDeferred` / `SwiftAI.cancelDeferred` validate handle/model affinity, resolve provider auth from request/env options, check cancellation, and throw typed `AIError.unsupported` for providers that do not expose deferred lifecycle support.
- `FauxProvider` implements deterministic submit → pending → ready, failed fetch, cancel/cancelled, `pollAfterMs`, `deferredFetchCount`, and `cancelledDeferred` behavior.
- `TelemetryContext` is a Swift-native typed context on `StreamOptions` and `ImagesOptions`, with propagation tests across stream, simple stream, deferred fetch/cancel, and images.
- `ProviderHeaders = [String: String?]` is the public model/stream/image header override type. `AIUtilities.applyProviderHeaders` is wired into production provider request builders, and `testProviderHeadersNullDeletionAppliedInResponsesRequest` proves a default Authorization header can be deleted while unrelated headers remain.
- `ModelRuntime.refresh(force:)` now cancels older in-flight provider refresh work before running the forced refresh; tests assert newer refresh results supersede older network work and document runtime API-key refresh separation from OAuth token refresh.
- OAuth refresh signal propagation maps to Swift structured cancellation (`Task.checkCancellation`) through the new cancellation-aware `OAuthProvider.refreshToken(credentials:cancellation:)` protocol path. `OAuthRegistry.resolveAPIKey`/`refreshToken` preflight cancellation, preserve typed/cause errors for non-cancel failures, and `testOAuthRefreshCancellationPreAndMidRefresh` covers pre-cancelled and mid-refresh cancellation without task leakage.

## Exact 101-path appendix

Every row below is path-addressable to the exact `packages/ai` diff. Rows name the Swift source/test evidence or the structural reason a JS-only surface is not a SwiftPM runtime primitive.

| # | Upstream path | Swift disposition |
| ---: | --- | --- |
| 1 | `packages/ai/CHANGELOG.md` | Release notes only; recorded v0.84.0 scope/tag/counts in `RELEASE.md` and this audit. |
| 2 | `packages/ai/README.md` | README API examples/docs only; Swift public surface documented in `README.md`, `PARITY.md`, and release ledger. |
| 3 | `packages/ai/package.json` | Package/Vitest metadata; SwiftPM analogue is `Package.swift` and `.github/workflows/ci.yml`, checked by `scripts/static-check.py`. |
| 4 | `packages/ai/scripts/generate-models.ts` | Catalog generator semantics reproduced by `scripts/generate-models.py`; comparator confirms exact `1153/38/9` text and `42/1/1` image counts. |
| 5 | `packages/ai/src/api/anthropic-messages.ts` | Anthropic bearer/OAuth/header/stream deltas covered by `ProviderMetadataTests.testGitHubCopilotAnthropicHeadersAndAdaptiveThinking`, `SwiftAITests.testAnthropicRequestAndSSEProcessing`, raw stop/usage tests, and central `OAuthRegistry` refresh tests. |
| 6 | `packages/ai/src/api/azure-openai-responses.ts` | Responses-family request/status behavior covered by `OpenAIResponsesProvider` request builders, Azure URL normalization tests, terminal-event rejection tests, and sampling merge tests. |
| 7 | `packages/ai/src/api/bedrock-converse-stream.ts` | Core Bedrock request/stop/error behavior covered by `testBedrockRequestAndRegionHelpers`, `testBedrockThinkingPayloadParity`, and `testBedrockFailureMetadataDiagnostics`; AWS SigV4 I/O remains in `BedrockTransport` contract. |
| 8 | `packages/ai/src/api/google-generative-ai.ts` | Google request/SSE/tool behavior covered by `testGoogleRequestURLAndSSEProcessing`, `testGoogleGemini3UnsignedToolCalls`, `testGoogleToolResultSerialization`, and provider metadata Google tests. |
| 9 | `packages/ai/src/api/google-shared.ts` | Shared Google signed/unsigned empty block and retry serialization covered by `testGoogleGemini3UnsignedToolCalls`, `testGoogleSharedImageToolResultRouting`, `testGoogleSameModelSignatureReplay`, and URL/SSE tests. |
| 10 | `packages/ai/src/api/google-vertex.ts` | Vertex URL/auth semantics covered by `testGoogleVertexAPIKeyResolutionURLSemantics`; shared body/tool handling uses same `GoogleGenerativeAIProvider` helpers as Generative AI. |
| 11 | `packages/ai/src/api/lazy.ts` | JS dynamic import/lazy loader has no SwiftPM runtime analogue; Swift providers are registered explicitly by `SwiftAI.bootstrap()` and `Registry` tests assert registration/clear/unregister behavior. |
| 12 | `packages/ai/src/api/openai-codex-responses.ts` | Codex Responses SSE/zstd/terminal/OAuth behavior covered by Codex transport tests, zstd frame tests, terminal-event tests, and OpenAI Codex OAuth tests. |
| 13 | `packages/ai/src/api/openai-completions.ts` | OpenAI Completions deltas covered by prompt-cache, tool-choice, image tool-result, thinking-as-text, raw finish, sampling, and new `thinking_token_budget` tests. |
| 14 | `packages/ai/src/api/openai-responses-shared.ts` | Shared Responses deltas covered by Responses/Azure/Codex builders, terminal status rejection, custom/function tool deltas, image tool-result tests, and sampling merge assertions. |
| 15 | `packages/ai/src/api/openai-responses.ts` | OpenAI Responses direct surface covered by request URL/body tests, response-id propagation, terminal event rejection, and sampling/request metadata assertions. |
| 16 | `packages/ai/src/api/simple-options.ts` | JS simple-stream adapter maps to Swift `AIProvider.streamSimple`; `SwiftAI.stream` dispatches `streamSimple` when reasoning is set, with request option tests covering max tokens/temperature/reasoning. |
| 17 | `packages/ai/src/auth/credential-store.ts` | Credential store semantics covered by `testAuthCredentialStoreAndCodable` plus OAuth refresh validity/cancellation tests using `InMemoryCredentialStore` and `OAuthRegistry`. |
| 18 | `packages/ai/src/auth/helpers.ts` | Auth helper URL/domain/PKCE behavior covered by OAuth utility tests (`normalizeDomain`, PKCE verifier/challenge, callback URL helpers). |
| 19 | `packages/ai/src/auth/oauth/anthropic.ts` | Anthropic OAuth/bearer distinction covered by `anthropic-auth-token` equivalent env tests and central OAuth refresh/callback contract; provider-specific browser callback is JS process surface. |
| 20 | `packages/ai/src/auth/oauth/device-code.ts` | Device-code polling interval/slow-down/cancellation covered by `testOAuthDeviceCodePollingImmediateAndCancellation`, Radius device polling, Kimi, and xAI tests. |
| 21 | `packages/ai/src/auth/oauth/github-copilot.ts` | GitHub Copilot device URI/domain/model filtering covered by `testGitHubCopilotOAuthModelFilteringAndVerificationURI` and base URL tests. |
| 22 | `packages/ai/src/auth/oauth/kimi-coding.ts` | Kimi device/refresh paths and trusted verification URI complete covered by `testKimiCodingOAuthDeviceAndRefresh`. |
| 23 | `packages/ai/src/auth/oauth/openai-codex.ts` | OpenAI Codex device/refresh/zstd OAuth surface covered by `testOpenAICodexOAuth...` and Codex transport tests. |
| 24 | `packages/ai/src/auth/oauth/openrouter.ts` | OpenRouter OAuth is central-registry credential refresh in Swift; provider catalog/env lookup and OAuth registry missing/provider failure paths are tested. |
| 25 | `packages/ai/src/auth/oauth/radius.ts` | Radius OAuth discovery/device/token/gateway config covered by `testRadiusOAuthConfigCredentialsAndModelInjection`, `testRadiusOAuthHTTPPathsAndTypedErrors`, and `testRadiusOAuthDevicePollingTransitionsAndCancellation`. |
| 26 | `packages/ai/src/auth/oauth/xai.ts` | xAI device/refresh and `verification_uri_complete` trust/fallback covered by `testXAIOAuthDeviceRefreshTransitionsAndErrors` and `testXAIOAuthDeviceCodePrefersTrustedCompleteVerificationURI`. |
| 27 | `packages/ai/src/auth/resolve.ts` | Auth resolution, post-refresh validity, typed/cause error preservation, and caller-owned cancellation are covered by `testOAuthRefreshValidityWindowAndPostRefreshCheck`, `testOAuthRefreshCancellationPreAndMidRefresh`, and provider env precedence tests. |
| 28 | `packages/ai/src/auth/types.ts` | Auth option shapes map to Swift `Credential`, `OAuthCredentials`, and `OAuthLoginCallbacks`; Codable and callback/device tests cover persisted shape. |
| 29 | `packages/ai/src/cli.ts` | CLI command wiring is package executable-only; Swift library has no CLI target, and release metadata is documented in `RELEASE.md`. |
| 30 | `packages/ai/src/env-api-keys.ts` | Provider env names covered by `ProviderEnvironment` tests, including Baseten, Anthropic auth token precedence, Bedrock authenticated marker, Radius, and OpenRouter. |
| 31 | `packages/ai/src/image-models.generated.ts` | Image catalog regenerated exactly from tag; `scripts/audit-parity.py` asserts `42/42` image provider/id pairs. |
| 32 | `packages/ai/src/images-models.ts` | Image registry/runtime maps to Swift `ImagesRegistry` and generated `BuiltinImageModels`; image catalog and OpenRouter image tests cover dispatch metadata. |
| 33 | `packages/ai/src/models-store.ts` | Runtime store maps to Swift actor-backed `ModelRuntime` and `InMemoryProviderModelsStore`; cache/ETag/fallback tested in `testRadiusRuntimeProviderRefreshUsesConfigAndCacheFallback`; forced refresh cancellation/newer-result supersession tested in `testProviderHeadersNullDeletionAndRefreshCancellation`. |
| 34 | `packages/ai/src/models.generated.ts` | Text catalog regenerated exactly from tag; comparator asserts `1153/1153` provider/id pairs. |
| 35 | `packages/ai/src/models.ts` | Provider/model publication maps to `AIRegistry` and `ModelRuntime.replaceModels`; registry/runtime tests cover replacement and stale removal. Public deferred lifecycle is ported via `DeferredHandle`, `StopReason.deferred`, `APIProvider.fetchDeferred`, `APIProvider.cancelDeferred`, `SwiftAI.fetchDeferred`, and `SwiftAI.cancelDeferred`; authenticated dispatch/capability tests cover the changed provider contract. |
| 36 | `packages/ai/src/providers/all.ts` | JS provider barrel exports map to explicit Swift bootstrap registrations; `testRegistryAndSwiftAIStream` and bootstrap tests verify provider availability. |
| 37 | `packages/ai/src/providers/amazon-bedrock.ts` | Bedrock provider metadata/credentials surface maps to `Provider.amazonBedrock`, env authenticated marker, `BedrockTransport`, region helpers, and failure metadata tests. |
| 38 | `packages/ai/src/providers/anthropic.ts` | Anthropic provider metadata/header behavior covered by Anthropic request tests and GitHub Copilot Anthropic compat tests. |
| 39 | `packages/ai/src/providers/baseten.models.ts` | Baseten generated model metadata covered by `testBasetenProviderAndCatalogMetadata` plus exact catalog comparator. |
| 40 | `packages/ai/src/providers/baseten.ts` | Baseten provider/env/compat covered by `Provider.baseten`, `BASETEN_API_KEY`, and OpenAI Completions chat-template/reasoning tests. |
| 41 | `packages/ai/src/providers/cloudflare-auth.ts` | Cloudflare account/base URL auth maps to `AIUtilities.resolveCloudflareBaseURL`; covered by `testCloudflareBaseURLHelpers` and Responses cache-retention exclusion. |
| 42 | `packages/ai/src/providers/faux.ts` | Faux provider deterministic stream/abort/pending behavior plus deferred lifecycle covered by `testFauxProviderDeferredLifecycle`, `testFauxProviderDeferredFailureAndCancel`, and existing Faux stream/cache/tool tests. |
| 43 | `packages/ai/src/providers/github-copilot.ts` | GitHub Copilot provider base URL/model filtering/headers covered by OAuth and Anthropic header tests. |
| 44 | `packages/ai/src/providers/google-vertex.ts` | Google Vertex provider auth/base URL semantics covered by `testGoogleVertexAPIKeyResolutionURLSemantics` and env ADC tests. |
| 45 | `packages/ai/src/providers/kimi-coding.ts` | Kimi Coding provider OAuth paths and catalog/runtime metadata covered by Kimi OAuth and Kimi catalog tests. |
| 46 | `packages/ai/src/providers/openai-codex.ts` | OpenAI Codex provider OAuth and Responses routing covered by Codex OAuth, stream, zstd, and terminal tests. |
| 47 | `packages/ai/src/providers/opencode-go.ts` | OpenCode Go provider catalog/disposition covered by generated catalog tests and Responses routing/model selection tests. |
| 48 | `packages/ai/src/providers/radius.ts` | Radius provider OAuth/model injection/runtime refresh covered by Radius OAuth and runtime provider tests. |
| 49 | `packages/ai/src/providers/xai.ts` | xAI provider catalog, OAuth, and exact Responses routing/request matrix covered by xAI OAuth tests and `testGrok45ResponsesCatalogAndActualRequestMatrix`. |
| 50 | `packages/ai/src/types.ts` | Types/options covered by Codable shape tests, `samplingParams`, `supportsThinkingTokenBudget`, `ProviderHeaders` nullable deletion markers, `DeferredHandle`, `DeferredRequestOptions`, `TelemetryContext`, `StopReason.deferred`, stop reason, usage, diagnostics, and request option assertions. |
| 51 | `packages/ai/src/utils/abort.ts` | Abort utility maps to Swift structured cancellation; covered by OAuth polling cancellation, ProviderRetry cancellation, retry-aborted test, and Bedrock abort diagnostic suppression. |
| 52 | `packages/ai/src/utils/error-body.ts` | Provider error body normalization maps to Swift `AIUtilities.normalizeProviderError`/error-body tests and PiMessages response-failure diagnostics. |
| 53 | `packages/ai/src/utils/overflow.ts` | Overflow detection covered by `testContextOverflowDiagnosticsNilSafety`, `testContextOverflowAndToolValidation`, and context-window clamp tests. |
| 54 | `packages/ai/src/utils/validation.ts` | Nullable union validation ported in `ContextUtilities.validateAndCoerce`; `testToolValidationCoercionParity` covers primitive coercions plus v0.84 null/oneOf/anyOf assertions. |
| 55 | `packages/ai/test/abort.test.ts` | Assertion matrix row 1 covers mid-stream/immediate abort; Swift cancellation evidence: OAuth poller, ProviderRetry, retry-aborted, Bedrock abort suppression. |
| 56 | `packages/ai/test/anthropic-adaptive-thinking-models.test.ts` | Matrix row 2; Swift evidence: generated Anthropic/GitHub Copilot Claude adaptive thinking model metadata and Bedrock adaptive thinking tests. |
| 57 | `packages/ai/test/anthropic-auth-token.test.ts` | Matrix row 3; Swift evidence: `ProviderEnvironment` ANTHROPIC_AUTH_TOKEN precedence and Anthropic bearer header tests. |
| 58 | `packages/ai/test/anthropic-oauth.test.ts` | Matrix row 4; Swift evidence: central OAuth refresh validity and Anthropic/GitHub Copilot OAuth/header tests; browser callback mechanics are represented by Swift callback structs. |
| 59 | `packages/ai/test/anthropic-sse-parsing.test.ts` | Matrix row 5; Swift evidence: Anthropic SSE parsing preserves content/thinking/usage/raw stop in `testAnthropicRequestAndSSEProcessing`. |
| 60 | `packages/ai/test/baseten-models.test.ts` | Matrix row 6; Swift evidence: Baseten catalog/env/openai-compatible reasoning tests. |
| 61 | `packages/ai/test/bedrock-error-metadata.test.ts` | Matrix row 7; Swift evidence: `testBedrockFailureMetadataDiagnostics` covers all bounded metadata cases. |
| 62 | `packages/ai/test/context-overflow.test.ts` | Matrix row 8; Swift evidence: overflow diagnostics and max-token context clamp tests. |
| 63 | `packages/ai/test/cross-provider-handoff.test.ts` | Matrix row 9; Swift evidence: registry/model selection and multi-provider generated catalog tests; JS handoff harness callbacks map to Swift registry dispatch. |
| 64 | `packages/ai/test/deferred-tools.test.ts` | Matrix row 10; Swift evidence: OpenAI Completions Kimi deferred tool request-body tests, public deferred lifecycle API tests, and tool-call-without-result behavior. |
| 65 | `packages/ai/test/empty.test.ts` | Matrix row 11; Swift evidence: empty/blank content serialization in Bedrock, Google, and request builders. |
| 66 | `packages/ai/test/error-body.test.ts` | Matrix row 12; Swift evidence: provider error-body normalization and response-failure diagnostic tests. |
| 67 | `packages/ai/test/fireworks-models.test.ts` | Matrix row 13; Swift evidence: Fireworks Kimi metadata and Anthropic tool-compat request shape tests. |
| 68 | `packages/ai/test/github-copilot-oauth.test.ts` | Matrix row 14; Swift evidence: GitHub Copilot OAuth model filtering, verification URI trust, slow-down interval, and base URL tests. |
| 69 | `packages/ai/test/google-shared-gemini3-unsigned-tool-call.test.ts` | Matrix row 15; Swift evidence: `testGoogleGemini3UnsignedToolCalls`. |
| 70 | `packages/ai/test/google-shared-retry.test.ts` | Matrix row 16; Swift evidence: ProviderRetry retry-after/cancellation plus Google request/stream deterministic processing. |
| 71 | `packages/ai/test/google-shared-signed-empty-blocks.test.ts` | Matrix row 17; Swift evidence: Google signed empty/thought signature replay and unsigned block stripping tests. |
| 72 | `packages/ai/test/image-tool-result.test.ts` | Matrix row 18; Swift evidence: OpenAI/Responses/Completions/Google image tool-result serialization tests. |
| 73 | `packages/ai/test/kimi-coding-oauth.test.ts` | Matrix row 19; Swift evidence: Kimi device authorization, trusted complete URI, polling and refresh tests. |
| 74 | `packages/ai/test/model-catalog-types.test.ts` | Matrix row 20; Swift evidence: generated model metadata Codable/catalog tests and static comparator. |
| 75 | `packages/ai/test/models-runtime.test.ts` | Matrix row 21; Swift evidence: `ModelRuntime` refresh/cache/replacement tests plus forced refresh cancellation/supersession test. |
| 76 | `packages/ai/test/oauth-auth.test.ts` | Matrix row 22; Swift evidence: credential store, env precedence, OAuth resolve, typed refresh-error preservation, and refresh cancellation tests. |
| 77 | `packages/ai/test/oauth-device-code.test.ts` | Matrix row 23; Swift evidence: device code poll immediate/slow-down/cancel plus provider device tests. |
| 78 | `packages/ai/test/oauth.ts` | Matrix row 24; Swift evidence: OAuth utility/domain/PKCE/callback tests. |
| 79 | `packages/ai/test/openai-codex-oauth.test.ts` | Matrix row 25; Swift evidence: OpenAI Codex OAuth device/poll/refresh/zstd tests. |
| 80 | `packages/ai/test/openai-codex-stream.test.ts` | Matrix row 26; Swift evidence: Codex transport stream and terminal-event tests. |
| 81 | `packages/ai/test/openai-completions-prompt-cache.test.ts` | Matrix row 27; Swift evidence: OpenAI Completions prompt cache retention/request-body tests. |
| 82 | `packages/ai/test/openai-completions-thinking-as-text.test.ts` | Matrix row 28; Swift evidence: OpenAI Completions reasoning-as-text and raw reasoning details tests. |
| 83 | `packages/ai/test/openai-completions-thinking-token-budget.test.ts` | Matrix row 29; Swift evidence: `testOpenAICompletionsThinkingTokenBudget`. |
| 84 | `packages/ai/test/openai-completions-tool-choice.test.ts` | Matrix row 30; Swift evidence: OpenAI Completions tool choice/strict/function request tests. |
| 85 | `packages/ai/test/openai-completions-tool-result-images.test.ts` | Matrix row 31; Swift evidence: Completions image tool-result routing tests. |
| 86 | `packages/ai/test/openai-responses-terminal-event.test.ts` | Matrix row 32; Swift evidence: Responses terminal-event missing/error status tests. |
| 87 | `packages/ai/test/openrouter-oauth.test.ts` | Matrix row 33; Swift evidence: OpenRouter env/catalog/OAuth registry failure paths. |
| 88 | `packages/ai/test/overflow.test.ts` | Matrix row 34; Swift evidence: context overflow pattern/non-overflow diagnostics tests. |
| 89 | `packages/ai/test/providers.test.ts` | Matrix row 35; Swift evidence: bootstrap provider registration, Baseten/env/provider API catalog tests. |
| 90 | `packages/ai/test/qwen-token-plan-models.test.ts` | Matrix row 36; Swift evidence: Qwen Token Plan catalog/provider tests. |
| 91 | `packages/ai/test/radius-oauth.test.ts` | Matrix row 37; Swift evidence: Radius OAuth config/token/device/runtime model injection tests. |
| 92 | `packages/ai/test/sampling-options.test.ts` | Matrix row 38; Swift evidence: samplingParams model/default/override tests across Completions/Responses. |
| 93 | `packages/ai/test/stream.test.ts` | Matrix row 39; Swift evidence: SSE parser, OpenAI/Anthropic/Google/PiMessages stream processing tests. |
| 94 | `packages/ai/test/telemetry-options.test.ts` | Matrix row 40; Swift evidence: `TelemetryContext` propagates through `stream`, `streamSimple`, `fetchDeferred`, `cancelDeferred`, and `generateImages` in `testTelemetryContextPropagatesThroughStreamDeferredAndImages`. |
| 95 | `packages/ai/test/tokens.test.ts` | Matrix row 41; Swift evidence: usage/token aggregation tests across providers. |
| 96 | `packages/ai/test/tool-call-without-result.test.ts` | Matrix row 42; Swift evidence: pending/tool-call-without-result and retry assistant tests. |
| 97 | `packages/ai/test/total-tokens.test.ts` | Matrix row 43; Swift evidence: totalTokens/usage parsing tests. |
| 98 | `packages/ai/test/unicode-surrogate.test.ts` | Matrix row 44; Swift evidence: surrogate sanitization tests in request builders. |
| 99 | `packages/ai/test/validation.test.ts` | Matrix row 45; Swift evidence: primitive and nullable union validation tests in `testToolValidationCoercionParity`. |
| 100 | `packages/ai/test/xai-oauth.test.ts` | Matrix row 46; Swift evidence: xAI OAuth device/refresh/errors and complete verification URI trust tests. |
| 101 | `packages/ai/vitest.config.ts` | Vitest runner configuration; Swift analogue is XCTest/SwiftPM and CI workflow, checked by static and GitHub Actions gates. |

## Exact 46 changed-test assertion matrix

The release diff contains exactly 46 changed upstream test files. This matrix records the changed assertion group for each file and the Swift evidence or precise structural rationale.

| # | Upstream changed test | Changed assertion group | Swift evidence / rationale |
| ---: | --- | --- | --- |
| 1 | `abort.test.ts` | Abort before request and during stream produces aborted stop without provider diagnostics. | Swift structured cancellation; `testOAuthDeviceCodePollingImmediateAndCancellation`, `testProviderRetryCapAndCancellation`, `testRetryAssistantCallReportsAbortedRetriesUnsuccessful`, Bedrock abort suppression. |
| 2 | `anthropic-adaptive-thinking-models.test.ts` | New/renamed Claude models advertise adaptive thinking support. | Generated catalog assertions plus `testGitHubCopilotAnthropicHeadersAndAdaptiveThinking` and `testBedrockThinkingPayloadParity`. |
| 3 | `anthropic-auth-token.test.ts` | `ANTHROPIC_AUTH_TOKEN` takes precedence over API key and is emitted as bearer auth. | `testProviderEnvironmentAndOptions` and Anthropic request/header tests. |
| 4 | `anthropic-oauth.test.ts` | OAuth refresh/auth callback keeps Anthropic bearer semantics and failure surfacing. | Central `OAuthRegistry` refresh-validity/cause tests; provider callback structs are Swift-native. |
| 5 | `anthropic-sse-parsing.test.ts` | SSE preserves content from `content_block_start`, usage, raw stop, and error text. | `testAnthropicRequestAndSSEProcessing`, `testProviderRawStopReasonHandling`. |
| 6 | `baseten-models.test.ts` | Baseten GLM/Kimi catalog, thinking toggles, chat-template args, `reasoning_effort`, env key. | `testBasetenProviderAndCatalogMetadata`, OpenAI Completions chat-template/thinking tests, `BASETEN_API_KEY` env assertion. |
| 7 | `bedrock-error-metadata.test.ts` | Diagnostics include status/errorCode/requestId, preserve errorMessage, handle send/stream modeled/unmodeled errors, filter transport names, aborts, overlong values, and `Unknown`. | `BedrockFailureMetadata`, `BedrockProvider.failureMessage`, `testBedrockFailureMetadataDiagnostics`. |
| 8 | `context-overflow.test.ts` | Overflow classification includes diagnostic/error body patterns and excludes retry/rate-limit noise. | `testContextOverflowDiagnosticsNilSafety`, `testContextOverflowAndToolValidation`, clamp tests. |
| 9 | `cross-provider-handoff.test.ts` | Provider/model handoff preserves selected model/provider dispatch. | `AIRegistry`/`ModelRuntime` replacement tests and generated catalog provider/id assertions. |
| 10 | `deferred-tools.test.ts` | Kimi/deferred tool declarations and background/deferred operation surfaces. | `testOpenAICompletionsKimiDeferredTools`; public background response lifecycle is ported through `DeferredHandle`, `StopReason.deferred`, provider `fetchDeferred`/`cancelDeferred`, and Faux lifecycle tests. |
| 11 | `empty.test.ts` | Empty content blocks are serialized safely instead of malformed requests. | Bedrock blank-content tests, Google empty block tests, and request builders insert/strip placeholders deterministically. |
| 12 | `error-body.test.ts` | Provider error bodies ignore streams, keep parsed JSON, and preserve SDK validation messages. | Swift provider error-body normalization and PiMessages response-failure diagnostics tests. |
| 13 | `fireworks-models.test.ts` | Fireworks Kimi metadata, max tokens, Anthropic compat/tool request shape. | `testFireworksKimiK26ModelMetadataAndCompat`, `testFireworksAnthropicToolCompatRequestShape`. |
| 14 | `github-copilot-oauth.test.ts` | Copilot device URI trust, slow-down interval, base URL, and Anthropic model filtering. | `testGitHubCopilotOAuthModelFilteringAndVerificationURI`, base URL tests. |
| 15 | `google-shared-gemini3-unsigned-tool-call.test.ts` | Gemini 3 unsigned tool calls omit stale signatures; non-Gemini behavior retained. | `testGoogleGemini3UnsignedToolCalls`. |
| 16 | `google-shared-retry.test.ts` | Google retry path keeps retry semantics and bounded delays. | `ProviderRetry` cap/cancellation tests plus Google URL/SSE deterministic tests. |
| 17 | `google-shared-signed-empty-blocks.test.ts` | Signed empty thinking/tool blocks keep same-model signatures and strip invalid cross-model signatures. | `testGoogleSameModelSignatureReplay`, `testGoogleGemini3UnsignedToolCalls`, `testGoogleThinkingSignatureDetectionAndRetention`. |
| 18 | `image-tool-result.test.ts` | Image tool results route as image parts for multimodal providers and text placeholders otherwise. | `testGoogleMultimodalToolResultSerialization`, OpenAI Responses/Completions image tool-result tests. |
| 19 | `kimi-coding-oauth.test.ts` | Kimi device code complete URI, polling transitions, refresh. | `testKimiCodingOAuthDeviceAndRefresh`. |
| 20 | `model-catalog-types.test.ts` | Generated model data validates provider/API/type counts. | `testGeneratedModelRegistryMetadata`, `scripts/audit-parity.py`. |
| 21 | `models-runtime.test.ts` | Runtime model store replacement, cache fallback, stale removal, cancellation/newer refresh supersession. | `ModelRuntime` tests including Radius runtime refresh/cache fallback and `testProviderHeadersNullDeletionAndRefreshCancellation`. |
| 22 | `oauth-auth.test.ts` | Credential store, OAuth auth resolution precedence, refresh error preservation, pre-cancel and mid-refresh cancellation. | `testAuthCredentialStoreAndCodable`, `testOAuthRegistryCausePreservingFailures`, `testOAuthRefreshCancellationPreAndMidRefresh`, env/OAuth registry tests. |
| 23 | `oauth-device-code.test.ts` | Device-code slow_down/pending/complete/cancel/timeout behavior. | `testOAuthDeviceCodePollingImmediateAndCancellation`, Radius/xAI/Kimi device tests. |
| 24 | `oauth.ts` | Shared OAuth utilities: domain normalization, PKCE, callbacks. | `testOAuthUtilitiesAndGitHubCopilotModelFiltering` and provider OAuth tests. |
| 25 | `openai-codex-oauth.test.ts` | Codex device flow, token refresh, zstd SSE requirements. | OpenAI Codex OAuth and zstd frame tests. |
| 26 | `openai-codex-stream.test.ts` | Codex Responses stream terminal/error/status handling. | Codex transport and Responses terminal event tests. |
| 27 | `openai-completions-prompt-cache.test.ts` | Prompt-cache retention/request fields on OpenAI-compatible completions. | OpenAI Completions prompt cache tests. |
| 28 | `openai-completions-thinking-as-text.test.ts` | Reasoning/thinking-as-text deltas and encrypted reasoning details. | OpenAI Completions reasoning detail tests. |
| 29 | `openai-completions-thinking-token-budget.test.ts` | vLLM `thinking_token_budget`, capability flag, explicit budgets, clamp/min answer tokens. | `testOpenAICompletionsThinkingTokenBudget`. |
| 30 | `openai-completions-tool-choice.test.ts` | Tool choice/strict function request-body shape. | OpenAI Completions tool-choice/strict assertions. |
| 31 | `openai-completions-tool-result-images.test.ts` | Image tool-result payloads for OpenAI-compatible chat completions. | Completions image tool-result test. |
| 32 | `openai-responses-terminal-event.test.ts` | Terminal events with failed status map to error; missing terminal is rejected. | OpenAI Responses terminal event tests. |
| 33 | `openrouter-oauth.test.ts` | OpenRouter OAuth/env/provider metadata. | OpenRouter env/catalog assertions and OAuth registry failure paths. |
| 34 | `overflow.test.ts` | Overflow patterns for provider errors, diagnostics, usage/context windows. | Context overflow tests and clamp tests. |
| 35 | `providers.test.ts` | Provider list includes Baseten/new catalog providers and auth names. | Generated catalog, bootstrap registration, ProviderEnvironment tests. |
| 36 | `qwen-token-plan-models.test.ts` | Qwen Token Plan model/catalog disposition. | Qwen Token Plan catalog/provider tests. |
| 37 | `radius-oauth.test.ts` | Radius OAuth discovery, token exchange, device transitions, gateway model injection. | Radius OAuth config/HTTP/device/runtime tests. |
| 38 | `sampling-options.test.ts` | Advanced sampling params merge model defaults then per-request overrides. | `samplingParams` tests across OpenAI Completions and Responses/Azure/Codex builders. |
| 39 | `stream.test.ts` | Stream assembly, raw stop, malformed delta, tool/function precedence. | SSE parser and provider stream processing tests. |
| 40 | `telemetry-options.test.ts` | Telemetry context threads through request surfaces, deferred ops, and images. | Swift `TelemetryContext` is an idiomatic public value propagated by `StreamOptions`/`ImagesOptions`; `testTelemetryContextPropagatesThroughStreamDeferredAndImages` covers stream, simple, deferred fetch/cancel, and images. |
| 41 | `tokens.test.ts` | Usage token accounting and reasoning/cache token fields. | Usage parsing tests across providers. |
| 42 | `tool-call-without-result.test.ts` | Tool call pending/no-result handling remains safe. | Pending stop/tool-call-without-result and retry assistant tests. |
| 43 | `total-tokens.test.ts` | Total tokens computed/preserved from provider usage. | `Usage.totalTokens` parsing assertions. |
| 44 | `unicode-surrogate.test.ts` | Invalid Unicode surrogate sanitization in outgoing/incoming text. | `AIUtilities.sanitizeSurrogates` request-builder tests. |
| 45 | `validation.test.ts` | Primitive coercion plus v0.84 nullable union preservation/coercion. | `testToolValidationCoercionParity` with null union, plain `oneOf`, and `"42"` anyOf number/null. |
| 46 | `xai-oauth.test.ts` | xAI device/refresh errors, trusted `verification_uri_complete`, fallback, untrusted rejection. | `testXAIOAuthDeviceRefreshTransitionsAndErrors`, `testXAIOAuthDeviceCodePrefersTrustedCompleteVerificationURI`. |
