# swift-ai parity status

Tracks upstream `@earendil-works/pi-ai` **v0.80.9** via direct upstream inspection (release tag `2d16f92973230a7e095aa984f150ba8702784f50`). `STATUS.json` contains the same high-level status in machine-readable form.

## Implemented

- SwiftPM package consumable as library product `SwiftAI`.
- Core text type system: APIs, providers, messages, content blocks, tools, usage, diagnostics, model metadata, stream options.
- Core image type system: image APIs/providers, image context/input/output, image model metadata, assistant image result shape, image options.
- Event protocol as a Swift `AIEvent` enum.
- Actor-backed registries for text API providers, text models, image API providers, and image models.
- Full embedded text model registry generated from upstream `pi-ai` v0.80.9: **1065 models / 35 providers**.
- Full embedded image model registry generated from upstream `pi-ai` v0.80.9: **35 models / 1 provider**.
- Environment key lookup with per-request `StreamOptions.env` / `ImagesOptions.env` overlay.
- OpenAI-compatible compat detection, including v0.80.2 `chat-template` thinking kwargs metadata.
- Basic context overflow detection and tool required-argument validation helpers.
- SSE parser.
- OpenAI-compatible Chat Completions provider with common `SwiftAI.stream`/`SwiftAI.complete` entry points, including strict-mode tool schema emission when supported, developer-role system prompts for reasoning models when compatible, multimodal user/tool-result image replay, assistant tool-call replay, `reasoning_content` replay when required, synthetic assistant-after-tool-result separators, tool-result name replay when required, v0.80.2 custom auth header/empty-tools/prompt-cache-key behavior, v0.80.9 Kimi deferred-tools serialization, and error finish-reason events.
- OpenAI-compatible SSE streaming parser for text, thinking/reasoning, tool calls, finish reasons, response metadata, and usage.
- OpenAI Responses/Azure Responses/OpenAI Codex provider: request construction, assistant reasoning/text/tool-call replay items, Azure config resolution (including deployment maps and base URL normalization), Azure tool-call history trimming, Azure reasoning event normalization, Codex URL/account headers, pluggable Codex transport, default reasoning/include behavior, prompt-cache fields, SSE parsing for text/reasoning/tool events, failed-response and generic API error events, completion usage including cached input tokens, response status mapping, tool-use completion upgrade, and stop reasons.
- Faux provider/test double: model registration, queued/dynamic responses, text/thinking/tool/error message helpers, simulated stream events, and call-count state.
- Cost calculation utilities matching upstream per-million-token pricing, including cache read/write and Anthropic-style 1h cache writes; wired into streamed text and image provider usage where metadata is available.
- Message transformation helpers: cross-provider thinking replay rules, unsupported-image downgrade, assistant error trimming, and synthetic tool results for orphaned tool calls; wired into provider request builders.
- Prompt cache helpers and session-resource cleanup registry, with OpenAI prompt-cache key clamping, env-driven cache retention, and provider-specific long-retention suppression wired into Chat Completions and Responses requests.
- Diagnostics and logging helpers: thrown-value formatting, serializable assistant diagnostics, diagnostic append helper, pluggable discard/stderr logger, and global logger actor.
- Context overflow and JSON Schema tool argument validation helpers, including required fields, primitive type checks, and string enum checks.
- Simple-options/thinking helpers: supported level discovery, xhigh clamping, nearest-level clamping, provider-specific thinking value mapping, default thinking budgets, and max-token/thinking-budget adjustment.
- OpenRouter image generation provider request/response path, including multimodal payload construction, string/object `image_url` response forms, `data:` URL image extraction, text output, usage, and cost calculation.
- Shared HTTP retry/backoff helper wired into OpenAI-compatible text and OpenRouter image providers, including upstream no-retry defaults, opt-in default retry config via `maxRetryDelayMs`, retryable status set, exponential backoff/jitter, and `Retry-After` cap handling.
- OAuth core framework: credentials, auth/prompt callbacks, provider registry, PKCE utilities, and device-flow response shape.
- GitHub Copilot OAuth provider: device-code login, token refresh, Copilot model policy enablement, available-model fetching/filtering, and base URL extraction.
- OpenAI Codex OAuth provider: Auth0 device-code login, token polling, refresh-token exchange, and API-key extraction.
- Anthropic OAuth provider: PKCE authorization URL construction, authorization-code token exchange, refresh-token exchange, and API-key extraction. SwiftPM portability uses host prompt for the callback code instead of embedding a local HTTP server.
- Google Gemini CLI and Antigravity OAuth providers: PKCE authorization URL construction, project ID capture, authorization-code token exchange, refresh-token exchange, and JSON API-key payload generation.
- Anthropic Messages provider: request construction, thinking budgets/adaptive thinking, beta headers, prompt cache-control annotations (including v0.80.2 tool cache-control compatibility and session-affinity metadata), tool_use/tool_result request blocks, SSE parsing for text/thinking/tool events, usage, stop reasons, and truncated-stream errors.
- Mistral Conversations provider: request construction, reasoning/prompt mode handling, tools, SSE parsing for text/reasoning/tool events, usage, stop reasons, and error finish events.
- Google Gemini/Vertex REST provider: request construction, Gemini thinking config, tools/images/function calls, functionResponse tool results including multimodal image parts when supported, same-model thought signature replay, stream URL construction, SSE parsing for text/thinking/tool events, usage, and stop reasons.
- Google Gemini CLI / Cloud Code Assist provider: OAuth JSON credential parsing, CCA wrapper request construction, functionResponse tool results, session ID support, headers, request/response hooks, and wrapped Gemini SSE unwrapping/parsing.
- Amazon Bedrock provider surface: registration, pluggable `BedrockTransport`, region/endpoint/ARN resolution helpers, and serializable ConverseStream request construction for messages, system prompts, tools, inference config, request metadata, images, tool calls, and tool results.

## v0.80.9 release audit

See `docs/upstream-v0.80.9-audit.md` for the exact material-delta disposition matrix from prior pinned `2be9efa` to release tag `2d16f92973230a7e095aa984f150ba8702784f50`.

## Pluggable/non-bundled runtime pieces

The core SwiftPM package provides functional parity for the upstream text/image registry surface and bundled HTTP/SSE providers while intentionally keeping heavyweight transport stacks out of the main target:

- **Amazon Bedrock live transport** is exposed through `BedrockTransport`. The core package provides provider registration, region/endpoint helpers, and ConverseStream request construction; a consumer-supplied transport provides AWS SigV4 signing and AWS event-stream IO.
- **OpenAI Codex WebSocket/session-cache transport** is exposed through `CodexTransport`. The core package bundles the Codex HTTP/SSE path and Codex request/account handling; a consumer-supplied transport can provide the WebSocket session-cache path.
- **Vendor SDK-native retry behavior** is represented by the shared retry policy for bundled HTTP providers. SDK-native retry stacks are delegated to any pluggable transport/vendor SDK module that supplies them.

Everything above is documented in `docs/TRANSPORTS.md` and reflected in `STATUS.json`.

## Validation constraints

The current container does not include a Swift toolchain (`swift` is not installed), so this repo has been statically checked here and should be compiled/tested with Swift 5.9+ on a Swift host using:

```bash
make test
```

A toolchain-light static validation gate is available and has been used in this container:

```bash
make static-check
```
