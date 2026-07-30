# Release parity record

This file is the durable release-audit ledger for `swift-ai`. It must be updated as part of every future upstream `@earendil-works/pi-ai` release parity commit before the work is reported complete.

## Current upstream parity baseline

- Upstream package: `@earendil-works/pi-ai`
- Current upstream release: `v0.83.0`
- Current upstream tag commit: `845d6ff1f6643aba440341cce877ce1c43ebbc39`
- Previous accepted upstream release: `v0.82.1`
- Previous accepted upstream tag commit: `b4f293684bba718d59cc1157679bcf6157b3a7f5`
- Swift parity branch: `main`
- Current Swift parity commits for v0.83.0:
  - `cd5f2871a404c9471c598b9289e7ebb57fea54c8` — `Sync upstream v0.83.0 parity`
  - `bdc55b3643921eb70aefd627702a8a0f7768c338` — `Complete v0.83.0 runtime stop handling`
  - `5d2ecee6784b957d5636060c37997c9bee91f29d` — `Fix OAuth minimum validity refresh semantics`
  - `adaa42f434264968440b8c06492b0ca660bfea47` — `Document upstream release audit policy`
- Latest accepted CI for this release chain: <https://github.com/rcarmo/swift-ai/actions/runs/30522489514>

## Exact upstream delta

Release-only audit scope: `packages/ai` diff from `b4f293684bba718d59cc1157679bcf6157b3a7f5` to `845d6ff1f6643aba440341cce877ce1c43ebbc39`.

Exact changed-path count: **41**.

Changed paths:

```text
packages/ai/CHANGELOG.md
packages/ai/README.md
packages/ai/package.json
packages/ai/scripts/generate-models.ts
packages/ai/src/api/anthropic-messages.ts
packages/ai/src/api/azure-openai-responses.ts
packages/ai/src/api/bedrock-converse-stream.ts
packages/ai/src/api/google-generative-ai.ts
packages/ai/src/api/google-vertex.ts
packages/ai/src/api/mistral-conversations.ts
packages/ai/src/api/openai-codex-responses.ts
packages/ai/src/api/openai-completions.ts
packages/ai/src/api/openai-responses-shared.ts
packages/ai/src/api/openai-responses.ts
packages/ai/src/api/openrouter-images.ts
packages/ai/src/api/pi-messages.ts
packages/ai/src/api/simple-options.ts
packages/ai/src/auth/oauth/openrouter.ts
packages/ai/src/auth/resolve.ts
packages/ai/src/providers/faux.ts
packages/ai/src/types.ts
packages/ai/test/anthropic-sse-parsing.test.ts
packages/ai/test/azure-openai-responses-reasoning-replay.test.ts
packages/ai/test/bedrock-credentials.test.ts
packages/ai/test/bedrock-raw-stop-reason.test.ts
packages/ai/test/constrained-sampling.test.ts
packages/ai/test/faux-provider.test.ts
packages/ai/test/fetch-option.test.ts
packages/ai/test/github-copilot-anthropic.test.ts
packages/ai/test/google-raw-stop-reason.test.ts
packages/ai/test/mistral-raw-stop-reason.test.ts
packages/ai/test/models-runtime.test.ts
packages/ai/test/oauth-auth.test.ts
packages/ai/test/openai-completions-raw-stop-reason.test.ts
packages/ai/test/openai-completions-tool-choice.test.ts
packages/ai/test/openai-responses-partial-json-cleanup.test.ts
packages/ai/test/openai-responses-terminal-event.test.ts
packages/ai/test/openrouter-oauth.test.ts
packages/ai/test/pi-messages.test.ts
packages/ai/test/qwen-token-plan-models.test.ts
packages/ai/test/validation.test.ts
```

The detailed disposition matrix is in [`docs/upstream-v0.83.0-audit.md`](docs/upstream-v0.83.0-audit.md).

## Exact catalog parity

Generated from exact upstream tag `845d6ff1f6643aba440341cce877ce1c43ebbc39`; live main was not chased.

Text catalog:

- Swift source snapshot: `scripts/models.v0.83.0.json`
- Exact upstream comparator source: `scripts/upstream-models.845d6ff.json`
- Embedded Swift registry: `Sources/SwiftAI/ModelsGenerated.swift`
- Provider/id pairs: `1153/1153`
- Providers: `37`
- APIs: `9`

Image catalog:

- Swift source snapshot: `scripts/image-models.v0.83.0.json`
- Exact upstream comparator source: `scripts/upstream-image-models.845d6ff.json`
- Embedded Swift registry: `Sources/SwiftAI/ImageModelsGenerated.swift`
- Provider/id pairs: `40/40`
- Providers: `1`
- APIs: `1`

Comparator gate:

```bash
python3 scripts/audit-parity.py
```

Expected output includes:

```text
ok: 1153 text models / 37 providers / 9 APIs; 40 image models / 1 providers / 1 APIs
```

## Swift implementation, adaptations, and N/A decisions

### Implemented

- Regenerated v0.83.0 text and image catalogs from the exact upstream tag.
- Added `StopReason.pending` to represent upstream's new pending initial stream state.
- Added `Message.rawStopReason` to preserve provider-native finish/status/stop reasons.
- OpenAI Completions:
  - Preserves raw `finish_reason`.
  - Errors when a stream ends without `finish_reason`.
  - Preserves valid function payloads when malformed custom payloads are also present.
- OpenAI Responses, Azure Responses, and Codex Responses:
  - Preserve raw response status.
  - Reject `pending`, `in_progress`, `queued`, unknown, and missing terminal statuses as errors.
- Anthropic Messages:
  - Preserves raw `stop_reason`.
  - Errors when a stream ends without a stop reason.
  - Maps `sensitive` to an error with provider stop detail.
- Google Generative AI:
  - Preserves raw `finishReason`.
  - Maps unknown finish reasons to errors.
  - Errors when stream finishes without a stop reason.
- Mistral Conversations:
  - Preserves raw `finish_reason`.
  - Maps unknown or missing finish reasons to errors.
- Bedrock:
  - Unknown stop reasons map to errors.
  - `BedrockProvider.applyStopReason(_:to:)` preserves raw stop reasons for Bedrock transport integrations.
- OpenRouter OAuth:
  - Accepts both direct authorization code and callback URL input via `authorizationCode(from:)`.
- OAuth credential resolution:
  - `OAuthRegistry.resolveAPIKey(...)` enforces effective minimum validity as `max(300s, override)`.
  - Default 5-minute early refresh is applied.
  - Below-default overrides still use 300 seconds.
  - Explicit stricter overrides are enforced after refresh.
  - Refreshed credentials that still fail an explicit stricter minimum are rejected with cause-preserving `ModelsError`.

### Existing Swift equivalents / adaptations

- Upstream JS `fetch` injection maps to Swift's existing testable request/transport seams:
  - provider `requestTransport` hooks,
  - `BedrockTransport`,
  - `CodexTransport`,
  - request/response hooks such as `onPayload` and `onResponse`.
- Bedrock credential/profile priority remains transport-owned in Swift because SwiftPM core does not implement AWS SigV4 credential sourcing; `BedrockTransport` owners provide credentials/signing.

### N/A decisions

- Direct JS `fetch` callback API is not mirrored as a Swift option because Swift uses typed pluggable transports and URLSession-based request paths.
- JS SDK-specific Bedrock credential resolution is not part of SwiftPM core; it remains intentionally delegated to `BedrockTransport`.

## Tests and gates

Local validation for v0.83.0 corrective work used Swift `6.3.2`:

```bash
swift build -Xswiftc -warnings-as-errors
swift test
for i in 1 2 3; do swift test; done
make check
python3 scripts/audit-parity.py
python3 scripts/static-check.py
grep -R "XCTSkip" -n Tests || true
```

Latest local results before the documentation-policy update:

- `swift test`: `217` tests, `0` failures.
- deterministic `swift test` ×3: passed.
- `make check`: passed.
- `scripts/audit-parity.py`: passed with exact v0.83.0 counts.
- `scripts/static-check.py`: passed.
- hidden skip scan: no `XCTSkip` matches.

Latest GitHub Actions for the current release documentation-policy commit:

- Run: <https://github.com/rcarmo/swift-ai/actions/runs/30522489514>
- Commit: `adaa42f434264968440b8c06492b0ca660bfea47`
- Jobs:
  - `static-check`: success
  - `swift-test (ubuntu-latest)`: success
  - `swift-test (macos-14)`: success

## Future release-audit checklist

For every future upstream release audit:

1. Pin the exact upstream tag and SHA.
2. Diff only from the last accepted upstream tag to the new official tag.
3. Record exact changed path count and disposition matrix.
4. Regenerate text and image snapshots from the exact tag.
5. Update comparator sources and expected counts.
6. Implement all applicable Swift production deltas with executable tests.
7. Document every adaptation and N/A decision here and in the per-release audit doc.
8. Run local gates and require green GitHub Actions on Ubuntu, macOS, and static-check.
9. Commit/push cleanly as Rui Carmo.
