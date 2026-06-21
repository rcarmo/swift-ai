# swift-ai parity status

Tracks upstream `@earendil-works/pi-ai` / audited `go-ai` **v0.79.9**.

## Implemented

- SwiftPM package consumable as library product `SwiftAI`.
- Core text type system: APIs, providers, messages, content blocks, tools, usage, diagnostics, model metadata, stream options.
- Core image type system: image APIs/providers, image context/input/output, image model metadata, assistant image result shape, image options.
- Event protocol as a Swift `AIEvent` enum.
- Actor-backed registries for text API providers, text models, image API providers, and image models.
- Full embedded text model registry generated from `go-ai` v0.79.9: **979 models / 35 providers**.
- Full embedded image model registry generated from `go-ai` v0.79.9: **34 models / 1 provider**.
- Environment key lookup with per-request `StreamOptions.env` / `ImagesOptions.env` overlay.
- OpenAI-compatible compat detection, including v0.79.9 `chat-template` thinking kwargs metadata.
- Basic context overflow detection and tool required-argument validation helpers.
- SSE parser.
- OpenAI-compatible Chat Completions provider with common `SwiftAI.stream`/`SwiftAI.complete` entry points, including strict-mode tool schema emission when supported, developer-role system prompts for reasoning models when compatible, multimodal user/tool-result image replay, assistant tool-call replay, `reasoning_content` replay when required, synthetic assistant-after-tool-result separators, tool-result name replay when required, and error finish-reason events.
- OpenAI-compatible SSE streaming parser for text, thinking/reasoning, tool calls, finish reasons, response metadata, and usage.
- OpenAI Responses/Azure Responses/OpenAI Codex provider: request construction, assistant reasoning/text/tool-call replay items, Azure config resolution (including deployment maps and base URL normalization), Azure tool-call history trimming, Azure reasoning event normalization, Codex URL/account headers, pluggable Codex transport, default reasoning/include behavior, prompt-cache fields, SSE parsing for text/reasoning/tool events, failed-response error events, completion usage, response status mapping, tool-use completion upgrade, and stop reasons.
- Faux provider/test double: model registration, queued/dynamic responses, text/thinking/tool/error message helpers, simulated stream events, and call-count state.
- Cost calculation utilities matching upstream per-million-token pricing, including cache read/write and Anthropic-style 1h cache writes; wired into streamed text and image provider usage where metadata is available.
- Message transformation helpers: cross-provider thinking replay rules, unsupported-image downgrade, assistant error trimming, and synthetic tool results for orphaned tool calls; wired into provider request builders.
- Prompt cache helpers and session-resource cleanup registry, with OpenAI prompt-cache key clamping and env-driven cache retention wired into Chat Completions and Responses requests.
- Diagnostics and logging helpers: thrown-value formatting, serializable assistant diagnostics, diagnostic append helper, pluggable discard/stderr logger, and global logger actor.
- Context overflow and JSON Schema tool argument validation helpers, including required fields, primitive type checks, and string enum checks.
- Simple-options/thinking helpers: supported level discovery, xhigh clamping, nearest-level clamping, provider-specific thinking value mapping, default thinking budgets, and max-token/thinking-budget adjustment.
- OpenRouter image generation provider request/response path, including multimodal payload construction and `data:` URL image extraction.
- Shared HTTP retry/backoff helper wired into OpenAI-compatible text and OpenRouter image providers, including upstream no-retry defaults, opt-in default retry config via `maxRetryDelayMs`, retryable status set, exponential backoff/jitter, and `Retry-After` cap handling.
- OAuth core framework: credentials, auth/prompt callbacks, provider registry, PKCE utilities, and device-flow response shape.
- GitHub Copilot OAuth provider: device-code login, token refresh, Copilot model policy enablement, available-model fetching/filtering, and base URL extraction.
- OpenAI Codex OAuth provider: Auth0 device-code login, token polling, refresh-token exchange, and API-key extraction.
- Anthropic OAuth provider: PKCE authorization URL construction, authorization-code token exchange, refresh-token exchange, and API-key extraction. SwiftPM portability uses host prompt for the callback code instead of embedding a local HTTP server.
- Google Gemini CLI and Antigravity OAuth providers: PKCE authorization URL construction, project ID capture, authorization-code token exchange, refresh-token exchange, and JSON API-key payload generation.
- Anthropic Messages provider: request construction, thinking budgets/adaptive thinking, beta headers, prompt cache-control annotations, tool_use/tool_result request blocks, SSE parsing for text/thinking/tool events, usage, and stop reasons.
- Mistral Conversations provider: request construction, reasoning/prompt mode handling, tools, SSE parsing for text/reasoning/tool events, usage, and stop reasons.
- Google Gemini/Vertex REST provider: request construction, Gemini thinking config, tools/images/function calls, functionResponse tool results including multimodal image parts when supported, same-model thought signature replay, stream URL construction, SSE parsing for text/thinking/tool events, usage, and stop reasons.
- Google Gemini CLI / Cloud Code Assist provider: OAuth JSON credential parsing, CCA wrapper request construction, functionResponse tool results, session ID support, headers, request/response hooks, and wrapped Gemini SSE unwrapping/parsing.
- Amazon Bedrock provider surface: registration, pluggable `BedrockTransport`, region/endpoint/ARN resolution helpers, and serializable ConverseStream request construction for messages, system prompts, tools, inference config, request metadata, images, tool calls, and tool results.

## Known gaps vs upstream runtime parity

The package is structurally consumable via SwiftPM, but provider-runtime parity is still incomplete:

- OpenAI-compatible provider lacks only a very small number of advanced provider-specific replay edge cases from `go-ai`.
- OpenAI Responses/Codex provider has pluggable WebSocket transport support but does not bundle a WebSocket/session-cache transport implementation; a few advanced prompt-cache edge cases remain.
- Anthropic Messages provider lacks only a few advanced replay edge cases.
- Google providers lack only a very small number of advanced upstream replay edge cases.
- OAuth flow surface now covers upstream providers: GitHub Copilot, OpenAI Codex, Anthropic, Google Gemini CLI, and Google Antigravity.
- Provider environment/API-key resolution: upstream provider env var mapping, scoped env override, generic fallback names, explicit option API key override, cache-retention env handling, and authenticated sentinels for Vertex ADC/Bedrock credential presence.
- Request/response interception hooks on text and image options, wired into HTTP providers with serializable payload maps and response metadata.
- Incremental/partial JSON object parsing for streamed tool-call arguments, wired into text providers that accumulate tool deltas.
- Copilot/OpenAI session headers: Copilot dynamic initiator/vision headers, standard Copilot headers, OpenAI-compatible session affinity headers, Azure session headers, and Responses Copilot dynamic headers.
- Utility parity: deterministic SHA-256 short hashes, surrogate sanitization, Cloudflare provider detection, and Cloudflare base URL placeholder resolution; provider request builders sanitize serialized text inputs and Mistral tool-call ID fallback uses deterministic hashes.
- Harness/context helpers: deep clone, JSON save/load, rough token estimation, context-window fit checks, tail compaction, turn appenders, text/tool extraction, and tool-execution detection.
- Amazon Bedrock live transport is pluggable but not bundled; full out-of-the-box runtime parity requires AWS SigV4/event-stream support or an AWS SDK transport module.
- Advanced vendor SDK retry behavior is not fully implemented where a vendor SDK is not bundled.

## Validation constraints

The current container does not include a Swift toolchain (`swift` is not installed), so this repo has been statically checked here and should be compiled/tested with Swift 5.9+ on a Swift host using:

```bash
swift test
```

A toolchain-light static validation gate is available and has been used in this container:

```bash
python3 scripts/static-check.py
```
