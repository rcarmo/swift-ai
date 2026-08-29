# Release parity record

This file is the durable release-audit ledger for `swift-ai`. It must be updated as part of every future upstream `@earendil-works/pi-ai` release parity commit before the work is reported complete.

## Current upstream parity baseline

- Upstream package: `@earendil-works/pi-ai`
- Current upstream release: `v0.84.4`
- Current upstream tag commit: `b79e4cc834970cca69daebffab7df1da7d1e52c4`
- Published: `2026-08-28T22:05:13.974Z`
- Previous accepted upstream release: `v0.84.3`
- Previous accepted upstream tag commit: `4e58f324fae8ebfa98a3d45181fb248072a2afac`
- Previous accepted Swift runtime: `3cd3a869845310a0f9a3970a904e8ff76ca4d22e`
- Previous accepted Swift docs HEAD: `92d5c47f18deed495ecd6752966fb704047e8099`
- Verified npm artifact SHA-256: `dfd3c929cee5a7387199a0a24dfc1be2096f1ea8f59ffb8285198a0ed01ebf93`
- Swift parity branch: `main`
- Current Swift parity commit for v0.84.4:
  - `015543adb6bf7fb54348f0c0a3d14146ee94c28f` — `Sync upstream v0.84.4 parity`

## Exact upstream delta

Release-only audit scope: `packages/ai` diff from `4e58f324fae8ebfa98a3d45181fb248072a2afac` to `b79e4cc834970cca69daebffab7df1da7d1e52c4`.

Exact changed-path count: **15**.

Changed test paths: **6** total = **5 modified + 1 added** (`fireworks-models.test.ts`, `mistral-http-transport.test.ts`, `openai-completions-reasoning-details.test.ts`, `openai-completions-tool-choice.test.ts`, `zai-coding-plan-models.test.ts`, plus added `openrouter-reasoning-options.test.ts`).

The detailed disposition matrix is in [`docs/upstream-v0.84.4-audit.md`](docs/upstream-v0.84.4-audit.md). The cumulative whole-corpus test crosswalk is in [`docs/upstream-v0.84.4-test-crosswalk.md`](docs/upstream-v0.84.4-test-crosswalk.md) and covers all **137** upstream `packages/ai/test/*.test.ts` files.

## Exact catalog parity

Text catalog:

- Swift source snapshot: `scripts/models.v0.84.4.json`
- Exact upstream comparator source: `scripts/upstream-models.b79e4cc.json`
- Embedded Swift registry: `Sources/SwiftAI/ModelsGenerated.swift`
- Full records: `1290/1290`
- Providers: `39`
- APIs: `9`
- Full-record delta vs committed v0.84.3 snapshot: `+57/-79/227 changed`

Image catalog:

- Swift source snapshot: `scripts/image-models.v0.84.4.json`
- Exact upstream comparator source: `scripts/upstream-image-models.b79e4cc.json`
- Embedded Swift registry: `Sources/SwiftAI/ImageModelsGenerated.swift`
- Full records: `50/50`
- Providers: `1`
- APIs: `1`
- Full-record delta vs committed v0.84.3 snapshot: `+5/-0/0 changed`

Expected comparator output:

```text
ok: 1290 text models / 39 providers / 9 APIs; 50 image models / 1 providers / 1 APIs; text delta +57/-79/227 changed; image delta +5/-0/0 changed
```

## Swift implementation, adaptations, and N/A decisions

Implemented/adapted:

- Regenerated v0.84.4 text and image catalogs from the verified npm artifact.
- Extended full-record audit/self-test gates to v0.84.4 text and image deltas.
- Added exact generated catalog coverage for Cloudflare Gateway `workers-ai/` `/compat` mirror entries, ZAI GLM-5.3 cost metadata, Fireworks removal, DeepSeek V4 Flash Vision Exp, and OpenRouter image additions.
- OpenAI-compatible Chat Completions now serializes explicit `toolChoice`, including `"none"`, even when no tools are present.
- OpenAI-compatible streaming now merges adjacent `reasoning.text` and `reasoning.summary` reasoning-detail deltas while preserving metadata/order, then replays them exactly once through `reasoning_details` from the thinking signature.
- Mistral fragmented indexed tool-call chunks now merge when later chunks omit tool-call ID and carry an empty function name.
- OpenRouter `supported_efforts` metadata is represented as Swift `thinkingLevelMap`, with mandatory/optional/off semantics and request payload omission/`none`/explicit effort behavior covered by tests.

N/A/adapted:

- JS package docs/changelog/package version mechanics are recorded in this ledger and `STATUS.json`.
- Generator implementation changes are represented by exact generated Swift snapshots and full-record text/image comparator/self-test gates.
- Live/provider credential matrices remain classified in the crosswalk and are not faked.

## Tests and gates

Local validation for v0.84.4 parity work uses Swift `6.3.2`:

```bash
swift build -Xswiftc -warnings-as-errors
swift test
for i in 1 2 3; do swift test; done
make check
make sbom-check
python3 scripts/audit-parity.py
python3 scripts/audit-parity.py --self-test
python3 scripts/static-check.py
grep -R "XCTSkip" -n Tests || true
```

Latest local results before this commit:

- `swift build -Xswiftc -warnings-as-errors`: passed.
- focused v0.84.4 correction tests: passed for explicit no-tools `toolChoice`, OpenAI-compatible reasoning-details merge/replay, Mistral fragmented tool-call merge, OpenRouter reasoning option semantics, and generated catalog metadata.
- `swift test`: `260` tests, `0` failures.
- deterministic `swift test` ×3: passed (`260` tests each run).
- `make check`: passed (`260` tests, `0` failures).
- `make sbom-check`: passed; generated `.artifacts/sbom/swift-ai.cdx.json` and `.artifacts/sbom/swift-ai.cdx.json.sha256`.
- SBOM tool/version: `swift-ai-sbom` `1.1.0` (pinned local policy `scripts/sbom-policy.json`) plus pinned OSV Scanner `2.5.1`.
- SBOM SHA-256 for the accepted candidate is generated from exact `git rev-parse HEAD`; for dirty local candidates the SBOM records `git.dirty=true` and must be regenerated after commit before final evidence is reported.
- SBOM provenance/dependency graph: root package records exact Git revision and `Package.resolved` resolution policy; dependency edges are derived from `swift package show-dependencies --format json` as root `swift-ai` → direct `swift-crypto` → transitive `swift-asn1`.
- SBOM scan/license disposition: real OSV Scanner JSON output is written to `.artifacts/sbom/osv-scanner.json`; high/critical findings fail unless covered by non-expired structured waivers (`id`, `owner`, `rationale`, `mitigation`, `expires`); license review passed for `swift-asn1` and `swift-crypto` under `Apache-2.0`.
- SBOM artifact retention: final Ubuntu CI uploads SBOM, checksum, OSV output, scan summary, and license review artifacts with 30-day retention.
- Dependency-lock policy: `Package.resolved` is tracked and required for SBOM generation/validation; volatile SBOM output under `.artifacts/` is not committed.
- `scripts/audit-parity.py`: passed with exact v0.84.4 full-record counts and text/image deltas.
- `scripts/audit-parity.py --self-test`: passed, text and image metadata fault injections caught.
- `scripts/static-check.py`: passed, including text/image mutation self-test.
- hidden skip scan: no `XCTSkip` matches.

Hosted GitHub Actions evidence for v0.84.4 runtime/catalog commit `015543adb6bf7fb54348f0c0a3d14146ee94c28f`:

- Run: <https://github.com/rcarmo/swift-ai/actions/runs/33251959680>
- Status: `completed`
- Conclusion: `success`
- Jobs:
  - `static-check`: success
  - `swift-test (ubuntu-latest)`: success
  - `swift-test (macos-14)`: success

## Prior accepted v0.84.3 evidence

Final v0.84.3 docs HEAD: `92d5c47f18deed495ecd6752966fb704047e8099`.

Final v0.84.3 runtime commit: `3cd3a869845310a0f9a3970a904e8ff76ca4d22e`.

- Run: <https://github.com/rcarmo/swift-ai/actions/runs/32770344240>
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
8. Run local gates and require green GitHub Actions on Ubuntu and static-check; macOS hosted CI is disabled for the foreseeable future.
9. Commit/push cleanly as Rui Carmo.
