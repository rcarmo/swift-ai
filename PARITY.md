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
- Initial OpenAI-compatible Chat Completions provider with common `SwiftAI.stream`/`SwiftAI.complete` entry points.
- OpenRouter image generation provider request/response path, including multimodal payload construction and `data:` URL image extraction.

## Known gaps vs upstream runtime parity

The package is structurally consumable via SwiftPM, but provider-runtime parity is still incomplete:

- OpenAI-compatible provider currently performs a non-streaming `/chat/completions` request and emits a final `.done`; full SSE delta/tool/thinking streaming is not yet ported.
- OpenAI Responses / Azure Responses runtime is not implemented.
- Anthropic Messages runtime is not implemented.
- Google Gemini / Gemini CLI / Vertex runtime is not implemented.
- Mistral Conversations runtime is not implemented.
- Bedrock Converse runtime is not implemented.
- OpenAI Codex runtime is not implemented.
- OAuth flows are not implemented.
- OpenRouter image generation retry/backoff hooks are not fully ported.
- Provider-specific retry/backoff behavior is not fully implemented.
- Full upstream transform/harness/session-resource helpers are not implemented.

## Validation constraints

The current container does not include a Swift toolchain (`swift` is not installed), so this repo has been statically checked here and should be compiled/tested with Swift 5.9+ on a Swift host using:

```bash
swift test
```
