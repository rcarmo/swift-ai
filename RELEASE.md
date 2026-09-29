# Release parity record

This file is the durable release-audit ledger for `swift-ai`. It must be updated as part of every future upstream `@earendil-works/pi-ai` release parity commit before the work is reported complete.

## Current upstream parity baseline

- Upstream package: `@earendil-works/pi-ai`
- Current upstream release: `v0.99.1`
- Current upstream tag commit: `d86654abb8862e201933517d6f1fce9f88dd117f`
- Published: `2026-09-29T18:10:40.924Z`
- Previous accepted upstream release: `v0.87.1`
- Previous accepted upstream tag commit: `f07218c4d4bbc12bef056a7058c3dd49dfe41abe`
- Previous accepted Swift runtime baseline: `8a126fc8bb8429801905e502eb92ef2da6721d74`
- Previous accepted Swift README documentation commit: `40c823a064f83c676513e17926ebaa28c624228e`
- Previous accepted Swift evidence documentation commit: `7149ae964cec4adc869d89ef0137d7bf2669837c`
- Verified npm artifact SHA-256: `f9f44692157d0bf5679c4a17304a310028231d7daaeaaea3b73252f4b7a264d3`
- Verified npm artifact SHA-512: `f958152090e40ced9e7d824a104aaf3d31f8ce69c8697740a6919b3bebca140f6acb93dd8458807a7b8502453ea220927ce0b874c1c3cab8dd41e2f86680b909`
- Swift parity branch: `main`
- Current Swift parity runtime commit for v0.99.1: `dc549fe0709128c73d9d8f8f2d5a031c1a6b6482`.
- Runtime v0.99.1 accepted by CI run `36636114608`; README count updates and durable `upstream-v0.99.1` SBOM links are now documented. v0.87.1/v0.87.0/v0.85.1 evidence remains preserved below.

## Exact upstream delta

Release-only audit scope: `packages/ai` diff from accepted v0.87.1 `f07218c4d4bbc12bef056a7058c3dd49dfe41abe` to v0.99.1 `d86654abb8862e201933517d6f1fce9f88dd117f`.

Exact changed-path count: **169**. Changed-path manifest hash: `086beb5b751f144f9e45034bfbb2b0f4e8a0d3a00f9e17ec1b073b3a8397221e`. Source/package diff: `+7001/-2913`; status classes: `24A/4D/140M/1R`.

Changed executable upstream tests: **58** (`+3142/-385`), manifest hash `d8eefa94ed87c03de0545965351de4d800cf76ce1db33b0f62fab0f9ab3c7acc`. Final executable upstream test corpus: **160** basename rows, manifest hash `7ad5f140edc5bc49a348b7b7e36ea266dd82a3075c23ad9997b6e8bc21992b06`.

The detailed disposition matrix is in [`docs/upstream-v0.99.1-audit.md`](docs/upstream-v0.99.1-audit.md). The cumulative whole-corpus test crosswalk is in [`docs/upstream-v0.99.1-test-crosswalk.md`](docs/upstream-v0.99.1-test-crosswalk.md) and is fail-closed validated: 58 unique changed rows, dispositions `9 ported / 49 adapted / 0 pending`.

## Exact catalog parity

Signed npm tarball schema-v6 oracle:

- Provider-data manifest: schema `6`, provider files `42`, structure hash `58511a57fb2db5e984ee62857d8079aec6ff800e19226c327c118e7f57ea916b`.
- Chat snapshot: `scripts/models.v0.99.1.json` / exact upstream comparator `scripts/upstream-models.d86654a.json` / embedded Swift registry `Sources/SwiftAI/Models/Generated/ModelsGenerated.swift`; **1523 models / 41 providers / 10 APIs**.
- Image snapshot: `scripts/image-models.v0.99.1.json` / exact upstream comparator `scripts/upstream-image-models.d86654a.json` / embedded Swift registry `Sources/SwiftAI/Models/Generated/ImageModelsGenerated.swift`; **57 models / 1 provider / 1 API**.
- Classifier snapshot: `scripts/classifier-models.v0.99.1.json` / exact upstream comparator `scripts/upstream-classifier-models.d86654a.json` / embedded Swift registry `Sources/SwiftAI/Models/Generated/ClassifierModelsGenerated.swift`; **12 models / 5 providers / 2 APIs**.
- Normalized deltas vs accepted v0.87.1: chat `+59/-31/110 changed`, image `+2/-0/54 changed`, classifier `+12`.

Expected comparator output:

```text
ok: 1523 chat models / 41 providers / 10 APIs; 57 image models / 1 providers / 1 APIs; 12 classifier models / 5 providers / 2 APIs; text delta +59/-31/110 changed; image delta +2/-0/54 changed; classifier delta +12
```

## Swift implementation, adaptations, and N/A decisions

Implemented/adapted:

- Regenerated v0.99.1 chat, image, and classifier catalogs from the verified signed npm artifact; live catalog hydration is deliberately excluded.
- Added schema-v6 provider-data manifest validation, exact classifier registry generation, and fail-closed crosswalk validation for all 58 changed tests.
- Added typed classifier model/provider/API surface, classifier registry/bootstrap, TypeSafe/System One and Cloudflare Workers AI System One deterministic request/response behavior, and `SwiftAI.classify`.
- Ported OpenAI ChatGPT OAuth/shared callback deterministic primitives, ChatGPT direct-token Responses field suppression, usage-limit URL enrichment, raw provider stream-event hooks before normalization, and retained/excluded `thinkingLevel`/`nestedCalls` wire behavior.
- Added GPT-6.1 Sol and Codex default/catalog gates across OpenAI, OpenAI Codex, Azure OpenAI Responses, OpenRouter, and Vercel AI Gateway.
- Preserved accepted v0.87.1 runtime behavior and historical release evidence.

N/A/adapted:

- JS package/changelog mechanics and browser-only callback server implementation details are represented by Swift deterministic primitives and audit evidence.
- Live/provider credential matrices remain classified in the crosswalk and are not faked.

## Tests and gates

Local validation for v0.99.1 parity work used Swift `6.3.2` and nice `10`/`-j 2` for heavy Swift work. Final local results before this docs-only commit:

- `swift build -Xswiftc -warnings-as-errors -j 2`: passed.
- `swift test -j 2`: `286` tests, `0` failures.
- deterministic `swift test -j 2` ×2: passed (`286` tests each run).
- `make check`: passed (`286` tests, `0` failures).
- `make sbom-check`: passed with CycloneDX, SwiftPM graph, OSV, waiver self-tests, and license review.
- `python3 scripts/audit-parity.py`: passed with exact v0.99.1 schema-v6 counts and deltas.
- `python3 scripts/audit-parity.py --self-test`: passed, text/image/classifier metadata mutation and crosswalk corruption self-tests caught.
- `python3 scripts/static-check.py`: passed.
- hidden skip scan: no `XCTSkip` matches.
- clean checkout validation: passed for audit self-test, focused v0.99.1 tests (`11` tests, `0` failures), static check, and SBOM check.
- Hosted Ubuntu/static CI: run `36636114608` completed successfully for runtime commit `dc549fe0709128c73d9d8f8f2d5a031c1a6b6482`; jobs `109637025438` (`static-check`) and `109637025642` (`swift-test (ubuntu-latest)`) passed.

## SBOM/security evidence model

- SBOM tool/version: `swift-ai-sbom` `1.1.0` (pinned local policy `scripts/sbom-policy.json`) plus pinned OSV Scanner `2.5.1`.
- Runtime SBOM SHA-256 is generated from exact accepted runtime commits; embedded revision must match the runtime commit.
- SBOM provenance/dependency graph: root package records exact Git revision and `Package.resolved`; dependency edges are derived from `swift package show-dependencies --format json` as root `swift-ai` -> direct `swift-crypto` -> transitive `swift-asn1`.
- SBOM scan/license disposition: real OSV Scanner JSON output is written to `.artifacts/sbom/osv-scanner.json`; high/critical findings fail unless covered by non-expired structured waivers (`id`, `owner`, `rationale`, `mitigation`, `expires`).
- SBOM artifact retention: Ubuntu/static CI uploads SBOM, checksum, OSV output, scan summary, and license review artifacts with 30-day retention. Durable release assets for v0.87.0 are version-pinned under `upstream-v0.87.0` and published by the manual SBOM release workflow, which validates a matching `upstream_version`, full runtime SHA, existing tag target, embedded revision, OSV/license status, and checksum naming before `--clobber` uploads.
- Dependency-lock policy: `Package.resolved` is tracked and required for SBOM generation/validation; volatile SBOM output under `.artifacts/` is not committed.

## Accepted v0.99.1 runtime evidence

Final v0.99.1 runtime commit: `dc549fe0709128c73d9d8f8f2d5a031c1a6b6482`.

- Runtime CI run: <https://github.com/rcarmo/swift-ai/actions/runs/36636114608>
- Runtime CI jobs: `109637025438` (`static-check`) and `109637025642` (`swift-test (ubuntu-latest)`)
- Runtime SBOM artifact: `11064291751` / `swift-ai-sbom-dc549fe0709128c73d9d8f8f2d5a031c1a6b6482`
- Runtime SBOM archive SHA-256: `2899c2dffe0d401c4ab20a9fe9834f7a15ee9a11584789373c7cf2168640d308`
- Runtime inner SBOM SHA-256: `b6056920ebf73e272f0dc74119480dcfd04b769bccb884067e0771e2e91255e5`
- SBOM component count: `2`; CycloneDX `1.5`; root component `swift-ai@0.99.1`; embedded revision matches the runtime commit; dirty flag is `false`; OSV vulnerability, security, and license scans passed.
- Status: `completed`
- Conclusion: `success`
- Routine hosted CI: Ubuntu/static only; macOS disabled after policy update.

## Accepted v0.87.1 runtime evidence

Final v0.87.1 runtime commit: `8a126fc8bb8429801905e502eb92ef2da6721d74`.

- Runtime CI run: <https://github.com/rcarmo/swift-ai/actions/runs/35794536991>
- Runtime CI jobs: `106970635220` (`swift-test (ubuntu-latest)`) and `106970635393` (`static-check`)
- Runtime SBOM artifact: `10723117599` / `swift-ai-sbom-8a126fc8bb8429801905e502eb92ef2da6721d74`
- Runtime SBOM archive SHA-256: `fa7f65018406926f913360e6d9bbbb9c1e28ca2ad0e68ecb4ba789945ed4a435`
- Runtime inner SBOM SHA-256: `3405700b03b751916446ff6b32190733de1845aa1486513730500a954495e3ac`
- SBOM component count: `2`; CycloneDX `1.5`; root component `swift-ai@0.87.1`; embedded revision matches the runtime commit; dirty flag is `false`; OSV vulnerability, security, and license scans passed.
- Status: `completed`
- Conclusion: `success`
- Routine hosted CI: Ubuntu/static only; macOS disabled after policy update.

## Accepted v0.87.0 runtime evidence

Final v0.87.0 runtime commit: `bc1f1e8f93cb8b8dfc9dbe753b86cc235ae4aacb`.

- Runtime CI run: <https://github.com/rcarmo/swift-ai/actions/runs/35651037149>
- Runtime CI jobs: `106503225568` (`swift-test (ubuntu-latest)`) and `106503225813` (`static-check`)
- Runtime SBOM artifact: `10661774667` / `swift-ai-sbom-bc1f1e8f93cb8b8dfc9dbe753b86cc235ae4aacb`
- Runtime SBOM archive SHA-256: `6a5716d314c7aba79ad44c1ba226b55fd0e66713dd67c788ee20eef6e4b750a0`
- Runtime inner SBOM SHA-256: `9aa10446a20fe5354dc1e501f598b790ed4b64cb1528f3bc53165586156f30b5`
- SBOM component count: `2`; embedded revision matches the runtime commit; dirty flag is `false`; OSV vulnerability and license scans passed.
- Status: `completed`
- Conclusion: `success`
- Routine hosted CI: Ubuntu/static only; macOS disabled after policy update.

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
