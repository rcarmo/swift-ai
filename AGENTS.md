# Coding

* Follow YAGNI principles.

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
* Required local gates before the final push:
  - `swift build -Xswiftc -warnings-as-errors`
  - `swift test`
  - deterministic `swift test` repeats when doing release parity work
  - `make check`
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
* Run hosted CI only once at the end after all local work is complete. Do not use hosted CI as an iterative debugging loop.
* Batch reviewer/auditor corrections locally unless explicitly told otherwise, then make a single final push/CI run.
* macOS hosted CI is disabled for the foreseeable future. Routine CI retains Ubuntu Swift tests and static checks only.
* If workflow syntax/static policy changes are made, validate them locally with `python3 scripts/static-check.py` and `git diff --check` before pushing.

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
