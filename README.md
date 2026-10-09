# swift-ai

[![CI](https://github.com/rcarmo/swift-ai/actions/workflows/ci.yml/badge.svg)](https://github.com/rcarmo/swift-ai/actions/workflows/ci.yml)
[![CycloneDX SBOM](https://img.shields.io/badge/SBOM-CycloneDX-blue)](https://github.com/rcarmo/swift-ai/releases/download/v1.0.1/sbom.cdx.json)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

SwiftPM port of [@earendil-works/pi-ai](https://www.npmjs.com/package/@earendil-works/pi-ai), built for Swift applications that need the same provider catalogue, streaming events, OAuth flows, and request-shaping behaviour without pulling in the TypeScript runtime.

The current development candidate targets upstream `@earendil-works/pi-ai` and `pi-durable` **v1.1.0**, pinned to the official 7 October release. Its catalogues contain **1563 chat models across 41 providers and 10 APIs**, **61 image models**, and **26 classifier models across 6 providers and 3 APIs**. The last accepted and published Swift release is **v1.0.1**.

## Port status

The v1.1.0 candidate adds OpenAI Decisions classification with image inputs, thinking-level sampling overrides, Azure provider routing, context estimates at 3.5 characters per token, tiered prices, updated retry cases and response/tool duration metadata. Durable additions cover ordered scan cursors and persisted provider session IDs. Local verification passed **388 tests**, catalogue comparators and corruption self-tests, SBOM checks, OSV scanning and licence review.

Full release parity is incomplete. The exact [AI audit](docs/upstream-v1.1.0-audit.md) has 82 changed paths and 38 changed test paths; the [durable audit](docs/durable-v1.1.0-audit.md) has unresolved rows. The v1.1.0 durable inventory contains **67 source paths and 49 executable test suites**. Fork/reset, inbox steering, compaction, subagents, hooks/extensions, watches/events/views/task graphs, built-in tools and SQLite/JSONL backends are not implemented by this candidate.

Linux is verified locally; macOS persistence and other Apple platforms need real-host validation. A focused nine-test Massif run passed with an 11,557,726-byte useful-heap peak, mostly registry bootstrap/decoding. A full-suite CPU sampling capture ran, but the gprofng report reader crashed, so CPU hotspot attribution is unverified. There is no measured equivalent-workload performance improvement. No v1.1.0 tag, release or assets have been published.

## Documentation

The short usage guide lives in [`docs/USAGE.md`](docs/USAGE.md), with transport notes in [`docs/TRANSPORTS.md`](docs/TRANSPORTS.md). The release ledger and upstream audit material are deliberately separate from this README:

* [`RELEASE.md`](RELEASE.md) records the accepted upstream release, validation gates, and CI/SBOM references.
* [`docs/upstream-v1.0.1-audit.md`](docs/upstream-v1.0.1-audit.md) and [`docs/upstream-v1.0.1-test-crosswalk.md`](docs/upstream-v1.0.1-test-crosswalk.md) map the pinned provider release diff to Swift code and tests.
* [`docs/durable/native-design.md`](docs/durable/native-design.md) describes the implemented storage, generation and owned-tools phases. The [contract](docs/durable/contract-crosswalk.md) and [test](docs/durable/test-crosswalk.md) crosswalks retain the phased roadmap.
* [`PARITY.md`](PARITY.md) retains the older provider inventory; use the v1.1.0 candidate audit and `STATUS.json` for development coverage, and `RELEASE.md` for accepted validation/publication results.

## Features

`swift-ai` keeps the upstream shape where that matters -- model metadata, provider routing, streaming events, tool calls, OAuth credentials, cache hints, and stop reasons -- but uses Swift value types, `Codable`, actors, and `AsyncStream` throughout.

The package includes:

* Core chat, image, classifier, provider, message, content-block, tool, usage, diagnostic, and stream-option types.
* Actor-backed chat/image/classifier model/provider registries plus `await SwiftAI.bootstrap()` for one-call registration.
* OpenAI Chat Completions, OpenAI Responses, Azure OpenAI Responses, OpenAI Codex SSE, Anthropic Messages, Google Gemini/Vertex, Google Gemini CLI/Cloud Code Assist, Mistral Conversations, Pi Messages, OpenRouter Images, TypeSafe System One, Cloudflare Workers AI and OpenAI Decisions classifiers, and Faux test streams.
* OAuth providers for GitHub Copilot, OpenAI Codex, Anthropic, Gemini CLI, Google Antigravity, Radius, and xAI.
* SSE parsing, partial JSON recovery for streamed tool calls, prompt-cache helpers, context overflow helpers, JSON Schema tool argument validation, retry/backoff utilities, diagnostics, pluggable logging, and request/response hooks.
* Generated chat, image, and classifier catalogues from the pinned upstream release, including compatibility metadata for reasoning, cache control, response APIs, image APIs, and provider-specific routing.
* Durable memory and framed-journal storage, bounded mutation/session ownership, persistent generation and explicit recovery, plus serial child tool execution with durable checkpoints.

## Installation

Add the package to another SwiftPM project:

```swift
// Package.swift
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/rcarmo/swift-ai.git", exact: "1.0.1")
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

The manifest declares SwiftPM tools version 5.9 and targets macOS 13, iOS 16, tvOS 16, and watchOS 9. Local verification used Swift 6.3.2 on Linux; hosted verification used Ubuntu Swift 6.4. Those manifest declarations do not establish testing on Swift 5.9 or the Apple platforms. The `CZstd` system-library target also requires libzstd (`libzstd-dev` on Debian/Ubuntu, `zstd` via Homebrew).

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
* `Sources/SwiftAI/Models/Generated/` contains generated chat, image and classifier catalogues.
* `Sources/SwiftAI/Durable/` contains persistent records, storage, mutation ownership, generation, recovery and owned-tools runtime.
* `Sources/CZstd/` exposes the small C module map used for Codex zstd request compression.

Tests follow the same split under `Tests/SwiftAITests/`, with provider tests kept separate from core utility, environment, overflow, and model registry checks.

## Provider status

Bundled text providers currently cover OpenAI Completions, OpenAI Responses, Azure OpenAI Responses, OpenAI Codex Responses over SSE, Anthropic Messages, Google Generative AI, Google Vertex, Google Gemini CLI / Cloud Code Assist, Mistral Conversations, Pi Messages, and Faux test streams.

Image generation is exposed through OpenRouter Images, using the generated image catalogue. `SwiftAI.classify` uses TypeSafe System One, Cloudflare Workers AI System One or OpenAI Decisions for Choice, Score and Noul questions. Decisions maps Noul to predicates and supports image-capable classifier models. Bedrock ConverseStream request building and provider registration are present; consumers supply the live SigV4/event-stream transport.

## Known limitations/divergences

The core package avoids bundling heavyweight vendor SDKs and WebSocket stacks. That keeps the SwiftPM target small and lets applications choose their own networking dependencies where the upstream JavaScript package can lean on platform-specific machinery.

* Bedrock live AWS SigV4/event-stream transport is exposed through `BedrockTransportRegistry`; `BedrockProvider.buildConverseRequest(model:context:options:)` returns the serialisable request body for a transport implementation.
* Codex SSE is bundled. Codex WebSocket/session-cache transport is exposed through `CodexTransportRegistry`, and [`docs/TRANSPORTS.md`](docs/TRANSPORTS.md) spells out the handshake and local integration-test requirements.
* Vendor SDK-native retry behaviour is not bundled where the matching vendor SDK is not bundled; the package provides a shared retry/backoff layer for the HTTP paths it owns.
* Live provider smoke tests require caller-supplied credentials and network access; deterministic suite results do not establish live-provider verification.
* OAuth browser callback listeners and UI automation are supplied by the host. Radius discovery, PKCE/device-code flows, token refresh, credential caching and model injection are implemented; browser callback automation is not bundled.
* The persistent journal backend has Linux/macOS code paths. Linux is verified; macOS persistence still needs a real-host check. Other platforms return a typed unsupported-storage error, and cross-language journal compatibility is not provided.

## Compatibility/versioning

The last accepted upstream baseline is `@earendil-works/pi-ai` v1.0.1, tag commit `a7229ddc21810d6245105978033b7df645ecc2f7`. Native `v1.0.1` and its `upstream-v1.0.1` alias target the accepted provider and useful durable runtime recorded in [`RELEASE.md`](RELEASE.md). The v1.1.0 development candidate does not change that published release target. The installation example pins the accepted release; use a reviewed candidate commit to consume v1.1.0 work.

Pin a release or commit when consuming the package. A matching version identifies the audited upstream baseline; it does not guarantee every upstream transport or durable feature is implemented.

## Development checks

Use the repository Make targets to keep generated output out of the checkout:

```bash
make static-check
make build
make test
```

Make resolves a project-owned root once: locally `/workspace/tmp/swift-ai` when usable, otherwise the platform temp base plus `/swift-ai`. CI prefers `RUNNER_TEMP`, then the original inherited `TMPDIR`, then platform temp, always appending `swift-ai`. An absolute `PROJECT_TMP_BASE` or project-named `PROJECT_TMP_ROOT` can override the base/root; invalid or conflicting overrides fail.

SwiftPM/compiler/Python/Go caches use `cache/`, generated builds use `build/`, and isolated test/temp files use `runs/<purpose>/<run-id>/`. Tests require the scratch variables exported by Make. [`AGENTS.md`](AGENTS.md) documents the paths and cleanup boundaries; `make clean` removes only this project's cache/build directories and must be used only when no job owns them.

## Upstream and attribution

This project is a derivative port of [@earendil-works/pi-ai](https://www.npmjs.com/package/@earendil-works/pi-ai), part of the [earendil-works/pi](https://github.com/earendil-works/pi/tree/main/packages/ai) project, originally created by [Mario Zechner](https://mariozechner.at). The TypeScript API design, event protocol, provider implementations, model registry, and OAuth flows originate upstream. This port adapts them idiomatically for Swift. All credit for the original design goes to Mario and the upstream contributors.

## Supply-chain metadata

The native v1.0.1 release publishes a version-pinned [CycloneDX SBOM](https://github.com/rcarmo/swift-ai/releases/download/v1.0.1/sbom.cdx.json) and [checksum](https://github.com/rcarmo/swift-ai/releases/download/v1.0.1/sbom.cdx.json.sha256) for its exact accepted runtime. The verified dependency graph is `swift-ai -> swift-crypto -> swift-asn1`; the release scan found zero vulnerabilities and the licence review passed. Publication identifiers and provenance are recorded in [`RELEASE.md`](RELEASE.md).

The dispatch-only publishing workflow is [`publish-sbom-release.yml`](.github/workflows/publish-sbom-release.yml); it takes a version-pinned `release_tag`, matching `upstream_version`, and explicit runtime ref, validates the CycloneDX payload, OSV scan, licence review, embedded revision, tag target, and checksum naming, then uploads the release assets with `--clobber`.

## License

MIT.
