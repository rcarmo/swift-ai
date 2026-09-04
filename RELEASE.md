# Release parity record

This file is the durable release-audit ledger for `swift-ai`. It must be updated as part of every future upstream `@earendil-works/pi-ai` release parity commit before the work is reported complete.

## Current upstream parity baseline

- Upstream package: `@earendil-works/pi-ai`
- Current upstream release: `v0.85.0`
- Current upstream tag commit: `107d79f11072bbc8a3a757ed7fd69596bee7d68c`
- Published: `2026-09-04T10:13:48.137Z`
- Previous accepted upstream release: `v0.84.4`
- Previous accepted upstream tag commit: `b79e4cc834970cca69daebffab7df1da7d1e52c4`
- Previous accepted Swift baseline: `61849874ea9b45c54caa7d6bbe10c7addcc72d5e`
- Verified npm artifact SHA-256: `46188bdacb555a07466a0111f3963f20932a16199e4d6cfb8d44a7fe5fc6e342`
- Verified npm artifact SHA-512: `09b79e647dcd1dabfb46cd7cdad62ad1ea020167c377532f3805cace89c8178b8ddee3bdf4407c893d477f21a87c998f9007fc31e23038142daaa774ce0acf58`
- Swift parity branch: `main`
- Current Swift parity commit for v0.85.0: this release update commit; final SHA and CI run are reported after push.

## Exact upstream delta

Release-only audit scope: `packages/ai` diff from `b79e4cc834970cca69daebffab7df1da7d1e52c4` to `107d79f11072bbc8a3a757ed7fd69596bee7d68c`.

Exact changed-path count: **51**. Changed-path manifest hash: `db461a56838926cf60d4ae0196ed98fcc215616dacff013ad8c235bb8ad9b83f`.

Changed path classes: source/scripts **19** (`16M/2A/1D`), tests **29** (`22M/6A/1D`), package/docs **3**.

Final upstream test corpus: **142** files. Corpus manifest hash: `56f8742065a4ad01d73e5aee53035324f2e7333a735222ab15db870819e29065`.

The detailed disposition matrix is in [`docs/upstream-v0.85.0-audit.md`](docs/upstream-v0.85.0-audit.md). The cumulative whole-corpus test crosswalk is in [`docs/upstream-v0.85.0-test-crosswalk.md`](docs/upstream-v0.85.0-test-crosswalk.md).

## Exact catalog parity

Text catalog:

- Swift source snapshot: `scripts/models.v0.85.0.json`
- Exact upstream comparator source: `scripts/upstream-models.107d79f.json`
- Embedded Swift registry: `Sources/SwiftAI/Models/Generated/ModelsGenerated.swift`
- Full records: `1336/1336`
- Providers: `39`
- APIs: `9`
- Full-record delta vs committed v0.84.4 snapshot: `+72/-26/79 changed`

Image catalog:

- Swift source snapshot: `scripts/image-models.v0.85.0.json`
- Exact upstream comparator source: `scripts/upstream-image-models.107d79f.json`
- Embedded Swift registry: `Sources/SwiftAI/Models/Generated/ImageModelsGenerated.swift`
- Full records: `50/50`
- Providers: `1`
- APIs: `1`
- Full-record delta vs committed v0.84.4 snapshot: `+0/-0/0 changed`

Expected comparator output:

```text
ok: 1336 text models / 39 providers / 9 APIs; 50 image models / 1 providers / 1 APIs; text delta +72/-26/79 changed; image delta +0/-0/0 changed
```

## Swift implementation, adaptations, and N/A decisions

Implemented/adapted:

- Regenerated v0.85.0 text and image catalogs from the verified npm artifact.
- Extended full-record audit/self-test gates to v0.85.0 text and image deltas.
- Added Swift `providerThinkingLevel` message metadata plus assistant-message frame encoder and reducer surfaces, including legacy grammar JSON-prefix checkpoints and explicit invalid-order/kind/end invariants.
- Ported Anthropic mid-conversation effort metadata: beta headers, adaptive output config, providerThinkingLevel propagation, final `input_transformations` diagnostics, and fallback marker handling; live Anthropic thinking-binding E2E remains credential-gated and not faked.
- Ported OpenAI Responses `supportsMaxOutputTokens` payload omission/clamping, terminal stale-error cleanup with `incomplete_details.reason` mapping, and OpenAI-compatible vLLM priority serialization.
- Preserved OpenAI-compatible reasoning-detail merge/replay, custom deltas, tool-choice, tool-result images, parser/error/usage behavior through existing production tests.
- Ported UUIDv7 timestamp extraction and expanded NO_PROXY matching for wildcard, leading-dot, IPv6, and host:port entries.
- Adapted Cloudflare AI binding replacement: SwiftPM has no Workers binding object, but generated Cloudflare catalog/routing/base URL behavior and request builders remain covered.
- Updated catalog representatives for xAI, Qwen Token Plan Individual, OpenRouter, Baseten, routing fixes, and generated model deltas.

N/A/adapted:

- JS package docs/changelog/package version mechanics are recorded in this ledger and `STATUS.json`.
- Generator implementation changes are represented by exact generated Swift snapshots and full-record text/image comparator/self-test gates.
- Cloudflare Workers AI binding object replacement is JS runtime-specific; Swift covers portable catalog/routing/request behavior.
- Live/provider credential matrices remain classified in the crosswalk and are not faked.

## Tests and gates

Local validation for v0.85.0 parity work uses Swift `6.3.2`:

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
- focused v0.85.0 tests: passed for assistant frame encoder/reducer state-machine behavior, legacy grammar prefix checkpoints, frame invariant/purity coverage, UUID timestamp, NO_PROXY, Anthropic mid-conversation effort/providerThinkingLevel, Anthropic input transformation/fallback handling, Responses max output-token support, Responses terminal stale-error/incomplete mappings, and vLLM priority.
- `swift test`: `271` tests, `0` failures.
- deterministic `swift test` ×3: passed (`271` tests each run).
- `make check`: passed (`271` tests, `0` failures).
- `scripts/audit-parity.py`: passed with exact v0.85.0 full-record counts and text/image deltas.
- `scripts/audit-parity.py --self-test`: passed, text/image metadata fault injections and unchanged-image baseline corruption caught.
- `scripts/static-check.py`: passed, including text/image mutation self-test.
- `make sbom-check`: passed with CycloneDX, SwiftPM graph, OSV, waiver self-tests, and license review.
- exact v0.85.0 manifest validation: passed for 51 changed-path rows/hash and 142 test-corpus rows/hash; audit/crosswalk row counts are validator-enforced.
- clean checkout validation: passed warnings-as-errors build, `swift test`, static check, SBOM/OSV/license checks, diff check, and hidden-skip scan.
- hidden skip scan: no `XCTSkip` matches.
- Hosted Ubuntu/static CI must be captured after push and reported with the final handoff.

## SBOM/security evidence model

- SBOM tool/version: `swift-ai-sbom` `1.1.0` (pinned local policy `scripts/sbom-policy.json`) plus pinned OSV Scanner `2.5.1`.
- SBOM SHA-256 for the accepted candidate is generated from exact `git rev-parse HEAD`; for dirty local candidates the SBOM records `git.dirty=true` and must be regenerated after commit before final evidence is reported.
- SBOM provenance/dependency graph: root package records exact Git revision and `Package.resolved`; dependency edges are derived from `swift package show-dependencies --format json` as root `swift-ai` → direct `swift-crypto` → transitive `swift-asn1`.
- SBOM scan/license disposition: real OSV Scanner JSON output is written to `.artifacts/sbom/osv-scanner.json`; high/critical findings fail unless covered by non-expired structured waivers (`id`, `owner`, `rationale`, `mitigation`, `expires`).
- SBOM artifact retention: final Ubuntu CI uploads SBOM, checksum, OSV output, scan summary, and license review artifacts with 30-day retention.
- Dependency-lock policy: `Package.resolved` is tracked and required for SBOM generation/validation; volatile SBOM output under `.artifacts/` is not committed.

## Prior accepted v0.84.4 evidence

Final v0.84.4 release docs HEAD: `ed03aa02239f28ab59e7c0874518a1377eeca688`.

Final v0.84.4 runtime/catalog commit: `015543adb6bf7fb54348f0c0a3d14146ee94c28f`.

Final source-tree/SBOM baseline before v0.85.0: `61849874ea9b45c54caa7d6bbe10c7addcc72d5e`.

- Release run: <https://github.com/rcarmo/swift-ai/actions/runs/33251959680>
- Source-tree/SBOM run: <https://github.com/rcarmo/swift-ai/actions/runs/33258310597>
- Status: `completed`
- Conclusion: `success`
- Routine hosted CI: Ubuntu/static only; macOS disabled after policy update.

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
