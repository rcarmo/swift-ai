# swift-ai

SwiftPM library port of [`@earendil-works/pi-ai`](https://www.npmjs.com/package/@earendil-works/pi-ai), using [`go-ai`](https://github.com/rcarmo/go-ai) as the audited reference implementation.

This package is an initial Swift port prepared for consumption as a SwiftPM library. It tracks upstream `@earendil-works/pi-ai` **0.79.9**.

## What is implemented

- Core `Codable` type system: models, providers, messages, tools, usage, diagnostics, stream options.
- Stream event enum matching the `pi-ai`/`go-ai` event protocol.
- Actor-backed provider and model registry.
- Built-in bootstrap entry point: `await SwiftAI.bootstrap()`.
- Environment API key lookup with per-request `StreamOptions.env` overlay.
- OpenAI-compatible compat detection, including `chat-template` thinking kwargs.
- Context overflow and basic tool argument validation helpers.
- SSE parser.
- OpenAI Chat Completions provider exposed through the common async stream/complete API, with SSE event parsing for text, thinking, tool calls, usage, and finish reasons.
- OpenAI Responses, Azure OpenAI Responses, and OpenAI Codex SSE provider with parsing, reasoning, prompt cache fields, Azure configuration, and Codex account headers.
- Shared HTTP retry/backoff helper for 429/5xx responses and `Retry-After`.
- OAuth framework plus GitHub Copilot, OpenAI Codex, Anthropic, Gemini CLI, and Antigravity OAuth support.
- Provider environment/API-key resolution matching upstream env names and scoped overrides.
- Request/response interception hooks for text and image HTTP providers.
- Partial JSON parser for streamed tool-call arguments.
- Copilot and OpenAI/Azure session-affinity header helpers wired into providers.
- Deterministic short hashes and Unicode surrogate sanitization helpers.
- Anthropic Messages provider with SSE parsing for text, thinking, tool calls, usage, and stop reasons.
- Mistral Conversations provider with reasoning/prompt mode and SSE event parsing.
- Google Gemini/Vertex REST provider with thinking config, multimodal/tool request support, and SSE event parsing.
- Google Gemini CLI / Cloud Code Assist provider with OAuth JSON credentials and wrapped Gemini SSE parsing.
- Faux provider/test double for credential-free SwiftPM tests.
- Token cost calculation utilities wired into provider usage metadata.
- Message transformation helpers for cross-provider replay, image downgrade, and synthetic tool results.
- Prompt-cache helpers and session-resource cleanup registry.
- Diagnostics and pluggable logging helpers.
- Context overflow detection and JSON Schema tool argument validation helpers.
- Simple-options/thinking level and token-budget helpers.
- Full embedded text model catalog generated from audited `go-ai`/upstream `pi-ai` v0.79.9: 979 models / 35 providers.
- Full embedded image model catalog: 34 OpenRouter image models.

## Usage

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

This is not yet a full provider-complete port. The SwiftPM package is structured so additional providers can be added incrementally under `Sources/SwiftAI/Providers/` while preserving the public API.

- OpenAI-compatible provider still lacks some provider-specific header/retry/prompt-cache edge cases.
- Bedrock runtime is not implemented yet.
- Image-generation model discovery is ported, but the OpenRouter image generation runtime is not implemented yet.
- OAuth flows are not ported yet.
- This container does not include `swift`, so compilation must be run on a Swift 5.9+ toolchain host.

## Development

```bash
swift test
```

## License

MIT.
