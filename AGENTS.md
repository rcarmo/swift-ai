# Coding

* Follow YAGNI principles.

## Change discipline

* Read the relevant source, generated-data inputs, tests, and release/audit docs before editing. Do not edit blind.
* Keep changes narrow and intentional; preserve public API/source compatibility unless an upstream release explicitly requires a breaking change and the release ledger records it.
* Do not hand-edit generated artifacts. Regenerate from pinned official inputs and keep generator/comparator evidence with the change.
* Use pinned inputs only: official upstream tag/artifact, committed snapshots, `Package.resolved`, and checked-in policy files. Do not rely on upstream `main`, live provider catalogs, local machine state, or secrets.
* Keep deterministic tests independent of network, wall clock, hidden environment, ordering accidents, and hosted CI side effects.

## Source tree layout

* `Sources/SwiftAI/Core/`: public core types, contexts, events, registries, images surface, and status constants.
* `Sources/SwiftAI/Auth/`: credential stores, OAuth protocols/providers support, and environment/API-key resolution.
* `Sources/SwiftAI/Transport/`: HTTP/SSE/proxy/retry/session-resource transport helpers.
* `Sources/SwiftAI/Models/Generated/`: generated text/image registries only. Do not edit by hand; update generators/checkers when this path changes.
* `Sources/SwiftAI/Support/`: shared compatibility, diagnostics, logging, runtime, parsing, harness, and utility helpers.
* `Sources/SwiftAI/Providers/`: provider implementations and OAuth provider implementations.
* `Sources/CZstd/`: C shim target for zstd support.
* `Tests/SwiftAITests/Core/`: core utility, environment, and overflow tests.
* `Tests/SwiftAITests/Models/`: generated registry/image model tests.
* `Tests/SwiftAITests/Providers/`: provider, metadata, OAuth, and broad parity tests. Do not split the large provider test file unless explicitly requested.
* `Tests/SwiftAITests/Integration/`: reserved for integration-style tests.

## Upstream release parity audits

* Maintain root `RELEASE.md` for every upstream `@earendil-works/pi-ai` release audit.
* Update `RELEASE.md` in the same release commit before reporting completion.
* Audit only the latest official published upstream tag/artifact against the exact previously accepted upstream/Swift baseline. Never audit or generate parity from upstream `main`.
* Record the upstream tag, upstream tag SHA, and verified npm artifact SHA-256 before implementation.
* Derive exact scope first, before editing runtime code:
  - exact upstream changed-path count and path matrix,
  - exact upstream test corpus/crosswalk and changed-test markers,
  - exact full-record text and image catalog deltas.
* Regenerate catalogs cleanly from the pinned official artifact/tag only. Keep full-record text and image comparators strict, including deliberate text+image fault/self-test coverage.
* Port applicable behavior as production Swift behavior, not test-only shims. Preserve production transport and `AsyncSequence` semantics where upstream behavior is transport/streaming-related.
* Keep concurrency changes structured and sendable/cancellation-aware. Deterministic tests must not depend on network, wall clock, process environment, hidden skips, or ordering accidents.
* Classification rules:
  - Use `ported` only when executable Swift production behavior and tests cover the upstream behavior.
  - Use `adapted` only with a precise Swift architectural reason and equivalent production evidence.
  - Use `live-only` only for credential/network-provider behavior that cannot be deterministically exercised; keep it separate from deterministic coverage and never use it to hide missing portable logic.
  - Use `N/A` narrowly for JS/package/runtime mechanics that do not exist in SwiftPM; document why.
* Production evidence must cover the real changed surface: wire serialization, production transport seams, `AsyncSequence`/stream behavior, parsers, replay semantics, error handling, cancellation, usage/cost accounting, generated catalog metadata, and registry/runtime behavior as applicable. Helper-only tests are not a substitute when provider transport/parser/replay behavior changed.
* Do not hide or weaken tests. No hidden skips, broad TODO classifications, unproven N/A claims, or “documented but untested” production deltas are acceptable.
* Required local gates before the final push:
  - `swift build -Xswiftc -warnings-as-errors`
  - `swift test`
  - deterministic `swift test` repeats when doing release parity work
  - `make check`
  - `make sbom-check`
  - `python3 scripts/audit-parity.py`
  - `python3 scripts/audit-parity.py --self-test`
  - `python3 scripts/static-check.py`
  - `grep -R "XCTSkip" -n Tests || true`
* The release entry must include:
  - current upstream baseline/tag/SHA and previous accepted baseline,
  - npm artifact SHA-256,
  - exact upstream changed-path count and summary,
  - exact text/image catalog comparator counts and source files,
  - every Swift implementation, fix, adaptation, and N/A decision,
  - local validation gates and GitHub Actions run/status.
* Maintain the per-release audit matrix and whole-corpus test crosswalk alongside `RELEASE.md`.
* Do not consider an upstream release audit complete until `RELEASE.md`, the audit matrix, and the crosswalk are current and the final hosted CI run is green.

## CI policy

* Local-first workflow is mandatory: complete all local implementation, tests, static checks, docs, and Git hygiene before pushing.
* Run hosted CI only once at the end after all local work is complete. Do not use hosted CI as an iterative debugging loop for developer push cycles.
* Weekly scheduled maintenance CI is independent of developer final-only CI: it exists to rerun pinned SBOM, OSV, license, static, and Ubuntu checks between releases without implying a new release candidate.
* Batch reviewer/auditor corrections locally unless explicitly told otherwise, then make a single final push/CI run.
* Evidence-only follow-up commits after a green tested candidate must be docs-only and use `[skip ci]` in the commit title when possible, or otherwise rely on proven `paths-ignore` semantics. Such commits must clearly record the tested runtime/SBOM SHA, CI run, artifact digest, and distinct docs-only SHA without pretending the docs commit was the tested runtime candidate.
* macOS hosted CI is disabled for the foreseeable future. Routine CI retains Ubuntu Swift tests and static checks only.
* If workflow syntax/static policy changes are made, validate them locally with `python3 scripts/static-check.py` and `git diff --check` before pushing.

## Supply chain, SBOM, and security

* `make sbom` must generate CycloneDX JSON and SHA-256 checksum artifacts under `.artifacts/sbom/` using the pinned local generator policy in `scripts/sbom-policy.json`.
* `make sbom-check` must validate SBOM schema, checksum, required components, exact Git revision/dirty state, SwiftPM dependency graph edges, `Package.resolved` consistency, no secrets/absolute paths, license policy, and pinned OSV vulnerability scan results.
* Do not commit volatile SBOM artifacts; `.artifacts/` remains gitignored.
* SBOM contents must identify the root Swift package/revision and resolved direct/transitive SwiftPM graph from tracked `Package.resolved`. If the dependency policy changes, document the dependency-free/resolution policy explicitly.
* High/critical vulnerabilities, unparseable severity, or incompatible/unknown licenses require owner, rationale, mitigation, and expiry before completion. Expired waivers are invalid.
* Final Ubuntu CI must generate/validate/scan and upload SBOM, checksum, OSV output, scan summary, and license review artifacts with retention.
* `RELEASE.md` must record SBOM tool/version, artifact paths, digest provenance model, scan disposition, license disposition, and artifact retention for release parity work.

## Lifecycle and Definition of Done

* Scheduled dependency/security review: at least once per upstream release audit and whenever `Package.resolved`, `Package.swift`, Swift toolchain, SBOM policy, or CI images change.
* Urgent advisory trigger: immediately review when OSV/GitHub/security advisories mention SwiftPM dependencies, build tooling, GitHub Actions, or provider transport code.
* Generated drift trigger: regenerate and compare catalogs whenever upstream generator/data files change, artifact SHA changes, or comparator self-tests fail.
* API/deprecation/removal trigger: review public API compatibility whenever upstream removes/renames models, providers, APIs, request fields, response fields, or auth/runtime behavior.
* Release/tag/changelog trigger: update `RELEASE.md`, audit matrix, crosswalk, provenance evidence, rollback SHA, and post-release verification/issues for every accepted upstream tag.
* Rollback/evidence retention: final reports must include the accepted runtime SHA, any docs-only SHA, CI run URL, artifact retention, and the previous accepted rollback SHA.
* Definition of Done for release parity: exact scope/crosswalk, production runtime evidence, clean+fault catalog gates, Swift gates/no hidden skips, SBOM+scan+license evidence, current `RELEASE.md`, one green Ubuntu/static hosted CI run, clean sync, and documented rollback/evidence.

## Git workflow

- Never use `git rebase`. Always use `git merge` / `git pull --no-rebase`.
- Resolve reviewer findings locally before the final push.
- Keep the working tree clean and synced after push (`HEAD == origin/main`).
- Commit as `Rui Carmo <rui.carmo@gmail.com>` unless explicitly told otherwise.
- Configure both local and global Git identity before committing:
  - `git config user.name "Rui Carmo"`
  - `git config user.email "rui.carmo@gmail.com"`
  - `git config --global user.name "Rui Carmo"`
  - `git config --global user.email "rui.carmo@gmail.com"`
