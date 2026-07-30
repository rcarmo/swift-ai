# Coding

* Follow YAGNI principles.

## Upstream release parity audits

* Maintain root `RELEASE.md` for every upstream `@earendil-works/pi-ai` release audit.
* Update `RELEASE.md` in the same release commit before reporting completion.
* The release entry must include:
  - current upstream baseline/tag/SHA and previous accepted baseline,
  - exact upstream changed-path count and summary,
  - exact text/image catalog comparator counts and source files,
  - every Swift implementation, fix, adaptation, and N/A decision,
  - local validation gates and GitHub Actions run/status.
* Do not consider an upstream release audit complete until `RELEASE.md` is current.

## Git workflow

- Never use `git rebase`. Always use `git merge` / `git pull --no-rebase`.
- Commit as `Rui Carmo <rui.carmo@gmail.com>` unless explicitly told otherwise.
- Configure both local and global Git identity before committing:
  - `git config user.name "Rui Carmo"`
  - `git config user.email "rui.carmo@gmail.com"`
  - `git config --global user.name "Rui Carmo"`
  - `git config --global user.email "rui.carmo@gmail.com"`
