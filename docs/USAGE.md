# SwiftPM usage

## Add the dependency

In another Swift package:

```swift
// Package.swift
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/rcarmo/swift-ai.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [.product(name: "SwiftAI", package: "swift-ai")]
        )
    ]
)
```

For a local checkout during development:

```swift
.package(path: "../swift-ai")
```

## Bootstrap registries/providers

```swift
import SwiftAI

await SwiftAI.bootstrap()
```

`bootstrap()` registers:

- all embedded text/image models
- bundled text providers
- bundled image providers
- OAuth providers
- pluggable transport surfaces

## Run a basic completion

```swift
import SwiftAI

await SwiftAI.bootstrap()

let model = await AIRegistry.shared.model(provider: .openAI, id: "gpt-4.1-mini")!
var options = StreamOptions()
options.env = ["OPENAI_API_KEY": "..."] // or rely on process env

let message = try await SwiftAI.complete(
    model: model,
    context: AIContext(messages: [.user("Say hello in one sentence.")]),
    options: options
)

print(Harness.textContent(in: message))
```

## Stream events

```swift
let events = await SwiftAI.stream(
    model: model,
    context: AIContext(messages: [.user("Think step by step, then answer.")]),
    options: options
)

for await event in events {
    switch event {
    case .textDelta(_, let delta, _):
        print(delta, terminator: "")
    case .done(let reason, let message):
        print("\nDone: \(reason), tokens: \(message.usage?.totalTokens ?? 0)")
    case .error(_, _, let error):
        print("Error: \(String(describing: error))")
    default:
        break
    }
}
```

## OAuth providers

OAuth providers are registered by `SwiftAI.bootstrap()`:

```swift
let provider = await OAuthRegistry.shared.provider(id: "github-copilot")!
let credentials = try await provider.login(callbacks: OAuthLoginCallbacks(
    onAuth: { info in print("Open: \(info.url) — \(info.instructions)") },
    onPrompt: { prompt in
        print(prompt.message)
        return readLine() ?? ""
    },
    onProgress: { print($0) }
))
```

For Gemini CLI/Antigravity, `apiKey(credentials:)` returns the JSON payload expected by the provider:

```swift
let key = provider.apiKey(credentials: credentials)
var options = StreamOptions()
options.apiKey = key
```

## Pluggable transports

The lightweight core target does not bundle heavyweight transport stacks for:

- Amazon Bedrock AWS SigV4/event-stream
- OpenAI Codex WebSocket/session-cache

Use `BedrockTransportRegistry` and `CodexTransportRegistry` to provide those implementations. See [TRANSPORTS.md](TRANSPORTS.md).

## Validate a checkout

Without Swift installed:

```bash
make static-check
```

With Swift 5.9+:

```bash
make test
```
