# Upstream v0.84.1 whole-corpus test crosswalk

Scope: exact official upstream tag `53fa77ccd8a279eb87e92294ef3687b03ff80112`, `packages/ai/test/*.test.ts`.

Baseline: accepted v0.84.0 crosswalk at `a5f43bf8aff3c55752432655f7334e3dafd1e256`.

This is the bounded v0.84.1 corpus inventory. It covers exactly 128 upstream test files. Disposition counts: `ported: 103`, `adapted: 8`, `live-only: 7`, `adapted/live-remainder: 10`, open items: `0`.

The v0.84.1 changed-test slice contains exactly 14 paths total: 13 existing tests modified plus 1 new `generate-models-strict.test.ts`.

| # | Upstream test path | Disposition | Swift evidence | Notes |
| ---: | --- | --- | --- | --- |
| 1 | `packages/ai/test/abort.test.ts` | adapted/live-remainder | `testOAuthDeviceCodePollingImmediateAndCancellation`, `testProviderRetryCapAndCancellation`, `testRetryAssistantCallReportsAbortedRetriesUnsuccessful`, Bedrock abort diagnostic suppression | Deterministic Swift cancellation/abort behavior is covered; upstream live/provider abort matrices remain credential-gated and unexecuted. |
| 2 | `packages/ai/test/anthropic-adaptive-thinking-models.test.ts` | ported | `testAnthropicAdaptiveThinkingModels` / `testGitHubCopilotAnthropicHeadersAndAdaptiveThinking` / `testBedrockThinkingPayloadParity` | Adaptive thinking model metadata and request payload assertions. |
| 3 | `packages/ai/test/anthropic-auth-token.test.ts` | ported | `testProviderEnvironmentAndOptions`, Anthropic request/header tests | `ANTHROPIC_AUTH_TOKEN` precedence and bearer auth behavior. |
| 4 | `packages/ai/test/anthropic-cache-write-1h-cost.test.ts` | ported | usage/cost cache-write assertions in core/provider tests | Swift `Usage.cacheWrite1h`/cost fields and cache-write cost calculation are executable in provider/core tests. |
| 5 | `packages/ai/test/anthropic-eager-tool-input-compat.test.ts` | ported | `testFireworksAnthropicToolCompatRequestShape`, Anthropic tool JSON tests | Anthropic eager tool input compatibility flags shape tool payloads. |
| 6 | `packages/ai/test/anthropic-eager-tool-input-e2e.test.ts` | live-only | N/A live credential-gated E2E | Requires live Anthropic credentials/network; deterministic Swift tests cover request-shape compatibility only. |
| 7 | `packages/ai/test/anthropic-empty-thinking-signature-compat.test.ts` | ported | `testOpenAIResponsesAssistantItemsAllowEmptyThinkingSignature`, Anthropic empty signature tests | Empty thinking signature handling is executable in Swift request conversion tests. |
| 8 | `packages/ai/test/anthropic-force-adaptive-thinking.test.ts` | ported | `testAnthropicAdaptiveThinkingPayloads`, `testGitHubCopilotAnthropicHeadersAndAdaptiveThinking` | Force-adaptive thinking metadata/request behavior. |
| 9 | `packages/ai/test/anthropic-long-cache-retention-e2e.test.ts` | live-only | N/A live credential-gated E2E | Long cache retention live cost/behavior requires provider account; Swift deterministic tests cover payload fields. |
| 10 | `packages/ai/test/anthropic-oauth.test.ts` | ported | Anthropic OAuth/registry tests | OAuth auth callback, refresh validity, and bearer resolution through Swift callbacks/registry. |
| 11 | `packages/ai/test/anthropic-opus-4-8-smoke.test.ts` | live-only | N/A live credential-gated smoke | Provider smoke requires live Anthropic access; catalog/request metadata covered deterministically. |
| 12 | `packages/ai/test/anthropic-sse-parsing.test.ts` | ported | `testAnthropicRequestAndSSEProcessing`, raw stop tests | SSE parsing, usage, stop reason, and content deltas. |
| 13 | `packages/ai/test/anthropic-temperature-compat.test.ts` | ported | `testAnthropicTemperatureCompat` | Temperature omitted for models that do not support it. |
| 14 | `packages/ai/test/anthropic-thinking-disable.test.ts` | ported | `testAnthropicThinkingPayloads` | Thinking disabled/default payload behavior. |
| 15 | `packages/ai/test/anthropic-tool-name-normalization.test.ts` | ported | Anthropic tool-name normalization assertions | Tool name normalization in request builder. |
| 16 | `packages/ai/test/azure-openai-base-url.test.ts` | ported | `testAzureOpenAIResponsesConfigAndPayload` | Azure base URL/deployment/API-version normalization. |
| 17 | `packages/ai/test/azure-openai-responses-reasoning-replay.test.ts` | ported | `testAzureResponsesReasoningEncryptedContentReplay`, `testAzureReasoningEventNormalization` | Azure reasoning replay and encrypted content normalization. |
| 18 | `packages/ai/test/baseten-models.test.ts` | ported | `testBasetenProviderAndCatalogMetadata` | Baseten catalog/env/chat-template reasoning metadata. |
| 19 | `packages/ai/test/bedrock-convert-messages.test.ts` | ported | `testBedrockConvertMessagesSkipsUnknownAndBlankContent`, `testBedrockRequestAndRegionHelpers` | Bedrock message conversion, blank/unknown handling. |
| 20 | `packages/ai/test/bedrock-credentials.test.ts` | adapted | `testGetEnvAPIKeyWithEnvBedrockAuthenticated`, Bedrock transport contract tests | AWS credential chain is transport-owned in Swift; core exposes authenticated marker and transport seam. |
| 21 | `packages/ai/test/bedrock-custom-headers.test.ts` | ported | `testBedrockCustomHeaderFiltering` | Reserved SigV4/auth headers filtered; allowed custom headers retained. |
| 22 | `packages/ai/test/bedrock-endpoint-resolution.test.ts` | ported | `testBedrockRequestAndRegionHelpers`, `ProviderMetadataTests.testBedrockRegionStopReasonAndImageBlockHelpers` | Region/ARN/endpoint resolution. |
| 23 | `packages/ai/test/bedrock-error-metadata.test.ts` | ported | `testBedrockFailureMetadataDiagnostics` | Bounded Bedrock response diagnostics. |
| 24 | `packages/ai/test/bedrock-models.test.ts` | ported | generated catalog comparator + Bedrock metadata tests | Bedrock model catalog/provider metadata. |
| 25 | `packages/ai/test/bedrock-raw-stop-reason.test.ts` | ported | `testBedrockRawStopReasonSuccessAndGuardrailError` | `end_turn` success and `guardrail_intervened` error raw stop cases. |
| 26 | `packages/ai/test/bedrock-thinking-payload.test.ts` | ported | `testBedrockThinkingPayloadParity` | Bedrock adaptive/enabled thinking payloads. |
| 27 | `packages/ai/test/cache-retention.test.ts` | ported | prompt cache retention tests in `SwiftAITests` | Prompt cache key/retention for Completions/Responses/Anthropic. |
| 28 | `packages/ai/test/cloudflare-stream.test.ts` | ported | `testCloudflareStreamPreservesUnresolvedPlaceholdersAndMaterializesResolvedEndpoint` | Resolved env materializes Cloudflare endpoint; unresolved `{VAR}` placeholders are preserved through request construction. |
| 29 | `packages/ai/test/compat-env.test.ts` | ported | `testProviderEnvironmentAndOptions`, env tests | Provider env/API-key resolution. |
| 30 | `packages/ai/test/constrained-sampling.test.ts` | ported | constrained sampling grammar/json-schema tests | Grammar/custom tool and strict JSON schema payloads. |
| 31 | `packages/ai/test/context-estimate.test.ts` | ported | `testV0803EstimateClampErrorAndRetryUtilities`, CoreUtility context tests | Context token estimation and trailing-token handling. |
| 32 | `packages/ai/test/context-overflow.test.ts` | ported | `testContextOverflowDiagnosticsNilSafety`, `testContextOverflowAndToolValidation` | Overflow classification from messages/diagnostics/usage. |
| 33 | `packages/ai/test/cross-provider-handoff.test.ts` | adapted/live-remainder | registry/model dispatch tests | Swift registry/model dispatch is covered; upstream cross-provider live handoff matrix remains provider-credential gated. |
| 34 | `packages/ai/test/deferred-tools.test.ts` | ported | `testOpenAICompletionsKimiDeferredTools`, deferred lifecycle tests | Deferred tools plus background response lifecycle. |
| 35 | `packages/ai/test/empty.test.ts` | adapted/live-remainder | empty/blank content provider tests | Portable empty content serialization is covered; upstream provider live matrix remainder is unexecuted. |
| 36 | `packages/ai/test/env-api-keys.test.ts` | ported | EnvironmentTests + `ProviderEnvironment` tests | Provider env key matrix. |
| 37 | `packages/ai/test/error-body.test.ts` | ported | provider error body normalization tests | Error body extraction without stream serialization. |
| 38 | `packages/ai/test/faux-provider.test.ts` | ported | Faux provider tests including deferred lifecycle | Faux stream, queue, usage, cache and deferred states. |
| 39 | `packages/ai/test/fetch-option.test.ts` | adapted | typed request transports (`requestTransport`, `CodexTransport`, `BedrockTransport`) tests | JS `fetch` injection maps to explicit Swift transport seams. |
| 40 | `packages/ai/test/fireworks-models.test.ts` | ported | `testFireworksKimiK26ModelMetadataAndCompat`, `testFireworksAnthropicToolCompatRequestShape` | Fireworks catalog and Anthropic compat payload. |
| 41 | `packages/ai/test/generate-models-strict.test.ts` | ported | `scripts/generate-models.py`, exact `scripts/models.v0.84.1.json` / `upstream-models.53fa77c.json`, `scripts/audit-parity.py` | Strict Individual allowlist is represented by exact seven-model catalog assertions and comparator source equality before generated Swift is accepted. |
| 42 | `packages/ai/test/github-copilot-anthropic.test.ts` | ported | `testGitHubCopilotAnthropicHeadersAndAdaptiveThinking` | GitHub Copilot Anthropic headers/model metadata. |
| 43 | `packages/ai/test/github-copilot-oauth.test.ts` | ported | `testGitHubCopilotOAuthModelFilteringAndVerificationURI` | OAuth device URI, model filtering, base URL. |
| 44 | `packages/ai/test/google-raw-stop-reason.test.ts` | ported | `testGoogleRawStopReasonMalformedFunctionAndVertexSafetyErrors` | GenAI `MALFORMED_FUNCTION_CALL` and Vertex `SAFETY` raw stop errors. |
| 45 | `packages/ai/test/google-shared-convert-tools.test.ts` | ported | `testGoogleSharedConvertToolsSchemaMetaHandling` | Tool schema/meta handling. |
| 46 | `packages/ai/test/google-shared-gemini3-unsigned-tool-call.test.ts` | ported | `testGoogleGemini3UnsignedToolCalls` | Gemini 3 unsigned/cross-model tool-call signature behavior. |
| 47 | `packages/ai/test/google-shared-image-tool-result-routing.test.ts` | ported | `testGoogleSharedImageToolResultRouting` | Image tool-result routing for Gemini 2 vs Gemini 3. |
| 48 | `packages/ai/test/google-shared-retry.test.ts` | ported | `testProviderRetryCapAndCancellation`, Google request tests | Retry/cancellation semantics via Swift provider retry utilities. |
| 49 | `packages/ai/test/google-shared-signed-empty-blocks.test.ts` | ported | `testGoogleSameModelSignatureReplay`, `testGoogleThinkingSignatureDetectionAndRetention` | Signed empty/thought signature retention/replay. |
| 50 | `packages/ai/test/google-thinking-disable.test.ts` | ported | Google thinking config tests | Disabled/default thinking config. |
| 51 | `packages/ai/test/google-thinking-signature.test.ts` | ported | `testGoogleThinkingSignatureDetectionAndRetention` | Thought signature detection/retention. |
| 52 | `packages/ai/test/google-vertex-api-key-resolution.test.ts` | ported | `testGoogleVertexAPIKeyResolutionURLSemantics`, EnvironmentTests | Vertex ADC/API-key URL semantics. |
| 53 | `packages/ai/test/image-model-data.test.ts` | adapted | `scripts/audit-parity.py`, image catalog comparator | Generator-policy/catalog-data validation is handled by exact image catalog comparator, not runtime helper tests. |
| 54 | `packages/ai/test/image-tool-result.test.ts` | adapted/live-remainder | OpenAI/Google image tool-result tests | Portable image tool-result payload routing is covered; upstream live multimodal provider matrix remainder is unexecuted. |
| 55 | `packages/ai/test/images-models.test.ts` | ported | image registry/catalog tests | Image model registry/provider metadata. |
| 56 | `packages/ai/test/images.test.ts` | adapted/live-remainder | OpenRouter image payload/response tests | Deterministic image request/response parsing is covered; live image-generation provider calls are not executed. |
| 57 | `packages/ai/test/interleaved-thinking.test.ts` | adapted/live-remainder | Anthropic/Bedrock interleaved thinking tests | Portable interleaved/adaptive thinking payload behavior is covered; live provider matrix remainder is unexecuted. |
| 58 | `packages/ai/test/kimi-coding-oauth.test.ts` | ported | `testKimiCodingOAuthDeviceAndRefresh` | Kimi OAuth device/refresh transitions. |
| 59 | `packages/ai/test/lax-message-content.test.ts` | ported | message transform/content tests | Lax content/unknown blocks handled safely. |
| 60 | `packages/ai/test/lazy-module-load.test.ts` | adapted | Swift bootstrap/registry tests | JS lazy module loading maps to explicit Swift bootstrap registration. |
| 61 | `packages/ai/test/max-thinking.test.ts` | ported | thinking helpers and provider payload tests | Max/xhigh thinking mapping and clamps. |
| 62 | `packages/ai/test/mistral-raw-stop-reason.test.ts` | ported | `testMistralRawStopReasonStopErrorAndUnknown` | Mistral `stop`, `error`, and unknown raw finish reasons. |
| 63 | `packages/ai/test/mistral-reasoning-mode.test.ts` | ported | `ProviderMetadataTests.testMistralReasoningModeAndPromptCacheKey` | Mistral reasoning mode/effort and prompt cache key. |
| 64 | `packages/ai/test/mistral-tool-schema.test.ts` | ported | Mistral tool schema tests | Tool schema conversion and validation error behavior. |
| 65 | `packages/ai/test/model-catalog-types.test.ts` | adapted | `scripts/audit-parity.py`, generated metadata tests | Generator/catalog type validation is exact comparator + generated Swift metadata assertions. |
| 66 | `packages/ai/test/model-data-validation.test.ts` | adapted | `scripts/audit-parity.py`, model snapshot files | Model data validation is a generator/catalog policy check; Swift exact JSON snapshots and comparator enforce it. |
| 67 | `packages/ai/test/models-runtime.test.ts` | ported | ModelRuntime tests | Runtime refresh/cache/replacement/supersession semantics. |
| 68 | `packages/ai/test/node-http-proxy.test.ts` | adapted | Codex/HTTP proxy transport tests where applicable | Node HTTP proxy env surface is JS runtime-specific; Swift transports own proxy behavior. |
| 69 | `packages/ai/test/oauth-auth.test.ts` | ported | OAuth registry/credential tests | Auth resolution, refresh, cancellation, cause preservation. |
| 70 | `packages/ai/test/oauth-device-code.test.ts` | ported | `testOAuthDeviceCodePollingImmediateAndCancellation`, provider device tests | Device-code pending/slow_down/timeout/cancel. |
| 71 | `packages/ai/test/openai-codex-cache-affinity-e2e.test.ts` | live-only | N/A live credential-gated E2E | Codex cache affinity E2E requires live account/network; Swift deterministic tests cover headers/cache session construction. |
| 72 | `packages/ai/test/openai-codex-oauth.test.ts` | ported | OpenAI Codex OAuth tests | Codex OAuth device/refresh/account id/zstd auth behavior. |
| 73 | `packages/ai/test/openai-codex-stream.test.ts` | ported | Codex stream/transport tests | Codex SSE/WebSocket response stream behavior. |
| 74 | `packages/ai/test/openai-completions-cache-control-format.test.ts` | ported | `testOpenAICompletionsAnthropicCacheControlFormat` | Anthropic cache-control format on OpenAI-compatible payloads. |
| 75 | `packages/ai/test/openai-completions-empty-tools.test.ts` | ported | OpenAI Completions empty tools tests | Empty tools omitted from request payload. |
| 76 | `packages/ai/test/openai-completions-prompt-cache.test.ts` | ported | prompt cache tests | Prompt cache key/retention handling. |
| 77 | `packages/ai/test/openai-completions-raw-stop-reason.test.ts` | ported | `testOpenAICompletionsMissingAndRawFinishReason` | OpenAI Completions `stop` success and `content_filter` error raw finish reasons. |
| 78 | `packages/ai/test/openai-completions-reasoning-details.test.ts` | ported | OpenAI Completions reasoning details tests | Encrypted reasoning details attached to tool calls. |
| 79 | `packages/ai/test/openai-completions-response-model.test.ts` | ported | OpenAI Completions response model tests | Response model propagation/absence behavior. |
| 80 | `packages/ai/test/openai-completions-retry.test.ts` | ported | Provider retry tests + Completions transport retry wiring | Retryable provider errors and capped retry delays. |
| 81 | `packages/ai/test/openai-completions-thinking-as-text.test.ts` | ported | thinking-as-text tests | Reasoning text/chunks as thinking content. |
| 82 | `packages/ai/test/openai-completions-thinking-token-budget.test.ts` | ported | `testOpenAICompletionsThinkingTokenBudgetEdges` | vLLM `thinking_token_budget` capability, budgets and clamping. |
| 83 | `packages/ai/test/openai-completions-tool-choice.test.ts` | ported | tool choice/strict tool request tests | Tool choice and strict function payload. |
| 84 | `packages/ai/test/openai-completions-tool-result-images.test.ts` | ported | OpenAI tool-result image tests | Image tool-result batching/routing. |
| 85 | `packages/ai/test/openai-responses-cache-affinity-e2e.test.ts` | live-only | N/A live credential-gated E2E | OpenAI cache affinity E2E requires live account/network; deterministic tests cover session/cache request fields. |
| 86 | `packages/ai/test/openai-responses-compat.test.ts` | ported | OpenAI Responses compat tests | Responses compat flags and request fields. |
| 87 | `packages/ai/test/openai-responses-empty-tool-result.test.ts` | ported | `testOpenAIResponsesToolResultImagesStayInFunctionCallOutput` and empty output branch | Empty tool result output fallback. |
| 88 | `packages/ai/test/openai-responses-foreign-toolcall-id.test.ts` | ported | `testOpenAIResponsesForeignToolCallIDNormalization` | Foreign/long tool call ID normalization. |
| 89 | `packages/ai/test/openai-responses-message-id.test.ts` | ported | Responses message ID tests | Message/reasoning/function IDs in input/output conversion. |
| 90 | `packages/ai/test/openai-responses-partial-json-cleanup.test.ts` | ported | Responses partial JSON cleanup tests | Streaming scratch fields not persisted. |
| 91 | `packages/ai/test/openai-responses-reasoning-replay-e2e.test.ts` | live-only | N/A live credential-gated E2E | Reasoning replay E2E requires live OpenAI account; deterministic replay/encrypted-content tests cover conversion logic. |
| 92 | `packages/ai/test/openai-responses-terminal-event.test.ts` | ported | `testResponsesRejectPendingTerminalStatuses` | Terminal pending/in_progress/queued statuses rejected. |
| 93 | `packages/ai/test/openai-responses-tool-result-images.test.ts` | ported | `testOpenAIResponsesToolResultImagesStayInFunctionCallOutput` | Image tool results remain in function_call_output. |
| 94 | `packages/ai/test/openrouter-cache-control-models.test.ts` | ported | `testOpenRouterAnthropicLatestModelsEnableAnthropicCacheControl` | All four `~anthropic/claude-*-latest` models assert `cacheControlFormat == "anthropic"`. |
| 95 | `packages/ai/test/openrouter-cache-write-repro.test.ts` | ported | OpenRouter cache write usage tests | Cache read/write usage accounting for OpenRouter completions. |
| 96 | `packages/ai/test/openrouter-images.test.ts` | ported | OpenRouter image tests | Image payload and response parsing. |
| 97 | `packages/ai/test/openrouter-oauth.test.ts` | ported | OpenRouter OAuth tests | OpenRouter code exchange and OAuth key handling. |
| 98 | `packages/ai/test/overflow.test.ts` | ported | overflow tests | Provider overflow classification. |
| 99 | `packages/ai/test/pi-messages.test.ts` | ported | PiMessages tests | PiMessages request/SSE/diagnostic handling. |
| 100 | `packages/ai/test/provider-error-body-passthrough.test.ts` | ported | provider error body tests | Provider error body passthrough, not catalog metadata. |
| 101 | `packages/ai/test/provider-error-body-regression.test.ts` | ported | provider error body regression tests | Provider error body normalization/regression, not catalog metadata. |
| 102 | `packages/ai/test/provider-retry.test.ts` | ported | `testProviderRetryPolicyAndDNSClassifier`, `testProviderRetryCapAndCancellation`, `testProviderRetryWiredIntoResponsesTransport` | Provider retry policies/delays/cancellation; not catalog comparator. |
| 103 | `packages/ai/test/providers.test.ts` | ported | provider registry/deferred/auth tests | Provider dispatch, auth, deferred capabilities, runtime refresh. |
| 104 | `packages/ai/test/qwen-token-plan-models.test.ts` | ported | `testUpstream0811QwenTokenPlanCatalogMetadata`, `testUpstream0841QwenTokenPlanIndividualProvider`, `testUpstream0841QwenTokenPlanIndividualRequestShape` | Qwen Token Plan, CN, and Individual catalog/env/request-shape behavior, including exact Individual seven-model allowlist and qwen `enable_thinking`/`reasoning_effort` payloads. |
| 105 | `packages/ai/test/radius-oauth.test.ts` | ported | Radius OAuth/config/runtime tests | Radius OAuth, gateway config, model injection. |
| 106 | `packages/ai/test/reasoning-options.test.ts` | adapted | `testReasoningOptionsGeneratorArchitectureEvidence` + exact catalog comparator | Generator policy is adapted to Swift generated `thinkingLevelMap` assertions; no standalone generator helper is shipped. |
| 107 | `packages/ai/test/responseid.test.ts` | ported | response ID tests | Response ID propagation across providers. |
| 108 | `packages/ai/test/retry.test.ts` | ported | retry assistant/provider tests | Assistant retry and provider retry behavior. |
| 109 | `packages/ai/test/sampling-options.test.ts` | ported | sampling options tests | Model/request sampling params merge. |
| 110 | `packages/ai/test/stream.test.ts` | adapted/live-remainder | SSE/stream parser tests | Deterministic stream parser/delta/finish/error cases are covered; upstream live stream-provider matrix remainder is unexecuted. |
| 111 | `packages/ai/test/supports-xhigh.test.ts` | ported | supported thinking level tests | XHigh/max supported thinking levels. |
| 112 | `packages/ai/test/telemetry-options.test.ts` | ported | `testTelemetryContextPropagatesThroughStreamDeferredAndImages` | Typed telemetry context propagation. |
| 113 | `packages/ai/test/text.test.ts` | ported | text utility tests | Text/sanitize helpers. |
| 114 | `packages/ai/test/together-models.test.ts` | ported | Together model metadata tests | Together catalog/reasoning controls. |
| 115 | `packages/ai/test/tokens.test.ts` | ported | usage/token parsing tests | Token and usage accounting. |
| 116 | `packages/ai/test/tool-call-id-normalization.test.ts` | ported | tool call ID normalization tests | Tool call ID normalization across providers. |
| 117 | `packages/ai/test/tool-call-without-result.test.ts` | adapted/live-remainder | tool-call-without-result tests | Pending/tool-call no-result behavior is covered deterministically; live provider matrix remainder is unexecuted. |
| 118 | `packages/ai/test/total-tokens.test.ts` | ported | total token usage tests | Total token parsing/fallbacks. |
| 119 | `packages/ai/test/transform-messages-copilot-openai-to-anthropic.test.ts` | ported | transform messages/Copilot Anthropic tests | Message transform from OpenAI/Copilot to Anthropic payloads. |
| 120 | `packages/ai/test/unicode-surrogate.test.ts` | ported | unicode surrogate tests | Invalid surrogate sanitization. |
| 121 | `packages/ai/test/uuid.test.ts` | ported | `CoreUtilityTests.testV0803EstimateClampErrorAndRetryUtilities` | UUIDv7 RFC version/variant layout, monotonic lexical order within fixed millisecond, and sequence overflow timestamp advance. |
| 122 | `packages/ai/test/validation.test.ts` | ported | `testToolValidationCoercionParity` | Tool argument coercion including nullable unions. |
| 123 | `packages/ai/test/xai-oauth.test.ts` | ported | xAI OAuth tests | xAI OAuth device/refresh/verification URI complete. |
| 124 | `packages/ai/test/xai-responses.test.ts` | ported | `testGrok45ResponsesCatalogAndActualRequestMatrix` | xAI retired exclusions, low/medium/high-only Grok 4.5 levels, and actual Responses request matrix. |
| 125 | `packages/ai/test/xhigh.test.ts` | adapted/live-remainder | xhigh support tests | XHigh/max mapping is covered deterministically; upstream live provider matrix remainder is unexecuted. |
| 126 | `packages/ai/test/xiaomi-models.test.ts` | ported | Xiaomi model placement tests | Xiaomi catalog placement. |
| 127 | `packages/ai/test/xiaomi-token-plan-ams-anthropic-empty-signature-smoke.test.ts` | live-only | N/A live/provider smoke | Smoke test requires live Xiaomi/Anthropic-compatible endpoint; deterministic catalog/signature tests cover portable logic. |
| 128 | `packages/ai/test/zen.test.ts` | adapted/live-remainder | misc provider/catalog tests | Deterministic provider/catalog behavior is covered; upstream live/provider matrix remainder is unexecuted. |
