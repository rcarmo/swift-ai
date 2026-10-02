# Release status

This repository tracks Swift runtime parity for `@earendil-works/pi-ai`.

## Current target

- Upstream package: `@earendil-works/pi-ai`
- Current upstream release: `v1.0.0`
- Current upstream tag commit: `a13d35a742c6ef8462812a28fbe1d8c8b7431c32`
- Verified npm tarball SHA-256: `f39b99c29b8598f175b10840e5d2a81983e7c0ce5cae4d7df83a1007447d2c2b`
- Swift parity branch: `main`
- Current Swift v1.0.0 runtime/classifier release: completed; runtime commit `7e7e2de2495c646857369d6ac63cb64a5bced5a6`, native `v1.0.0`, and upstream alias `upstream-v1.0.0` are published and verified.
- Accepted rollback runtime: v0.99.2 commit `379018acd61375462d02a971e5283be6b009d33e`.

## Exact upstream delta

Release-only audit scope: `packages/ai` diff from accepted v0.99.2 `005af57d88ee23b33778f343a9595b32e67ff788` to v1.0.0 `a13d35a742c6ef8462812a28fbe1d8c8b7431c32`.

Exact changed-path count: **8**. Changed-path manifest hash: `b8db49581470036b68078ac093dc6b41eaa92222647b14cf44a92b870d54eab4`. Source/package diff: `+192/-14`; status classes: `8M`.

Changed executable upstream tests: **3**, manifest hash `fbe3c63453261a58352b5e238f5f9488f33a13016485c7e3a49cce17bfdaaca2`. Final executable upstream test corpus: **171** basename rows, manifest hash `9d24da3ede393a95a7131b1c9ac494f57d8165161d6eb581109c86809131abfc`.

The detailed disposition matrix is in [`docs/upstream-v1.0.0-audit.md`](docs/upstream-v1.0.0-audit.md). The cumulative whole-corpus test crosswalk is in [`docs/upstream-v1.0.0-test-crosswalk.md`](docs/upstream-v1.0.0-test-crosswalk.md) and is fail-closed validated: 3 unique changed rows, dispositions `2 ported / 1 adapted / 0 pending`.

## Exact catalog parity

Signed npm tarball schema-v6 oracle:

- Provider-data manifest: schema `6`, provider files `42`, structure hash `235f2f320916ab6b0d7193e0bf66ec7983e9bc05abeddd7264923fb1e7eaf76e`.
- Chat snapshot: `scripts/models.v1.0.0.json` / exact upstream comparator `scripts/upstream-models.a13d35a.json` / embedded Swift registry `Sources/SwiftAI/Models/Generated/ModelsGenerated.swift`; **1532 models / 41 providers / 10 APIs**.
- Image snapshot: `scripts/image-models.v1.0.0.json` / exact upstream comparator `scripts/upstream-image-models.a13d35a.json` / embedded Swift registry `Sources/SwiftAI/Models/Generated/ImageModelsGenerated.swift`; **57 models / 1 provider / 1 API**.
- Classifier snapshot: `scripts/classifier-models.v1.0.0.json` / exact upstream comparator `scripts/upstream-classifier-models.a13d35a.json` / embedded Swift registry `Sources/SwiftAI/Models/Generated/ClassifierModelsGenerated.swift`; **15 models / 5 providers / 2 APIs**.
- Normalized deltas vs accepted v0.99.2: chat `+5/-2/19 changed`, image `+0/-0/0 changed`, classifier `+0/-0/1 changed`.

Expected comparator output:

```text
ok: 1532 chat models / 41 providers / 10 APIs; 57 image models / 1 providers / 1 APIs; 15 classifier models / 5 providers / 2 APIs; text delta +5/-2/19 changed; image delta +0/-0/0 changed; classifier delta +0/-0/1 changed
```

## Swift implementation, adaptations, and separate follow-up scope

Implemented/adapted in the v1.0.0 local candidate:

- Regenerated v1.0.0 chat, image, and classifier catalogs from the verified signed npm artifact; live catalog hydration remains excluded.
- Ported OpenAI Responses grammar replay so one capability/transcript-resolved grammar map drives tool declarations, assistant replay items and tool-result outputs.
- Preserved function-call foreign ID normalization while dropping foreign/different-model custom grammar item IDs against the expected `ctc_` prefix.
- Ported Anthropic OAuth browser/copy-code selection through an additive Swift auth prompt adapter, exact upstream constants, JSON token POST/refresh bodies, parser/state behavior, cancellation checkpoints and request/response secret redaction.
- Kept OAuth callback browser-page SVG branding as N/A/adapted because this Swift package has a callback decision utility but no bound page renderer; no server/renderer was introduced solely for branding.

Separate classifier contract follow-up, included in this local candidate but distinct from the 8-path upstream delta:

- Enforces System One object-state wire contract with a new object-safe initializer while preserving the public `JSONValue` state API.
- Preserves `bool -> noul` wire mapping and public bool probability output.
- Requires bool criteria to include both `true` and `false` for System One wire requests.
- Requires finite choice probabilities/confidence and finite score/confidence.
- Parses usage before answer semantics and preserves valid billed usage on structurally valid JSON with semantic answer errors.
- Treats malformed usage as optional and ignored; fractional/out-of-range usage and total-token overflow do not trap.
- Native Foundation/Swift `Double` cannot represent whole-body JSON numeric overflow such as `1e400`; those syntactically valid JavaScript-number bodies fail Swift whole-JSON decode and intentionally return stable error/no hook/no usage as a documented native adaptation rather than partial billing recovery.
- Implements deterministic production classify transport for TypeSafe and Cloudflare envelopes through `SwiftAI.classify`, existing retry/cancel/header/env/hook patterns, option-scoped request transport injection, case-insensitive header nil suppression, timestamping, and absolute HTTP(S) URL validation.
- Llama classifier provider remains outside the current two-API Swift surface and is N/A for this lane.

Durable execution support requested after this lane is intentionally not part of this candidate and must remain a separate future feature.

## Tests and gates

Local validation for v1.0.0 parity work uses Swift `6.3.2`; heavy Swift gates must run under nice `10` with `-j 2`.

Final local gates passed for the current local candidate:

- Focused auditor/runtime filter covering Anthropic OAuth, Responses grammar replay, and System One classifier: `14` auditor-filter tests / `0` failures independently; local broader focused filter: `15` tests / `0` failures (`.artifacts/v1.0.0-validation/focused-runtime-classifier-final.log`).
- `nice -n 10 swift build -j 2 -Xswiftc -warnings-as-errors`: passed using `/home/agent/.local/share/swiftly/toolchains/6.3.2/usr/bin/swift` (`6.3.2`) with no warnings (`final-swift-build-warnings-as-errors.log`).
- `nice -n 10 swift test -j 2`: `299` tests, `0` failures (`final-swift-test-full.log`).
- Deterministic repeats before final doc-only ledger updates: `nice -n 10 swift test -j 2` ×2 passed, `295` tests / `0` failures each (`swift-test-deterministic-1.log`, `swift-test-deterministic-2.log`).
- `nice -n 10 make check MAKEFLAGS=-j2`: passed static checks, SBOM generation/check/scan, warnings-as-errors build, and full tests (`final-make-check.log`).
- `nice -n 10 make sbom-check`: passed; local dirty-tree SBOM SHA-256 `e8f92d7c04ead6f3e8601f7cb8aaf0c07d716eb872932ee0e53126e977233736`; OSV and license checks passed with `2` components (`corrections-make-sbom-check.log`).
- `python3 scripts/audit-parity.py`: passed exact full-record text/image/classifier comparators (`final-audit-parity.log`).
- `python3 scripts/audit-parity.py --self-test`: passed deliberate text/image/classifier metadata and crosswalk corruption checks (`final-audit-parity-self-test.log`).
- `python3 scripts/static-check.py`: passed (`final-static-check.log`).
- `grep -R "XCTSkip" -n Tests || true`: no matches (`xctskip-scan.log`).
- `git diff --check`: passed (`final-git-diff-check.log`).
- Clean source snapshot validation passed audit, warnings-as-errors build, and full tests (`clean-source-snapshot.log`).

Hosted CI/SHA-specific SBOM evidence is pending. No v1.0.0 commit/push/tag/release has been made.

## SBOM/security evidence model

- SBOM tool/version: `swift-ai-sbom` `1.1.0` (pinned local policy `scripts/sbom-policy.json`) plus pinned OSV Scanner `2.5.1`.
- Runtime SBOM SHA-256 is generated from exact accepted runtime commits; embedded revision must match the runtime commit.
- SBOM provenance/dependency graph: root package records exact Git revision and `Package.resolved`; dependency edges are derived from `swift package show-dependencies --format json` as root `swift-ai` -> direct `swift-crypto` -> transitive `swift-asn1`.
- SBOM scan/license disposition: real OSV Scanner JSON output is written to `.artifacts/sbom/osv-scanner.json`; high/critical findings fail unless covered by non-expired structured waivers (`id`, `owner`, `rationale`, `mitigation`, `expires`).
- SBOM artifact retention: Ubuntu/static CI uploads SBOM, checksum, OSV output, scan summary, and license review artifacts with 30-day retention. Durable release assets for accepted releases are version-pinned under `upstream-vX.Y.Z` and published by the manual SBOM release workflow after validation.
- Dependency-lock policy: `Package.resolved` is tracked and required for SBOM generation/validation; volatile SBOM output under `.artifacts/` is not committed.

## v1.0.0 runtime evidence

Accepted runtime commit: `7e7e2de2495c646857369d6ac63cb64a5bced5a6` (`Port pi-ai v1.0.0 and align classifier contract`). Parent/rollback lineage: `4dc7db8f4e9f68488f65f785e8abea29f53cf8f7` docs/status head after v0.99.2, with accepted v0.99.2 runtime `379018acd61375462d02a971e5283be6b009d33e`.

- Runtime CI run: <https://github.com/rcarmo/swift-ai/actions/runs/36975868783>
- Runtime CI jobs: `110739451479` (`static-check`) and `110739451623` (`swift-test (ubuntu-latest)`)
- Runtime SBOM artifact: `11213542896` / `swift-ai-sbom-7e7e2de2495c646857369d6ac63cb64a5bced5a6`
- Runtime SBOM archive SHA-256: `6ee0577132499facf1cf5d5253e3f1b6de0fbbb326dfde55ffe256b7bb576f55`
- Runtime inner SBOM SHA-256: `0f2d015b7ff90e6bce928ba55279fa0eb6e0125b5028b6c2ba09df68ef6a747c`
- SBOM provenance: root component `swift-ai@1.0.0`; embedded `git.revision=7e7e2de2495c646857369d6ac63cb64a5bced5a6`; `git.dirty=false`; CycloneDX component count `2` (`swift-crypto`, `swift-asn1`); dependency graph has the root edge `swift-ai -> swift-crypto -> swift-asn1` with `3` dependency entries.
- Security/license: OSV scanner `2.5.1` returned no vulnerabilities; high/critical findings are empty; no waivers; license review passed for `swift-asn1` and `swift-crypto` under approved licenses.
- Native release: `v1.0.0`, release database ID `401602448`, workflow run `36976441736` (`publish-sbom` job `110741196478`), annotated tag object `0058c94c523539e5869fe10d6e42ea919288eef2` by `Rui Carmo <rui.carmo@gmail.com>` targeting runtime `7e7e2de2495c646857369d6ac63cb64a5bced5a6`; assets `605030772` (`sbom.cdx.json`, digest `sha256:0f2d015b7ff90e6bce928ba55279fa0eb6e0125b5028b6c2ba09df68ef6a747c`) and `605030770` (`sbom.cdx.json.sha256`, digest `sha256:919a78b5e50df1313fd700b72008a54badd85f9e7de3a3c71cca60a475beb855`).
- Upstream alias release: `upstream-v1.0.0`, release database ID `401604641`, workflow run `36976866533` (`publish-sbom` job `110742466133`), ref targets runtime `7e7e2de2495c646857369d6ac63cb64a5bced5a6`; assets `605037982` (`sbom.cdx.json`, digest `sha256:0f2d015b7ff90e6bce928ba55279fa0eb6e0125b5028b6c2ba09df68ef6a747c`) and `605037981` (`sbom.cdx.json.sha256`, digest `sha256:919a78b5e50df1313fd700b72008a54badd85f9e7de3a3c71cca60a475beb855`).
- Native and alias SBOM bytes are identical to the accepted hosted runtime artifact. Future `v1.0.0` or `upstream-v1.0.0` references must continue to target runtime `7e7e2de2495c646857369d6ac63cb64a5bced5a6`, not this docs/status receipt head.

## Accepted v0.99.2 runtime evidence

Accepted runtime commit: `379018acd61375462d02a971e5283be6b009d33e` (`Update Swift AI parity to v0.99.2`).

- Runtime CI run: <https://github.com/rcarmo/swift-ai/actions/runs/36782139648>
- Runtime CI jobs: `110114736031` (`static-check`) and `110114736235` (`swift-test (ubuntu-latest)`)
- Runtime SBOM artifact: `11127418783` / `swift-ai-sbom-379018acd61375462d02a971e5283be6b009d33e`
- Runtime inner SBOM SHA-256: `4167897e88c69f56d861a8e2831fdd7db14ca0758940beb44cae552397b9701a`
- SBOM provenance: root component `swift-ai@0.99.2`; embedded `git.revision=379018acd61375462d02a971e5283be6b009d33e`; `git.dirty=false`; CycloneDX component count `2` (`swift-crypto`, `swift-asn1`); dependency graph has the root edge `swift-ai -> swift-crypto -> swift-asn1`.
- Security/license: OSV scanner `2.5.1` returned no vulnerabilities; high/critical findings are empty; license review passed for `swift-asn1` and `swift-crypto` under approved licenses.
- Native release: `v0.99.2`; upstream alias release: `upstream-v0.99.2`.

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
