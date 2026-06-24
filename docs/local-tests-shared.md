# Shared local tests adaptation status

Source corpus: `/workspace/projects/go-ai/docs/local-tests-shared.md` (188 Go local regression tests).
Upstream npm tarball `@earendil-works/pi-ai v0.80.2` does not include `*.test.ts`, so Go local tests are the cross-port regression reference.

## Summary

- Go local tests inventoried: **189**
- Adapted in Swift semantic tests: **136**
- Partial/pluggable transport coverage: **11**
- Pending direct Swift adaptation: **42**

## Highest-priority pending buckets

1. Bedrock live event-stream/SigV4 behavior tests — blocked until a `BedrockTransport` implementation is supplied; request-surface tests exist.
2. Codex WebSocket/session-cache tests — blocked until a `CodexTransport` implementation is supplied; SSE and protocol surface tests exist.
3. Full one-for-one provider retry integration tests — Swift has retry policy tests and provider semantic tests, but not every Go httptest scenario is mirrored yet.

## Test mapping

| Status | Go test | Go file | Swift coverage | Covers |
|---|---|---|---|---|
| ADAPTED | `TestCompleteNilModelDoesNotPanic` | `audit_hardening_test.go` | `testCompleteNilModelDoesNotPanic` | model registry/generated metadata parity: Complete Nil Model Does Not Panic |
| ADAPTED | `TestNilRegistrationNoops` | `audit_hardening_test.go` | `testRegistryClearAndUnregister` | Nil Registration Noops |
| ADAPTED | `TestCloneContextDeepCopiesNestedFields` | `audit_hardening_test.go` | `testCloneContextDeepCopiesNestedFieldsAndToolCalls` | Clone Context Deep Copies Nested Fields |
| ADAPTED | `TestGetToolCallsReturnsArgumentCopies` | `audit_hardening_test.go` | `testCloneContextDeepCopiesNestedFieldsAndToolCalls` | tool-call/schema conversion behavior: Get Tool Calls Returns Argument Copies |
| ADAPTED | `TestMapThinkingAndCostNilSafe` | `audit_hardening_test.go` | `testThinkingAndCostNilSafety` | reasoning/thinking wire-format behavior: Map Thinking And Cost Nil Safe |
| ADAPTED | `TestAdjustMaxTokensForThinkingReservesOutput` | `audit_hardening_test.go` | `testThinkingHelpers`, `testThinkingAndCostNilSafety` | reasoning/thinking wire-format behavior: Adjust Max Tokens For Thinking Reserves Output |
| ADAPTED | `TestIsContextOverflowUsesDiagnosticsAndNilSafe` | `audit_hardening_test.go` | `testContextOverflowDiagnosticsNilSafety` | Is Context Overflow Uses Diagnostics And Nil Safe |
| ADAPTED | `TestAdaptReasoningItem` | `coverage_boost_test.go` | `testAzureReasoningEventNormalization` | reasoning/thinking wire-format behavior: Adapt Reasoning Item |
| ADAPTED | `TestAdaptCommentaryDone` | `coverage_boost_test.go` | `testAzureReasoningEventNormalization` | Adapt Commentary Done |
| ADAPTED | `TestNormalizeReasoningTextDone` | `coverage_boost_test.go` | `testAzureReasoningEventNormalization` | reasoning/thinking wire-format behavior: Normalize Reasoning Text Done |
| ADAPTED | `TestShortHash` | `coverage_boost_test.go` | `testHashAndSanitizeUtilities` | Short Hash |
| ADAPTED | `TestCopilotHeaders` | `coverage_boost_test.go` | `testCopilotAndSessionHeaders` | auth/header/env edge case: Copilot Headers |
| ADAPTED | `TestCopilotHeadersWithIntent` | `coverage_boost_test.go` | `testCopilotAndSessionHeaders` | auth/header/env edge case: Copilot Headers With Intent |
| ADAPTED | `TestNewStderrLogger` | `coverage_boost_test.go` | `testLoggerRegistrySetAndReset` | New Stderr Logger |
| ADAPTED | `TestClearModels` | `coverage_boost_test.go` | `testRegistryClearAndUnregister` | model registry/generated metadata parity: Clear Models |
| ADAPTED | `TestDefaultRetryConfig` | `coverage_boost_test.go` | `testRetryPolicy` | retry/cancellation robustness: Default Retry Config |
| ADAPTED | `TestNoRetryConfig` | `coverage_boost_test.go` | `testRetryPolicy` | retry/cancellation robustness: No Retry Config |
| PENDING | `TestNewHTTPClient` | `coverage_boost_test.go` | `—` | New HTTPClient |
| PENDING | `TestDoWithRetrySuccess` | `coverage_boost_test.go` | `—` | retry/cancellation robustness: Do With Retry Success |
| ADAPTED | `TestDoWithRetry429` | `coverage_boost_test.go` | `testRetryPolicy` | retry/cancellation robustness: Do With Retry429 |
| PENDING | `TestDoWithRetryExhausted` | `coverage_boost_test.go` | `—` | retry/cancellation robustness: Do With Retry Exhausted |
| PENDING | `TestDoWithRetryOnRetryCallback` | `coverage_boost_test.go` | `—` | retry/cancellation robustness: Do With Retry On Retry Callback |
| ADAPTED | `TestAppendAssistantMessage` | `coverage_boost_test.go` | `testAppendAssistantMessageAndGetTextContent` | Append Assistant Message |
| ADAPTED | `TestGetTextContent` | `coverage_boost_test.go` | `testAppendAssistantMessageAndGetTextContent` | Get Text Content |
| ADAPTED | `TestInvokeOnResponse` | `coverage_boost_test.go` | `testStreamAndImageOptionHooks` | Invoke On Response |
| ADAPTED | `TestCompleteViaFaux` | `coverage_boost_test.go` | `testFauxProviderHelpers` | Complete Via Faux |
| PENDING | `TestStreamMissingFunction` | `coverage_boost_test.go` | `—` | streaming/event transport behavior: Stream Missing Function |
| ADAPTED | `TestCompleteErrorEventWithoutMessage` | `coverage_boost_test.go` | `testCompleteErrorEventWithoutMessage` | Complete Error Event Without Message |
| ADAPTED | `TestApplyToolCallLimitNoOp` | `coverage_test.go` | `testAzureToolCallLimit` | tool-call/schema conversion behavior: Apply Tool Call Limit No Op |
| ADAPTED | `TestApplyToolCallLimitTrims` | `coverage_test.go` | `testAzureToolCallLimit` | tool-call/schema conversion behavior: Apply Tool Call Limit Trims |
| ADAPTED | `TestAzureSessionHeaders` | `coverage_test.go` | `testCopilotAndSessionHeaders` | auth/header/env edge case: Azure Session Headers |
| ADAPTED | `TestNormalizeAzureReasoningEventPassthrough` | `coverage_test.go` | `testAzureReasoningEventNormalization` | reasoning/thinking wire-format behavior: Normalize Azure Reasoning Event Passthrough |
| ADAPTED | `TestNormalizeAzureReasoningEventCommentary` | `coverage_test.go` | `testAzureReasoningEventNormalization` | reasoning/thinking wire-format behavior: Normalize Azure Reasoning Event Commentary |
| ADAPTED | `TestNormalizeAzureReasoningTextDelta` | `coverage_test.go` | `testAzureReasoningEventNormalization` | reasoning/thinking wire-format behavior: Normalize Azure Reasoning Text Delta |
| ADAPTED | `TestDetectCompatProviders` | `coverage_test.go` | `testCompatProviderDetectionAndModelRegistry` | Detect Compat Providers |
| ADAPTED | `TestResolveAPIKey` | `coverage_test.go` | `testResolveAPIKeyExplicitOptionPrecedence` | auth/header/env edge case: Resolve APIKey |
| ADAPTED | `TestTransformMessagesPreservesImages` | `coverage_test.go` | `testTransformPreservesImagesForVisionModelsAndDowngradesTextModels` | image generation behavior: Transform Messages Preserves Images |
| ADAPTED | `TestTransformInsertsSyntheticToolResults` | `coverage_test.go` | `testTransformSkipsErroredAssistantMessagesAndInsertsSyntheticToolResults` | tool-call/schema conversion behavior: Transform Inserts Synthetic Tool Results |
| ADAPTED | `TestClampReasoning` | `coverage_test.go` | `testThinkingHelpers` | reasoning/thinking wire-format behavior: Clamp Reasoning |
| ADAPTED | `TestSupportsXhigh` | `coverage_test.go` | `testThinkingHelpers` | Supports Xhigh |
| ADAPTED | `TestValidateTypeChecks` | `coverage_test.go` | `testContextOverflowAndToolValidation` | Validate Type Checks |
| ADAPTED | `TestUnregisterAndClear` | `coverage_test.go` | `testRegistryClearAndUnregister` | Unregister And Clear |
| ADAPTED | `TestStreamNilModel` | `defensive_test.go` | `testStreamNilModelAndNoProvider` | streaming/event transport behavior: Stream Nil Model |
| ADAPTED | `TestAppendAssistantMessageNilSafe` | `defensive_test.go` | `testAppendAssistantMessageNilSafe` | Append Assistant Message Nil Safe |
| PENDING | `TestDoWithRetryRequiresReplayableBody` | `defensive_test.go` | `—` | provider request/payload parity: Do With Retry Requires Replayable Body |
| ADAPTED | `TestDoWithRetryNegativeMaxRetriesClampsToSingleAttempt` | `defensive_test.go` | `testRetryPolicy` | retry/cancellation robustness: Do With Retry Negative Max Retries Clamps To Single Attempt |
| PENDING | `TestDoWithRetryReplaysBodyAcrossRetries` | `defensive_test.go` | `—` | provider request/payload parity: Do With Retry Replays Body Across Retries |
| PENDING | `TestExamplesBuild` | `examples_smoke_test.go` | `—` | Examples Build |
| PENDING | `TestExamplesMissingCredentialMessages` | `examples_smoke_test.go` | `—` | Examples Missing Credential Messages |
| ADAPTED | `TestUserMessage` | `goai_test.go` | `testUserMessageAndContextJSON` | User Message |
| ADAPTED | `TestContextJSON` | `goai_test.go` | `testUserMessageAndContextJSON` | Context JSON |
| ADAPTED | `TestModelRegistry` | `goai_test.go` | `testCompatProviderDetectionAndModelRegistry`, `testGeneratedModelRegistryMetadata` | model registry/generated metadata parity: Model Registry |
| ADAPTED | `TestStreamNoProvider` | `goai_test.go` | `testStreamNilModelAndNoProvider` | streaming/event transport behavior: Stream No Provider |
| ADAPTED | `TestIsContextOverflow` | `goai_test.go` | `testContextOverflowAndToolValidation` | Is Context Overflow |
| ADAPTED | `TestValidateToolCall` | `goai_test.go` | `testContextOverflowAndToolValidation` | tool-call/schema conversion behavior: Validate Tool Call |
| ADAPTED | `TestGetEnvAPIKey` | `goai_test.go` | `testGetEnvAPIKeyProviderMappings` | auth/header/env edge case: Get Env APIKey |
| ADAPTED | `TestGetEnvAPIKeyAnthropic` | `goai_test.go` | `testGetEnvAPIKeyProviderMappings` | auth/header/env edge case: Get Env APIKey Anthropic |
| ADAPTED | `TestGetEnvAPIKeyWithEnvBedrockAuthenticated` | `goai_test.go` | `testGetEnvAPIKeyWithEnvBedrockAuthenticated` | auth/header/env edge case: Get Env APIKey With Env Bedrock Authenticated |
| ADAPTED | `TestGetEnvAPIKeyWithEnvGoogleVertexADC` | `goai_test.go` | `testGetEnvAPIKeyWithEnvGoogleVertexADC` | auth/header/env edge case: Get Env APIKey With Env Google Vertex ADC |
| ADAPTED | `TestCalculateCost` | `goai_test.go` | `testCostCalculation` | Calculate Cost |
| ADAPTED | `TestCalculateCostAnthropicLongCacheWrite` | `goai_test.go` | `testCostCalculation` | prompt/cache usage or retention behavior: Calculate Cost Anthropic Long Cache Write |
| ADAPTED | `TestModelsAreEqual` | `goai_test.go` | `testModelsAreEqual` | model registry/generated metadata parity: Models Are Equal |
| ADAPTED | `TestAdjustMaxTokensForThinking` | `goai_test.go` | `testThinkingHelpers` | reasoning/thinking wire-format behavior: Adjust Max Tokens For Thinking |
| ADAPTED | `TestTransformSkipsErroredMessages` | `goai_test.go` | `testTransformSkipsErroredAssistantMessagesAndInsertsSyntheticToolResults` | Transform Skips Errored Messages |
| ADAPTED | `TestTransformDowngradesImages` | `goai_test.go` | `testTransformPreservesImagesForVisionModelsAndDowngradesTextModels` | image generation behavior: Transform Downgrades Images |
| ADAPTED | `TestSanitizeSurrogates` | `goai_test.go` | `testHashAndSanitizeUtilities` | Sanitize Surrogates |
| ADAPTED | `TestDetectCompat` | `goai_test.go` | `testCompatProviderDetectionAndModelRegistry` | Detect Compat |
| ADAPTED | `TestClampThinkingLevelPrefersUpgrade` | `goai_test.go` | `testThinkingHelpers` | reasoning/thinking wire-format behavior: Clamp Thinking Level Prefers Upgrade |
| ADAPTED | `TestHasOpenAIAuthHeader` | `goai_test.go` | `testAuthHeaderAndMergeHelpers` | auth/header/env edge case: Has Open AIAuth Header |
| ADAPTED | `TestMergeProviderHeadersAppliesOverridesAndSuppressions` | `goai_test.go` | `testAuthHeaderAndMergeHelpers` | auth/header/env edge case: Merge Provider Headers Applies Overrides And Suppressions |
| ADAPTED | `TestApplyDefaultHeadersPreservesExplicitEmptyOverride` | `goai_test.go` | `testAuthHeaderAndMergeHelpers` | auth/header/env edge case: Apply Default Headers Preserves Explicit Empty Override |
| ADAPTED | `TestHasAnthropicAuthHeader` | `goai_test.go` | `testAuthHeaderAndMergeHelpers` | auth/header/env edge case: Has Anthropic Auth Header |
| ADAPTED | `TestBuildCopilotDynamicHeaders` | `goai_test.go` | `testCopilotAndSessionHeaders` | auth/header/env edge case: Build Copilot Dynamic Headers |
| PENDING | `TestAgentLoopHarness` | `harness_integration_test.go` | `—` | Agent Loop Harness |
| PENDING | `TestStreamingHarness` | `harness_integration_test.go` | `—` | streaming/event transport behavior: Streaming Harness |
| PENDING | `TestErrorHandlingHarness` | `harness_integration_test.go` | `—` | Error Handling Harness |
| PENDING | `TestContextCompactionHarness` | `harness_integration_test.go` | `—` | Context Compaction Harness |
| PENDING | `TestHooksHarness` | `harness_integration_test.go` | `—` | Hooks Harness |
| PENDING | `TestCrossProviderHandoff` | `harness_integration_test.go` | `—` | Cross Provider Handoff |
| ADAPTED | `TestCloneContext` | `harness_test.go` | `testHarnessHelpers` | Clone Context |
| ADAPTED | `TestCloneContextNil` | `harness_test.go` | `testHarnessCloneNilAndSaveLoadContext` | Clone Context Nil |
| ADAPTED | `TestSaveLoadContext` | `harness_test.go` | `testHarnessCloneNilAndSaveLoadContext` | Save Load Context |
| ADAPTED | `TestEstimateTokens` | `harness_test.go` | `testHarnessHelpers` | Estimate Tokens |
| ADAPTED | `TestFitsInContextWindow` | `harness_test.go` | `testHarnessHelpers` | Fits In Context Window |
| ADAPTED | `TestCompactContext` | `harness_test.go` | `testHarnessHelpers` | Compact Context |
| ADAPTED | `TestGetToolCalls` | `harness_test.go` | `testHarnessHelpers` | tool-call/schema conversion behavior: Get Tool Calls |
| ADAPTED | `TestNeedsToolExecution` | `harness_test.go` | `testHarnessHelpers` | tool-call/schema conversion behavior: Needs Tool Execution |
| ADAPTED | `TestAppendHelpers` | `harness_test.go` | `testHarnessHelpers` | Append Helpers |
| ADAPTED | `TestHooksOnStreamOptions` | `harness_test.go` | `testStreamAndImageOptionHooks` | streaming/event transport behavior: Hooks On Stream Options |
| ADAPTED | `TestInvokeOnPayloadNil` | `harness_test.go` | `testStreamAndImageOptionHooks` | provider request/payload parity: Invoke On Payload Nil |
| ADAPTED | `TestImageAPIProviderRegistered` | `images_test.go` | `testImageRegistryRegistersProvidersAndModels` | image generation behavior: Image APIProvider Registered |
| ADAPTED | `TestBuiltinImageModels` | `images_test.go` | `testGeneratedImageModelRegistryMetadata` | model registry/generated metadata parity: Builtin Image Models |
| ADAPTED | `TestGenerateImagesErrorPaths` | `images_test.go` | `testGenerateImagesErrorPathsAndHookError` | image generation behavior: Generate Images Error Paths |
| ADAPTED | `TestGenerateImagesOpenRouterHooksAndResponse` | `images_test.go` | `testOpenRouterImageResponseParser` | image generation behavior: Generate Images Open Router Hooks And Response |
| ADAPTED | `TestGenerateImagesOpenRouterUsesProviderEnvAPIKey` | `images_test.go` | `testOpenRouterImageAPIKeyResolution` | auth/header/env edge case: Generate Images Open Router Uses Provider Env APIKey |
| ADAPTED | `TestGenerateImagesOpenRouterPayloadParityAndAbort` | `images_test.go` | `testOpenRouterImagePayloadBuilder` | provider request/payload parity: Generate Images Open Router Payload Parity And Abort |
| PARTIAL | `TestGenerateImagesOpenRouterRetriesAndHookError` | `images_test.go` | `testGenerateImagesErrorPathsAndHookError`, `testRetryPolicy` | image generation behavior: hook error covered; HTTP retry integration is policy-covered, not fully transport-replayed |
| ADAPTED | `TestNormalizeAnthropicBaseURLAddsV1` | `inference/provider/anthropic/anthropic_copilot_test.go` | `testAnthropicBaseURLNormalizationAddsV1` | provider OAuth/provider-specific behavior: Normalize Anthropic Base URLAdds V1 |
| PENDING | `TestStreamAnthropicUsesBearerForCopilot` | `inference/provider/anthropic/anthropic_copilot_test.go` | `—` | streaming/event transport behavior: Stream Anthropic Uses Bearer For Copilot |
| PENDING | `TestBuildRequestJSONRoundTrip` | `inference/provider/anthropic/anthropic_copilot_test.go` | `—` | provider request/payload parity: Build Request JSONRound Trip |
| PENDING | `TestStreamAnthropicParsesOneHourCacheWriteUsage` | `inference/provider/anthropic/anthropic_retry_test.go` | `—` | streaming/event transport behavior: Stream Anthropic Parses One Hour Cache Write Usage |
| PENDING | `TestStreamAnthropicUsesExplicitAuthHeaderWithoutAPIKey` | `inference/provider/anthropic/anthropic_retry_test.go` | `—` | streaming/event transport behavior: Stream Anthropic Uses Explicit Auth Header Without APIKey |
| PENDING | `TestStreamAnthropicRetries429AndSucceeds` | `inference/provider/anthropic/anthropic_retry_test.go` | `—` | streaming/event transport behavior: Stream Anthropic Retries429 And Succeeds |
| PENDING | `TestProcessConverseStreamSurfacesStreamErr` | `inference/provider/bedrock/bedrock_stream_test.go` | `—` | streaming/event transport behavior: Process Converse Stream Surfaces Stream Err |
| PENDING | `TestMapStopReason` | `inference/provider/bedrock/bedrock_stream_test.go` | `—` | Map Stop Reason |
| PENDING | `TestExtractRegionFromURL` | `inference/provider/bedrock/bedrock_test.go` | `—` | Extract Region From URL |
| PARTIAL | `TestShouldUseExplicitBedrockEndpoint` | `inference/provider/bedrock/bedrock_test.go` | `pluggable transport surface / semantic tests` | Should Use Explicit Bedrock Endpoint |
| PARTIAL | `TestBedrockCustomHeaderReservation` | `inference/provider/bedrock/bedrock_test.go` | `pluggable transport surface / semantic tests` | auth/header/env edge case: Bedrock Custom Header Reservation |
| PARTIAL | `TestBedrockOptionPrecedenceAndRequestMetadata` | `inference/provider/bedrock/bedrock_test.go` | `pluggable transport surface / semantic tests` | provider request/payload parity: Bedrock Option Precedence And Request Metadata |
| PENDING | `TestBuildConverseInputIncludesSystemToolsAndThinking` | `inference/provider/bedrock/bedrock_test.go` | `—` | tool-call/schema conversion behavior: Build Converse Input Includes System Tools And Thinking |
| PENDING | `TestBuildConverseInputUsesNativeXhighForClaudeOpus47` | `inference/provider/bedrock/bedrock_test.go` | `—` | Build Converse Input Uses Native Xhigh For Claude Opus47 |
| PENDING | `TestConvertMessagesCoalescesConsecutiveToolResults` | `inference/provider/bedrock/bedrock_test.go` | `—` | tool-call/schema conversion behavior: Convert Messages Coalesces Consecutive Tool Results |
| PENDING | `TestCreateImageBlockDecodesBase64` | `inference/provider/bedrock/bedrock_test.go` | `—` | image generation behavior: Create Image Block Decodes Base64 |
| PARTIAL | `TestBedrockPayloadHookCanReplaceInput` | `inference/provider/bedrock/bedrock_test.go` | `pluggable transport surface / semantic tests` | provider request/payload parity: Bedrock Payload Hook Can Replace Input |
| ADAPTED | `TestFauxContentAndAssistantHelpers` | `inference/provider/faux/faux_test.go` | `testFauxProviderHelpers` | Faux Content And Assistant Helpers |
| ADAPTED | `TestFauxTextStream` | `inference/provider/faux/faux_test.go` | `testFauxProviderHelpers` | streaming/event transport behavior: Faux Text Stream |
| ADAPTED | `TestFauxComplete` | `inference/provider/faux/faux_test.go` | `testFauxProviderHelpers` | Faux Complete |
| ADAPTED | `TestFauxToolCall` | `inference/provider/faux/faux_test.go` | `testFauxThinkingToolFactoryMultipleAndError` | tool-call/schema conversion behavior: Faux Tool Call |
| ADAPTED | `TestFauxThinking` | `inference/provider/faux/faux_test.go` | `testFauxThinkingToolFactoryMultipleAndError` | reasoning/thinking wire-format behavior: Faux Thinking |
| ADAPTED | `TestFauxResponseFactory` | `inference/provider/faux/faux_test.go` | `testFauxThinkingToolFactoryMultipleAndError` | Faux Response Factory |
| ADAPTED | `TestFauxMultipleResponses` | `inference/provider/faux/faux_test.go` | `testFauxThinkingToolFactoryMultipleAndError` | Faux Multiple Responses |
| ADAPTED | `TestFauxError` | `inference/provider/faux/faux_test.go` | `testFauxThinkingToolFactoryMultipleAndError` | Faux Error |
| PARTIAL | `TestFauxAbort` | `inference/provider/faux/faux_test.go` | `AsyncStream cancellation not directly mirrored yet` | retry/cancellation robustness: Faux Abort |
| ADAPTED | `TestFauxCallCount` | `inference/provider/faux/faux_test.go` | `testFauxThinkingToolFactoryMultipleAndError` | Faux Call Count |
| PENDING | `TestStreamGeminiCLIRetries429AndSucceeds` | `inference/provider/geminicli/geminicli_retry_test.go` | `—` | streaming/event transport behavior: Stream Gemini CLIRetries429 And Succeeds |
| ADAPTED | `TestBuildStreamURLEscapesPathAndQuery` | `inference/provider/google/google_audit_test.go` | `testGoogleStreamURLEscapingAndMultilineSSE` | streaming/event transport behavior: Build Stream URLEscapes Path And Query |
| ADAPTED | `TestBuildVertexStreamURLUsesProjectAndLocationOptions` | `inference/provider/google/google_audit_test.go` | `testGoogleStreamURLEscapingAndMultilineSSE`, `testGoogleVertexAPIKeyResolutionURLSemantics` | streaming/event transport behavior: Build Vertex Stream URLUses Project And Location Options |
| ADAPTED | `TestProcessStreamHandlesMultilineSSE` | `inference/provider/google/google_audit_test.go` | `testGoogleStreamURLEscapingAndMultilineSSE`, `testSSEParserMultilineStickyIDAndRetry` | streaming/event transport behavior: Process Stream Handles Multiline SSE |
| PENDING | `TestStreamGoogleRetries429AndSucceeds` | `inference/provider/google/google_retry_test.go` | `—` | streaming/event transport behavior: Stream Google Retries429 And Succeeds |
| PENDING | `TestStreamMistralRetries429AndSucceeds` | `inference/provider/mistral/mistral_retry_test.go` | `—` | streaming/event transport behavior: Stream Mistral Retries429 And Succeeds |
| ADAPTED | `TestStreamOpenAIInvokesOnPayload` | `inference/provider/openai/openai_payload_test.go` | `testStreamAndImageOptionHooks` | provider request/payload parity: Stream Open AIInvokes On Payload |
| PENDING | `TestStreamOpenAIUsesExplicitAuthHeaderWithoutAPIKey` | `inference/provider/openai/openai_payload_test.go` | `—` | streaming/event transport behavior: Stream Open AIUses Explicit Auth Header Without APIKey |
| PENDING | `TestStreamOpenAICloudflareAIGatewayHeadersAndURL` | `inference/provider/openai/openai_payload_test.go` | `—` | streaming/event transport behavior: Stream Open AICloudflare AIGateway Headers And URL |
| ADAPTED | `TestBuildRequestBodyClampsPromptCacheKey` | `inference/provider/openai/openai_payload_test.go` | `testOpenAICompletionsRequestCacheAndThinkingFormats` | provider request/payload parity: Build Request Body Clamps Prompt Cache Key |
| ADAPTED | `TestBuildRequestBodyUsesCompatThinkingFormats` | `inference/provider/openai/openai_payload_test.go` | `testOpenAICompletionsRequestCacheAndThinkingFormats` | provider request/payload parity: Build Request Body Uses Compat Thinking Formats |
| ADAPTED | `TestProcessSSEStreamCapturesResponseModelAndCacheUsage` | `inference/provider/openai/openai_payload_test.go` | `testOpenAISSEProcessing`, `testOpenAIResponseModelEchoAndEmptyIgnored` | streaming/event transport behavior: Process SSEStream Captures Response Model And Cache Usage |
| ADAPTED | `TestProcessSSEStreamAttachesPendingEncryptedReasoningDetails` | `inference/provider/openai/openai_payload_test.go` | `testOpenAIReasoningDetailsStreamingAndReplay` | streaming/event transport behavior: Process SSEStream Attaches Pending Encrypted Reasoning Details |
| PENDING | `TestStreamOpenAIRetries429AndSucceeds` | `inference/provider/openai/openai_retry_test.go` | `—` | streaming/event transport behavior: Stream Open AIRetries429 And Succeeds |
| ADAPTED | `TestBuildCodexRequestClampsPromptCacheKey` | `inference/provider/openaicodex/codex_request_test.go` | `testCodexResponsesRequestHeadersAndErrors` | provider request/payload parity: Build Codex Request Clamps Prompt Cache Key |
| ADAPTED | `TestBuildCodexRequestMatchesPiaiShape` | `inference/provider/openaicodex/codex_request_test.go` | `testCodexResponsesRequestHeadersAndErrors` | provider request/payload parity: Build Codex Request Matches Piai Shape |
| ADAPTED | `TestExtractCodexEventErrorUsesNestedPayload` | `inference/provider/openaicodex/codex_request_test.go` | `testCodexResponsesRequestHeadersAndErrors` | provider request/payload parity: Extract Codex Event Error Uses Nested Payload |
| ADAPTED | `TestBuildCodexHeadersAddsAccountAndExperimentalHeaders` | `inference/provider/openaicodex/codex_request_test.go` | `testCodexResponsesRequestHeadersAndErrors` | auth/header/env edge case: Build Codex Headers Adds Account And Experimental Headers |
| PENDING | `TestStreamViaSSERetries429AndSucceeds` | `inference/provider/openaicodex/codex_retry_test.go` | `—` | streaming/event transport behavior: Stream Via SSERetries429 And Succeeds |
| PARTIAL | `TestStreamViaWebSocketAutoUsesCachedDeltaAndDebugStats` | `inference/provider/openaicodex/codex_ws_test.go` | `pluggable transport surface / semantic tests` | streaming/event transport behavior: Stream Via Web Socket Auto Uses Cached Delta And Debug Stats |
| PARTIAL | `TestRemoveCodexWebSocketSessionClosesConnection` | `inference/provider/openaicodex/codex_ws_test.go` | `pluggable transport surface / semantic tests` | streaming/event transport behavior: Remove Codex Web Socket Session Closes Connection |
| PARTIAL | `TestStreamCodexWebSocketSetupFailureFallsBackToSSEWithDiagnostic` | `inference/provider/openaicodex/codex_ws_test.go` | `pluggable transport surface / semantic tests` | streaming/event transport behavior: Stream Codex Web Socket Setup Failure Falls Back To SSEWith Diagnostic |
| PARTIAL | `TestStreamCodexRetriesWebSocketConnectionLimitOnceBeforeSSE` | `inference/provider/openaicodex/codex_ws_test.go` | `pluggable transport surface / semantic tests` | streaming/event transport behavior: rs-ai-origin Codex connection-limit retry: real WebSocket connection receives nested `websocket_connection_limit_reached`, retries one fresh WS handshake, then falls back to SSE |
| PARTIAL | `TestStreamViaWebSocketProtocolFlow` | `inference/provider/openaicodex/codex_ws_test.go` | `pluggable transport surface / semantic tests` | streaming/event transport behavior: Stream Via Web Socket Protocol Flow |
| ADAPTED | `TestResolveAzureResponsesConfigUsesEnvAndDeploymentMap` | `inference/provider/openairesponses/responses_azure_test.go` | `testAzureResponsesHelpers`, `testAzureOpenAIResponsesConfigAndPayloadDefaults` | Resolve Azure Responses Config Uses Env And Deployment Map |
| ADAPTED | `TestResolveAzureResponsesConfigNormalizesAzureHost` | `inference/provider/openairesponses/responses_azure_test.go` | `testAzureOpenAIResponsesBaseURLNormalization` | Resolve Azure Responses Config Normalizes Azure Host |
| PENDING | `TestResponsesUsesExplicitAuthHeaderWithoutAPIKey` | `inference/provider/openairesponses/responses_azure_test.go` | `—` | auth/header/env edge case: Responses Uses Explicit Auth Header Without APIKey |
| PENDING | `TestAzureResponsesRequestAppliesCleanupAndSessionHeaders` | `inference/provider/openairesponses/responses_azure_test.go` | `—` | provider request/payload parity: Azure Responses Request Applies Cleanup And Session Headers |
| ADAPTED | `TestAzureResponsesNormalizesCommentaryIntoThinkingEvents` | `inference/provider/openairesponses/responses_azure_test.go` | `testAzureReasoningEventNormalization` | reasoning/thinking wire-format behavior: Azure Responses Normalizes Commentary Into Thinking Events |
| ADAPTED | `TestBuildRequestOmitsDefaultReasoningForGitHubCopilot` | `inference/provider/openairesponses/responses_request_test.go` | `testOpenAIResponsesProviderDefaultReasoningMatrix` | provider request/payload parity: Build Request Omits Default Reasoning For Git Hub Copilot |
| ADAPTED | `TestBuildRequestClampsPromptCacheKey` | `inference/provider/openairesponses/responses_request_test.go` | `testAzureOpenAIResponsesConfigAndPayloadDefaults` | provider request/payload parity: Build Request Clamps Prompt Cache Key |
| ADAPTED | `TestBuildRequestDefaultsReasoningForNonCopilotReasoningModels` | `inference/provider/openairesponses/responses_request_test.go` | `testOpenAIResponsesProviderDefaultReasoningMatrix` | provider request/payload parity: Build Request Defaults Reasoning For Non Copilot Reasoning Models |
| PENDING | `TestBuildAssistantItemsAllowsEmptyThinkingSignature` | `inference/provider/openairesponses/responses_request_test.go` | `—` | reasoning/thinking wire-format behavior: Build Assistant Items Allows Empty Thinking Signature |
| PENDING | `TestStreamResponsesRetries429AndSucceeds` | `inference/provider/openairesponses/responses_retry_test.go` | `—` | streaming/event transport behavior: Stream Responses Retries429 And Succeeds |
| ADAPTED | `TestParseCompleteJSON` | `internal/jsonparse/partial_test.go` | `testPartialJSONParser` | Parse Complete JSON |
| ADAPTED | `TestParsePartialJSON` | `internal/jsonparse/partial_test.go` | `testPartialJSONParser` | Parse Partial JSON |
| ADAPTED | `TestParseEmpty` | `internal/jsonparse/partial_test.go` | `testPartialJSONParser` | Parse Empty |
| ADAPTED | `TestComputeBackoff` | `internal/retry/backoff_test.go` | `testRetryPolicy` | Compute Backoff |
| ADAPTED | `TestComputeBackoffConstant` | `internal/retry/backoff_test.go` | `testRetryPolicy` | Compute Backoff Constant |
| ADAPTED | `TestIsRetryableStatus` | `internal/retry/backoff_test.go` | `testRetryPolicy` | retry/cancellation robustness: Is Retryable Status |
| ADAPTED | `TestParseRetryAfter` | `internal/retry/backoff_test.go` | `testRetryPolicy` | retry/cancellation robustness: Parse Retry After |
| ADAPTED | `TestParseDurationString` | `internal/retry/backoff_test.go` | `testRetryPolicy` | Parse Duration String |
| ADAPTED | `TestDiscardLoggerDefault` | `logger_test.go` | `testLoggerRegistrySetAndReset` | Discard Logger Default |
| ADAPTED | `TestSimpleLogger` | `logger_test.go` | `testLoggerRegistrySetAndReset` | Simple Logger |
| ADAPTED | `TestLogLevelFiltering` | `logger_test.go` | `testLoggerRegistrySetAndReset` | Log Level Filtering |
| ADAPTED | `TestSetLogger` | `logger_test.go` | `testLoggerRegistrySetAndReset` | Set Logger |
| ADAPTED | `TestSetLoggerNil` | `logger_test.go` | `testLoggerRegistrySetAndReset` | Set Logger Nil |
| ADAPTED | `TestTransformMessagesAddsSyntheticResultForTrailingOrphan` | `logic_audit_test.go` | `testTransformSkipsErroredAssistantMessagesAndInsertsSyntheticToolResults` | Transform Messages Adds Synthetic Result For Trailing Orphan |
| ADAPTED | `TestTransformMessagesNilModelReturnsInput` | `logic_audit_test.go` | `testTransformPreservesImagesForVisionModelsAndDowngradesTextModels` | model registry/generated metadata parity: Transform Messages Nil Model Returns Input |
| PENDING | `TestApplyToolCallLimitUsesBudgetTrim` | `logic_audit_test.go` | `—` | tool-call/schema conversion behavior: Apply Tool Call Limit Uses Budget Trim |
| ADAPTED | `TestRegisterBuiltinModels` | `models_test.go` | `testGeneratedModelRegistryMetadata` | model registry/generated metadata parity: Register Builtin Models |
| ADAPTED | `TestGeneratedModelMetadataParity` | `models_test.go` | `testGeneratedModelRegistryMetadata` | model registry/generated metadata parity: Generated Model Metadata Parity |
| ADAPTED | `TestListModelsFilter` | `models_test.go` | `testGeneratedModelRegistryMetadata` | model registry/generated metadata parity: List Models Filter |
| ADAPTED | `TestPKCE` | `oauth/oauth_test.go` | `testOAuthPKCEAndCopilotHelpers` | PKCE |
| ADAPTED | `TestNormalizeDomain` | `oauth/oauth_test.go` | `testOAuthPKCEAndCopilotHelpers` | Normalize Domain |
| ADAPTED | `TestGetGitHubCopilotBaseURL` | `oauth/oauth_test.go` | `testOAuthPKCEAndCopilotHelpers` | provider OAuth/provider-specific behavior: Get Git Hub Copilot Base URL |
| ADAPTED | `TestGitHubCopilotModelFiltering` | `oauth/oauth_test.go` | `testOAuthPKCEAndCopilotHelpers` | model registry/generated metadata parity: Git Hub Copilot Model Filtering |
| ADAPTED | `TestIsSelectableCopilotModel` | `oauth/oauth_test.go` | `testGitHubCopilotOAuthModelFilteringAndVerificationURI`, `testOAuthPKCEAndCopilotHelpers` | streaming/event transport behavior: Is Selectable Copilot Model |
| PENDING | `TestGetAPIKeyRefreshesExpiredCredential` | `oauth/oauth_test.go` | `—` | auth/header/env edge case: Get APIKey Refreshes Expired Credential |
| PENDING | `TestGetAPIKeyKeepsValidCredential` | `oauth/oauth_test.go` | `—` | auth/header/env edge case: Get APIKey Keeps Valid Credential |
| ADAPTED | `TestOAuthRegistryRoundTrip` | `oauth/oauth_test.go` | `testOAuthRegistryRoundTrip` | auth/header/env edge case: OAuth Registry Round Trip |
| PENDING | `TestParseSSESurfacesReaderErrors` | `transports/sse/sse_error_test.go` | `—` | streaming/event transport behavior: Parse SSESurfaces Reader Errors |
| ADAPTED | `TestParseSSE` | `transports/sse/sse_test.go` | `testSSEParser` | streaming/event transport behavior: Parse SSE |
| ADAPTED | `TestParseMultilineData` | `transports/sse/sse_test.go` | `testSSEParserMultilineStickyIDAndRetry` | Parse Multiline Data |
| ADAPTED | `TestParseStickyIDAndRetry` | `transports/sse/sse_test.go` | `testSSEParserMultilineStickyIDAndRetry` | retry/cancellation robustness: Parse Sticky IDAnd Retry |
