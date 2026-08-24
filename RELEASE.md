# Release parity record

This file is the durable release-audit ledger for `swift-ai`. It must be updated as part of every future upstream `@earendil-works/pi-ai` release parity commit before the work is reported complete.

## Current upstream parity baseline

- Upstream package: `@earendil-works/pi-ai`
- Current upstream release: `v0.84.3`
- Current upstream tag commit: `4e58f324fae8ebfa98a3d45181fb248072a2afac`
- Previous accepted upstream release: `v0.84.2`
- Previous accepted upstream tag commit: `914cf1472e715297caa30db4b9535d534a9eb718`
- Previous accepted Swift baseline: `a0d7277982b5725e93a3a8eb71e4ae7b4be8dbff`
- Verified npm artifact SHA-256: `9c40af2f43950f8e94e7bbcd0c1b3548f000972da00c4fb9c0d0529d4d7d5431`
- Swift parity branch: `main`
- Current Swift parity commits for v0.84.3:
  - `663467a106896c9f8fa3796e393d1996eab1f5ff` — `Sync upstream v0.84.3 parity`
  - `57f96f6c56462d1875c4e8f5a6a0c04f9c6d36ec` — `Close v0.84.3 Copilot policy gaps`
  - `e9735bc0116e69909764f0f4b53f4304188d4bb7` — `Close v0.84.3 final transport gaps`
  - `3cd3a869845310a0f9a3970a904e8ff76ca4d22e` — `Close v0.84.3 Copilot rate-limit semantics`

## Exact upstream delta

Release-only audit scope: `packages/ai` diff from `914cf1472e715297caa30db4b9535d534a9eb718` to `4e58f324fae8ebfa98a3d45181fb248072a2afac`.

Exact changed-path count: **48**.

Changed test paths: **25** total = **20 modified + 5 new** (`azure-openai-tool-choice.test.ts`, `bedrock-redacted-reasoning.test.ts`, `bedrock-response-headers.test.ts`, `google-thinking-level-map.test.ts`, `zai-coding-plan-models.test.ts`).

The detailed disposition matrix is in [`docs/upstream-v0.84.3-audit.md`](docs/upstream-v0.84.3-audit.md). The cumulative whole-corpus test crosswalk is in [`docs/upstream-v0.84.3-test-crosswalk.md`](docs/upstream-v0.84.3-test-crosswalk.md) and covers all **136** upstream `packages/ai/test/*.test.ts` files.

## Exact catalog parity

Text catalog:

- Swift source snapshot: `scripts/models.v0.84.3.json`
- Exact upstream comparator source: `scripts/upstream-models.4e58f32.json`
- Embedded Swift registry: `Sources/SwiftAI/ModelsGenerated.swift`
- Full records: `1312/1312`
- Providers: `39`
- APIs: `9`
- Full-record delta vs committed v0.84.2 snapshot: `+81/-36/88 changed`

Image catalog:

- Swift source snapshot: `scripts/image-models.v0.84.3.json`
- Exact upstream comparator source: `scripts/upstream-image-models.4e58f32.json`
- Embedded Swift registry: `Sources/SwiftAI/ImageModelsGenerated.swift`
- Full records: `45/45`
- Providers: `1`
- APIs: `1`
- Full-record delta vs committed v0.84.2 snapshot: `+0/0/0 changed`

Expected comparator output:

```text
ok: 1312 text models / 39 providers / 9 APIs; 45 image models / 1 providers / 1 APIs; text delta +81/-36/88 changed; image delta +0/-0/0 changed
```

## Swift implementation, adaptations, and N/A decisions

Implemented/adapted:

- Regenerated v0.84.3 text and image catalogs from the verified npm artifact.
- Extended full-record audit/self-test gates to v0.84.3 text and image deltas.
- Added provider-neutral `toolChoice` forwarding for Responses/Azure/Pi and retained OpenAI-compatible support.
- Added default Pi `User-Agent` across HTTP adapters with explicit header override support.
- Added Anthropic server-side fallback request/beta metadata and fallback compatibility metadata decoding.
- Preserved/adapted Bedrock redacted reasoning/replay and raw response headers through pluggable transport/onResponse seams, including fake production-transport streaming coverage.
- Added Google thinking level mapping and configurable token budgets.
- Preserved OpenAI-compatible configurable thinking budgets and reasoning-details replay.
- Updated built-in xAI catalog to Responses/Grok 4.6/default endpoint/reasoning/UA behavior through exact catalog and actual transport request tests.
- Preserved Copilot throttling/retry/policy-update/login budget/persistence via bounded structured concurrency and cancellation-aware sleep/retry evidence, including policy POST retry/failure continuation and stop-after-exhausted-rate-limit semantics without blocking credential persistence.
- Added ZAI Coding Plan China/global and DeepSeek V4 Pro 0813 generated compatibility.

N/A/adapted:

- JS package docs/exports/lazy module mechanics are not SwiftPM runtime behavior.
- Live/provider credential matrices remain classified in the crosswalk and are not faked.

## Tests and gates

Local validation for v0.84.3 parity work uses Swift `6.3.2`:

```bash
swift build -Xswiftc -warnings-as-errors
swift test
for i in 1 2 3; do swift test; done
make check
python3 scripts/audit-parity.py
python3 scripts/audit-parity.py --self-test
python3 scripts/static-check.py
grep -R "XCTSkip" -n Tests || true
```

Latest local results before this commit:

- `swift build -Xswiftc -warnings-as-errors`: passed.
- focused v0.84.3 correction tests: passed, including Copilot policy catalog/retry filtering, policy POST retry/failure continuation, stop-after-exhausted-rate-limit semantics, HTTP-date `Retry-After`, post-auth credential persistence, Grok 4.6 actual transport assertions, and fake Bedrock transport redacted-reasoning/header streaming.
- `swift test`: `256` tests, `0` failures.
- deterministic `swift test` ×3: passed (`256` tests each run).
- `make check`: passed (`256` tests, `0` failures).
- `scripts/audit-parity.py`: passed with exact v0.84.3 full-record counts and text/image deltas.
- `scripts/audit-parity.py --self-test`: passed, text and image metadata fault injections caught.
- `scripts/static-check.py`: passed, including self-test.
- hidden skip scan: no `XCTSkip` matches.

GitHub Actions evidence for final v0.84.3 runtime commit `3cd3a869845310a0f9a3970a904e8ff76ca4d22e`:

- Run: <https://github.com/rcarmo/swift-ai/actions/runs/32770344240>
- Status: `completed`
- Conclusion: `success`
- Jobs:
  - `static-check`: success
  - `swift-test (ubuntu-latest)`: success
  - `swift-test (macos-14)`: success

Prior implementation evidence for `663467a106896c9f8fa3796e393d1996eab1f5ff`:

- Run: <https://github.com/rcarmo/swift-ai/actions/runs/32761084973>
- Status: `completed`
- Conclusion: `success`
- Jobs:
  - `static-check`: success
  - `swift-test (ubuntu-latest)`: success
  - `swift-test (macos-14)`: success

## Future release-audit checklist

1. Pin the exact upstream tag and SHA.
2. Diff only from the last accepted upstream tag to the new official tag.
3. Record exact changed path count and disposition matrix.
4. Regenerate text and image snapshots from the exact tag/artifact.
5. Update comparator sources and expected counts/deltas.
6. Implement all applicable Swift production deltas with executable tests.
7. Document every adaptation and N/A decision here and in the per-release audit doc.
8. Run local gates and require green GitHub Actions on Ubuntu, macOS, and static-check.
9. Commit/push cleanly as Rui Carmo.
