# Upstream parity gaps — @earendil-works/pi-ai v0.80.2

Generated for the standing parity audit. Source of truth: extracted upstream package `/tmp/pi-ai-0.80.2/package/dist` plus direct Swift source inspection in `/workspace/projects/swift-ai`.

## Coverage estimate

- **Registry/model surface:** 100% for upstream v0.80.2 generated registries (`999` text models / `35` providers / `9` APIs; `34` image models / `1` image provider / `1` image API).
- **Core type/event/options surface:** ~90%. Codable JSON-compatible core, events, options, compat metadata, auth credential types, and validation helpers are present. TypeBox-specific exports are intentionally represented as `JSONValue`/schema values rather than TypeBox.
- **Bundled provider runtime surface:** ~88%. HTTP/SSE providers are implemented; Bedrock live SigV4/event-stream and Codex WebSocket/session-cache are pluggable extension points rather than bundled transports.
- **Upstream source test parity:** classified/covered. Source tests from `/tmp/pi-upstream-src/packages/ai/test` are tracked in `docs/upstream-tests-source.md` with no `PENDING` rows (`41` deterministic adapted, `29` partial, `18` live-gated, `1` not applicable).

## Top remaining gaps

1. **Bedrock live transport** — `PARTIAL`. `BedrockTransport` protocol and request builder exist, but an AWS SigV4/event-stream transport module is not bundled.
2. **Codex WebSocket/session-cache transport** — `PARTIAL`. HTTP/SSE Codex path and `CodexTransport` protocol exist, but WebSocket/session-cache transport is not bundled.
3. **Live E2E execution** — `LIVE-GATED`. Live wrappers exist for initial high-value upstream rows; broader provider matrices remain guarded because they require provider credentials and network access.

## Upstream index exports

| Upstream export/module | Swift status | Swift path |
|---|---:|---|
| `types.ts` core model/message/event option types | DONE | `Sources/SwiftAI/Types.swift`, `Sources/SwiftAI/Events.swift` |
| `models.ts`, `models.generated.ts`, provider model registries | DONE | `Sources/SwiftAI/ModelsGenerated.swift`, `scripts/models.v0.80.2.json` |
| `images-models.ts`, image generated registry | DONE | `Sources/SwiftAI/ImageModelsGenerated.swift`, `Sources/SwiftAI/Images.swift` |
| `api/lazy.ts` lazy wrappers | PARTIAL | Registry/provider protocols in `Sources/SwiftAI/Registry.swift`; no lazy module loader needed for SwiftPM static linking |
| `auth/types.ts`, `auth/context.ts`, `auth/credential-store.ts`, `auth/helpers.ts`, `auth/resolve.ts` | PARTIAL | `Sources/SwiftAI/Auth.swift`, `Sources/SwiftAI/Env.swift`, OAuth providers. Full app-owned auth orchestration is host responsibility. |
| `providers/faux.ts` | DONE | `Sources/SwiftAI/Providers/FauxProvider.swift` |
| `session-resources.ts` | DONE | `Sources/SwiftAI/SessionResources.swift` |
| `utils/diagnostics.ts` | DONE | `Sources/SwiftAI/Diagnostics.swift` |
| `utils/event-stream.ts` | DONE | `Sources/SwiftAI/Events.swift`, provider `AsyncStream<AIEvent>` implementations |
| `utils/json-parse.ts` | DONE | `Sources/SwiftAI/PartialJSON.swift` |
| `utils/overflow.ts` | DONE | `Sources/SwiftAI/Context.swift` |
| `utils/typebox-helpers.ts` / TypeBox exports | PARTIAL | `JSONValue` schemas in `Sources/SwiftAI/Types.swift`; no TypeBox runtime in Swift |
| `utils/validation.ts` | DONE | `Sources/SwiftAI/Context.swift` |
| `utils/hash.ts`, `utils/sanitize-unicode.ts`, headers | DONE | `Sources/SwiftAI/Utilities.swift`, `Sources/SwiftAI/HTTPMetadata.swift` |
| OAuth public types/providers | DONE | `Sources/SwiftAI/OAuth.swift`, provider OAuth files |

## Provider/API runtime parity

| Upstream API/provider module | Status | Swift path | Notes |
|---|---:|---|---|
| `api/openai-completions.ts` | DONE | `Sources/SwiftAI/Providers/OpenAICompletionsProvider.swift` | Includes streaming, tool calls, multimodal replay, compat thinking, cache/session headers, v0.80.2 auth-header/empty-tools behavior. |
| `api/openai-responses.ts` | DONE | `Sources/SwiftAI/Providers/OpenAIResponsesProvider.swift` | Includes replay items, reasoning defaults, cache usage, failed/generic errors, status mapping. |
| `api/azure-openai-responses.ts` | DONE | `Sources/SwiftAI/Providers/OpenAIResponsesProvider.swift`, `Sources/SwiftAI/AzureHelpers.swift` | Includes Azure URL/deployment helpers, tool-call trimming, reasoning event normalization. |
| `api/openai-codex-responses.ts` | PARTIAL | `Sources/SwiftAI/Providers/OpenAIResponsesProvider.swift` | SSE path bundled; WebSocket/session-cache exposed via `CodexTransport`. |
| `api/anthropic-messages.ts` | DONE | `Sources/SwiftAI/Providers/AnthropicMessagesProvider.swift` | Includes cache control, tool_use/tool_result, truncated stream errors, compat flags. |
| `api/google-generative-ai.ts` | DONE | `Sources/SwiftAI/Providers/GoogleGenerativeAIProvider.swift` | Includes Gemini/Vertex request and SSE semantics, signatures, tool results/images. |
| `api/google-vertex.ts` | DONE | `Sources/SwiftAI/Providers/GoogleGenerativeAIProvider.swift` | Vertex URL/auth sentinel support; bearer/ADC transport is host/env based. |
| `api/google-gemini-cli.ts` | DONE | `Sources/SwiftAI/Providers/GoogleGeminiCLIProvider.swift` | CCA wrapper, OAuth JSON credentials, wrapped SSE unwrapping. |
| `api/mistral-conversations.ts` | DONE | `Sources/SwiftAI/Providers/MistralConversationsProvider.swift` | Streaming, reasoning, tools, usage, error finish. |
| `api/openrouter-images.ts` | DONE | `Sources/SwiftAI/Providers/OpenRouterImagesProvider.swift` | Payload, text/images, string/object image_url, usage/cost. |
| `api/bedrock-converse-stream.ts` | PARTIAL | `Sources/SwiftAI/Providers/BedrockProvider.swift` | Request surface and `BedrockTransport`; live AWS transport not bundled. |

## Provider registry/model files

| Upstream provider model family | Status | Swift path |
|---|---:|---|
| All 35 text providers in `dist/providers/*.models.js` | DONE | `Sources/SwiftAI/ModelsGenerated.swift`; verified by `scripts/audit-parity.py` |
| OpenRouter image provider models | DONE | `Sources/SwiftAI/ImageModelsGenerated.swift`; verified by `scripts/audit-parity.py` |
| Provider aliases/wrappers under `dist/providers/*.js` | DONE/PARTIAL | Runtime is API-based in Swift; all generated APIs have bootstrap registrations. |

## OAuth/auth parity

| Upstream OAuth/auth module | Status | Swift path | Notes |
|---|---:|---|---|
| `utils/oauth/github-copilot.ts` | DONE | `Sources/SwiftAI/Providers/GitHubCopilotOAuthProvider.swift` | Device flow, token exchange, model availability/filtering, policy enable. |
| `utils/oauth/openai-codex.ts` | DONE | `Sources/SwiftAI/Providers/OpenAICodexOAuthProvider.swift` | Device flow and refresh. |
| `utils/oauth/anthropic.ts` | DONE/PARTIAL | `Sources/SwiftAI/Providers/AnthropicOAuthProvider.swift` | Uses host-prompted callback code for SwiftPM portability instead of local server. |
| `google-gemini-cli` / Antigravity OAuth | DONE/PARTIAL | `Sources/SwiftAI/Providers/GoogleOAuthProviders.swift` | Uses host-prompted callback code for SwiftPM portability. |
| `auth/*` credential store/context types | PARTIAL | `Sources/SwiftAI/Auth.swift` | Types and in-memory serialized store implemented; full app persistence is host-owned as upstream intends. |

## Event types / stream protocol

| Event/protocol area | Status | Swift path |
|---|---:|---|
| start/done/error/text/thinking/tool event stream | DONE | `Sources/SwiftAI/Events.swift` |
| OpenAI SSE chunks | DONE | `OpenAICompletionsProvider.swift` |
| Responses SSE chunks | DONE | `OpenAIResponsesProvider.swift` |
| Anthropic SSE chunks | DONE | `AnthropicMessagesProvider.swift` |
| Gemini/CCA SSE chunks | DONE | `GoogleGenerativeAIProvider.swift`, `GoogleGeminiCLIProvider.swift` |
| Mistral SSE chunks | DONE | `MistralConversationsProvider.swift` |
| Bedrock event stream | PARTIAL | `BedrockTransport` receives request and emits `AIEvent`; AWS event stream adapter not bundled |

## Tests

| Upstream test artifact | Status | Swift path |
|---|---:|---|
| `*.test.ts` in npm tarball | MISSING UPSTREAM ARTIFACT | No upstream tests are included in `/tmp/pi-ai-0.80.2/package`; source tests are tracked from `/tmp/pi-upstream-src/packages/ai/test`. |
| Upstream source tests | CLASSIFIED/COVERED | `docs/upstream-tests-source.md`, `docs/upstream-tests-parity.md`; no `PENDING` rows. |
| Semantic Swift tests for ported behavior | DONE/PARTIAL | `Tests/SwiftAITests/` |
| Toolchain-light validation | DONE | `scripts/static-check.py`, `scripts/audit-parity.py`, `Makefile` |
| SwiftPM CI | DONE | `.github/workflows/ci.yml` |

## Current validation command

```bash
make static-check
```

Run `make test` on a Swift 5.9+ host.
