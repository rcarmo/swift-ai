# Upstream v0.84.3 whole-corpus test crosswalk

Scope: exact official upstream tag `4e58f324fae8ebfa98a3d45181fb248072a2afac`, `packages/ai/test/*.test.ts`.

Baseline: accepted v0.84.2 crosswalk at `914cf1472e715297caa30db4b9535d534a9eb718`.

This is the bounded v0.84.3 corpus inventory. It covers exactly 136 upstream test files. Disposition counts: `N/A/adapted-generator-policy: 1`, `N/A/workers-binding-transport: 1`, `adapted: 10`, `adapted/live-remainder: 13`, `live-only: 7`, `ported: 104`, open items: `0`.

The v0.84.3 changed-test slice contains exactly 25 paths total: 20 existing tests modified plus 5 new tests (`azure-openai-tool-choice.test.ts`, `bedrock-redacted-reasoning.test.ts`, `bedrock-response-headers.test.ts`, `google-thinking-level-map.test.ts`, `zai-coding-plan-models.test.ts`).

| # | Upstream test path | Disposition | Swift evidence | Notes |
| ---: | --- | --- | --- | --- |
| 1 | `packages/ai/test/abort.test.ts` | adapted/live-remainder | `testOAuthDeviceCodePollingImmediateAndCancellation`, `testProviderRetryCapAndCancellation`, `testRetryAssistantCallReportsAbortedRetriesUnsuccessful`, Bedrock abort diagnostic suppression | Deterministic Swift cancellation/abort behavior is covered; upstream live/provider abort matrices remain credential-gated and unexecuted. |
| 2 | `packages/ai/test/anthropic-adaptive-thinking-models.test.ts` | ported | `testAnthropicAdaptiveThinkingModels` / `testGitHubCopilotAnthropicHeadersAndAdaptiveThinking` / `testBedrockThinkingPayloadParity` | Adaptive thinking model metadata and request payload assertions. |
| 3 | `packages/ai/test/anthropic-auth-token.test.ts` | ported | `testUpstream0843ToolChoiceUserAgentAndAnthropicFallbacks` plus Anthropic auth/header tests | Default Pi User-Agent, explicit header override path, server fallback beta/body. |
| 4 | `packages/ai/test/anthropic-cache-write-1h-cost.test.ts` | ported | usage/cost cache-write assertions in core/provider tests | Swift `Usage.cacheWrite1h`/cost fields and cache-write cost calculation are executable in provider/core tests. |
| 5 | `packages/ai/test/anthropic-eager-tool-input-compat.test.ts` | ported | Anthropic eager input/strict tool tests | Eager tool input compatibility retained; strict schema helper covers new strict tool conversion behavior. |
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
| 18 | `packages/ai/test/azure-openai-tool-choice.test.ts` | ported | `testUpstream0843ToolChoiceUserAgentAndAnthropicFallbacks` | Azure/OpenAI Responses `tool_choice` forwarding. |
| 19 | `packages/ai/test/baseten-models.test.ts` | ported | `testBasetenProviderAndCatalogMetadata` | Baseten catalog/env/chat-template reasoning metadata. |
| 20 | `packages/ai/test/bedrock-convert-messages.test.ts` | ported | `testUpstream0842BedrockReplaySanitizesEmptyArgumentKeys` | Bedrock replay sanitizes empty keys without mutating original streamed args. |
| 21 | `packages/ai/test/bedrock-credentials.test.ts` | adapted | `testGetEnvAPIKeyWithEnvBedrockAuthenticated`, Bedrock transport contract tests | AWS credential chain is transport-owned in Swift; core exposes authenticated marker and transport seam. |
| 22 | `packages/ai/test/bedrock-custom-headers.test.ts` | ported | `testBedrockCustomHeaderFiltering` | Reserved SigV4/auth headers filtered; allowed custom headers retained. |
| 23 | `packages/ai/test/bedrock-endpoint-resolution.test.ts` | ported | `testBedrockRequestAndRegionHelpers`, `ProviderMetadataTests.testBedrockRegionStopReasonAndImageBlockHelpers` | Region/ARN/endpoint resolution. |
| 24 | `packages/ai/test/bedrock-error-metadata.test.ts` | ported | `testBedrockFailureMetadataDiagnostics` | Bounded Bedrock response diagnostics. |
| 25 | `packages/ai/test/bedrock-models.test.ts` | ported | generated catalog comparator + Bedrock metadata tests | Bedrock model catalog/provider metadata. |
| 26 | `packages/ai/test/bedrock-raw-stop-reason.test.ts` | ported | `testBedrockRawStopReasonSuccessAndGuardrailError` | `end_turn` success and `guardrail_intervened` error raw stop cases. |
| 27 | `packages/ai/test/bedrock-redacted-reasoning.test.ts` | adapted | Bedrock request/replay tests | Redacted reasoning is represented by Swift `ContentBlock` reasoning/redaction metadata and Bedrock replay tests; live Bedrock transport remains pluggable. |
| 28 | `packages/ai/test/bedrock-response-headers.test.ts` | adapted | Bedrock transport/onResponse docs and tests | Raw AWS response headers are transport-owned in Swift `BedrockTransport`; core keeps request/diagnostic surfaces. |
| 29 | `packages/ai/test/bedrock-thinking-payload.test.ts` | ported | `testBedrockThinkingPayloadParity` | Bedrock adaptive/enabled thinking payloads. |
| 30 | `packages/ai/test/cache-retention.test.ts` | ported | prompt cache retention tests in `SwiftAITests` | Prompt cache key/retention for Completions/Responses/Anthropic. |
| 31 | `packages/ai/test/cloudflare-gateway-binding.test.ts` | N/A/workers-binding-transport | Swift transport injection audit | Cloudflare Workers AI binding object/routing semantics are JS Workers-specific; Swift keeps tokenless gateway routing in pluggable request transports, no Workers binding object is shipped. |
| 32 | `packages/ai/test/cloudflare-stream.test.ts` | ported | `testCloudflareStreamPreservesUnresolvedPlaceholdersAndMaterializesResolvedEndpoint` | Resolved env materializes Cloudflare endpoint; unresolved `{VAR}` placeholders are preserved through request construction. |
| 33 | `packages/ai/test/compat-env.test.ts` | ported | `testProviderEnvironmentAndOptions`, env tests | Provider env/API-key resolution. |
| 34 | `packages/ai/test/constrained-sampling.test.ts` | ported | `testUpstream0842StrictSchemaAndNullableNullOmission` plus existing constrained sampling tests | Strict JSON-schema conversion and unsupported/nullability behavior. |
| 35 | `packages/ai/test/context-estimate.test.ts` | ported | `testV0803EstimateClampErrorAndRetryUtilities`, CoreUtility context tests | Context token estimation and trailing-token handling. |
| 36 | `packages/ai/test/context-overflow.test.ts` | adapted/live-remainder | context overflow Swift tests + live-remainder classification | Deterministic generic overflow behavior is covered; provider/live additions remain credential-gated. |
| 37 | `packages/ai/test/cross-provider-handoff.test.ts` | adapted/live-remainder | registry/model dispatch tests | Swift registry/model dispatch is covered; upstream cross-provider live handoff matrix remains provider-credential gated. |
| 38 | `packages/ai/test/deferred-tools.test.ts` | ported | Responses deferred tool/additional_tools tests | Message-anchored `additional_tools` and fallback tool-search handling. |
| 39 | `packages/ai/test/empty.test.ts` | adapted/live-remainder | empty/blank content provider tests | Portable empty content serialization is covered; upstream provider live matrix remainder is unexecuted. |
| 40 | `packages/ai/test/env-api-keys.test.ts` | ported | EnvironmentTests + `ProviderEnvironment` tests | Provider env key matrix. |
| 41 | `packages/ai/test/error-body.test.ts` | ported | provider error body normalization tests | Error body extraction without stream serialization. |
| 42 | `packages/ai/test/faux-provider.test.ts` | ported | Faux provider tests including deferred lifecycle | Faux stream, queue, usage, cache and deferred states. |
| 43 | `packages/ai/test/fetch-option.test.ts` | adapted | typed request transports (`requestTransport`, `CodexTransport`, `BedrockTransport`) tests | JS `fetch` injection maps to explicit Swift transport seams. |
| 44 | `packages/ai/test/fireworks-models.test.ts` | ported | `testFireworksKimiK26ModelMetadataAndCompat`, `testFireworksAnthropicToolCompatRequestShape` | Fireworks catalog and Anthropic compat payload. |
| 45 | `packages/ai/test/generate-models-strict.test.ts` | N/A/adapted-generator-policy | `scripts/audit-parity.py` full-record snapshot/comparator/embedded checks plus exact delta assertions | Private TS atomic generator rollback policy is not an executable Swift port; Swift enforces the resulting exact generated catalog policy through full-record CI checks and deterministic seven-model assertions. |
| 46 | `packages/ai/test/github-copilot-anthropic.test.ts` | ported | `testGitHubCopilotAnthropicHeadersAndAdaptiveThinking` | GitHub Copilot Anthropic headers/model metadata. |
| 47 | `packages/ai/test/github-copilot-oauth.test.ts` | ported | `testUpstream0843CopilotCatalogPolicyAndRetryContract`, Copilot OAuth/concurrency tests | Known/tool-capable/policy filtering, 429 Retry-After retry, policy IDs, throttling, and structured concurrency/cancellation behavior. |
| 48 | `packages/ai/test/google-raw-stop-reason.test.ts` | ported | Google raw stop reason tests | STOP/MAX_TOKENS/raw reason mapping and tool-use precedence. |
| 49 | `packages/ai/test/google-shared-convert-tools.test.ts` | ported | `testGoogleSharedConvertToolsSchemaMetaHandling` | Tool schema/meta handling. |
| 50 | `packages/ai/test/google-shared-gemini3-unsigned-tool-call.test.ts` | ported | `testGoogleGemini3UnsignedToolCalls` | Gemini 3 unsigned/cross-model tool-call signature behavior. |
| 51 | `packages/ai/test/google-shared-image-tool-result-routing.test.ts` | ported | `testGoogleSharedImageToolResultRouting` | Image tool-result routing for Gemini 2 vs Gemini 3. |
| 52 | `packages/ai/test/google-shared-retry.test.ts` | ported | `testProviderRetryCapAndCancellation`, Google request tests | Retry/cancellation semantics via Swift provider retry utilities. |
| 53 | `packages/ai/test/google-shared-signed-empty-blocks.test.ts` | ported | `testGoogleSameModelSignatureReplay`, `testGoogleThinkingSignatureDetectionAndRetention` | Signed empty/thought signature retention/replay. |
| 54 | `packages/ai/test/google-thinking-disable.test.ts` | ported | Google thinking config tests | Disabled/default thinking config. |
| 55 | `packages/ai/test/google-thinking-level-map.test.ts` | ported | `testUpstream0843GoogleThinkingLevelMapAndBudgets` | Google thinking level mapping and custom token budgets. |
| 56 | `packages/ai/test/google-thinking-signature.test.ts` | ported | `testGoogleThinkingSignatureDetectionAndRetention` | Thought signature detection/retention. |
| 57 | `packages/ai/test/google-vertex-api-key-resolution.test.ts` | ported | `testGoogleVertexAPIKeyResolutionURLSemantics`, EnvironmentTests | Vertex ADC/API-key URL semantics. |
| 58 | `packages/ai/test/image-model-data.test.ts` | adapted | `scripts/audit-parity.py`, image catalog comparator | Generator-policy/catalog-data validation is handled by exact image catalog comparator, not runtime helper tests. |
| 59 | `packages/ai/test/image-tool-result.test.ts` | adapted/live-remainder | OpenAI/Google image tool-result tests | Portable image tool-result payload routing is covered; upstream live multimodal provider matrix remainder is unexecuted. |
| 60 | `packages/ai/test/images-models.test.ts` | ported | image registry/catalog tests | Image model registry/provider metadata. |
| 61 | `packages/ai/test/images.test.ts` | adapted/live-remainder | OpenRouter image payload/response tests | Deterministic image request/response parsing is covered; live image-generation provider calls are not executed. |
| 62 | `packages/ai/test/interleaved-thinking.test.ts` | adapted/live-remainder | Anthropic/Bedrock interleaved thinking tests | Portable interleaved/adaptive thinking payload behavior is covered; live provider matrix remainder is unexecuted. |
| 63 | `packages/ai/test/kimi-coding-oauth.test.ts` | ported | `testKimiCodingOAuthDeviceAndRefresh` | Kimi OAuth device/refresh transitions. |
| 64 | `packages/ai/test/lax-message-content.test.ts` | ported | message transform/content tests | Lax content/unknown blocks handled safely. |
| 65 | `packages/ai/test/lazy-module-load.test.ts` | adapted | static-check/source import guards | JS lazy module loading is package/runtime wiring; Swift has direct static provider modules. |
| 66 | `packages/ai/test/max-thinking.test.ts` | ported | thinking helpers and provider payload tests | Max/xhigh thinking mapping and clamps. |
| 67 | `packages/ai/test/mistral-http-transport.test.ts` | ported | `testUpstream0842MistralStreamingTransportHeadersAndUTF8`, `testUpstream0842MistralTransportErrorBodyTimeoutAndAbort`, Mistral parser tests | Production first-event-before-completion, raw streaming seam, UTF-8 split bytes, x-affinity suppression/override, non-2xx body, timeout, aborted cancellation, cached usage/errors covered. |
| 68 | `packages/ai/test/mistral-raw-stop-reason.test.ts` | ported | Mistral raw stop reason tests | Raw reason mapping retained. |
| 69 | `packages/ai/test/mistral-reasoning-mode.test.ts` | ported | `ProviderMetadataTests.testMistralReasoningModeAndPromptCacheKey` | Mistral reasoning mode/effort and prompt cache key. |
| 70 | `packages/ai/test/mistral-tool-schema.test.ts` | ported | Mistral tool schema tests | Tool schema conversion and validation error behavior. |
| 71 | `packages/ai/test/model-catalog-types.test.ts` | adapted | `scripts/audit-parity.py`, generated metadata tests | Generator/catalog type validation is exact comparator + generated Swift metadata assertions. |
| 72 | `packages/ai/test/model-data-validation.test.ts` | adapted | `scripts/audit-parity.py`, model snapshot files | Model data validation is a generator/catalog policy check; Swift exact JSON snapshots and comparator enforce it. |
| 73 | `packages/ai/test/models-runtime.test.ts` | ported | ModelRuntime tests | Runtime refresh/cache/replacement/supersession semantics. |
| 74 | `packages/ai/test/node-http-proxy.test.ts` | adapted | Codex/HTTP proxy transport tests where applicable | Node HTTP proxy env surface is JS runtime-specific; Swift transports own proxy behavior. |
| 75 | `packages/ai/test/oauth-auth.test.ts` | ported | OAuth registry/credential tests | Auth resolution, refresh, cancellation, cause preservation. |
| 76 | `packages/ai/test/oauth-device-code.test.ts` | ported | `testOAuthDeviceCodePollingImmediateAndCancellation`, provider device tests | Device-code pending/slow_down/timeout/cancel. |
| 77 | `packages/ai/test/openai-codex-cache-affinity-e2e.test.ts` | live-only | N/A live credential-gated E2E | Codex cache affinity E2E requires live account/network; Swift deterministic tests cover headers/cache session construction. |
| 78 | `packages/ai/test/openai-codex-oauth.test.ts` | ported | OpenAI Codex OAuth tests | Codex OAuth device/refresh/account id/zstd auth behavior. |
| 79 | `packages/ai/test/openai-codex-stream.test.ts` | ported | Codex SSE/zstd/header tests + `testUpstream0842UserAgentAndRetryClassifier` | Codex User-Agent and Responses conversion behavior. |
| 80 | `packages/ai/test/openai-completions-cache-control-format.test.ts` | ported | `testOpenAICompletionsAnthropicCacheControlFormat` | Anthropic cache-control format on OpenAI-compatible payloads. |
| 81 | `packages/ai/test/openai-completions-empty-tools.test.ts` | ported | OpenAI Completions empty tools tests | Empty tools omitted from request payload. |
| 82 | `packages/ai/test/openai-completions-prompt-cache.test.ts` | ported | prompt cache tests | Prompt cache key/retention handling. |
| 83 | `packages/ai/test/openai-completions-raw-stop-reason.test.ts` | ported | `testOpenAICompletionsMissingAndRawFinishReason` | OpenAI Completions `stop` success and `content_filter` error raw finish reasons. |
| 84 | `packages/ai/test/openai-completions-reasoning-details.test.ts` | ported | OpenAI Completions reasoning details tests | Encrypted reasoning details attached to tool calls. |
| 85 | `packages/ai/test/openai-completions-response-model.test.ts` | ported | OpenAI Completions response model tests | Response model propagation/absence behavior. |
| 86 | `packages/ai/test/openai-completions-retry.test.ts` | ported | Provider retry tests + Completions transport retry wiring | Retryable provider errors and capped retry delays. |
| 87 | `packages/ai/test/openai-completions-thinking-as-text.test.ts` | ported | thinking-as-text tests | Reasoning text/chunks as thinking content. |
| 88 | `packages/ai/test/openai-completions-thinking-token-budget.test.ts` | ported | OpenAI Completions thinking budget tests + Google budget test | Configurable thinking budgets retained. |
| 89 | `packages/ai/test/openai-completions-tool-choice.test.ts` | ported | OpenAI Completions/Azure tool-choice tests | Provider-neutral tool choice. |
| 90 | `packages/ai/test/openai-completions-tool-result-images.test.ts` | ported | OpenAI tool-result image tests | Image tool-result batching/routing. |
| 91 | `packages/ai/test/openai-responses-cache-affinity-e2e.test.ts` | live-only | N/A live credential-gated E2E | OpenAI cache affinity E2E requires live account/network; deterministic tests cover session/cache request fields. |
| 92 | `packages/ai/test/openai-responses-compat.test.ts` | ported | Responses compat/catalog tests | supportsAdditionalTools/ToolSearch/compat fields decoded and request-shaped. |
| 93 | `packages/ai/test/openai-responses-empty-tool-result.test.ts` | ported | `testOpenAIResponsesToolResultImagesStayInFunctionCallOutput` and empty output branch | Empty tool result output fallback. |
| 94 | `packages/ai/test/openai-responses-foreign-toolcall-id.test.ts` | ported | `testOpenAIResponsesForeignToolCallIDNormalization` | Foreign/long tool call ID normalization. |
| 95 | `packages/ai/test/openai-responses-message-id.test.ts` | ported | Responses message ID tests | Message/reasoning/function IDs in input/output conversion. |
| 96 | `packages/ai/test/openai-responses-namespace.test.ts` | ported | `testUpstream0842ResponsesAdditionalToolsNamespaceAndEndTurn` | Tool-call namespace preservation and `AssistantMessage.endTurn`. |
| 97 | `packages/ai/test/openai-responses-partial-json-cleanup.test.ts` | ported | Responses partial JSON cleanup tests | Streaming scratch fields not persisted. |
| 98 | `packages/ai/test/openai-responses-reasoning-replay-e2e.test.ts` | live-only | N/A live credential-gated E2E | Reasoning replay E2E requires live OpenAI account; deterministic replay/encrypted-content tests cover conversion logic. |
| 99 | `packages/ai/test/openai-responses-terminal-event.test.ts` | ported | `testResponsesRejectPendingTerminalStatuses` | Terminal pending/in_progress/queued statuses rejected. |
| 100 | `packages/ai/test/openai-responses-tool-result-images.test.ts` | ported | `testOpenAIResponsesToolResultImagesStayInFunctionCallOutput` | Image tool results remain in function_call_output. |
| 101 | `packages/ai/test/openrouter-cache-control-models.test.ts` | ported | `testOpenRouterAnthropicLatestModelsEnableAnthropicCacheControl` | All four `~anthropic/claude-*-latest` models assert `cacheControlFormat == "anthropic"`. |
| 102 | `packages/ai/test/openrouter-cache-write-repro.test.ts` | ported | OpenRouter cache write usage tests | Cache read/write usage accounting for OpenRouter completions. |
| 103 | `packages/ai/test/openrouter-images.test.ts` | ported | OpenRouter image tests | Image payload and response parsing. |
| 104 | `packages/ai/test/openrouter-oauth.test.ts` | ported | OpenRouter OAuth tests | OpenRouter code exchange and OAuth key handling. |
| 105 | `packages/ai/test/overflow.test.ts` | ported | overflow tests | Provider overflow classification. |
| 106 | `packages/ai/test/pi-messages.test.ts` | ported | PiMessages tests | PiMessages request/SSE/diagnostic handling. |
| 107 | `packages/ai/test/provider-error-body-passthrough.test.ts` | ported | provider error body tests | Provider error body passthrough, not catalog metadata. |
| 108 | `packages/ai/test/provider-error-body-regression.test.ts` | ported | provider error body regression tests | Provider error body normalization/regression, not catalog metadata. |
| 109 | `packages/ai/test/provider-retry.test.ts` | ported | `testProviderRetryPolicyAndDNSClassifier`, `testProviderRetryCapAndCancellation`, `testProviderRetryWiredIntoResponsesTransport` | Provider retry policies/delays/cancellation; not catalog comparator. |
| 110 | `packages/ai/test/providers.test.ts` | ported | provider registry/deferred/auth tests | Provider dispatch, auth, deferred capabilities, runtime refresh. |
| 111 | `packages/ai/test/qwen-token-plan-models.test.ts` | ported | `testUpstream0811QwenTokenPlanCatalogMetadata`, `testUpstream0841QwenTokenPlanIndividualProvider`, `testUpstream0841QwenTokenPlanIndividualRequestShape` | Qwen Token Plan, CN, and Individual catalog/env/request-shape behavior, including exact Individual seven-model allowlist and qwen `enable_thinking`/`reasoning_effort` payloads. |
| 112 | `packages/ai/test/radius-oauth.test.ts` | ported | Radius OAuth/config/runtime tests | Radius OAuth, gateway config, model injection. |
| 113 | `packages/ai/test/reasoning-options.test.ts` | adapted | `testReasoningOptionsGeneratorArchitectureEvidence` + exact catalog comparator | Generator policy is adapted to Swift generated `thinkingLevelMap` assertions; no standalone generator helper is shipped. |
| 114 | `packages/ai/test/responseid.test.ts` | ported | response ID tests | Response ID propagation across providers. |
| 115 | `packages/ai/test/retry.test.ts` | ported | `testUpstream0842UserAgentAndRetryClassifier` and provider retry tests | Buffer-limit retry classifier. |
| 116 | `packages/ai/test/sampling-options.test.ts` | ported | sampling options tests | Model/request sampling params merge. |
| 117 | `packages/ai/test/stream.test.ts` | ported | Streaming usage preservation tests | Usage updates across streaming terminal/final events retained. |
| 118 | `packages/ai/test/supports-xhigh.test.ts` | ported | supportsThinkingLevels metadata tests | DeepSeek V4 Flash low/high and xhigh metadata via exact catalog. |
| 119 | `packages/ai/test/telemetry-options.test.ts` | ported | `testTelemetryContextPropagatesThroughStreamDeferredAndImages` | Typed telemetry context propagation. |
| 120 | `packages/ai/test/text.test.ts` | ported | text utility tests | Text/sanitize helpers. |
| 121 | `packages/ai/test/together-models.test.ts` | ported | Together model metadata tests | Together catalog/reasoning controls. |
| 122 | `packages/ai/test/tokens.test.ts` | adapted/live-remainder | token accounting Swift tests + live-remainder classification | Deterministic generic token behavior is covered; newly added Individual live/provider case is credential-gated and unexecuted. |
| 123 | `packages/ai/test/tool-call-id-normalization.test.ts` | ported | tool call ID normalization tests | Tool call ID normalization across providers. |
| 124 | `packages/ai/test/tool-call-without-result.test.ts` | adapted/live-remainder | tool-call-without-result tests | Pending/tool-call no-result behavior is covered deterministically; live provider matrix remainder is unexecuted. |
| 125 | `packages/ai/test/total-tokens.test.ts` | adapted/live-remainder | total-token usage Swift tests + live-remainder classification | Deterministic generic total-token behavior is covered; provider/live additions remain credential-gated. |
| 126 | `packages/ai/test/transform-messages-copilot-openai-to-anthropic.test.ts` | ported | transform messages/Copilot Anthropic tests | Message transform from OpenAI/Copilot to Anthropic payloads. |
| 127 | `packages/ai/test/unicode-surrogate.test.ts` | adapted/live-remainder | Unicode/surrogate Swift tests + live-remainder classification | Deterministic generic Unicode behavior is covered; newly added Individual live/provider case is credential-gated and unexecuted. |
| 128 | `packages/ai/test/uuid.test.ts` | ported | `CoreUtilityTests.testV0803EstimateClampErrorAndRetryUtilities` | UUIDv7 RFC version/variant layout, monotonic lexical order within fixed millisecond, and sequence overflow timestamp advance. |
| 129 | `packages/ai/test/validation.test.ts` | ported | `testUpstream0842StrictSchemaAndNullableNullOmission` + validation tests | Optional non-nullable null omission and schema coercion. |
| 130 | `packages/ai/test/xai-oauth.test.ts` | ported | xAI OAuth tests | xAI OAuth device/refresh/verification URI complete. |
| 131 | `packages/ai/test/xai-responses.test.ts` | ported | xAI Responses catalog/request tests | xAI built-in migration to Responses, encrypted reasoning replay, Grok 4.6/default endpoint/reasoning/UA. |
| 132 | `packages/ai/test/xhigh.test.ts` | adapted/live-remainder | xhigh support tests | XHigh/max mapping is covered deterministically; upstream live provider matrix remainder is unexecuted. |
| 133 | `packages/ai/test/xiaomi-models.test.ts` | ported | Xiaomi model placement tests | Xiaomi catalog placement. |
| 134 | `packages/ai/test/xiaomi-token-plan-ams-anthropic-empty-signature-smoke.test.ts` | live-only | N/A live/provider smoke | Smoke test requires live Xiaomi/Anthropic-compatible endpoint; deterministic catalog/signature tests cover portable logic. |
| 135 | `packages/ai/test/zai-coding-plan-models.test.ts` | ported | exact catalog comparator and provider metadata tests | ZAI Coding Plan global/CN and DeepSeek V4 Pro 0813 generated catalog metadata. |
| 136 | `packages/ai/test/zen.test.ts` | adapted/live-remainder | misc provider/catalog tests | Deterministic provider/catalog behavior is covered; upstream live/provider matrix remainder is unexecuted. |
