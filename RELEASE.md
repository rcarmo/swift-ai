# Release parity record

This file is the durable release-audit ledger for `swift-ai`. It must be updated as part of every future upstream `@earendil-works/pi-ai` release parity commit before the work is reported complete.

## Current upstream parity baseline

- Upstream package: `@earendil-works/pi-ai`
- Current upstream release: `v0.84.1`
- Current upstream tag commit: `53fa77ccd8a279eb87e92294ef3687b03ff80112`
- Previous accepted upstream release: `v0.84.0`
- Previous accepted upstream tag commit: `a5f43bf8aff3c55752432655f7334e3dafd1e256`
- Previous accepted Swift baseline: `80366a574649a64350baabc9b31c093a36f3a904`
- Swift parity branch: `main`
- Current Swift parity commit for v0.84.1: this release update commit (exact SHA/CI run to be reported after GitHub verifies it).
- Last accepted v0.84.0 CI: <https://github.com/rcarmo/swift-ai/actions/runs/31133380351>

## Exact upstream delta

Release-only audit scope: `packages/ai` diff from `a5f43bf8aff3c55752432655f7334e3dafd1e256` to `53fa77ccd8a279eb87e92294ef3687b03ff80112`.

Exact changed-path count: **25**.

Changed paths:

```text
packages/ai/CHANGELOG.md
packages/ai/README.md
packages/ai/package.json
packages/ai/scripts/generate-models.ts
packages/ai/scripts/model-data.ts
packages/ai/src/env-api-keys.ts
packages/ai/src/models.generated.ts
packages/ai/src/providers/all.ts
packages/ai/src/providers/qwen-token-plan-individual.models.ts
packages/ai/src/providers/qwen-token-plan-individual.ts
packages/ai/src/types.ts
packages/ai/test/abort.test.ts
packages/ai/test/context-overflow.test.ts
packages/ai/test/cross-provider-handoff.test.ts
packages/ai/test/empty.test.ts
packages/ai/test/generate-models-strict.test.ts
packages/ai/test/image-tool-result.test.ts
packages/ai/test/model-data-validation.test.ts
packages/ai/test/openai-completions-tool-choice.test.ts
packages/ai/test/qwen-token-plan-models.test.ts
packages/ai/test/stream.test.ts
packages/ai/test/tokens.test.ts
packages/ai/test/tool-call-without-result.test.ts
packages/ai/test/total-tokens.test.ts
packages/ai/test/unicode-surrogate.test.ts
```

The detailed disposition matrix is in [`docs/upstream-v0.84.1-audit.md`](docs/upstream-v0.84.1-audit.md). The cumulative whole-corpus test crosswalk is in [`docs/upstream-v0.84.1-test-crosswalk.md`](docs/upstream-v0.84.1-test-crosswalk.md) and covers all **128** upstream `packages/ai/test/*.test.ts` files. The v0.84.1 changed-test slice is exactly **14** paths total: **13 existing tests modified + 1 new `generate-models-strict.test.ts`**.

## Exact catalog parity

Generated from exact upstream tag `53fa77ccd8a279eb87e92294ef3687b03ff80112`; live main was not chased.

Text catalog:

- Swift source snapshot: `scripts/models.v0.84.1.json`
- Exact upstream comparator source: `scripts/upstream-models.53fa77c.json`
- Embedded Swift registry: `Sources/SwiftAI/ModelsGenerated.swift`
- Provider/id pairs: `1220/1220`
- Providers: `39`
- APIs: `9`

Image catalog:

- Swift source snapshot: `scripts/image-models.v0.84.1.json`
- Exact upstream comparator source: `scripts/upstream-image-models.53fa77c.json`
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
ok: 1220 text models / 39 providers / 9 APIs; 42 image models / 1 providers / 1 APIs
```

## Swift implementation, adaptations, and N/A decisions

### Implemented

- Regenerated v0.84.1 text catalog from the exact upstream npm/tag artifact and updated the embedded Swift registry to `1220` models / `39` providers.
- Added `Provider.qwenTokenPlanIndividual` for upstream `qwen-token-plan-individual`.
- Added provider environment lookup for Individual via shared international Token Plan credentials: `QWEN_TOKEN_PLAN_API_KEY` first, then `DASHSCOPE_API_KEY` fallback.
- Ported Qwen Token Plan Individual provider semantics:
  - OpenAI Completions API.
  - Singapore Token Plan base URL: `https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1`.
  - Exact seven-model text-only allowlist: `deepseek-v4-flash-0731`, `deepseek-v4-pro`, `glm-5.2`, `qwen3.6-flash`, `qwen3.7-max`, `qwen3.7-plus`, `qwen3.8-max`.
  - Retired `qwen3.8-max-preview` and image model IDs are excluded.
- Ported the v0.84.1 Qwen request-body behavior by emitting `enable_thinking` for Qwen-format OpenAI Completions models and `reasoning_effort` when `supportsReasoningEffort` is true.
- Added deterministic Swift tests for Individual catalog/env metadata and Qwen request payloads, including qwen3.8 `xhigh` mapping.
- Added `docs/upstream-v0.84.1-test-crosswalk.md` with the exact 128-file upstream test manifest and updated disposition counts (`ported: 103`, `adapted: 8`, `live-only: 7`, `adapted/live-remainder: 10`, open items: 0).

### Existing Swift equivalents / adaptations

- Upstream strict generator tests map to Swift's exact source/comparator/embedded registry gate in `scripts/audit-parity.py` plus deterministic seven-model Individual assertions.
- Upstream package docs/version changes are recorded in `RELEASE.md`, `PARITY.md`, `STATUS.json`, and `docs/upstream-v0.84.1-audit.md`.
- The v0.84.1 modified live/provider tests retain the existing `live-only` or `adapted/live-remainder` classification where credentials or provider-specific live behavior are required; portable request/catalog behavior is covered deterministically.

### N/A decisions

- NPM package metadata and Vitest runner wiring are monorepo-only and have no SwiftPM runtime analogue.
- JS generated provider shard files map to Swift's single embedded `ModelsGenerated.swift` registry rather than one Swift file per provider.

## Tests and gates

Local validation for v0.84.1 parity work uses Swift `6.3.2`:

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

- `swift build -Xswiftc -warnings-as-errors`: passed.
- `swift test`: `236` tests, `0` failures.
- deterministic `swift test` ×3: passed (`236` tests each run).
- `make check`: passed (`236` tests, `0` failures).
- `scripts/audit-parity.py`: passed with exact v0.84.1 counts.
- `scripts/static-check.py`: passed.
- hidden skip scan: no `XCTSkip` matches.

Fresh GitHub Actions evidence for this release commit must be captured from the pushed commit and reported with the final handoff.

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
