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
- Shared HTTP retry/backoff helper for 429/5xx responses and `Retry-After`.
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
- Anthropic, Google, Mistral, Bedrock and OAuth providers are type/registry placeholders, not runtime implementations yet.
- Image-generation model discovery is ported, but the OpenRouter image generation runtime is not implemented yet.
- OAuth flows are not ported yet.
- This container does not include `swift`, so compilation must be run on a Swift 5.9+ toolchain host.

## Development

```bash
swift test
```

## License

MIT.
