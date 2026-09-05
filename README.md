# swift-ai

[![CI](https://github.com/rcarmo/swift-ai/actions/workflows/ci.yml/badge.svg)](https://github.com/rcarmo/swift-ai/actions/workflows/ci.yml)
[![CycloneDX SBOM](https://img.shields.io/badge/SBOM-CycloneDX-blue)](https://github.com/rcarmo/swift-ai/releases/download/upstream-v0.85.0/sbom.cdx.json)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

SwiftPM port of [@earendil-works/pi-ai](https://www.npmjs.com/package/@earendil-works/pi-ai), built for Swift applications that need the same provider catalogue, streaming events, OAuth flows, and request-shaping behaviour without pulling in the TypeScript runtime.

It currently tracks upstream `@earendil-works/pi-ai` v0.85.0 and embeds the audited model registries: 1336 text models across 39 providers and 9 text APIs, plus 50 image models. `STATUS.json` carries the same numbers in machine-readable form, and `SwiftAIStatus` exposes them at runtime.

## Documentation

The short usage guide lives in [`docs/USAGE.md`](docs/USAGE.md), with transport notes in [`docs/TRANSPORTS.md`](docs/TRANSPORTS.md). The release ledger and upstream audit material are deliberately separate from this README:

* [`RELEASE.md`](RELEASE.md) records the accepted upstream release, validation gates, and CI/SBOM references.
* [`PARITY.md`](PARITY.md) summarises the current parity baseline.
* [`docs/upstream-v0.85.0-audit.md`](docs/upstream-v0.85.0-audit.md) and [`docs/upstream-v0.85.0-test-crosswalk.md`](docs/upstream-v0.85.0-test-crosswalk.md) map the exact upstream release diff to Swift code and tests.

## Features

`swift-ai` keeps the upstream shape where that matters -- model metadata, provider routing, streaming events, tool calls, OAuth credentials, cache hints, and stop reasons -- but uses Swift value types, `Codable`, actors, and `AsyncStream` throughout.

The package includes:

* Core model, provider, message, content-block, tool, usage, diagnostic, stream-option, and image types.
* Actor-backed model/provider registries plus `await SwiftAI.bootstrap()` for one-call registration.
* OpenAI Chat Completions, OpenAI Responses, Azure OpenAI Responses, OpenAI Codex SSE, Anthropic Messages, Google Gemini/Vertex, Google Gemini CLI/Cloud Code Assist, Mistral Conversations, Pi Messages, OpenRouter Images, and Faux provider support.
* OAuth providers for GitHub Copilot, OpenAI Codex, Anthropic, Gemini CLI, Google Antigravity, Radius, and xAI.
* SSE parsing, partial JSON recovery for streamed tool calls, prompt-cache helpers, context overflow helpers, JSON Schema tool argument validation, retry/backoff utilities, diagnostics, pluggable logging, and request/response hooks.
* Generated text and image catalogues from the pinned upstream release, including compatibility metadata for reasoning, cache control, response APIs, image APIs, and provider-specific routing.

## Installation

Add the package to another SwiftPM project:

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

For a local checkout during development, use:

```swift
.package(path: "../swift-ai")
```

The package requires SwiftPM tools version 5.9 or newer. The current manifest targets macOS 13, iOS 16, tvOS 16, and watchOS 9.

## Quick start

```swift
import SwiftAI

await SwiftAI.bootstrap()

let model = await AIRegistry.shared.model(provider: .openAI, id: "gpt-4.1-mini")!
var options = StreamOptions()
options.env = ["OPENAI_API_KEY": "..."] // or rely on the process environment

let message = try await SwiftAI.complete(
    model: model,
    context: AIContext(messages: [.user("Say hello in one sentence.")]),
    options: options
)

print(Harness.textContent(in: message))
```

Streaming uses the same event protocol as the rest of the port:

```swift
let stream = await SwiftAI.stream(
    model: model,
    context: AIContext(messages: [.user("Think briefly, then answer.")]),
    options: options
)

for await event in stream {
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

## Package/source layout

The Swift target is split by role rather than provider history:

* `Sources/SwiftAI/Core/` contains public types, registries, events, context helpers, image types, status metadata, and assistant frame replay utilities.
* `Sources/SwiftAI/Providers/` contains bundled provider implementations and OAuth providers.
* `Sources/SwiftAI/Auth/` contains shared OAuth data structures and registries.
* `Sources/SwiftAI/Support/` contains SSE parsing, partial JSON parsing, diagnostics, harness helpers, Azure helpers, environment handling, and utility code.
* `Sources/SwiftAI/Transport/` contains retry, HTTP metadata/proxy helpers, and pluggable transport registries.
* `Sources/SwiftAI/Models/Generated/` contains generated text and image catalogues.
* `Sources/CZstd/` exposes the small C module map used for Codex zstd request compression.

Tests follow the same split under `Tests/SwiftAITests/`, with provider tests kept separate from core utility, environment, overflow, and model registry checks.

## Provider status

Bundled text providers currently cover OpenAI Completions, OpenAI Responses, Azure OpenAI Responses, OpenAI Codex Responses over SSE, Anthropic Messages, Google Generative AI, Google Vertex, Google Gemini CLI / Cloud Code Assist, Mistral Conversations, Pi Messages, and Faux test streams.

Image generation is exposed through OpenRouter Images, using the generated image catalogue. Bedrock ConverseStream request building and provider registration are present, but live AWS transport is intentionally pluggable because SigV4 and AWS event-stream handling are better supplied by the consuming application.

## Known limitations/divergences

The core package avoids bundling heavyweight vendor SDKs and WebSocket stacks. That keeps the SwiftPM target small and lets applications choose their own networking dependencies where the upstream JavaScript package can lean on platform-specific machinery.

* Bedrock live AWS SigV4/event-stream transport is exposed through `BedrockTransportRegistry`; `BedrockProvider.buildConverseRequest(model:context:options:)` returns the serialisable request body for a transport implementation.
* Codex SSE is bundled. Codex WebSocket/session-cache transport is exposed through `CodexTransportRegistry`, and [`docs/TRANSPORTS.md`](docs/TRANSPORTS.md) spells out the handshake and local integration-test requirements.
* Vendor SDK-native retry behaviour is not bundled where the matching vendor SDK is not bundled; the package provides a shared retry/backoff layer for the HTTP paths it owns.
* Live provider smoke tests are deliberately outside the SwiftPM test target unless credentials and network access are supplied by the caller.

## Compatibility/versioning

The current runtime parity baseline is upstream `@earendil-works/pi-ai` v0.85.0, tag commit `107d79f11072bbc8a3a757ed7fd69596bee7d68c`. The accepted Swift runtime commit is recorded in [`RELEASE.md`](RELEASE.md), along with local and hosted validation results.

The public API is still tracking upstream quickly, so consumers should pin a commit or tag rather than assuming broad semver stability. The generated catalogues and `STATUS.json` are the easiest way to verify which upstream release a checkout represents.

## Upstream and attribution

This project is a derivative port of [@earendil-works/pi-ai](https://www.npmjs.com/package/@earendil-works/pi-ai), part of the [earendil-works/pi](https://github.com/earendil-works/pi/tree/main/packages/ai) project, originally created by [Mario Zechner](https://mariozechner.at). The TypeScript API design, event protocol, provider implementations, model registry, and OAuth flows originate upstream. This port adapts them idiomatically for Swift. All credit for the original design goes to Mario and the upstream contributors.

## Supply-chain metadata

The accepted runtime for the current upstream v0.85.0 parity pass is `943861d656920758cdb77ce493b6b01c0a415c01`. Its durable CycloneDX SBOM is published as an immutable release asset at [`upstream-v0.85.0/sbom.cdx.json`](https://github.com/rcarmo/swift-ai/releases/download/upstream-v0.85.0/sbom.cdx.json), with the matching checksum at [`upstream-v0.85.0/sbom.cdx.json.sha256`](https://github.com/rcarmo/swift-ai/releases/download/upstream-v0.85.0/sbom.cdx.json.sha256).

The dispatch-only publishing workflow is [`publish-sbom-release.yml`](.github/workflows/publish-sbom-release.yml); it regenerates the SBOM from an explicit runtime ref, validates the CycloneDX payload, OSV scan, licence review, embedded revision, and checksum naming, then uploads the release assets with `--clobber`.

## License

MIT.
