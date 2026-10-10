# Release status

This repository tracks Swift runtime parity for `@earendil-works/pi-ai`.

## v1.1.0 development candidate (not accepted/published)

### Automatic pressure/overflow compaction chunk

Configured agents now validate persisted compaction policy, check context pressure before provider dispatch and link a bounded summarisation child to the generation intent in one commit. A context-overflow error can compact and retry once; failed-request usage is recorded before summarisation, and staged linked compaction recovery refreshes the parent transcript without rebilling. Repeated overflow stops after one compaction. Disabled policy preserves the single-attempt path. Refreshed context excludes other pending generations' admitted inputs. Full 423-test, warnings-as-errors and static/catalogue gates passed locally, including pressure, billed overflow, repeated overflow, disabled policy and staged child recovery. Background pressure scheduling, before-compact decisions/retry and complete upstream audit remain follow-up scope.

### Subagent conversations and completion reports chunk

Added durable child-conversation ownership, pinned subagent input/agent settings, explicit serial subagent resume, deduplicated child generation admission and staged completion reports. Report queueing and subagent terminal settlement share one commit; journal reopen and completing-stage recovery queue one report without repeating model effects. Background ownership is recorded, but execution still requires explicit resume. Full 418-test, warnings-as-errors and static/catalogue gates passed locally. Parallel scheduling, nested abort propagation, full subagent hook/tool integration and the broader upstream audit remain incomplete.

### Automatic inbox follow-up scheduling chunk

Configured agents can now admit `send` input and explicitly resume persisted inbox work without caller-owned provider execution. The generation worker schedules selected placed follow-ups after terminal settlement, reuses their existing input/submission IDs and respects agent one/all queue modes. Combined input context is preserved without duplicate entries; abort removes queued user inputs as unanswered while passive writes remain queued. Scheduling holds close reservations across asynchronous preparation. Full 416-test, warnings-as-errors and static/catalogue gates passed locally. Background subagents and automatic pressure/overflow compaction remain follow-up scope.

### Local environment and core tools chunk

Added a native execution-environment protocol and local owned-root adapter, streamed bounded UTF-8 line reads, BOM/replacement-character handling, exact original-region edit checks, CRLF/BOM-preserving writes, and core read/write/edit/bash tool registration through the durable provider/tool loop. Filesystem paths reject root escape and symlink traversal; trusted bash scripts are explicitly unsandboxed. Linux commands use detached process groups, timeout/cancellation termination, bounded output tails and spill files beneath project scratch. Tests verify descendant timeout termination, nonzero exits, byte-limit spill, line bounds, invalid UTF-8, overlapping/nonunique edits and isolation. Full 414-test, warnings-as-errors and static/catalogue gates passed locally. Native file watches, image/PowerShell tools, progressive output-window callbacks and the full read differential corpus remain follow-up scope.

### Native task ownership/recovery chunk

Added registered versioned native task definitions, explicit bounded resume, persisted input/checkpoints, child creation/wait, completing-stage results, ownership drain before parent settlement, abort-tree marking/handlers and task graph inspection. Missing/mismatched definitions block execution; completing recovery settles without repeating effects. A failed task does not stop later tasks, and committed pre-effect checkpoints survive failed callbacks. The scheduler is a serial native adapter; worker-slot yielding, arbitrary sibling waits, memos, handover/orphan policies, background generation/subagents and automatic wake are still follow-up scope. Full 410-test, warnings-as-errors and static/catalogue gates passed locally.

### Agent/prompt/request-hook chunk

Added persisted agent model/instructions/thinking/extension selection, install/replace/uninstall extension registry, selected prompt-section rendering and before-request/after-response hooks. Failed section renderers retain previously shown text without double tagging; invalid extension keys are rejected before installation. Named extension identity is pinned into generation intent, credentials/endpoints stay live-only, and after-response hook failures preserve billed usage. The native prompt currently passes a combined `AIContext.systemPrompt`; upstream mid-conversation system/tool-delta replay, task/tool hooks, wrappers and automatic scheduling still require integration. Full 406-test, warnings-as-errors and static/catalogue gates passed locally.

### Resumable manual compaction chunk

Added native tool-group-aware compaction cut selection and a durable manual summarisation task with a pinned pre-effect transcript, no-cache bounded summary request, persisted summary/usage stage, stale-head protection and atomic summary/usage settlement. Journal reopen and explicit recovery finalise a staged summary without another provider call. Owned compaction reservations keep close from releasing storage during effects; concurrent recovery of one compaction is rejected. Manual compaction requires an idle conversation. Automatic pressure/overflow compaction, hook decisions/retry and scheduler integration remain follow-up scope. Full 403-test, warnings-as-errors and static/catalogue gates passed locally for this chunk.

### Typed document migration and callback watches chunk

Added document definitions with scope/version/history/fork validation, pure read-time migration, owned-line update-time migration and fail-closed newer-version access. Throwing update callbacks persist no state; historical reads migrate the selected stored revision without rewriting journal history. Added callback watch handles with acquisition value before start, off-line serial delivery, bounded root-frame convergence, listener re-entry, retirement, idempotent stop/cancel and first-terminal-reason semantics. Stop does not join or cancel an already-running callback. Native root frames remain the Swift adaptation of Chord operations. Full 400-test, warnings-as-errors and static/catalogue gates passed locally. Typed document families and broader orchestration remain follow-up scope.

### Persisted inbox/boundary chunk

Inbox input and passive-write submissions now persist separately from generation admission, with request-ID semantic deduplication, withdrawal, bounded queue size and journal recovery. Post-tool boundaries place all passive writes before selected steering input; final boundaries also select follow-ups. Reset writes promote a tool boundary to final and stale head writes settle unanswered without restoring cut history. Tool-round continuation includes the placed steering context, and final answer settlement plus next boundary placement share one storage batch. The native API exposes explicit queue/placement operations; automatic follow-up run scheduling, configurable agent queue settings and abort cascades remain follow-up scope. Full 396-test, warnings-as-errors and static/catalogue gates passed locally for this chunk.

### Conversation/context/observation chunk

Native conversation forks now inherit visible ancestor entries through the exact cut, copy current/as-of conversation documents into independent instances, and leave initial-policy documents absent. Journal replay reconstructs rewindable document history. Reset markers and latest context edits define the active range; tool results are ordered by assistant calls, with explicit missing-result messages. Generation preparation and entry scans use that visible context. Document/view/commit observations acquire a baseline on the mutation line and publish acknowledged commits only, with bounded self-contained root frames, retirement and close termination.

Swift adaptation: observations use value-semantic `AsyncStream` frames and root replacements rather than Chord operation batches; a caller consumes frames serially. The upstream callback-style watch API, typed document families/migrations, inbox, compaction and broader orchestration still require follow-up. Local Swift 6.3.2 build/static checks and the full 392-test suite passed for this chunk, including nested forks, historical document copies, reset/edit/tool ordering, journal reopen, watch retirement/recreation and bounded convergence. Full v1.1.0 parity is not yet accepted.

* Official pi-ai/pi-durable tag: `abe508e1b89912adde45528136c3221eb69acdd7`.
* AI npm SHA-256: `6caab33cec57480ed02c57fe37428a030a77cc2a0662814b435a5cf8932ad829`.
* Durable npm SHA-256: `a0f95b4a418e8bc219e9cbde06baedada940c62c47068829208e4fff278c07be`.
* Catalogues: 1563 chat / 61 image / 26 classifier; deltas vs v1.0.1: chat +79/-52/199 changed, image +2/-0/0, classifier +6/-0/1. Exact pinned schema-v6 validation and full-record comparisons passed.
* Production candidate: OpenAI Decisions wire/parse/dispatch with billed refusal preservation and no 504 retry; classifier images; sampling-by-effective-thinking-level; Azure provider identity/completions; Bedrock GPT/Haiku effort; retry phrases; 3.5-character context estimate; tiered cost; response/tool duration; ordered native scan cursors; persisted provider session ID.
* Local Swift 6.3.2: warnings-as-errors build; full 388-test suite passed, no skips; static and catalogue corruption checks passed; SBOM/security/licence passed. These results apply to the dirty development candidate, not an accepted release ref.
* Focused nine-test Massif: pass, peak useful heap 11,557,726 bytes; largest named paths are registry registration, JSON decoding and catalogues. CPU clock-sampling collection completed a 388-test run, but gprofng display crashed (139), including machine-view retry; hotspot analysis is unavailable. No measured optimisation accepted.
* AI and durable exact-path matrices are [`docs/upstream-v1.1.0-audit.md`](docs/upstream-v1.1.0-audit.md) and [`docs/durable-v1.1.0-audit.md`](docs/durable-v1.1.0-audit.md). Unresolved rows prevent full parity acceptance. The existing v1.0.1 crosswalk gate is historical; catalogue checks now use v1.1.0 inputs.
* Broad durable features and real-host macOS persistence are incomplete. Current release tags/assets stay at accepted v1.0.1 runtime; no v1.1.0 publication authorised or performed.

## Accepted publication

- Upstream package: `@earendil-works/pi-ai`
- Current upstream release: `v1.0.1`
- Current upstream tag commit: `a7229ddc21810d6245105978033b7df645ecc2f7`
- Verified npm tarball SHA-256: `8a9e69b1309cf93405d87729fa123c8b11c6be7c646b16f34f8bef7b792f9138`
- Swift parity branch: `main`
- Accepted Swift v1.0.1 useful durable runtime: `211da0766cce098cc3525eb918e58f982d8453df`; the native `v1.0.1` tag/release and `upstream-v1.0.1` alias now target that runtime and publish its source-bound SBOM.
- The accepted durable vertical covers the native journal/storage foundation, durable generation/session/recovery and owned-tools runtime. It is useful and published, but it does not claim the full 60-source / 42-suite durable parity roadmap, macOS hosted validation, or completion of later cross-runtime work.
- Historical provider-only runtime `68e4052fde96cd9404aaddc56742c2ae5348664e`, old native tag object `f120f0c8976df20f82a55d1e5c9acfcceb02ff57`, and their original release assets remain recorded as rollback evidence; they are not the current release targets.
- Accepted rollback runtime before v1.0.1 provider work: v1.0.0 runtime commit `7e7e2de2495c646857369d6ac63cb64a5bced5a6`; earlier accepted v0.99.2 runtime `379018acd61375462d02a971e5283be6b009d33e`.

## Exact upstream delta

Release audit scope: `packages/ai` diff from accepted v1.0.0 `a13d35a742c6ef8462812a28fbe1d8c8b7431c32` to v1.0.1 `a7229ddc21810d6245105978033b7df645ecc2f7`.

Exact changed-path count: **19**. Changed-path manifest hash: `ac9e4b76f7bb921a251ac5f5e14af48b1fa73f6e40d4d49e41ee11d5fb902278`. Source/package diff: `+546/-153`; status classes: `18M/1A`.

Changed upstream tests: **6**, manifest hash `fd49b5003edf22d18b5c4a4fa5b4998e5bad49136cc6d356527dd7c3d655a659`. Whole corpus manifest: **171** paths (`164` executable plus support entries), SHA-256 `9d24da3ede393a95a7131b1c9ac494f57d8165161d6eb581109c86809131abfc`.

The detailed disposition matrix is in [`docs/upstream-v1.0.1-audit.md`](docs/upstream-v1.0.1-audit.md). The whole-corpus test crosswalk is in [`docs/upstream-v1.0.1-test-crosswalk.md`](docs/upstream-v1.0.1-test-crosswalk.md) and is fail-closed validated: 6 unique changed rows, dispositions `3 ported / 3 adapted / 0 pending`.

## Exact catalog parity

Verified pinned npm tarball schema-v6 oracle:

- Provider-data manifest: schema `6`, provider files `42`, changed provider JSON files `10`, generatedAt `2026-10-03T12:25:02.573Z`, structure hash `03d2e1aeeee6eb16959d4f727b47b9b187efaf863c688a47889fb90d200e6812`.
- Actual typed Swift export was independently compared against official raw snapshots with zero unexplained differences across all `1615` records. Native structural adaptations are limited to implicit `type` on `1536` chat and `59` image records and default `maxTokens = 0` for `20` classifier records where the official classifier records omit that field. Costs, tiers, provider arrays, image `inputLimits` and compat fields are preserved.
- Chat snapshot: `scripts/models.v1.0.1.json` / exact upstream comparator `scripts/upstream-models.a7229dd.json` / embedded Swift registry `Sources/SwiftAI/Models/Generated/ModelsGenerated.swift`; **1536 models / 41 providers / 10 APIs**.
- Image snapshot: `scripts/image-models.v1.0.1.json` / exact upstream comparator `scripts/upstream-image-models.a7229dd.json` / embedded Swift registry `Sources/SwiftAI/Models/Generated/ImageModelsGenerated.swift`; **59 models / 1 provider / 1 API**.
- Classifier snapshot: `scripts/classifier-models.v1.0.1.json` / exact upstream comparator `scripts/upstream-classifier-models.a7229dd.json` / embedded Swift registry `Sources/SwiftAI/Models/Generated/ClassifierModelsGenerated.swift`; **20 models / 5 providers / 2 APIs**.
- Normalized deltas vs accepted v1.0.0: chat `+17/-13/54 changed`, image `+2/-0/0 changed`, classifier `+5/-0/0 changed`.
- `scripts/validate-model-data.py` derives records directly from the verified tarball/provider shards, validates schema-v6 provider data and stages all generated outputs before replacing accepted outputs. It does not use pre-flattened auditor record files as authority.

Expected comparator output:

```text
ok: 1536 chat models / 41 providers / 10 APIs; 59 image models / 1 providers / 1 APIs; 20 classifier models / 5 providers / 2 APIs; text delta +17/-13/54 changed; image delta +2/-0/0 changed; classifier delta +5/-0/0 changed
```

## Swift implementation, adaptations, and separate follow-up scope

Implemented/adapted in the local v1.0.1 provider candidate:

- Regenerated v1.0.1 chat, image and classifier catalogs from the verified pinned npm artifact; live catalog hydration remains excluded.
- Added native schema-v6 provider-data validation and staged rendering controls for the pinned provider shards. This is a pre-replacement staging preflight, not an atomic multi-file transaction claim.
- Ported Anthropic inline tool definitions with `inline-tools-2026-09-15`, stable initial tool list plus placeholder, full inline `tool_definition` additions/redefinitions, same-name removal suppression, cache-control placement on the outer block, env/effective OAuth name mapping, strict/eager schema preservation, and no-initial-tool fallback.
- Swift has no `system` role. The initial tool-state adaptation is a first-message inert empty assistant metadata entry carrying `toolsAdded`; user, tool-result, non-empty assistant and later assistant metadata do not qualify as the initial tool baseline. Tests cover timestamp collisions, canonical OAuth tool-name collisions and incoming/replayed tool-name mapping.
- Added backward-compatible full tool-delta metadata on `Message` (`toolsAdded`, `toolsRemoved`) while retaining legacy `addedToolNames`. Added compat metadata fields for provider records; preserving these fields does not add broad runtime consumption for other provider APIs.
- Added `ImagesModel.inputLimits` so official image full-record metadata is retained. No image preprocessing/resizing feature is added in this lane.
- Ported Bedrock adaptive thinking `block_binding` and `thinking-binding-controls-2026-08-01` only for eligible families; 4.6 and GovCloud omit binding/beta while preserving effort/budget behavior.
- Ported Cloudflare Workers AI System One direct result-envelope parsing while retaining nested run-record behavior, usage preservation and public `SwiftAI.classify` coverage.
- Added the retryable provider phrase `model is at capacity` while preserving nonretryable quota/billing precedence.
- Preserved Swift ChatGPT OAuth as primitive utilities only. The package has no host browser callback listener; no listener API was invented for the upstream occupied-port behavior.

Out of scope for the provider-only candidate described above:

- The durable implementation was delivered later as the separately validated and published useful vertical recorded below. The earlier readiness report remains historical planning evidence at `/workspace/tmp/swift-ai-durable-v101-plan.md` SHA-256 `5d3a5616aee947d36268c066bf11b19aadcef7b217dd7752fcfa347f44e99e93`.
- Dependency, workflow, Package.swift, README, AGENTS, Makefile or live-credential changes.

## Tests and gates

Local validation for v1.0.1 provider work uses Swift `6.3.2`; heavy Swift gates run under nice `10` with `-j 2` where the command supports it.

Focused local gates passed for the current local candidate:

- Focused provider/catalog filter: Anthropic inline tools, effective OAuth serialization, full tool-delta Codable shape, typed catalog decode controls, Bedrock binding, Cloudflare direct envelope and capacity retry; `10` selected tests / `0` failures (`.artifacts/v1.0.1-validation/focused-prefreeze-controls.log`).
- Native hydration validator: valid tarball `--validate-only` passed; missing-file, source-hash, manifest-schema, bogus-modality, missing-cost, image-output, missing-chat-cap, duplicate, late-classifier and render/format post-staging faults rejected with accepted outputs unchanged.
- `python3 scripts/audit-parity.py`: passed exact full-record text/image/classifier comparators.
- `python3 scripts/audit-parity.py --self-test`: passed deliberate text/image/classifier metadata and crosswalk corruption checks.
- `python3 scripts/static-check.py`: passed.

Final local gates passed for the current local candidate:

- `nice -n 10 swift build -j 2 -Xswiftc -warnings-as-errors`: passed (`.artifacts/v1.0.1-validation/swift-build-warnings-as-errors-final-metadata.log`).
- `nice -n 10 swift test -j 2`: passed, `305` tests / `0` failures (`.artifacts/v1.0.1-validation/swift-test-full-final-metadata.log`).
- Deterministic repeats: `nice -n 10 swift test -j 2` ×2 passed, `305` tests / `0` failures each (`swift-test-deterministic-final-1.log`, `swift-test-deterministic-final-2.log`).
- `nice -n 10 make check MAKEFLAGS=-j2`: passed static checks, SBOM generation/check/scan, warnings-as-errors build and full tests (`make-check-final2.log`).
- `nice -n 10 make sbom-check`: passed. Dirty-local SBOM SHA-256 was `1016ff18ec02ec0492f86e30df19e9fcbbdce98019801187af0cea2ce805ac6e`; this is local dirty-tree evidence, not an accepted runtime SBOM claim (`make-sbom-check-final2.log`).
- `python3 scripts/audit-parity.py`, `python3 scripts/audit-parity.py --self-test` and `python3 scripts/static-check.py`: passed after the final metadata fixes.
- `grep -R "XCTSkip" -n Tests || true`: no matches.
- `git diff --check`: passed.
- Clean source snapshot validation passed audit, warnings-as-errors build and full tests (`clean-source-snapshot-final.log`).

The provider-only candidate was subsequently published at runtime `68e4052...`; the same-version native and alias releases were later reconciled to accepted useful durable runtime `211da076...` as recorded below.

## SBOM/security evidence model

- SBOM tool/version: `swift-ai-sbom` `1.1.0` (pinned local policy `scripts/sbom-policy.json`) plus pinned OSV Scanner `2.5.1`.
- Runtime SBOM SHA-256 is generated from exact accepted runtime commits; embedded revision must match the runtime commit.
- SBOM provenance/dependency graph: root package records exact Git revision and `Package.resolved`; dependency edges are derived from `swift package show-dependencies --format json` as root `swift-ai` -> direct `swift-crypto` -> transitive `swift-asn1`.
- SBOM scan/license disposition: real OSV Scanner JSON output is written to `.artifacts/sbom/osv-scanner.json`; high/critical findings fail unless covered by non-expired structured waivers (`id`, `owner`, `rationale`, `mitigation`, `expires`).
- SBOM artifact retention: Ubuntu/static CI uploads SBOM, checksum, OSV output, scan summary, and license review artifacts with 30-day retention. Durable release assets for accepted releases are version-pinned under `upstream-vX.Y.Z` and published by the manual SBOM release workflow after validation.
- Dependency-lock policy: `Package.resolved` is tracked and required for SBOM generation/validation; volatile SBOM output under `.artifacts/` is not committed.

## v1.0.1 initial provider publication evidence

Accepted runtime commit: `68e4052fde96cd9404aaddc56742c2ae5348664e` (`Port pi-ai v1.0.1 provider parity`). Parent: `daa9d9b07d13e5172f587b95918c6d9cedf43925`. Tree: `eb8d04a07912ce175e101dba36b6ca087de0b790`.

Hosted CI for the accepted runtime:

- Push CI run: <https://github.com/rcarmo/swift-ai/actions/runs/37165556108>
- Runtime CI jobs: `111327607813` (`swift-test (ubuntu-latest)`) and `111327607944` (`static-check`), both successful.
- Hosted tests: `305` tests, `0` failures.
- Runtime SBOM artifact: `11289268006`; artifact ZIP SHA-256 `7a2f41e16e1e575ae9262cca23db1f76f06e9c02f64949f76d83851d7e332162`.
- Runtime inner SBOM SHA-256: `352b5b40f7600b794d1acd956efbb05a3b565a263e2bd91da05270a55f71fd57`.
- SBOM provenance: root component `swift-ai@1.0.1`; embedded `git.revision=68e4052fde96cd9404aaddc56742c2ae5348664e`; `git.dirty=false`; CycloneDX component count `2` (`swift-crypto`, `swift-asn1`); dependency graph has `3` dependency entries.
- Security/license: OSV scanner returned no vulnerabilities; high/critical findings are empty; no waivers; license review passed for `swift-asn1` and `swift-crypto` under approved licenses.

Historical initial native provider release (superseded by the useful durable replacement below):

- Native release: `v1.0.1`, release database ID `402757174`, workflow run `37165998133` (`publish-sbom` job `111328878306`).
- Annotated tag object: `f120f0c8976df20f82a55d1e5c9acfcceb02ff57` by `Rui Carmo <rui.carmo@gmail.com>`, targeting runtime `68e4052fde96cd9404aaddc56742c2ae5348664e`.
- Assets: `608838456` (`sbom.cdx.json`, digest `sha256:352b5b40f7600b794d1acd956efbb05a3b565a263e2bd91da05270a55f71fd57`) and `608838457` (`sbom.cdx.json.sha256`, digest `sha256:438349ed2a330fe02a6d86208c2c8a0bcf6e2b0cb122477d35b3b39708d76d7a`).

Historical initial upstream alias release (superseded by the useful durable replacement below):

- Upstream alias release: `upstream-v1.0.1`, release database ID `402759260`, workflow run `37166282241` (`publish-sbom` job `111329721226`).
- Alias ref: lightweight `upstream-v1.0.1 -> 68e4052fde96cd9404aaddc56742c2ae5348664e`.
- Assets: `608847003` (`sbom.cdx.json`, digest `sha256:352b5b40f7600b794d1acd956efbb05a3b565a263e2bd91da05270a55f71fd57`) and `608847004` (`sbom.cdx.json.sha256`, digest `sha256:438349ed2a330fe02a6d86208c2c8a0bcf6e2b0cb122477d35b3b39708d76d7a`).

The historical provider native and alias SBOM bytes were identical to their hosted runtime artifact. Those old tag objects and asset bytes were preserved as rollback evidence during the later same-version replacement. The provider publication was not, by itself, durable completion.

A first historical tag-object creation attempt failed before any mutation because the Git Data API `tagger` field was submitted as a quoted JSON string. The corrected, authorised request used a JSON request body with a nested `tagger` object and then created `refs/tags/v1.0.1` from the returned tag-object SHA.

## Accepted v1.0.1 useful durable vertical

Accepted runtime commit: `211da0766cce098cc3525eb918e58f982d8453df` (`Make durable journal lock test portable`). Parent and production runtime checkpoint: `b87bb8d97fd86004c36ad5a734d1ce01e7f95beb` (`Add durable owned tools runtime`). The successor changes only `Tests/SwiftAITests/Durable/DurableJournalStorageTests.swift`; accepted S1c production sources remain byte-identical to `b87bb8d`.

The published vertical builds on S1b durable generation/session/recovery and S1c owned-tools runtime. Local validation at the runtime checkpoint included full-main and genuine clean-clone 379-test gates, focused durable suites, static checks, warnings-as-errors, no-skip checks, source-bound SBOM/security, and exact provenance. The final portability correction additionally passed three parallel targeted runs, one serial target, Journal8, and a genuine two-clone cold target/Journal8 validation.

Hosted runtime evidence:

- Original push CI run `37190522552`, attempt 1, failed only because the accepted foundational lock-process test hardcoded a local Swift 6.3.2 interpreter path. It was not retried.
- Fixture correction chronology was preserved: the first local target exposed XCTest stdout before the `LOCKED` acknowledgement; the next exposed premature storage deallocation; the next exposed checked-continuation diagnostics contaminating stderr. The final fixture holds storage strongly, writes a dedicated stderr acknowledgement, and blocks with Linux `pause()` until parent `SIGKILL`, without sleeps, retries, timeout widening, skips, assertion weakening or production changes.
- Natural successor push CI run `37194954000`, attempt 1, event `push`, exact runtime `211da076...`: success. Jobs `111414781814` (`swift-test (ubuntu-latest)`) and `111414781939` (`static-check`) both passed with every step successful. Hosted tests: **379 tests / 0 failures**; the corrected journal lock test executed and passed.
- Hosted SBOM artifact: ID `11300970536`; archive SHA-256 `67c223fcaeb5de886adbc8b9be1bb014e7dd84d70ea15e19cd5eba22f1205257`; source-bound SBOM SHA-256 `91a2696cbf7df84ab02b4b5e22bfc3437e8bd9ee76599bcaa02cc7491a2aea63`.
- SBOM provenance/security: root `swift-ai@1.0.1`; full `git.revision=211da076...`; `git.dirty=false`; 2 components; 3 dependency records / 2 edges (`swift-ai -> swift-crypto -> swift-asn1`); pinned real OSV Scanner `2.5.1` with zero vulnerabilities, high/critical findings or waivers; license review passed with zero unknown/incompatible components.

Same-version publication evidence:

- Native annotated tag object `665865debbf4cf6a9ed3d3f9de43dbb479f85541`, tagged by `Rui Carmo <rui.carmo@gmail.com>`, targets runtime `211da076...`.
- The first native publisher run `37195824689`, attempt 1, validated the exact runtime, tag and SBOM, then failed before asset upload because native release `target_commitish=main` could not be resolved in the workflow's detached checkout. It was not rerun. A bounded one-field release-target remediation changed release ID `402757174` to full runtime SHA.
- New native publisher run `37196193047`, attempt 1: success. Native release ID `402757174`; public assets `609645485` (`sbom.cdx.json`) and `609645500` (`sbom.cdx.json.sha256`).
- Upstream alias publisher run `37196599838`, attempt 1: success. Lightweight `upstream-v1.0.1 -> 211da076...`; release ID `402759260`; public assets `609655851` (`sbom.cdx.json`) and `609655848` (`sbom.cdx.json.sha256`).
- Native and alias public SBOM bytes are identical: SHA-256 `91a2696cbf7df84ab02b4b5e22bfc3437e8bd9ee76599bcaa02cc7491a2aea63`. The public sidecar file SHA-256 is `fddb4e05f7e459a03b17da734dd961744f43f24a435b60d4aa214afc8c5e0139`, and its contents verify the SBOM.
- Complete publication inventory remained 16 tag refs, 16 releases and 32 assets. The other 15 refs, 15 releases and 30 assets were preserved at each staged native/alias boundary. Historical provider runtime `68e4052...`, tag object `f120f0c...`, old native assets `608838456/608838457`, and old alias assets `608847003/608847004` remain rollback evidence.

Scope limits remain explicit: routine hosted CI is Ubuntu/static only and does not establish macOS behavior. This useful S1b/S1c vertical does not claim completion of the full 60-source / 42-suite durable parity roadmap, all later durable features, or broader Go/Rust parity work.

Release refs and public assets target runtime `211da076...`, not any later documentation-only ledger commit.

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
