# Upstream pi-ai v0.87.1 test crosswalk

This runtime-candidate crosswalk preserves the full upstream 150-test basename corpus while identifying the 9 changed tests from v0.87.1. Publication metadata remains blocked until runtime acceptance.

| # | Upstream test | Changed in v0.87.1 | Swift coverage |
| ---: | --- | :---: | --- |
| 1 | `abort.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 2 | `anthropic-adaptive-thinking-models.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 3 | `anthropic-auth-token.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 4 | `anthropic-cache-write-1h-cost.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 5 | `anthropic-eager-tool-input-compat.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 6 | `anthropic-eager-tool-input-e2e.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 7 | `anthropic-empty-thinking-signature-compat.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 8 | `anthropic-force-adaptive-thinking.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 9 | `anthropic-long-cache-retention-e2e.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 10 | `anthropic-mid-conversation-effort.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 11 | `anthropic-oauth.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 12 | `anthropic-opus-4-8-smoke.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 13 | `anthropic-sse-parsing.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 14 | `anthropic-temperature-compat.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 15 | `anthropic-thinking-binding-e2e.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 16 | `anthropic-thinking-disable.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 17 | `anthropic-tool-name-normalization.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 18 | `assistant-message-frame.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 19 | `azure-openai-base-url.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 20 | `azure-openai-responses-reasoning-replay.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 21 | `azure-openai-tool-choice.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 22 | `baseten-models.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 23 | `bedrock-cache-write-1h-cost.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 24 | `bedrock-convert-messages.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 25 | `bedrock-credentials.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 26 | `bedrock-custom-headers.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 27 | `bedrock-endpoint-resolution.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 28 | `bedrock-error-metadata.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 29 | `bedrock-models.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 30 | `bedrock-raw-stop-reason.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 31 | `bedrock-redacted-reasoning.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 32 | `bedrock-response-headers.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 33 | `bedrock-thinking-payload.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 34 | `cache-retention.test.ts` | yes | Existing prompt-cache/cache-retention Swift request tests. |
| 35 | `cloudflare-ai-binding.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 36 | `cloudflare-stream.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 37 | `compat-env.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 38 | `constrained-sampling.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 39 | `context-estimate.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 40 | `context-overflow.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 41 | `cross-provider-handoff.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 42 | `empty.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 43 | `env-api-keys.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 44 | `error-body.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 45 | `event-stream.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 46 | `faux-provider.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 47 | `fetch-option.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 48 | `fireworks-model-generation.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 49 | `fireworks-models.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 50 | `generate-models-strict.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 51 | `github-copilot-anthropic.test.ts` | yes | Generated Copilot Anthropic catalog aliases plus provider metadata/header tests. |
| 52 | `github-copilot-oauth.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 53 | `google-raw-stop-reason.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 54 | `google-shared-convert-tools.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 55 | `google-shared-gemini3-unsigned-tool-call.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 56 | `google-shared-image-tool-result-routing.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 57 | `google-shared-retry.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 58 | `google-shared-signed-empty-blocks.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 59 | `google-thinking-disable.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 60 | `google-thinking-level-map.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 61 | `google-thinking-signature.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 62 | `google-vertex-api-key-resolution.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 63 | `image-model-data.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 64 | `image-tool-result.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 65 | `images-models.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 66 | `images.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 67 | `interleaved-thinking.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 68 | `kimi-coding-oauth.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 69 | `lax-message-content.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 70 | `lazy-module-load.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 71 | `max-thinking.test.ts` | yes | Existing thinking-budget/max-token Swift tests and generated Claude Opus 5.5 metadata. |
| 72 | `message-types.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 73 | `meta-oauth.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 74 | `mistral-http-transport.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 75 | `mistral-raw-stop-reason.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 76 | `mistral-reasoning-mode.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 77 | `mistral-tool-schema.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 78 | `model-catalog-types.test.ts` | yes | Strict v0.87.1 full-record text/image catalog comparators and generated registry tests. |
| 79 | `model-data-validation.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 80 | `models-runtime.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 81 | `node-http-proxy.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 82 | `oauth-auth.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 83 | `oauth-device-code.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 84 | `openai-codex-cache-affinity-e2e.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 85 | `openai-codex-oauth.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 86 | `openai-codex-stream.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 87 | `openai-completions-cache-control-format.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 88 | `openai-completions-empty-tools.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 89 | `openai-completions-prompt-cache.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 90 | `openai-completions-raw-stop-reason.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 91 | `openai-completions-reasoning-details.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 92 | `openai-completions-response-model.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 93 | `openai-completions-retry.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 94 | `openai-completions-thinking-as-text.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 95 | `openai-completions-thinking-token-budget.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 96 | `openai-completions-tool-choice.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 97 | `openai-completions-tool-result-images.test.ts` | yes | `testOpenAICompatibleImageOnlyUserMessageOmitsEmptyTextPart`, `testOpenAIMultimodalAndToolResultReplay`, and tool-result image/empty-output tests. |
| 98 | `openai-completions-vllm-priority.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 99 | `openai-responses-cache-affinity-e2e.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 100 | `openai-responses-compat.test.ts` | yes | Existing OpenAI Responses compatibility request/parser tests and generated Grok metadata. |
| 101 | `openai-responses-empty-tool-result.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 102 | `openai-responses-foreign-toolcall-id.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 103 | `openai-responses-message-id.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 104 | `openai-responses-namespace.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 105 | `openai-responses-partial-json-cleanup.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 106 | `openai-responses-reasoning-replay-e2e.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 107 | `openai-responses-terminal-event.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 108 | `openai-responses-tool-result-images.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 109 | `opencode-provider-headers.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 110 | `openrouter-cache-control-models.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 111 | `openrouter-cache-write-repro.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 112 | `openrouter-images.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 113 | `openrouter-oauth.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 114 | `openrouter-reasoning-options.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 115 | `overflow.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 116 | `pi-messages.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 117 | `pre-generation-error.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 118 | `provider-error-body-passthrough.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 119 | `provider-error-body-regression.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 120 | `provider-retry.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 121 | `providers.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 122 | `qwen-token-plan-models.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 123 | `radius-oauth.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 124 | `radius-provider.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 125 | `reasoning-options.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 126 | `responseid.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 127 | `retry.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 128 | `sampling-options.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 129 | `stream.test.ts` | yes | Existing deterministic stream/SSE parser and provider stream tests. |
| 130 | `supports-xhigh.test.ts` | yes | Generated model metadata plus supported-thinking-level Swift tests. |
| 131 | `system-message-replay.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 132 | `telemetry-options.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 133 | `text.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 134 | `together-models.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 135 | `tokens.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 136 | `tool-call-id-normalization.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 137 | `tool-call-without-result.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 138 | `total-tokens.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 139 | `transcript-tool-changes.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 140 | `transform-messages-copilot-openai-to-anthropic.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 141 | `unicode-surrogate.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 142 | `uuid.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 143 | `validation.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 144 | `xai-oauth.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 145 | `xai-responses.test.ts` | yes | Generated Grok 4.7 Responses metadata plus existing Responses request/reasoning tests. |
| 146 | `xhigh.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 147 | `xiaomi-models.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 148 | `xiaomi-token-plan-ams-anthropic-empty-signature-smoke.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 149 | `zai-coding-plan-models.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
| 150 | `zen.test.ts` | no | Existing Swift deterministic runtime tests, exact generated catalog validators, or live-only classification unchanged from v0.87.0. |
