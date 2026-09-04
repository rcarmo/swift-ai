# Upstream pi-ai v0.85.0 release parity audit

Baseline: accepted official release `v0.84.4` / `b79e4cc834970cca69daebffab7df1da7d1e52c4`.
Target: official release `v0.85.0` / `107d79f11072bbc8a3a757ed7fd69596bee7d68c`.
Scope: release-only audit pinned to `107d79f`; no commits beyond the tag were considered.

Verified npm artifact SHA-256: `46188bdacb555a07466a0111f3963f20932a16199e4d6cfb8d44a7fe5fc6e342`.
Verified npm artifact SHA-512: `09b79e647dcd1dabfb46cd7cdad62ad1ea020167c377532f3805cace89c8178b8ddee3bdf4407c893d477f21a87c998f9007fc31e23038142daaa774ce0acf58`.

The bounded `packages/ai` delta is exactly 51 changed paths: source/scripts 19 (16M/2A/1D), tests 29 (22M/6A/1D), package/docs 3. Changed-path manifest hash: `db461a56838926cf60d4ae0196ed98fcc215616dacff013ad8c235bb8ad9b83f`. The cumulative whole-corpus test crosswalk covers exactly 142 upstream `packages/ai/test/*.test.ts` files in [`upstream-v0.85.0-test-crosswalk.md`](upstream-v0.85.0-test-crosswalk.md); corpus hash: `56f8742065a4ad01d73e5aee53035324f2e7333a735222ab15db870819e29065`.

## Exact changed-path disposition matrix

| # | Upstream path | Swift disposition |
| ---: | --- | --- |
| 1 | `M	packages/ai/CHANGELOG.md` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 2 | `M	packages/ai/README.md` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 3 | `M	packages/ai/package.json` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 4 | `M	packages/ai/scripts/generate-models.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 5 | `M	packages/ai/src/api/anthropic-messages.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 6 | `A	packages/ai/src/api/cloudflare-ai-binding.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 7 | `D	packages/ai/src/api/cloudflare-gateway-binding.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 8 | `M	packages/ai/src/api/openai-codex-responses.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 9 | `M	packages/ai/src/api/openai-completions.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 10 | `M	packages/ai/src/api/openai-responses-shared.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 11 | `M	packages/ai/src/api/openai-responses.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 12 | `M	packages/ai/src/api/pi-messages.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 13 | `M	packages/ai/src/index.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 14 | `M	packages/ai/src/models.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 15 | `M	packages/ai/src/providers/cloudflare-ai-gateway.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 16 | `M	packages/ai/src/providers/faux.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 17 | `M	packages/ai/src/providers/openrouter.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 18 | `M	packages/ai/src/types.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 19 | `A	packages/ai/src/utils/assistant-message-frame.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 20 | `M	packages/ai/src/utils/node-http-proxy.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 21 | `M	packages/ai/src/utils/retry.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 22 | `M	packages/ai/src/utils/uuid.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 23 | `M	packages/ai/test/anthropic-auth-token.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 24 | `M	packages/ai/test/anthropic-cache-write-1h-cost.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 25 | `A	packages/ai/test/anthropic-mid-conversation-effort.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 26 | `M	packages/ai/test/anthropic-sse-parsing.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 27 | `A	packages/ai/test/anthropic-thinking-binding-e2e.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 28 | `A	packages/ai/test/assistant-message-frame.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 29 | `M	packages/ai/test/baseten-models.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 30 | `A	packages/ai/test/cloudflare-ai-binding.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 31 | `D	packages/ai/test/cloudflare-gateway-binding.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 32 | `M	packages/ai/test/constrained-sampling.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 33 | `M	packages/ai/test/generate-models-strict.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 34 | `M	packages/ai/test/github-copilot-anthropic.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 35 | `M	packages/ai/test/github-copilot-oauth.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 36 | `M	packages/ai/test/node-http-proxy.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 37 | `M	packages/ai/test/openai-codex-stream.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 38 | `M	packages/ai/test/openai-completions-cache-control-format.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 39 | `M	packages/ai/test/openai-completions-thinking-as-text.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 40 | `M	packages/ai/test/openai-completions-tool-choice.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 41 | `M	packages/ai/test/openai-completions-tool-result-images.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 42 | `A	packages/ai/test/openai-completions-vllm-priority.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 43 | `M	packages/ai/test/openai-responses-compat.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 44 | `M	packages/ai/test/openai-responses-namespace.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 45 | `M	packages/ai/test/openrouter-cache-control-models.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 46 | `M	packages/ai/test/pi-messages.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 47 | `A	packages/ai/test/pre-generation-error.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 48 | `M	packages/ai/test/qwen-token-plan-models.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 49 | `M	packages/ai/test/tool-call-id-normalization.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 50 | `M	packages/ai/test/uuid.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |
| 51 | `M	packages/ai/test/xai-responses.test.ts` | Covered by exact generated snapshots, validators, or existing Swift runtime tests. |

## Catalog parity evidence

Text catalog: `scripts/models.v0.85.0.json` equals `scripts/upstream-models.107d79f.json`; embedded registry equals normalized snapshot. Full records: `1336/1336`, providers `39`, APIs `9`, delta `+72/-26/79 changed`.

Image catalog: `scripts/image-models.v0.85.0.json` equals `scripts/upstream-image-models.107d79f.json`; embedded registry equals snapshot. Full records: `50/50`, providers `1`, APIs `1`, delta `+0/-0/0 changed`.

## Portable behavior evidence

- Assistant message frame/reduction support preserves providerThinkingLevel and validates stream order/content indexes.
- Anthropic mid-conversation effort support adds beta/header and providerThinkingLevel coverage while retaining signed-thinking/history/replay/error/usage behavior.
- OpenAI Responses supportsMaxOutputTokens gates max_output_tokens and clamps the minimum to 16 when supported.
- OpenAI-compatible vLLM priority serializes through production request-body construction.
- UUIDv7 timestamp extraction and expanded NO_PROXY wildcard/IPv6/host:port behavior are covered in core utilities.
- Codex terminal SSE without a trailing blank line is covered by shared SSE EOF flushing used by Codex/Responses parsing.
- Cloudflare AI binding replacement is adapted as SwiftPM has no Workers binding object; generated Cloudflare catalog/routing and request URL behavior remain covered.

## Validation requirements

- `scripts/audit-parity.py` enforces exact text/image full-record parity, embedded registry equality, exact text delta `+72/-26/79`, exact image delta `+0/-0/0`, and `--self-test` metadata fault injection.
- Local gates must pass: warnings-as-errors build, full/deterministic Swift tests, `make check`, parity/static checks, SBOM/OSV/license checks, clean checkout, and zero hidden `XCTSkip` matches.
- Acceptance requires one final GitHub Actions run with Ubuntu Swift tests and static/SBOM checks green; macOS hosted CI remains disabled.
