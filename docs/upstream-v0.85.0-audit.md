# Upstream pi-ai v0.85.0 release parity audit

Baseline: accepted official release `v0.84.4` / `b79e4cc834970cca69daebffab7df1da7d1e52c4`.
Target: official release `v0.85.0` / `107d79f11072bbc8a3a757ed7fd69596bee7d68c`.
Scope: release-only audit pinned to `107d79f`; no commits beyond the tag were considered.

Verified npm artifact SHA-256: `46188bdacb555a07466a0111f3963f20932a16199e4d6cfb8d44a7fe5fc6e342`.
Verified npm artifact SHA-512: `09b79e647dcd1dabfb46cd7cdad62ad1ea020167c377532f3805cace89c8178b8ddee3bdf4407c893d477f21a87c998f9007fc31e23038142daaa774ce0acf58`.

The bounded `packages/ai` delta is exactly 51 changed paths: source/scripts 19 (16M/2A/1D), tests 29 (22M/6A/1D), package/docs 3. Changed-path manifest hash: `db461a56838926cf60d4ae0196ed98fcc215616dacff013ad8c235bb8ad9b83f`. The cumulative whole-corpus test crosswalk covers exactly 142 upstream `packages/ai/test/*.test.ts` files in [`upstream-v0.85.0-test-crosswalk.md`](upstream-v0.85.0-test-crosswalk.md); corpus hash: `56f8742065a4ad01d73e5aee53035324f2e7333a735222ab15db870819e29065`.

Exact manifests are committed as [`upstream-v0.85.0-changed-paths.txt`](upstream-v0.85.0-changed-paths.txt) and [`upstream-v0.85.0-test-corpus.txt`](upstream-v0.85.0-test-corpus.txt); `scripts/audit-parity.py` validates their row counts/hashes and this table/crosswalk row counts.

## Exact changed-path disposition matrix

| # | Marker | Upstream path | Swift disposition |
| ---: | :---: | --- | --- |
| 1 | M | `packages/ai/CHANGELOG.md` | Package changelog metadata recorded in RELEASE/STATUS; no Swift runtime behavior. |
| 2 | M | `packages/ai/README.md` | Upstream README metadata only; Swift README normalization remains separately blocked until runtime acceptance. |
| 3 | M | `packages/ai/package.json` | Package version/artifact metadata recorded; npm SHA-256/SHA-512 verified. |
| 4 | M | `packages/ai/scripts/generate-models.ts` | Adapted via exact v0.85.0 artifact snapshots, Swift generator destination, full-record comparator, and deliberate text/image faults. |
| 5 | M | `packages/ai/src/api/anthropic-messages.ts` | Ported: mid-conversation effort beta headers, adaptive output_config, providerThinkingLevel, final `input_transformations` diagnostics, pre-output fallback skip, and mid-output fallback error; existing production parser/replay/error/usage tests retained. |
| 6 | A | `packages/ai/src/api/cloudflare-ai-binding.ts` | N/A/adapted: JS Workers binding object has no SwiftPM equivalent; Swift preserves portable Cloudflare catalog/routing/base URL behavior. |
| 7 | D | `packages/ai/src/api/cloudflare-gateway-binding.ts` | Deleted upstream; Swift never exposed this JS binding object, so no runtime deletion needed. |
| 8 | M | `packages/ai/src/api/openai-codex-responses.ts` | Ported/adapted through shared SSE EOF flush and Codex terminal/error parser tests. |
| 9 | M | `packages/ai/src/api/openai-completions.ts` | Ported: vLLM priority; existing tool-choice, reasoning-details, tool-result image, custom delta, parser/error/usage tests retained. |
| 10 | M | `packages/ai/src/api/openai-responses-shared.ts` | Ported/adapted via Swift OpenAIResponsesProvider SSE parser, including terminal `errorMessage` cleanup, `incomplete_details.reason` stop mapping, custom tool/reasoning replay tests. |
| 11 | M | `packages/ai/src/api/openai-responses.ts` | Ported: supportsMaxOutputTokens omission and minimum 16 clamp; existing Responses request/parser tests retained. |
| 12 | M | `packages/ai/src/api/pi-messages.ts` | Ported/adapted through existing PiMessages production request/SSE/diagnostic tests; no additional Swift-specific transport change. |
| 13 | M | `packages/ai/src/index.ts` | Package export wiring; SwiftPM target recursively exposes public symbols, including AssistantMessageFrame types. |
| 14 | M | `packages/ai/src/models.ts` | Ported via generated catalog snapshots and cost/usage representative tests. |
| 15 | M | `packages/ai/src/providers/cloudflare-ai-gateway.ts` | Ported/adapted via generated Cloudflare Gateway records and request URL/env substitution tests. |
| 16 | M | `packages/ai/src/providers/faux.ts` | Ported/adapted through Swift Faux provider/test-double behavior and error/pre-generation tests. |
| 17 | M | `packages/ai/src/providers/openrouter.ts` | Ported through generated OpenRouter routing/catalog metadata and existing cache/reasoning tests. |
| 18 | M | `packages/ai/src/types.ts` | Ported: providerThinkingLevel plus new compat fields decode/encode in Swift model/message types. |
| 19 | A | `packages/ai/src/utils/assistant-message-frame.ts` | Ported: Swift AssistantMessageFrameEncoder/reducer plus custom strict discriminated JSON `Codable` wire grammar cover live partial offset reconciliation, legacy JSON-prefix checkpoint/resume, terminal omission, purity/metadata, start-partial sanitization, exact start/content whitelists, required non-null start core fields, required content fields, null/wrong-type optional rejection, authoritative absent/empty end signatures, and wrong-order/kind/index/end/unknown-case/extra-key rejection. |
| 20 | M | `packages/ai/src/utils/node-http-proxy.ts` | Ported: NO_PROXY bare domain, wildcard, leading-dot, IPv6 literal, and host:port matching. |
| 21 | M | `packages/ai/src/utils/retry.ts` | Ported/adapted via existing RetryPolicy/ProviderRetry cancellation and retry tests. |
| 22 | M | `packages/ai/src/utils/uuid.ts` | Ported: UUIDv7 timestamp extraction and existing RFC layout/monotonicity tests. |
| 23 | M | `packages/ai/test/anthropic-auth-token.test.ts` | Ported/adapted through Anthropic request header/beta override tests and production request builders. |
| 24 | M | `packages/ai/test/anthropic-cache-write-1h-cost.test.ts` | Ported through Anthropic usage/cache-write cost assertions. |
| 25 | A | `packages/ai/test/anthropic-mid-conversation-effort.test.ts` | Ported by testUpstream0850AnthropicMidConversationEffortHeadersAndProviderLevel. |
| 26 | M | `packages/ai/test/anthropic-sse-parsing.test.ts` | Ported through Anthropic SSE parser tests for text/thinking/tool/usage/error behavior, input transformation diagnostics, and fallback marker handling. |
| 27 | A | `packages/ai/test/anthropic-thinking-binding-e2e.test.ts` | Live-only/adapted: credential-gated E2E not faked; portable beta/providerThinkingLevel/replay behavior covered deterministically. |
| 28 | A | `packages/ai/test/assistant-message-frame.test.ts` | Ported by CoreUtilityTests assistant frame encoder/reducer/wire tests covering production frame state machine, exact upstream JSON grammar, strict malformed decode rejection, legacy grammar prefix checkpoints, validation invariants, and metadata purity. |
| 29 | M | `packages/ai/test/baseten-models.test.ts` | Ported through generated Baseten catalog/compat metadata tests. |
| 30 | A | `packages/ai/test/cloudflare-ai-binding.test.ts` | N/A/adapted: JS Workers binding replacement; Swift covers portable Cloudflare generated records/routing. |
| 31 | D | `packages/ai/test/cloudflare-gateway-binding.test.ts` | Deleted upstream; legacy binding test not in final corpus and no Swift equivalent existed. |
| 32 | M | `packages/ai/test/constrained-sampling.test.ts` | Ported through strict schema/grammar/tool validation tests. |
| 33 | M | `packages/ai/test/generate-models-strict.test.ts` | Adapted via full-record clean regeneration checks and text/image deliberate fault gates. |
| 34 | M | `packages/ai/test/github-copilot-anthropic.test.ts` | Ported through Copilot Anthropic header/adaptive thinking tests. |
| 35 | M | `packages/ai/test/github-copilot-oauth.test.ts` | Ported through Copilot OAuth/catalog/policy/retry/persistence tests. |
| 36 | M | `packages/ai/test/node-http-proxy.test.ts` | Ported by CoreUtilityTests.testHTTPProxyResolution expanded NO_PROXY cases. |
| 37 | M | `packages/ai/test/openai-codex-stream.test.ts` | Ported/adapted through Codex SSE parser/error/terminal EOF behavior and compression/transport tests. |
| 38 | M | `packages/ai/test/openai-completions-cache-control-format.test.ts` | Ported through OpenAI-compatible Anthropic cache-control format tests. |
| 39 | M | `packages/ai/test/openai-completions-thinking-as-text.test.ts` | Ported through thinking-as-text replay tests. |
| 40 | M | `packages/ai/test/openai-completions-tool-choice.test.ts` | Ported through tool_choice required/none request-body tests. |
| 41 | M | `packages/ai/test/openai-completions-tool-result-images.test.ts` | Ported through multimodal tool-result replay tests. |
| 42 | A | `packages/ai/test/openai-completions-vllm-priority.test.ts` | Ported by vLLM priority request-body assertion in testUpstream0850OpenAIResponsesMaxOutputTokenCompatAndVLLMPriority. |
| 43 | M | `packages/ai/test/openai-responses-compat.test.ts` | Ported by supportsMaxOutputTokens omission/clamp tests plus existing Responses compatibility tests. |
| 44 | M | `packages/ai/test/openai-responses-namespace.test.ts` | Ported through namespace/tool-call ID normalization and Responses replay tests. |
| 45 | M | `packages/ai/test/openrouter-cache-control-models.test.ts` | Ported through generated OpenRouter catalog/cache-control metadata tests. |
| 46 | M | `packages/ai/test/pi-messages.test.ts` | Ported through PiMessages request/SSE/diagnostic tests. |
| 47 | A | `packages/ai/test/pre-generation-error.test.ts` | Ported/adapted through Swift provider missing-auth/pre-generation error paths and stream error propagation tests. |
| 48 | M | `packages/ai/test/qwen-token-plan-models.test.ts` | Ported via exact generated Qwen Token Plan catalog metadata/request tests. |
| 49 | M | `packages/ai/test/tool-call-id-normalization.test.ts` | Ported through tool-call ID normalization tests. |
| 50 | M | `packages/ai/test/uuid.test.ts` | Ported through UUIDv7 timestamp/layout tests. |
| 51 | M | `packages/ai/test/xai-responses.test.ts` | Ported through xAI Responses/Grok request, UA, encrypted replay, and exact generated catalog tests. |

## Catalog parity evidence

Text catalog: `scripts/models.v0.85.0.json` equals `scripts/upstream-models.107d79f.json`; embedded registry equals normalized snapshot. Full records: `1336/1336`, providers `39`, APIs `9`, delta `+72/-26/79 changed`.

Image catalog: `scripts/image-models.v0.85.0.json` equals `scripts/upstream-image-models.107d79f.json`; embedded registry equals snapshot. Full records: `50/50`, providers `1`, APIs `1`, delta `+0/-0/0 changed`.

## Portable behavior evidence

- Assistant message frame encoder, reducer, and custom `Codable` wire representation preserve providerThinkingLevel, upstream discriminated JSON frame grammar/field names, sanitized assistant-only start frames, exact start/content whitelists, required non-null start core fields, required text/thinking/tool start fields, present-not-null optional metadata, authoritative end metadata (including absent and explicit empty signatures/namespace), text/thinking offset trimming, tool JSON exact and legacy-prefix checkpoint/resume behavior, terminal omission, mutable snapshot purity, and wrong-order/kind/index/end/unknown-case/extra-key rejection.
- Anthropic mid-conversation effort support adds beta/header and providerThinkingLevel coverage while retaining signed-thinking/history/replay/error/usage behavior; final stream `input_transformations` are surfaced as diagnostics and fallback markers are ignored only before output begins.
- OpenAI Responses supportsMaxOutputTokens gates max_output_tokens and clamps the minimum to 16 when supported.
- OpenAI Responses terminal SSE handling clears stale `errorMessage` on completed/length/toolUse mappings and reports `Response incomplete: <reason>` for content-filter or unknown incomplete reasons.
- OpenAI-compatible vLLM priority serializes through production request-body construction.
- UUIDv7 timestamp extraction and expanded NO_PROXY wildcard/IPv6/host:port behavior are covered in core utilities.
- Codex terminal SSE without a trailing blank line is covered by shared SSE EOF flushing used by Codex/Responses parsing.
- Cloudflare AI binding replacement is adapted as SwiftPM has no Workers binding object; generated Cloudflare catalog/routing and request URL behavior remain covered.

## Validation requirements

- `scripts/audit-parity.py` enforces exact text/image full-record parity, embedded registry equality, exact text delta `+72/-26/79`, exact image delta `+0/-0/0`, committed manifest row counts/hashes, audit/crosswalk row counts, and `--self-test` metadata fault injection including unchanged-image baseline corruption.
- Local gates must pass: warnings-as-errors build, full/deterministic Swift tests, `make check`, parity/static checks, SBOM/OSV/license checks, clean checkout, and zero hidden `XCTSkip` matches.
- Acceptance requires one final GitHub Actions run with Ubuntu Swift tests and static/SBOM checks green; macOS hosted CI remains disabled.
