# Release parity record

This file is the durable release-audit ledger for `swift-ai`. It must be updated as part of every future upstream `@earendil-works/pi-ai` release parity commit before the work is reported complete.

## Current upstream parity baseline

- Upstream package: `@earendil-works/pi-ai`
- Current upstream release: `v0.84.0`
- Current upstream tag commit: `a5f43bf8aff3c55752432655f7334e3dafd1e256`
- Previous accepted upstream release: `v0.83.0`
- Previous accepted upstream tag commit: `845d6ff1f6643aba440341cce877ce1c43ebbc39`
- Swift parity branch: `main`
- Current Swift parity commits for v0.84.0:
  - `f3879329ac0479116f049f17406a553f4fa14d56` — `Sync upstream v0.84.0 parity`
  - `fa33169cc030bf0fa169388ed90ab8407b9bf9ba` — `Complete v0.84.0 thinking budget parity`
  - `898e43dc31511e5c2704b05bda4dd63f279b90cd` — `Close v0.84.0 corrective audit gaps`
  - `46e02b699d86fdbea36f6a29228f517bfd4dbb61` — `Add v0.84.0 deferred lifecycle parity`
  - This corrective commit — production nullable ProviderHeaders deletion and cancellation-aware OAuth refresh protocol/registry/provider path, updated exact 101-path evidence, and exact 46 changed-test assertion matrix.
- Latest accepted CI for this release chain before this corrective commit: <https://github.com/rcarmo/swift-ai/actions/runs/31108725910>

## Exact upstream delta

Release-only audit scope: `packages/ai` diff from `845d6ff1f6643aba440341cce877ce1c43ebbc39` to `a5f43bf8aff3c55752432655f7334e3dafd1e256`.

Exact changed-path count: **101**.

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
packages/ai/src/api/google-shared.ts
packages/ai/src/api/google-vertex.ts
packages/ai/src/api/lazy.ts
packages/ai/src/api/openai-codex-responses.ts
packages/ai/src/api/openai-completions.ts
packages/ai/src/api/openai-responses-shared.ts
packages/ai/src/api/openai-responses.ts
packages/ai/src/api/simple-options.ts
packages/ai/src/auth/credential-store.ts
packages/ai/src/auth/helpers.ts
packages/ai/src/auth/oauth/anthropic.ts
packages/ai/src/auth/oauth/device-code.ts
packages/ai/src/auth/oauth/github-copilot.ts
packages/ai/src/auth/oauth/kimi-coding.ts
packages/ai/src/auth/oauth/openai-codex.ts
packages/ai/src/auth/oauth/openrouter.ts
packages/ai/src/auth/oauth/radius.ts
packages/ai/src/auth/oauth/xai.ts
packages/ai/src/auth/resolve.ts
packages/ai/src/auth/types.ts
packages/ai/src/cli.ts
packages/ai/src/env-api-keys.ts
packages/ai/src/image-models.generated.ts
packages/ai/src/images-models.ts
packages/ai/src/models-store.ts
packages/ai/src/models.generated.ts
packages/ai/src/models.ts
packages/ai/src/providers/all.ts
packages/ai/src/providers/amazon-bedrock.ts
packages/ai/src/providers/anthropic.ts
packages/ai/src/providers/baseten.models.ts
packages/ai/src/providers/baseten.ts
packages/ai/src/providers/cloudflare-auth.ts
packages/ai/src/providers/faux.ts
packages/ai/src/providers/github-copilot.ts
packages/ai/src/providers/google-vertex.ts
packages/ai/src/providers/kimi-coding.ts
packages/ai/src/providers/openai-codex.ts
packages/ai/src/providers/opencode-go.ts
packages/ai/src/providers/radius.ts
packages/ai/src/providers/xai.ts
packages/ai/src/types.ts
packages/ai/src/utils/abort.ts
packages/ai/src/utils/error-body.ts
packages/ai/src/utils/overflow.ts
packages/ai/src/utils/validation.ts
packages/ai/test/abort.test.ts
packages/ai/test/anthropic-adaptive-thinking-models.test.ts
packages/ai/test/anthropic-auth-token.test.ts
packages/ai/test/anthropic-oauth.test.ts
packages/ai/test/anthropic-sse-parsing.test.ts
packages/ai/test/baseten-models.test.ts
packages/ai/test/bedrock-error-metadata.test.ts
packages/ai/test/context-overflow.test.ts
packages/ai/test/cross-provider-handoff.test.ts
packages/ai/test/deferred-tools.test.ts
packages/ai/test/empty.test.ts
packages/ai/test/error-body.test.ts
packages/ai/test/fireworks-models.test.ts
packages/ai/test/github-copilot-oauth.test.ts
packages/ai/test/google-shared-gemini3-unsigned-tool-call.test.ts
packages/ai/test/google-shared-retry.test.ts
packages/ai/test/google-shared-signed-empty-blocks.test.ts
packages/ai/test/image-tool-result.test.ts
packages/ai/test/kimi-coding-oauth.test.ts
packages/ai/test/model-catalog-types.test.ts
packages/ai/test/models-runtime.test.ts
packages/ai/test/oauth-auth.test.ts
packages/ai/test/oauth-device-code.test.ts
packages/ai/test/oauth.ts
packages/ai/test/openai-codex-oauth.test.ts
packages/ai/test/openai-codex-stream.test.ts
packages/ai/test/openai-completions-prompt-cache.test.ts
packages/ai/test/openai-completions-thinking-as-text.test.ts
packages/ai/test/openai-completions-thinking-token-budget.test.ts
packages/ai/test/openai-completions-tool-choice.test.ts
packages/ai/test/openai-completions-tool-result-images.test.ts
packages/ai/test/openai-responses-terminal-event.test.ts
packages/ai/test/openrouter-oauth.test.ts
packages/ai/test/overflow.test.ts
packages/ai/test/providers.test.ts
packages/ai/test/qwen-token-plan-models.test.ts
packages/ai/test/radius-oauth.test.ts
packages/ai/test/sampling-options.test.ts
packages/ai/test/stream.test.ts
packages/ai/test/telemetry-options.test.ts
packages/ai/test/tokens.test.ts
packages/ai/test/tool-call-without-result.test.ts
packages/ai/test/total-tokens.test.ts
packages/ai/test/unicode-surrogate.test.ts
packages/ai/test/validation.test.ts
packages/ai/test/xai-oauth.test.ts
packages/ai/vitest.config.ts
```

The detailed disposition matrix is in [`docs/upstream-v0.84.0-audit.md`](docs/upstream-v0.84.0-audit.md).

## Exact catalog parity

Generated from exact upstream tag `a5f43bf8aff3c55752432655f7334e3dafd1e256`; live main was not chased.

Text catalog:

- Swift source snapshot: `scripts/models.v0.84.0.json`
- Exact upstream comparator source: `scripts/upstream-models.a5f43bf.json`
- Embedded Swift registry: `Sources/SwiftAI/ModelsGenerated.swift`
- Provider/id pairs: `1153/1153`
- Providers: `38`
- APIs: `9`

Image catalog:

- Swift source snapshot: `scripts/image-models.v0.84.0.json`
- Exact upstream comparator source: `scripts/upstream-image-models.a5f43bf.json`
- Embedded Swift registry: `Sources/SwiftAI/ImageModelsGenerated.swift`
- Provider/id pairs: `42/42`
- Providers: `1`
- APIs: `1`

Comparator gate:

```bash
python3 scripts/audit-parity.py
```

Expected output includes:

```text
ok: 1153 text models / 38 providers / 9 APIs; 42 image models / 1 providers / 1 APIs
```

## Swift implementation, adaptations, and N/A decisions

### Implemented

- Regenerated v0.84.0 text and image catalogs from the exact upstream tag.
- Added Baseten provider metadata and `BASETEN_API_KEY` environment lookup.
- Added `Model.samplingParams` and `StreamOptions.samplingParams`.
- OpenAI Completions and OpenAI Responses/Azure/Codex builders merge model sampling defaults with per-request overrides.
- Added `OpenAICompletionsCompat.supportsThinkingTokenBudget` and OpenAI Completions `thinking_token_budget` emission/clamping for vLLM-compatible providers.
- Ported v0.84 nullable union validation in `ContextUtilities.validateAndCoerce`: existing union-arm matches are preserved and non-matching values are coerced through `anyOf`/`oneOf` arms.
- Added a bounded Swift-native Bedrock failure metadata surface (`BedrockFailureMetadata` / `bedrock_response_failure`) for modeled send errors, modeled/unmodeled mid-stream errors, transport-name filtering, abort suppression, overlong value dropping, and `Unknown` placeholder omission.
- Added public deferred/background lifecycle support: `DeferredHandle`, `DeferredRequestOptions`, `StopReason.deferred`, `Message.deferred`, provider `fetchDeferred`/`cancelDeferred`, and `SwiftAI.fetchDeferred`/`SwiftAI.cancelDeferred`.
- Added deterministic `FauxProvider` deferred lifecycle support and tests for submit → pending → ready, failed fetch, cancel/cancelled, `pollAfterMs`, state counters, authenticated dispatch, and unsupported capability errors.
- Added Swift-native `TelemetryContext` on `StreamOptions` and `ImagesOptions`, with propagation tests through stream, simple stream, deferred fetch/cancel, and images.
- Added public nullable `ProviderHeaders` (`[String: String?]`) for `Model.headers`, `StreamOptions.headers`, `ImagesModel.headers`, and `ImagesOptions.headers`; production provider request builders now use `AIUtilities.applyProviderHeaders` so null deletion markers remove default/model headers case-insensitively.
- Added a production OpenAI Responses request test proving a default/model Authorization header is deleted while unrelated headers remain.
- Added cancellation-aware OAuth refresh protocol and registry path (`refreshToken(credentials:cancellation:)`), provider `Task.checkCancellation()` pre/post network awaits, pre-cancel and mid-refresh tests, and preserved typed/cause errors for non-cancellation failures.
- Added `ModelRuntime.refresh(force:)` cancellation/supersession test and documented runtime API-key refresh separation from OAuth token refresh.
- Replaced the v0.84 audit appendix with path-addressable evidence for all 101 changed paths and added/updated the exact 46 changed-test assertion matrix.
- Retained v0.83 raw stop reason, missing-finish, custom-tool, and terminal-status fixes.
- Added OAuth minimum-validity semantics: effective window is `max(300s, override)`, and explicit stricter overrides are enforced after refresh.
- Added representative v0.84 Baseten, Qwen Token Plan, and image catalog tests.

### Existing Swift equivalents / adaptations

- Upstream JS `fetch` injection maps to Swift's existing typed transport/request seams (`requestTransport`, `BedrockTransport`, `CodexTransport`, `onPayload`, `onResponse`).
- Provider model refresh publication maps to Swift's actor-backed `ModelRuntime`/`AIRegistry` replacement flow; forced model refresh cancels/supersedes older in-flight work and remains separate from OAuth token refresh in `OAuthRegistry`.
- Upstream JS `telemetryContext` threading is represented by a Swift-native typed `TelemetryContext` value that propagates through stream/deferred/image options.
- Swift preserves structured concurrency, AsyncSequence stream handling, typed errors, and actor/sendability boundaries instead of mirroring JS SDK internals.

### N/A decisions

- Direct JS `fetch` callback API is not mirrored as a Swift option because Swift uses typed pluggable transports and URLSession request paths.
- Bedrock credential/profile priority remains transport-owned in Swift because SwiftPM core does not implement AWS SigV4 credential sourcing.
- Vitest/CLI/package runner changes are monorepo-only.

## Tests and gates

Local validation for v0.84.0 parity work used Swift `6.3.2`:

```bash
swift build -Xswiftc -warnings-as-errors
swift test
for i in 1 2 3; do swift test; done
make check
python3 scripts/audit-parity.py
python3 scripts/static-check.py
grep -R "XCTSkip" -n Tests || true
```

Latest local results before this commit:

- `swift test`: `228` tests, `0` failures.
- deterministic `swift test` ×3: passed (`228` tests each run).
- `make check`: passed.
- `scripts/audit-parity.py`: passed with exact v0.84.0 counts.
- `scripts/static-check.py`: passed.
- hidden skip scan: no `XCTSkip` matches.

Latest GitHub Actions before this corrective commit:

- Run: <https://github.com/rcarmo/swift-ai/actions/runs/31108725910>
- Commit: `fa33169cc030bf0fa169388ed90ab8407b9bf9ba`
- Jobs:
  - `static-check`: success
  - `swift-test (ubuntu-latest)`: success
  - `swift-test (macos-14)`: success

Fresh GitHub Actions evidence for this corrective commit must be captured from the pushed commit and reported with the final handoff.

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
