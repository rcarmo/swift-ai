# Upstream v0.84.0 whole-corpus test crosswalk

Scope: exact official upstream tag `a5f43bf8aff3c55752432655f7334e3dafd1e256`, `packages/ai/test/*.test.ts`.

Exact cumulative upstream test-file count: **127**.

Disposition counts:
- ported: 111
- adapted: 9
- live-only: 7
- open items: 0

Credential-gated E2E/live files are explicitly marked `live-only` and are not claimed as deterministic Swift coverage. Generator-policy files are marked `adapted` unless a production Swift helper assertion executes.

| # | Upstream test file | Disposition | Swift evidence / N/A | Assertion disposition |
| ---: | --- | --- | --- | --- |
| 1 | `packages/ai/test/abort.test.ts` | ported | `testOAuthDeviceCodePollingImmediateAndCancellation`, `testProviderRetryCapAndCancellation`, `testRetryAssistantCallReportsAbortedRetriesUnsuccessful`, Bedrock abort diagnostic suppression | Structured cancellation and abort-normalized assistant responses. |
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
| 33 | `packages/ai/test/cross-provider-handoff.test.ts` | adapted | registry/model dispatch tests | JS handoff harness maps to Swift `AIRegistry`/`ModelRuntime` dispatch. |
| 34 | `packages/ai/test/deferred-tools.test.ts` | ported | `testOpenAICompletionsKimiDeferredTools`, deferred lifecycle tests | Deferred tools plus background response lifecycle. |
| 35 | `packages/ai/test/empty.test.ts` | ported | empty/blank content provider tests | Empty content serialization safeguards. |
| 36 | `packages/ai/test/env-api-keys.test.ts` | ported | EnvironmentTests + `ProviderEnvironment` tests | Provider env key matrix. |
| 37 | `packages/ai/test/error-body.test.ts` | ported | provider error body normalization tests | Error body extraction without stream serialization. |
| 38 | `packages/ai/test/faux-provider.test.ts` | ported | Faux provider tests including deferred lifecycle | Faux stream, queue, usage, cache and deferred states. |
| 39 | `packages/ai/test/fetch-option.test.ts` | adapted | typed request transports (`requestTransport`, `CodexTransport`, `BedrockTransport`) tests | JS `fetch` injection maps to explicit Swift transport seams. |
| 40 | `packages/ai/test/fireworks-models.test.ts` | ported | `testFireworksKimiK26ModelMetadataAndCompat`, `testFireworksAnthropicToolCompatRequestShape` | Fireworks catalog and Anthropic compat payload. |
| 41 | `packages/ai/test/github-copilot-anthropic.test.ts` | ported | `testGitHubCopilotAnthropicHeadersAndAdaptiveThinking` | GitHub Copilot Anthropic headers/model metadata. |
| 42 | `packages/ai/test/github-copilot-oauth.test.ts` | ported | `testGitHubCopilotOAuthModelFilteringAndVerificationURI` | OAuth device URI, model filtering, base URL. |
| 43 | `packages/ai/test/google-raw-stop-reason.test.ts` | ported | `testGoogleRawStopReasonMalformedFunctionAndVertexSafetyErrors` | GenAI `MALFORMED_FUNCTION_CALL` and Vertex `SAFETY` raw stop errors. |
| 44 | `packages/ai/test/google-shared-convert-tools.test.ts` | ported | `testGoogleSharedConvertToolsSchemaMetaHandling` | Tool schema/meta handling. |
| 45 | `packages/ai/test/google-shared-gemini3-unsigned-tool-call.test.ts` | ported | `testGoogleGemini3UnsignedToolCalls` | Gemini 3 unsigned/cross-model tool-call signature behavior. |
| 46 | `packages/ai/test/google-shared-image-tool-result-routing.test.ts` | ported | `testGoogleSharedImageToolResultRouting` | Image tool-result routing for Gemini 2 vs Gemini 3. |
| 47 | `packages/ai/test/google-shared-retry.test.ts` | ported | `testProviderRetryCapAndCancellation`, Google request tests | Retry/cancellation semantics via Swift provider retry utilities. |
| 48 | `packages/ai/test/google-shared-signed-empty-blocks.test.ts` | ported | `testGoogleSameModelSignatureReplay`, `testGoogleThinkingSignatureDetectionAndRetention` | Signed empty/thought signature retention/replay. |
| 49 | `packages/ai/test/google-thinking-disable.test.ts` | ported | Google thinking config tests | Disabled/default thinking config. |
| 50 | `packages/ai/test/google-thinking-signature.test.ts` | ported | `testGoogleThinkingSignatureDetectionAndRetention` | Thought signature detection/retention. |
| 51 | `packages/ai/test/google-vertex-api-key-resolution.test.ts` | ported | `testGoogleVertexAPIKeyResolutionURLSemantics`, EnvironmentTests | Vertex ADC/API-key URL semantics. |
| 52 | `packages/ai/test/image-model-data.test.ts` | adapted | `scripts/audit-parity.py`, image catalog comparator | Generator-policy/catalog-data validation is handled by exact image catalog comparator, not runtime helper tests. |
| 53 | `packages/ai/test/image-tool-result.test.ts` | ported | OpenAI/Google image tool-result tests | Image tool-result payload routing. |
| 54 | `packages/ai/test/images-models.test.ts` | ported | image registry/catalog tests | Image model registry/provider metadata. |
| 55 | `packages/ai/test/images.test.ts` | ported | OpenRouter image payload/response tests | Image generation request/response parsing. |
| 56 | `packages/ai/test/interleaved-thinking.test.ts` | ported | Anthropic/Bedrock interleaved thinking tests | Interleaved/adaptive thinking payload behavior. |
| 57 | `packages/ai/test/kimi-coding-oauth.test.ts` | ported | `testKimiCodingOAuthDeviceAndRefresh` | Kimi OAuth device/refresh transitions. |
| 58 | `packages/ai/test/lax-message-content.test.ts` | ported | message transform/content tests | Lax content/unknown blocks handled safely. |
| 59 | `packages/ai/test/lazy-module-load.test.ts` | adapted | Swift bootstrap/registry tests | JS lazy module loading maps to explicit Swift bootstrap registration. |
| 60 | `packages/ai/test/max-thinking.test.ts` | ported | thinking helpers and provider payload tests | Max/xhigh thinking mapping and clamps. |
| 61 | `packages/ai/test/mistral-raw-stop-reason.test.ts` | ported | `testMistralRawStopReasonStopErrorAndUnknown` | Mistral `stop`, `error`, and unknown raw finish reasons. |
| 62 | `packages/ai/test/mistral-reasoning-mode.test.ts` | ported | `ProviderMetadataTests.testMistralReasoningModeAndPromptCacheKey` | Mistral reasoning mode/effort and prompt cache key. |
| 63 | `packages/ai/test/mistral-tool-schema.test.ts` | ported | Mistral tool schema tests | Tool schema conversion and validation error behavior. |
| 64 | `packages/ai/test/model-catalog-types.test.ts` | adapted | `scripts/audit-parity.py`, generated metadata tests | Generator/catalog type validation is exact comparator + generated Swift metadata assertions. |
| 65 | `packages/ai/test/model-data-validation.test.ts` | adapted | `scripts/audit-parity.py`, model snapshot files | Model data validation is a generator/catalog policy check; Swift exact JSON snapshots and comparator enforce it. |
| 66 | `packages/ai/test/models-runtime.test.ts` | ported | ModelRuntime tests | Runtime refresh/cache/replacement/supersession semantics. |
| 67 | `packages/ai/test/node-http-proxy.test.ts` | adapted | Codex/HTTP proxy transport tests where applicable | Node HTTP proxy env surface is JS runtime-specific; Swift transports own proxy behavior. |
| 68 | `packages/ai/test/oauth-auth.test.ts` | ported | OAuth registry/credential tests | Auth resolution, refresh, cancellation, cause preservation. |
| 69 | `packages/ai/test/oauth-device-code.test.ts` | ported | `testOAuthDeviceCodePollingImmediateAndCancellation`, provider device tests | Device-code pending/slow_down/timeout/cancel. |
| 70 | `packages/ai/test/openai-codex-cache-affinity-e2e.test.ts` | live-only | N/A live credential-gated E2E | Codex cache affinity E2E requires live account/network; Swift deterministic tests cover headers/cache session construction. |
| 71 | `packages/ai/test/openai-codex-oauth.test.ts` | ported | OpenAI Codex OAuth tests | Codex OAuth device/refresh/account id/zstd auth behavior. |
| 72 | `packages/ai/test/openai-codex-stream.test.ts` | ported | Codex stream/transport tests | Codex SSE/WebSocket response stream behavior. |
| 73 | `packages/ai/test/openai-completions-cache-control-format.test.ts` | ported | `testOpenAICompletionsAnthropicCacheControlFormat` | Anthropic cache-control format on OpenAI-compatible payloads. |
| 74 | `packages/ai/test/openai-completions-empty-tools.test.ts` | ported | OpenAI Completions empty tools tests | Empty tools omitted from request payload. |
| 75 | `packages/ai/test/openai-completions-prompt-cache.test.ts` | ported | prompt cache tests | Prompt cache key/retention handling. |
| 76 | `packages/ai/test/openai-completions-raw-stop-reason.test.ts` | ported | `testOpenAICompletionsMissingAndRawFinishReason` | OpenAI Completions `stop` success and `content_filter` error raw finish reasons. |
| 77 | `packages/ai/test/openai-completions-reasoning-details.test.ts` | ported | OpenAI Completions reasoning details tests | Encrypted reasoning details attached to tool calls. |
| 78 | `packages/ai/test/openai-completions-response-model.test.ts` | ported | OpenAI Completions response model tests | Response model propagation/absence behavior. |
| 79 | `packages/ai/test/openai-completions-retry.test.ts` | ported | Provider retry tests + Completions transport retry wiring | Retryable provider errors and capped retry delays. |
| 80 | `packages/ai/test/openai-completions-thinking-as-text.test.ts` | ported | thinking-as-text tests | Reasoning text/chunks as thinking content. |
| 81 | `packages/ai/test/openai-completions-thinking-token-budget.test.ts` | ported | `testOpenAICompletionsThinkingTokenBudgetEdges` | vLLM `thinking_token_budget` capability, budgets and clamping. |
| 82 | `packages/ai/test/openai-completions-tool-choice.test.ts` | ported | tool choice/strict tool request tests | Tool choice and strict function payload. |
| 83 | `packages/ai/test/openai-completions-tool-result-images.test.ts` | ported | OpenAI tool-result image tests | Image tool-result batching/routing. |
| 84 | `packages/ai/test/openai-responses-cache-affinity-e2e.test.ts` | live-only | N/A live credential-gated E2E | OpenAI cache affinity E2E requires live account/network; deterministic tests cover session/cache request fields. |
| 85 | `packages/ai/test/openai-responses-compat.test.ts` | ported | OpenAI Responses compat tests | Responses compat flags and request fields. |
| 86 | `packages/ai/test/openai-responses-empty-tool-result.test.ts` | ported | `testOpenAIResponsesToolResultImagesStayInFunctionCallOutput` and empty output branch | Empty tool result output fallback. |
| 87 | `packages/ai/test/openai-responses-foreign-toolcall-id.test.ts` | ported | `testOpenAIResponsesForeignToolCallIDNormalization` | Foreign/long tool call ID normalization. |
| 88 | `packages/ai/test/openai-responses-message-id.test.ts` | ported | Responses message ID tests | Message/reasoning/function IDs in input/output conversion. |
| 89 | `packages/ai/test/openai-responses-partial-json-cleanup.test.ts` | ported | Responses partial JSON cleanup tests | Streaming scratch fields not persisted. |
| 90 | `packages/ai/test/openai-responses-reasoning-replay-e2e.test.ts` | live-only | N/A live credential-gated E2E | Reasoning replay E2E requires live OpenAI account; deterministic replay/encrypted-content tests cover conversion logic. |
| 91 | `packages/ai/test/openai-responses-terminal-event.test.ts` | ported | `testResponsesRejectPendingTerminalStatuses` | Terminal pending/in_progress/queued statuses rejected. |
| 92 | `packages/ai/test/openai-responses-tool-result-images.test.ts` | ported | `testOpenAIResponsesToolResultImagesStayInFunctionCallOutput` | Image tool results remain in function_call_output. |
| 93 | `packages/ai/test/openrouter-cache-control-models.test.ts` | ported | `testOpenRouterAnthropicLatestModelsEnableAnthropicCacheControl` | All four `~anthropic/claude-*-latest` models assert `cacheControlFormat == "anthropic"`. |
| 94 | `packages/ai/test/openrouter-cache-write-repro.test.ts` | ported | OpenRouter cache write usage tests | Cache read/write usage accounting for OpenRouter completions. |
| 95 | `packages/ai/test/openrouter-images.test.ts` | ported | OpenRouter image tests | Image payload and response parsing. |
| 96 | `packages/ai/test/openrouter-oauth.test.ts` | ported | OpenRouter OAuth tests | OpenRouter code exchange and OAuth key handling. |
| 97 | `packages/ai/test/overflow.test.ts` | ported | overflow tests | Provider overflow classification. |
| 98 | `packages/ai/test/pi-messages.test.ts` | ported | PiMessages tests | PiMessages request/SSE/diagnostic handling. |
| 99 | `packages/ai/test/provider-error-body-passthrough.test.ts` | ported | provider error body tests | Provider error body passthrough, not catalog metadata. |
| 100 | `packages/ai/test/provider-error-body-regression.test.ts` | ported | provider error body regression tests | Provider error body normalization/regression, not catalog metadata. |
| 101 | `packages/ai/test/provider-retry.test.ts` | ported | `testProviderRetryPolicyAndDNSClassifier`, `testProviderRetryCapAndCancellation`, `testProviderRetryWiredIntoResponsesTransport` | Provider retry policies/delays/cancellation; not catalog comparator. |
| 102 | `packages/ai/test/providers.test.ts` | ported | provider registry/deferred/auth tests | Provider dispatch, auth, deferred capabilities, runtime refresh. |
| 103 | `packages/ai/test/qwen-token-plan-models.test.ts` | ported | Qwen Token Plan catalog tests | Qwen Token Plan model/provider metadata. |
| 104 | `packages/ai/test/radius-oauth.test.ts` | ported | Radius OAuth/config/runtime tests | Radius OAuth, gateway config, model injection. |
| 105 | `packages/ai/test/reasoning-options.test.ts` | adapted | `testReasoningOptionsGeneratorArchitectureEvidence` + exact catalog comparator | Generator policy is adapted to Swift generated `thinkingLevelMap` assertions; no standalone generator helper is shipped. |
| 106 | `packages/ai/test/responseid.test.ts` | ported | response ID tests | Response ID propagation across providers. |
| 107 | `packages/ai/test/retry.test.ts` | ported | retry assistant/provider tests | Assistant retry and provider retry behavior. |
| 108 | `packages/ai/test/sampling-options.test.ts` | ported | sampling options tests | Model/request sampling params merge. |
| 109 | `packages/ai/test/stream.test.ts` | ported | SSE/stream parser tests | Stream parser, deltas, finish/error cases. |
| 110 | `packages/ai/test/supports-xhigh.test.ts` | ported | supported thinking level tests | XHigh/max supported thinking levels. |
| 111 | `packages/ai/test/telemetry-options.test.ts` | ported | `testTelemetryContextPropagatesThroughStreamDeferredAndImages` | Typed telemetry context propagation. |
| 112 | `packages/ai/test/text.test.ts` | ported | text utility tests | Text/sanitize helpers. |
| 113 | `packages/ai/test/together-models.test.ts` | ported | Together model metadata tests | Together catalog/reasoning controls. |
| 114 | `packages/ai/test/tokens.test.ts` | ported | usage/token parsing tests | Token and usage accounting. |
| 115 | `packages/ai/test/tool-call-id-normalization.test.ts` | ported | tool call ID normalization tests | Tool call ID normalization across providers. |
| 116 | `packages/ai/test/tool-call-without-result.test.ts` | ported | tool-call-without-result tests | Pending/tool-call result behavior. |
| 117 | `packages/ai/test/total-tokens.test.ts` | ported | total token usage tests | Total token parsing/fallbacks. |
| 118 | `packages/ai/test/transform-messages-copilot-openai-to-anthropic.test.ts` | ported | transform messages/Copilot Anthropic tests | Message transform from OpenAI/Copilot to Anthropic payloads. |
| 119 | `packages/ai/test/unicode-surrogate.test.ts` | ported | unicode surrogate tests | Invalid surrogate sanitization. |
| 120 | `packages/ai/test/uuid.test.ts` | ported | `CoreUtilityTests.testV0803EstimateClampErrorAndRetryUtilities` | UUIDv7 RFC version/variant layout, monotonic lexical order within fixed millisecond, and sequence overflow timestamp advance. |
| 121 | `packages/ai/test/validation.test.ts` | ported | `testToolValidationCoercionParity` | Tool argument coercion including nullable unions. |
| 122 | `packages/ai/test/xai-oauth.test.ts` | ported | xAI OAuth tests | xAI OAuth device/refresh/verification URI complete. |
| 123 | `packages/ai/test/xai-responses.test.ts` | ported | `testGrok45ResponsesCatalogAndActualRequestMatrix` | xAI retired exclusions, low/medium/high-only Grok 4.5 levels, and actual Responses request matrix. |
| 124 | `packages/ai/test/xhigh.test.ts` | ported | xhigh support tests | XHigh support mapping. |
| 125 | `packages/ai/test/xiaomi-models.test.ts` | ported | Xiaomi model placement tests | Xiaomi catalog placement. |
| 126 | `packages/ai/test/xiaomi-token-plan-ams-anthropic-empty-signature-smoke.test.ts` | live-only | N/A live/provider smoke | Smoke test requires live Xiaomi/Anthropic-compatible endpoint; deterministic catalog/signature tests cover portable logic. |
| 127 | `packages/ai/test/zen.test.ts` | ported | misc provider/catalog tests | Zen/provider metadata behavior covered by catalog/provider tests. |
