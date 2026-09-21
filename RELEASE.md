# Release parity record

This file is the durable release-audit ledger for `swift-ai`. It must be updated as part of every future upstream `@earendil-works/pi-ai` release parity commit before the work is reported complete.

## Current upstream parity baseline

- Upstream package: `@earendil-works/pi-ai`
- Current upstream release: `v0.85.1`
- Current upstream tag commit: `d981de1229ef899957bbe968bc8dcda02a21f477`
- Published: `2026-09-05T12:05:47.996Z`
- Previous accepted upstream release: `v0.85.0`
- Previous accepted upstream tag commit: `107d79f11072bbc8a3a757ed7fd69596bee7d68c`
- Previous accepted Swift runtime baseline: `943861d656920758cdb77ce493b6b01c0a415c01`
- Previous accepted Swift README documentation commit: `40c823a064f83c676513e17926ebaa28c624228e`
- Previous accepted Swift evidence documentation commit: `7149ae964cec4adc869d89ef0137d7bf2669837c`
- Verified npm artifact SHA-256: `af7d11986179445ce6fe88b37d57de22f823c0ffd3a65cae31c555b7f5e99253`
- Verified npm artifact SHA-512: `f958152090e40ced9e7d824a104aaf3d31f8ce69c8697740a6919b3bebca140f6acb93dd8458807a7b8502453ea220927ce0b874c1c3cab8dd41e2f86680b909`
- Swift parity branch: `main`
- Current Swift parity runtime commit for v0.85.1: `b1192ff853ac5b312cc9dcef47b76e1c97ddc70f`.
- Runtime v0.85.1 accepted by CI run `35154754780`; README count updates and durable `upstream-v0.85.1` SBOM links are now documented.

## Exact upstream delta

Release-only audit scope: `packages/ai` diff from `107d79f11072bbc8a3a757ed7fd69596bee7d68c` to `d981de1229ef899957bbe968bc8dcda02a21f477`.

Exact changed-path count: **9**. Changed-path manifest hash: `ee26f669d92dc77b265731165a2ff69ccb67defba92517cbbd5f97a186e187d2`.

Changed path classes: source/scripts **6** (`6M`), tests **3** (`3M`), package/docs **2** included in source/scripts count as changelog/package metadata. Source delta: `+128/-23`.

Final upstream test corpus remains **142** files. Corpus manifest hash: `56f8742065a4ad01d73e5aee53035324f2e7333a735222ab15db870819e29065`. Changed-test manifest hash: `f7e274bf229c90fc22ba22384c5b89f71a5c6801f77067d099525a9cdc537610`.

The detailed disposition matrix is in [`docs/upstream-v0.85.1-audit.md`](docs/upstream-v0.85.1-audit.md). The cumulative whole-corpus test crosswalk is in [`docs/upstream-v0.85.1-test-crosswalk.md`](docs/upstream-v0.85.1-test-crosswalk.md).

## Exact catalog parity

Text catalog:

- Swift source snapshot: `scripts/models.v0.85.1.json`
- Exact upstream comparator source: `scripts/upstream-models.d981de1.json`
- Embedded Swift registry: `Sources/SwiftAI/Models/Generated/ModelsGenerated.swift`
- Full records: `1354/1354`
- Providers: `39`
- APIs: `9`
- Full-record delta vs committed v0.85.0 snapshot: `+20/-2/18 changed`

Image catalog:

- Swift source snapshot: `scripts/image-models.v0.85.1.json`
- Exact upstream comparator source: `scripts/upstream-image-models.d981de1.json`
- Embedded Swift image registry: `Sources/SwiftAI/Models/Generated/ImageModelsGenerated.swift`
- Full records: `52/52`
- Providers: `1`
- APIs: `1`
- Full-record delta vs committed v0.85.0 snapshot: `+2/-0/0 changed`

Expected comparator output:

```text
ok: 1354 text models / 39 providers / 9 APIs; 52 image models / 1 providers / 1 APIs; text delta +20/-2/18 changed; image delta +2/-0/0 changed
```

## Swift implementation, adaptations, and N/A decisions

Implemented/adapted:

- Regenerated v0.85.1 text and image catalogs from the verified npm artifact.
- Extended full-record audit/self-test gates to v0.85.1 text and image deltas, preserving exact current-vs-upstream and v0.85.0 baseline comparisons.
- Ported OpenAI Responses prompt-cache options: explicit `none` emits `prompt_cache_options: {"mode":"explicit"}`, supported `long` emits `{ "ttl": "30m" }`, and legacy models retain `prompt_cache_retention: "24h"` without concurrent options emission.
- Added GPT-6 Astra catalog/compat coverage across OpenAI, OpenAI Codex, Azure OpenAI Responses, OpenCode, OpenRouter, and Vercel AI Gateway aliases, including 272000 context, 128000 max output, text/image modality, 10/50/1/12.5 costs, long-tier pricing metadata, tool search/additional tools, and off/minimal/low/medium/high/xhigh/max thinking levels.
- Added MAI Image 2.6 and MAI Image 2.6 Flash OpenRouter image model coverage.
- Preserved all accepted v0.85.0 runtime behavior: strict assistant frame wire grammar, Anthropic input transformations/fallback handling, Responses stale-error cleanup, model runtime replacement, OAuth flows, and existing provider parsers.

N/A/adapted:

- JS package docs/changelog/package version mechanics are recorded in this ledger and `STATUS.json`.
- Generator implementation changes are represented by exact generated Swift snapshots and full-record text/image comparator/self-test gates.
- Live/provider credential matrices remain classified in the crosswalk and are not faked.

## Tests and gates

Local validation for v0.85.1 parity work uses Swift `6.3.2`:

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
- focused v0.87.0 tests: passed for generated registry metadata, v0.87.0 thinking-level catalog changes, and preserved v0.85.1 Responses/GPT-6 Astra coverage.
- `swift test`: `275` tests, `0` failures.
- deterministic `swift test` ×3: passed (`275` tests each run).
- `make check`: passed (`275` tests, `0` failures).
- `scripts/audit-parity.py`: passed with exact v0.87.0 full-record counts and text/image deltas.
- `scripts/audit-parity.py --self-test`: passed, text/image metadata fault injections and image baseline corruption caught.
- `scripts/static-check.py`: passed, including text/image mutation self-test.
- `make sbom-check`: passed with CycloneDX, SwiftPM graph, OSV, waiver self-tests, and license review.
- exact v0.87.0 manifest validation: passed for 127 changed-path rows/hash and 150 basename test-corpus rows/hash; audit/crosswalk row counts are validator-enforced.
- hidden skip scan: no `XCTSkip` matches.
- clean checkout validation: must pass before pushing this runtime candidate.
- Hosted Ubuntu/static CI: must pass after this runtime candidate is pushed.

## SBOM/security evidence model

- SBOM tool/version: `swift-ai-sbom` `1.1.0` (pinned local policy `scripts/sbom-policy.json`) plus pinned OSV Scanner `2.5.1`.
- Runtime SBOM SHA-256 is generated from exact accepted runtime commits; embedded revision must match the runtime commit.
- SBOM provenance/dependency graph: root package records exact Git revision and `Package.resolved`; dependency edges are derived from `swift package show-dependencies --format json` as root `swift-ai` -> direct `swift-crypto` -> transitive `swift-asn1`.
- SBOM scan/license disposition: real OSV Scanner JSON output is written to `.artifacts/sbom/osv-scanner.json`; high/critical findings fail unless covered by non-expired structured waivers (`id`, `owner`, `rationale`, `mitigation`, `expires`).
- SBOM artifact retention: Ubuntu/static CI uploads SBOM, checksum, OSV output, scan summary, and license review artifacts with 30-day retention. Durable release assets for v0.85.1 are version-pinned under `upstream-v0.85.1` and published by the manual SBOM release workflow, which validates a matching `upstream_version`, full runtime SHA, existing tag target, embedded revision, OSV/license status, and checksum naming before `--clobber` uploads.
- Dependency-lock policy: `Package.resolved` is tracked and required for SBOM generation/validation; volatile SBOM output under `.artifacts/` is not committed.

## Accepted v0.85.1 runtime evidence

Final v0.85.1 runtime commit: `b1192ff853ac5b312cc9dcef47b76e1c97ddc70f`.

- Runtime CI run: <https://github.com/rcarmo/swift-ai/actions/runs/35154754780>
- Runtime CI jobs: `104991425729` (`swift-test (ubuntu-latest)`) and `104991425958` (`static-check`)
- Runtime SBOM artifact: `10470264358` / `swift-ai-sbom-b1192ff853ac5b312cc9dcef47b76e1c97ddc70f`
- Runtime SBOM archive SHA-256: `88c3a2b15d55afaf7e648fa93dd81a772c1a20d9a840b0af26ec91ca800c719f`
- Runtime inner SBOM SHA-256: `93f0bfe9594652b5f6a1bbfecef2c08c625a693180d2d2258c798e0118d4e5b8`
- SBOM component count: `2`; embedded revision matches the runtime commit; OSV vulnerability and license scans passed.
- Status: `completed`
- Conclusion: `success`
- Routine hosted CI: Ubuntu/static only; macOS disabled after policy update.

## Prior accepted v0.85.0 evidence

Final v0.85.0 runtime commit: `943861d656920758cdb77ce493b6b01c0a415c01`.

Final v0.85.0 README documentation commit: `40c823a064f83c676513e17926ebaa28c624228e`.

Final v0.85.0 evidence documentation commit: `7149ae964cec4adc869d89ef0137d7bf2669837c`.

- Runtime CI run: <https://github.com/rcarmo/swift-ai/actions/runs/33898454631>
- Runtime CI jobs: `101106599166` (`swift-test (ubuntu-latest)`) and `101106599391` (`static-check`)
- Runtime SBOM artifact: `9946734408` / `swift-ai-sbom-943861d656920758cdb77ce493b6b01c0a415c01`, expires `2026-10-04T17:04:56Z`
- Runtime SBOM archive SHA-256: `2feec153bd29d947ce79d0974bf43855a4745592c1307627bee50cb20e696319`
- Runtime inner SBOM SHA-256: `7e5f74c3f58888cac79b8030a5200e1ed9409eac5efad962d6d6b49ea75ba27e`
- Runtime checksum-file SHA-256: `d0d74904ffc0cfb899526971c4ee944ac0dc350cc1142087211cfb084f60c653`
- Status: `completed`
- Conclusion: `success`
- Routine hosted CI: Ubuntu/static only; macOS disabled after policy update.

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
