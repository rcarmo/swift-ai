# Pluggable transports

`swift-ai` keeps the core SwiftPM target lightweight. Two upstream runtime areas require heavyweight platform/network stacks and are exposed as pluggable protocols instead of being bundled directly.

## BedrockTransport

Amazon Bedrock live runtime requires AWS SigV4 signing and AWS event-stream handling. Register a transport after bootstrap:

```swift
import SwiftAI

struct MyBedrockTransport: BedrockTransport {
    func stream(
        request: [String: JSONValue],
        model: Model,
        context: AIContext,
        options: StreamOptions?
    ) -> AsyncStream<AIEvent> {
        AsyncStream { continuation in
            // 1. Sign `request` for Bedrock ConverseStream.
            // 2. Send with AWS SDK / custom SigV4 client.
            // 3. Convert Bedrock contentBlockDelta/messageStop events to AIEvent.
            continuation.finish()
        }
    }
}

await BedrockTransportRegistry.shared.setTransport(MyBedrockTransport())
```

`BedrockProvider.buildConverseRequest(model:context:options:)` returns the serializable ConverseStream-style request body for reuse by a transport implementation.

## CodexTransport

OpenAI Codex SSE fallback is bundled. The upstream WebSocket/session-cache path is exposed as a pluggable transport:

```swift
import SwiftAI

struct MyCodexTransport: CodexTransport {
    func stream(
        request: [String: JSONValue],
        model: Model,
        context: AIContext,
        options: StreamOptions?
    ) -> AsyncStream<AIEvent> {
        AsyncStream { continuation in
            // 1. Open/reuse a Codex WebSocket session.
            // 2. Send `request` using the Codex protocol envelope.
            // 3. Convert response.output_* events to AIEvent.
            continuation.finish()
        }
    }
}

await CodexTransportRegistry.shared.setTransport(MyCodexTransport())
```

If no `CodexTransport` is registered, `.openAICodexResponses` uses the bundled HTTP/SSE path.

## Validation

The static validation gate verifies the pluggable transport protocols and provider registrations exist:

```bash
make static-check
```

Run `make test` on a Swift 5.9+ host to compile and exercise the fake transport tests.
