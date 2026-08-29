# Upstream pi-ai v0.84.4 release parity audit

Baseline: accepted official release `v0.84.3` / `4e58f324fae8ebfa98a3d45181fb248072a2afac`.
Target: official release `v0.84.4` / `b79e4cc834970cca69daebffab7df1da7d1e52c4`.
Scope: release-only audit pinned to `b79e4cc`; no commits beyond the tag were considered.

Verified npm artifact SHA-256: `dfd3c929cee5a7387199a0a24dfc1be2096f1ea8f59ffb8285198a0ed01ebf93`.

The bounded `packages/ai` delta is exactly 15 changed paths: 5 source files, 2 scripts (1 modified + 1 added), 6 tests (5 modified + 1 added), and 2 package/docs paths. The cumulative whole-corpus test crosswalk covers exactly 137 upstream `packages/ai/test/*.test.ts` files in [`upstream-v0.84.4-test-crosswalk.md`](upstream-v0.84.4-test-crosswalk.md).

## Exact changed-path disposition matrix

| # | Upstream path | Swift disposition |
| ---: | --- | --- |
| 1 | `packages/ai/CHANGELOG.md` | Package/docs metadata recorded in STATUS/PARITY/RELEASE/audit. |
| 2 | `packages/ai/package.json` | Package version/artifact metadata recorded in STATUS/PARITY/RELEASE/audit. |
| 3 | `packages/ai/scripts/generate-models.ts` | Adapted via exact npm generated registry snapshots and Swift full-record comparator/self-test gates. |
| 4 | `packages/ai/scripts/openrouter-reasoning-options.ts` | Ported: OpenRouter `supported_efforts`/mandatory/optional/off semantics represented as Swift `thinkingLevelMap` metadata and request-payload behavior. |
| 5 | `packages/ai/src/api/mistral-conversations.ts` | Ported: fragmented indexed tool-call chunks merge when later fragments omit tool-call ID and carry an empty function name. |
| 6 | `packages/ai/src/api/openai-completions.ts` | Ported: explicit `toolChoice` serializes without tools; adjacent streamed `reasoning.text` and `reasoning.summary` details merge while preserving metadata/order and replay once via `reasoning_details`. |
| 7 | `packages/ai/src/image-models.generated.ts` | Ported via generated image catalog: 50 image models, +5/-0/0 full-record delta. |
| 8 | `packages/ai/src/providers/cloudflare-ai-gateway.ts` | Ported/adapted via generated Cloudflare Gateway catalog entries for tool-capable Workers AI models using `workers-ai/` IDs and `/compat` endpoint, with dedupe enforced by full-record comparator. |
| 9 | `packages/ai/src/types.ts` | Ported/adapted: provider-neutral `toolChoice` documentation semantics are covered by explicit no-tools payload test. |
| 10 | `packages/ai/test/fireworks-models.test.ts` | Ported/adapted: Fireworks removal and retained metadata covered by exact catalog comparator and generated metadata tests. |
| 11 | `packages/ai/test/mistral-http-transport.test.ts` | Ported: fragmented Mistral tool-call continuation case covered by executable SSE parser test. |
| 12 | `packages/ai/test/openai-completions-reasoning-details.test.ts` | Ported: adjacent reasoning-detail merge and exact once-only replay covered by executable parser/replay test. |
| 13 | `packages/ai/test/openai-completions-tool-choice.test.ts` | Ported: explicit `toolChoice: "none"` serializes even when no tools are present. |
| 14 | `packages/ai/test/openrouter-reasoning-options.test.ts` | Ported: OpenRouter mandatory/optional/off thinkingLevelMap and payload omission/none/effort behavior covered. |
| 15 | `packages/ai/test/zai-coding-plan-models.test.ts` | Ported: ZAI GLM-5.3 generated metadata/cost covered by exact catalog and representative assertions. |

## Catalog parity evidence

Text catalog: `scripts/models.v0.84.4.json` equals `scripts/upstream-models.b79e4cc.json`; embedded registry equals normalized snapshot. Full records: `1290/1290`, providers `39`, APIs `9`, delta `+57/-79/227 changed`.

Image catalog: `scripts/image-models.v0.84.4.json` equals `scripts/upstream-image-models.b79e4cc.json`; embedded registry equals snapshot. Full records: `50/50`, providers `1`, APIs `1`, delta `+5/-0/0 changed`.

## Portable behavior evidence

Implemented/adapted in Swift:

- OpenAI-compatible Chat Completions serializes explicit `toolChoice`, including `"none"`, even when no tools are defined.
- OpenAI-compatible streamed adjacent `reasoning.text` and `reasoning.summary` deltas merge while preserving metadata/order, then replay exactly once through `reasoning_details` from the thinking signature.
- Mistral fragmented indexed tool-call chunks merge when later fragments omit tool-call ID and have an empty function name.
- OpenRouter `supported_efforts` maps to Swift `thinkingLevelMap` for mandatory/optional/off semantics, with payload omission/`none`/explicit effort behavior tested.
- Cloudflare Gateway mirrors tool-capable Workers AI models with `workers-ai/` prefix and `/compat` endpoint through the generated catalog; duplicate provider/id pairs are rejected by the comparator.
- ZAI GLM-5.3 metadata/cost, Fireworks removal, DeepSeek V4 Flash Vision Exp, and the broader generated catalog changes are enforced by full-record text/image comparators.
- Image catalog additions include `meta/muse-image` and four Recraft v4 styles/vector variants.

JS-only/N/A decisions are limited to package version/changelog mechanics and generator implementation details that are represented by exact generated Swift snapshots and comparator fault gates.

## Validation requirements

- `scripts/audit-parity.py` enforces exact text/image full-record parity, embedded registry equality, exact text delta `+57/-79/227`, exact image delta `+5/-0/0`, and `--self-test` metadata fault injection.
- Local gates must pass: `swift build -Xswiftc -warnings-as-errors`, `swift test`, deterministic repeats, `make check`, parity/static checks, and zero hidden `XCTSkip` matches.
- Acceptance requires GitHub Actions `static-check`, Ubuntu Swift tests, and macOS Swift tests all green for the pushed commit.
