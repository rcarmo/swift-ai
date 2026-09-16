# Upstream pi-ai v0.85.1 release parity audit

Baseline: accepted official release `v0.85.0` / `107d79f11072bbc8a3a757ed7fd69596bee7d68c`.
Target: official release `v0.85.1` / `d981de1229ef899957bbe968bc8dcda02a21f477`.
Scope: release-only audit pinned to `d981de1`; no commits beyond the tag were considered.

Verified npm artifact SHA-256: `af7d11986179445ce6fe88b37d57de22f823c0ffd3a65cae31c555b7f5e99253`.
Verified npm artifact SHA-512: `f958152090e40ced9e7d824a104aaf3d31f8ce69c8697740a6919b3bebca140f6acb93dd8458807a7b8502453ea220927ce0b874c1c3cab8dd41e2f86680b909`.

The bounded `packages/ai` delta is exactly 9 modified paths. Changed-path manifest hash: `ee26f669d92dc77b265731165a2ff69ccb67defba92517cbbd5f97a186e187d2`. The cumulative whole-corpus test crosswalk remains exactly 142 upstream `packages/ai/test/*.test.ts` files in [`upstream-v0.85.1-test-crosswalk.md`](upstream-v0.85.1-test-crosswalk.md); corpus hash: `56f8742065a4ad01d73e5aee53035324f2e7333a735222ab15db870819e29065`. The modified-test slice is exactly 3 paths with hash `f7e274bf229c90fc22ba22384c5b89f71a5c6801f77067d099525a9cdc537610`.

Exact manifests are committed as [`upstream-v0.85.1-changed-paths.txt`](upstream-v0.85.1-changed-paths.txt) and [`upstream-v0.85.1-test-corpus.txt`](upstream-v0.85.1-test-corpus.txt); `scripts/audit-parity.py` validates their row counts/hashes and this table/crosswalk row counts.

## Exact changed-path disposition matrix

| # | Marker | Upstream path | Swift disposition |
| ---: | :---: | --- | --- |
| 1 | M | `packages/ai/CHANGELOG.md` | Package changelog metadata recorded in RELEASE/STATUS; no Swift runtime behavior. |
| 2 | M | `packages/ai/package.json` | Package version/artifact metadata recorded; npm SHA-256/SHA-512 verified. |
| 3 | M | `packages/ai/scripts/generate-models.ts` | Adapted via exact v0.85.1 artifact snapshots, Swift generated text/image registries, full-record current/baseline comparator, and deliberate text/image field faults. |
| 4 | M | `packages/ai/src/api/openai-responses.ts` | Ported: explicit prompt-cache mode maps none to prompt_cache_options {mode:"explicit"}, long mode to {ttl:"30m"} for supported models, and legacy models retain prompt_cache_retention "24h" without concurrent legacy/options emission. |
| 5 | M | `packages/ai/src/image-models.generated.ts` | Ported via exact v0.85.1 image snapshot and generated Swift image registry; MAI 2.6 and Flash additions covered by full-record comparator and model tests. |
| 6 | M | `packages/ai/src/types.ts` | Ported: OpenAI Responses compat gains supportsExplicitPromptCacheMode; GPT-6 Astra catalog/compat/thinking-level metadata decodes through existing Swift model types. |
| 7 | M | `packages/ai/test/cache-retention.test.ts` | Ported by Swift request-body matrix tests for Responses prompt cache options/legacy retention behavior. |
| 8 | M | `packages/ai/test/max-thinking.test.ts` | Ported by GPT-6 Astra thinking-level/support tests covering off/minimal/low/medium/high/xhigh/max and max clamp behavior. |
| 9 | M | `packages/ai/test/supports-xhigh.test.ts` | Ported by GPT-6 Astra catalog/compat tests covering OpenAI/Codex/provider aliases, context/output limits, costs, modalities, long tier, tool search, and additional tools. |

## Catalog parity evidence

Text catalog: `scripts/models.v0.85.1.json` equals `scripts/upstream-models.d981de1.json`; embedded registry equals normalized snapshot. Full records: `1354/1354`, providers `39`, APIs `9`, delta `+20/-2/18 changed`.

Image catalog: `scripts/image-models.v0.85.1.json` equals `scripts/upstream-image-models.d981de1.json`; embedded image registry equals snapshot. Full records: `52/52`, providers `1`, APIs `1`, delta `+2/-0/0 changed`.

## Portable behavior evidence

- OpenAI Responses prompt-cache options are request-body tested for explicit `none`, supported `long`, and legacy long-retention behavior without duplicate legacy/options fields.
- GPT-6 Astra text and image catalog records preserve OpenAI/Codex/provider aliases, 272000 context, 128000 max output, text/image modalities, 10/50/1/12.5 costs, long tier, tool search/additional tools, and full thinking levels.
- Exact text/image current-vs-upstream and v0.85.0 baseline deltas are enforced by full-record comparators and deliberate text/image field faults.

## Runtime acceptance evidence

Accepted runtime commit: `b1192ff853ac5b312cc9dcef47b76e1c97ddc70f`; CI run `35154754780`; jobs `104991425729` (`swift-test (ubuntu-latest)`) and `104991425958` (`static-check`) succeeded with `274` tests and no failures. SBOM artifact `10470264358` has archive SHA-256 `88c3a2b15d55afaf7e648fa93dd81a772c1a20d9a840b0af26ec91ca800c719f`; inner SBOM SHA-256 `93f0bfe9594652b5f6a1bbfecef2c08c625a693180d2d2258c798e0118d4e5b8`; embedded revision matches; OSV/license scans passed.

## Validation requirements

- `scripts/audit-parity.py` enforces exact text/image full-record parity, embedded registry equality, exact text delta `+20/-2/18`, exact image delta `+2/-0/0`, committed manifest row counts/hashes, audit/crosswalk row counts, and `--self-test` metadata fault injection including image baseline corruption.
- Local gates must pass: warnings-as-errors build, full/deterministic Swift tests, `make check`, parity/static checks, SBOM/OSV/license checks, clean checkout, and zero hidden `XCTSkip` matches.
- Acceptance requires one final GitHub Actions run with Ubuntu Swift tests and static/SBOM checks green; macOS hosted CI remains disabled.
