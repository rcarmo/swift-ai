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
- OpenAI-compatible Chat Completions provider with common `SwiftAI.stream`/`SwiftAI.complete` entry points.
- OpenAI-compatible SSE streaming parser for text, thinking/reasoning, tool calls, finish reasons, response metadata, and usage.
- OpenAI Responses/Azure Responses/OpenAI Codex SSE provider: request construction, Azure config resolution, Codex URL/account headers, reasoning/include support, prompt-cache fields, SSE parsing for text/reasoning/tool events, failures, completion usage, and stop reasons.
- Faux provider/test double: model registration, queued/dynamic responses, text/thinking/tool/error message helpers, simulated stream events, and call-count state.
- Cost calculation utilities matching upstream per-million-token pricing, including cache read/write and Anthropic-style 1h cache writes; wired into streamed text-provider usage where metadata is available.
- Message transformation helpers: cross-provider thinking replay rules, unsupported-image downgrade, assistant error trimming, and synthetic tool results for orphaned tool calls; wired into provider request builders.
- Prompt cache helpers and session-resource cleanup registry, with OpenAI prompt-cache key clamping wired into Chat Completions and Responses requests.
- Diagnostics and logging helpers: thrown-value formatting, serializable assistant diagnostics, diagnostic append helper, pluggable discard/stderr logger, and global logger actor.
- Context overflow and JSON Schema tool argument validation helpers, including required fields, primitive type checks, and string enum checks.
- Simple-options/thinking helpers: supported level discovery, xhigh clamping, nearest-level clamping, provider-specific thinking value mapping, default thinking budgets, and max-token/thinking-budget adjustment.
- OpenRouter image generation provider request/response path, including multimodal payload construction and `data:` URL image extraction.
- Shared HTTP retry/backoff helper wired into OpenAI-compatible text and OpenRouter image providers, including 429/5xx retry and `Retry-After` handling.
- OAuth core framework: credentials, auth/prompt callbacks, provider registry, PKCE utilities, and device-flow response shape.
- GitHub Copilot OAuth provider: device-code login, token refresh, Copilot model policy enablement, available-model fetching/filtering, and base URL extraction.
- OpenAI Codex OAuth provider: Auth0 device-code login, token polling, refresh-token exchange, and API-key extraction.
- Anthropic OAuth provider: PKCE authorization URL construction, authorization-code token exchange, refresh-token exchange, and API-key extraction. SwiftPM portability uses host prompt for the callback code instead of embedding a local HTTP server.
- Google Gemini CLI and Antigravity OAuth providers: PKCE authorization URL construction, project ID capture, authorization-code token exchange, refresh-token exchange, and JSON API-key payload generation.
- Anthropic Messages provider: request construction, thinking budgets/adaptive thinking, beta headers, SSE parsing for text/thinking/tool events, usage, and stop reasons.
- Mistral Conversations provider: request construction, reasoning/prompt mode handling, tools, SSE parsing for text/reasoning/tool events, usage, and stop reasons.
- Google Gemini/Vertex REST provider: request construction, Gemini thinking config, tools/images/function calls, stream URL construction, SSE parsing for text/thinking/tool events, usage, and stop reasons.

## Known gaps vs upstream runtime parity

The package is structurally consumable via SwiftPM, but provider-runtime parity is still incomplete:

- OpenAI-compatible provider lacks some provider-specific header/retry/prompt-cache edge cases from `go-ai`.
- OpenAI Responses/Codex provider lacks WebSocket transport and some upstream replay/signature/prompt-cache edge cases.
- Anthropic Messages provider lacks full prompt-cache replay/tool-result edge cases.
- Google Gemini CLI runtime is not implemented.
- Google provider lacks some upstream signature/tool-result edge cases.
- Bedrock Converse runtime is not implemented.
- OpenAI Codex runtime is not implemented.
- OAuth flow surface now covers upstream providers: GitHub Copilot, OpenAI Codex, Anthropic, Google Gemini CLI, and Google Antigravity.
- Provider environment/API-key resolution: upstream provider env var mapping, scoped env override, generic fallback names, explicit option API key override, cache-retention env handling, and authenticated sentinels for Vertex ADC/Bedrock credential presence.
- Request/response interception hooks on text and image options, wired into HTTP providers with serializable payload maps and response metadata.
- Incremental/partial JSON object parsing for streamed tool-call arguments, wired into text providers that accumulate tool deltas.
- Provider-specific retry defaults and advanced SDK retry behavior are not fully implemented.
- Full upstream transform/harness/session-resource helpers are not implemented.

## Validation constraints

The current container does not include a Swift toolchain (`swift` is not installed), so this repo has been statically checked here and should be compiled/tested with Swift 5.9+ on a Swift host using:

```bash
swift test
```
