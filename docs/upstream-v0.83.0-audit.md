# Upstream pi-ai v0.83.0 release parity audit

Baseline: accepted official release `v0.82.1` / `b4f293684bba718d59cc1157679bcf6157b3a7f5`.
Target: official release `v0.83.0` / `845d6ff1f6643aba440341cce877ce1c43ebbc39`.
Scope: release-only audit pinned to `845d6ff1`; no commits beyond the tag were considered.

The final `packages/ai` delta is exactly 41 changed paths.

## Exact changed-path disposition matrix

| Upstream paths | Material delta | Swift disposition |
| --- | --- | --- |
| `CHANGELOG.md`, `README.md`, `package.json` | Release metadata/docs/version updates. | Reflected in `STATUS.json`, `PARITY.md`, and this audit. |
| `scripts/generate-models.ts`, provider model JSON/type changes, catalog tests including `qwen-token-plan-models.test.ts` | Catalog refresh, notably Qwen Token Plan/OpenRouter/Vercel/model-source updates. | Regenerated exact-tag text/image Swift catalogs: **1153/1153** text provider/id pairs, **37** providers, **9** APIs; **40/40** image pairs. `scripts/audit-parity.py` compares Swift embedded/source registries against `scripts/upstream-models.845d6ff.json` and `scripts/upstream-image-models.845d6ff.json`. |
| `src/types.ts` | Adds `pending` stop reason, `rawStopReason`, and injectable fetch hooks for JS SDK calls/images. | Added Swift `StopReason.pending` and `Message.rawStopReason`. Existing Swift uses pluggable transports/hooks (`requestTransport`, `onPayload`, `onResponse`) rather than JS `fetch`, so fetch injection is N/A beyond existing transport injection points. |
| `src/api/openai-completions.ts`, `src/api/openai-responses.ts`, `src/api/azure-openai-responses.ts`, `src/api/openai-codex-responses.ts`, `src/api/anthropic-messages.ts`, `src/api/bedrock-converse-stream.ts`, `src/api/pi-messages.ts`, `src/providers/faux.ts`, stream/error tests | Streams now start as `pending`, preserve raw provider stop reasons, and error if stream completes without a final stop reason. Sensitive/unknown provider stop reasons are surfaced as errors. | Added raw stop reason persistence to OpenAI Completions/Responses and stricter missing-final-reason handling for Completions/Anthropic/Responses. Bedrock stop reason mapping already covers portable external-transport paths; tests cover missing finish reason, raw finish reason, Anthropic sensitive/missing stop reason, and existing Responses terminal behavior. |
| `src/auth/oauth/openrouter.ts`, auth tests | OpenRouter OAuth callback/manual flow accepts callback URL/code shapes. | Added callback URL code extraction to `OpenRouterOAuthProvider.authorizationCode(from:)`, while preserving SwiftPM prompt-based portability. Tests cover direct code and callback URL parsing. |
| `test/bedrock-credentials.test.ts`, Bedrock API changes | Bedrock credential/fetch-option test coverage in JS SDK path. | Swift Bedrock remains intentionally pluggable through `BedrockTransport`; AWS SigV4/credential resolution remains N/A to SwiftPM core beyond existing request-construction and transport-injection tests. |
| `test/fetch-option.test.ts` | JS providers accept custom fetch implementations. | N/A as a direct JS fetch option; Swift equivalents are existing pluggable transports/request hooks for deterministic tests and embedding. |
| Other auth/provider/test fixture updates | Regression coverage around existing providers, OAuth, raw stop reasons, xhigh/support metadata. | Covered by catalog comparator, representative metadata tests, and the new raw/missing stop reason and OpenRouter callback tests. |

## Validation requirements

- `scripts/audit-parity.py` enforces exact text and image catalog parity against v0.83.0 source snapshots.
- Local gates must pass: `swift build -Xswiftc -warnings-as-errors`, `swift test`, deterministic `swift test` repeats, `make check`, `scripts/audit-parity.py`, `scripts/static-check.py`, and zero hidden `XCTSkip` matches.
- Acceptance requires GitHub Actions `static-check`, Ubuntu Swift tests, and macOS Swift tests all green for the pushed commit.
