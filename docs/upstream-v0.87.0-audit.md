# Upstream pi-ai v0.87.0 release parity audit

Baseline: accepted official release `v0.85.1` / `d981de1229ef899957bbe968bc8dcda02a21f477`.
Target: official release `v0.87.0` / `16787ad5b2dc748047f314ca1bfe7708f30f54f3`.
Scope: cumulative release-only audit through `v0.86.0`, `v0.86.1`, and `v0.87.0`; no unreleased commits beyond the `v0.87.0` tag were considered.

Verified npm artifact SHA-256: `f2adf9de809d035f76f8dadf3d148720ebeef4606a848ab36ee834d895ae812f`.

The bounded `packages/ai` delta is exactly 127 changed paths. Changed-path manifest hash: `e6bd9733d8fff626838d386df8e6bb543d40d77af74340ee4f2f271b411b9828`. The changed-test full-path manifest covers 82 paths with hash `a12a1453c8fbabfd6902ced06304cbd2fa9f7d82ce89b91a1403366bc11fe5b2`; the changed-test basename manifest hash is `cb66d8f12cc4e23509e41e07c5bdddf546d961e731751254f01fbf0989676040`. The final upstream basename test corpus has 150 tests with hash `042cdfbc8cc089da71409e615fb54cfe7273a960f8e0d10e63e07584ae9f2e75`.

Exact manifests are committed as [`upstream-v0.87.0-changed-paths.txt`](upstream-v0.87.0-changed-paths.txt), [`upstream-v0.87.0-changed-tests.txt`](upstream-v0.87.0-changed-tests.txt), [`upstream-v0.87.0-changed-tests-basename.txt`](upstream-v0.87.0-changed-tests-basename.txt), and [`upstream-v0.87.0-test-corpus-basename.txt`](upstream-v0.87.0-test-corpus-basename.txt). `scripts/audit-parity.py` validates changed-path and full-corpus row counts/hashes plus this table/crosswalk row counts.

## Exact changed-path disposition matrix

| # | Marker | Upstream path | Swift disposition |
| ---: | :---: | --- | --- |
| 1 | M | `packages/ai/CHANGELOG.md` | Package metadata/documentation recorded in RELEASE/STATUS/audit docs; no Swift runtime behavior. |
| 2 | M | `packages/ai/README.md` | Package metadata/documentation recorded in RELEASE/STATUS/audit docs; no Swift runtime behavior. |
| 3 | M | `packages/ai/package.json` | Package metadata/documentation recorded in RELEASE/STATUS/audit docs; no Swift runtime behavior. |
| 4 | M | `packages/ai/scripts/generate-models.ts` | Adapted via exact v0.87.0 generated text/image snapshots, embedded Swift registries, full-record comparators, and deliberate metadata fault gates. |
| 5 | M | `packages/ai/src/api/anthropic-messages.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 6 | M | `packages/ai/src/api/azure-openai-responses.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 7 | M | `packages/ai/src/api/bedrock-converse-stream.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 8 | M | `packages/ai/src/api/google-generative-ai.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 9 | M | `packages/ai/src/api/google-shared.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 10 | M | `packages/ai/src/api/google-vertex.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 11 | M | `packages/ai/src/api/mistral-conversations.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 12 | M | `packages/ai/src/api/openai-codex-responses.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 13 | M | `packages/ai/src/api/openai-completions.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 14 | M | `packages/ai/src/api/openai-responses-shared.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 15 | M | `packages/ai/src/api/openai-responses.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 16 | M | `packages/ai/src/api/pi-messages.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 17 | M | `packages/ai/src/api/simple-options.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 18 | M | `packages/ai/src/api/transform-messages.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 19 | M | `packages/ai/src/auth/oauth/load.ts` | Ported/adapted through Swift OAuth/provider registry surfaces and deterministic provider/auth tests where portable. |
| 20 | M | `packages/ai/src/auth/oauth/meta.ts` | Ported/adapted through Swift OAuth/provider registry surfaces and deterministic provider/auth tests where portable. |
| 21 | M | `packages/ai/src/bun-oauth.ts` | Reviewed for Swift applicability and covered by exact generated snapshots, validators, or existing runtime surfaces. |
| 22 | M | `packages/ai/src/compat.ts` | Reviewed for Swift applicability and covered by exact generated snapshots, validators, or existing runtime surfaces. |
| 23 | M | `packages/ai/src/env-api-keys.ts` | Reviewed for Swift applicability and covered by exact generated snapshots, validators, or existing runtime surfaces. |
| 24 | M | `packages/ai/src/image-models.generated.ts` | Adapted via exact v0.87.0 generated text/image snapshots, embedded Swift registries, full-record comparators, and deliberate metadata fault gates. |
| 25 | M | `packages/ai/src/index.ts` | Reviewed for Swift applicability and covered by exact generated snapshots, validators, or existing runtime surfaces. |
| 26 | M | `packages/ai/src/models.generated.ts` | Adapted via exact v0.87.0 generated text/image snapshots, embedded Swift registries, full-record comparators, and deliberate metadata fault gates. |
| 27 | M | `packages/ai/src/models.ts` | Adapted via exact v0.87.0 generated text/image snapshots, embedded Swift registries, full-record comparators, and deliberate metadata fault gates. |
| 28 | M | `packages/ai/src/providers/all.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 29 | M | `packages/ai/src/providers/faux.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 30 | M | `packages/ai/src/providers/meta.models.ts` | Ported/adapted through Swift OAuth/provider registry surfaces and deterministic provider/auth tests where portable. |
| 31 | M | `packages/ai/src/providers/meta.ts` | Ported/adapted through Swift OAuth/provider registry surfaces and deterministic provider/auth tests where portable. |
| 32 | M | `packages/ai/src/providers/opencode-go.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 33 | M | `packages/ai/src/providers/opencode-headers.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 34 | M | `packages/ai/src/providers/opencode.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 35 | M | `packages/ai/src/providers/radius.models.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 36 | M | `packages/ai/src/providers/radius.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 37 | M | `packages/ai/src/types.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 38 | M | `packages/ai/src/utils/deferred-tools.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 39 | M | `packages/ai/src/utils/diagnostics.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 40 | M | `packages/ai/src/utils/estimate.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 41 | M | `packages/ai/src/utils/event-stream.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 42 | M | `packages/ai/src/utils/overflow.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 43 | M | `packages/ai/src/utils/retry.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 44 | M | `packages/ai/src/utils/text.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 45 | M | `packages/ai/src/utils/transcript.ts` | Ported/adapted through Swift provider/runtime code and deterministic request/parser/helper tests for the applicable portable behavior. |
| 46 | M | `packages/ai/test/anthropic-adaptive-thinking-models.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 47 | M | `packages/ai/test/anthropic-auth-token.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 48 | M | `packages/ai/test/anthropic-cache-write-1h-cost.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 49 | M | `packages/ai/test/anthropic-eager-tool-input-compat.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 50 | M | `packages/ai/test/anthropic-empty-thinking-signature-compat.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 51 | M | `packages/ai/test/anthropic-mid-conversation-effort.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 52 | M | `packages/ai/test/anthropic-sse-parsing.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 53 | M | `packages/ai/test/anthropic-thinking-binding-e2e.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 54 | M | `packages/ai/test/azure-openai-base-url.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 55 | M | `packages/ai/test/azure-openai-responses-reasoning-replay.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 56 | M | `packages/ai/test/azure-openai-tool-choice.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 57 | M | `packages/ai/test/bedrock-cache-write-1h-cost.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 58 | M | `packages/ai/test/bedrock-convert-messages.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 59 | M | `packages/ai/test/bedrock-custom-headers.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 60 | M | `packages/ai/test/bedrock-error-metadata.test.ts` | Ported/adapted through Swift OAuth/provider registry surfaces and deterministic provider/auth tests where portable. |
| 61 | M | `packages/ai/test/bedrock-raw-stop-reason.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 62 | M | `packages/ai/test/bedrock-redacted-reasoning.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 63 | M | `packages/ai/test/bedrock-response-headers.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 64 | M | `packages/ai/test/bedrock-thinking-payload.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 65 | M | `packages/ai/test/cache-retention.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 66 | M | `packages/ai/test/cloudflare-ai-binding.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 67 | M | `packages/ai/test/cloudflare-stream.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 68 | M | `packages/ai/test/codex-websocket-cached-probe.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 69 | M | `packages/ai/test/constrained-sampling.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 70 | M | `packages/ai/test/context-estimate.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 71 | M | `packages/ai/test/context-overflow.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 72 | M | `packages/ai/test/cross-provider-handoff.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 73 | M | `packages/ai/test/deferred-tools.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 74 | M | `packages/ai/test/event-stream.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 75 | M | `packages/ai/test/fetch-option.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 76 | M | `packages/ai/test/fireworks-model-generation.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 77 | M | `packages/ai/test/fireworks-models.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 78 | M | `packages/ai/test/github-copilot-anthropic.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 79 | M | `packages/ai/test/google-raw-stop-reason.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 80 | M | `packages/ai/test/google-shared-gemini3-unsigned-tool-call.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 81 | M | `packages/ai/test/google-shared-image-tool-result-routing.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 82 | M | `packages/ai/test/google-shared-signed-empty-blocks.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 83 | M | `packages/ai/test/google-thinking-level-map.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 84 | M | `packages/ai/test/google-vertex-api-key-resolution.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 85 | M | `packages/ai/test/max-thinking.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 86 | M | `packages/ai/test/message-types.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 87 | M | `packages/ai/test/meta-oauth.test.ts` | Ported/adapted through Swift OAuth/provider registry surfaces and deterministic provider/auth tests where portable. |
| 88 | M | `packages/ai/test/mistral-http-transport.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 89 | M | `packages/ai/test/mistral-raw-stop-reason.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 90 | M | `packages/ai/test/mistral-reasoning-mode.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 91 | M | `packages/ai/test/model-catalog-types.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 92 | M | `packages/ai/test/openai-codex-stream.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 93 | M | `packages/ai/test/openai-completions-cache-control-format.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 94 | M | `packages/ai/test/openai-completions-empty-tools.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 95 | M | `packages/ai/test/openai-completions-prompt-cache.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 96 | M | `packages/ai/test/openai-completions-raw-stop-reason.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 97 | M | `packages/ai/test/openai-completions-reasoning-details.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 98 | M | `packages/ai/test/openai-completions-retry.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 99 | M | `packages/ai/test/openai-completions-thinking-as-text.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 100 | M | `packages/ai/test/openai-completions-tool-choice.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 101 | M | `packages/ai/test/openai-completions-tool-result-images.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 102 | M | `packages/ai/test/openai-completions-vllm-priority.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 103 | M | `packages/ai/test/openai-responses-compat.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 104 | M | `packages/ai/test/openai-responses-empty-tool-result.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 105 | M | `packages/ai/test/openai-responses-foreign-toolcall-id.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 106 | M | `packages/ai/test/openai-responses-message-id.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 107 | M | `packages/ai/test/openai-responses-namespace.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 108 | M | `packages/ai/test/openai-responses-terminal-event.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 109 | M | `packages/ai/test/opencode-provider-headers.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 110 | M | `packages/ai/test/openrouter-reasoning-options.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 111 | M | `packages/ai/test/overflow.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 112 | M | `packages/ai/test/pi-messages.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 113 | M | `packages/ai/test/pre-generation-error.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 114 | M | `packages/ai/test/provider-error-body-regression.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 115 | M | `packages/ai/test/providers.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 116 | M | `packages/ai/test/radius-provider.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 117 | M | `packages/ai/test/retry.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 118 | M | `packages/ai/test/stream.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 119 | M | `packages/ai/test/supports-xhigh.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 120 | M | `packages/ai/test/system-message-replay.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 121 | M | `packages/ai/test/telemetry-options.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 122 | M | `packages/ai/test/tokens.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 123 | M | `packages/ai/test/tool-call-id-normalization.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 124 | M | `packages/ai/test/transcript-tool-changes.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 125 | M | `packages/ai/test/validation.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 126 | M | `packages/ai/test/xai-responses.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |
| 127 | M | `packages/ai/test/zai-coding-plan-models.test.ts` | Mapped in the v0.87.0 test crosswalk to Swift deterministic tests, exact catalog validators, or live-only classification. |

## Catalog parity evidence

Text catalog: `scripts/models.v0.87.0.json` equals `scripts/upstream-models.16787ad.json`; embedded registry equals normalized snapshot. Full records: `1445/1445`, providers `41`, APIs `10`, delta `+149/-58/986 changed` from v0.85.1 after excluding the new `inputLimits` advisory field from the baseline-delta count.

Image catalog: `scripts/image-models.v0.87.0.json` equals `scripts/upstream-image-models.16787ad.json`; embedded image registry equals snapshot. Full records: `54/54`, providers `1`, APIs `1`, delta `+2/-0/4 changed`.

## Portable behavior evidence

- Generated catalog parity covers the cumulative v0.86.0/v0.86.1/v0.87.0 model additions and metadata changes, including Meta provider models and new image resize/input-limit metadata.
- Existing and v0.87.0 Swift runtime tests cover request building, provider registry behavior, OAuth surfaces, retry/terminal stream behavior, and assistant transcript/event reconstruction where portable.
- Live provider/browser flows remain classified in the crosswalk and are not faked.

## Validation requirements

- `scripts/audit-parity.py` enforces exact text/image full-record parity, embedded registry equality, exact text delta `+149/-58/986`, exact image delta `+2/-0/4`, committed manifest row counts/hashes, audit/crosswalk row counts, and `--self-test` metadata fault injection including image baseline corruption.
- Local gates must pass: warnings-as-errors build, full/deterministic Swift tests, `make check`, parity/static checks, SBOM/OSV/license checks, clean checkout, and zero hidden `XCTSkip` matches.
- Acceptance requires one final GitHub Actions run with Ubuntu Swift tests and static/SBOM checks green; macOS hosted CI remains disabled.
