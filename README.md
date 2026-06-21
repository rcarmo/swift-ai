# swift-ai

SwiftPM library port of [`@earendil-works/pi-ai`](https://www.npmjs.com/package/@earendil-works/pi-ai), using [`go-ai`](https://github.com/rcarmo/go-ai) as the audited reference implementation.

This package is a SwiftPM library port prepared for consumption by Swift applications and services. It tracks upstream `@earendil-works/pi-ai` **0.79.9**. See `STATUS.json` for machine-readable parity/transport status, or `SwiftAIStatus` at runtime.

## What is implemented

- Core `Codable` type system: models, providers, messages, tools, usage, diagnostics, stream options.
- Stream event enum matching the `pi-ai`/`go-ai` event protocol.
- Actor-backed provider and model registry.
- Built-in bootstrap entry point: `await SwiftAI.bootstrap()`.
- Environment API key lookup with per-request `StreamOptions.env` overlay.
- OpenAI-compatible compat detection, including `chat-template` thinking kwargs.
- Context overflow and basic tool argument validation helpers.
- SSE parser.
- OpenAI Chat Completions provider exposed through the common async stream/complete API, with SSE event parsing for text, thinking, tool calls, usage, finish reasons, and strict-mode tool schemas.
- OpenAI Responses, Azure OpenAI Responses, and OpenAI Codex provider with parsing, reasoning, prompt cache fields, Azure configuration, Codex account headers, and pluggable Codex transport.
- Shared HTTP retry/backoff helper with upstream no-retry defaults, opt-in default retry config, 429/5xx handling, jitter, and `Retry-After` caps.
- OAuth framework plus GitHub Copilot, OpenAI Codex, Anthropic, Gemini CLI, and Antigravity OAuth support.
- Provider environment/API-key resolution matching upstream env names and scoped overrides.
- Request/response interception hooks for text and image HTTP providers.
- Partial JSON parser for streamed tool-call arguments.
- Copilot and OpenAI/Azure session-affinity header helpers wired into providers.
- Deterministic short hashes, Unicode surrogate sanitization, and Cloudflare base URL resolution helpers.
- Anthropic Messages provider with SSE parsing for text, thinking, tool calls, usage, and stop reasons.
- Mistral Conversations provider with reasoning/prompt mode and SSE event parsing.
- Google Gemini/Vertex REST provider with thinking config, multimodal/tool request support, and SSE event parsing.
- Google Gemini CLI / Cloud Code Assist provider with OAuth JSON credentials and wrapped Gemini SSE parsing.
- Faux provider/test double for credential-free SwiftPM tests.
- Token cost calculation utilities wired into text and image provider usage metadata.
- Message transformation helpers for cross-provider replay, image downgrade, and synthetic tool results.
- Prompt-cache helpers, session-resource cleanup registry, and harness/context utility helpers.
- Diagnostics and pluggable logging helpers.
- Context overflow detection and JSON Schema tool argument validation helpers.
- Simple-options/thinking level and token-budget helpers.
- Full embedded text model catalog generated from audited `go-ai`/upstream `pi-ai` v0.79.9: 979 models / 35 providers.
- Full embedded image model catalog: 34 OpenRouter image models.

## Usage

See `docs/USAGE.md` for SwiftPM dependency snippets, streaming examples, OAuth setup, and pluggable transport notes.

```swift
import SwiftAI

await SwiftAI.bootstrap()
let model = await AIRegistry.shared.model(provider: .openAI, id: "gpt-4.1-mini")!
let message = try await SwiftAI.complete(
    model: model,
    context: AIContext(messages: [.user("Say hello")]),
    options: StreamOptions()
)
print(message.content.first?.text ?? "")
```

Set `OPENAI_API_KEY` in the environment, or pass a scoped override:

```swift
var options = StreamOptions()
options.env = ["OPENAI_API_KEY": "..."]
```

## Current limitations

The core SwiftPM target intentionally avoids bundling heavyweight vendor SDK/WebSocket transports. Runtime surfaces are provided, and heavyweight transports are pluggable where needed.

- Bedrock has provider registration, ConverseStream request-building helpers, and a pluggable `BedrockTransport`; live AWS SigV4/event-stream transport is not bundled in this lightweight target.
- Codex SSE is bundled; Codex WebSocket/session-cache transport is available through the pluggable `CodexTransport` surface.
- See `docs/TRANSPORTS.md` for pluggable transport examples.
- Advanced vendor SDK-native retry behavior is not bundled where the corresponding vendor SDK is not bundled.
- This container does not include `swift`, so compilation must be run on a Swift 5.9+ toolchain host.

## Development

```bash
make static-check   # no Swift toolchain required
make test           # requires Swift 5.9+
```

GitHub Actions CI is provided for the static check plus Swift tests on Linux and macOS.

## License

MIT.
