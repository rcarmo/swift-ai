# Upstream v0.99.1 audit

Runtime accepted: Swift commit `dc549fe0709128c73d9d8f8f2d5a031c1a6b6482`, CI `36636114608`, SBOM artifact `11064291751`. README/PARITY/RELEASE metadata is updated by the post-runtime docs-only commit; durable release asset publication is handled by the guarded SBOM publisher.

## Verified release inputs

- npm package: `@earendil-works/pi-ai@0.99.1`
- npm tarball SHA-256: `f9f44692157d0bf5679c4a17304a310028231d7daaeaaea3b73252f4b7a264d3`
- npm/gitHead and upstream commit: `d86654abb8862e201933517d6f1fce9f88dd117f`
- Previous accepted upstream commit: `f07218c4d4bbc12bef056a7058c3dd49dfe41abe`
- Changed paths: `169`, diff `+7001/-2913`, manifest SHA-256 `086beb5b751f144f9e45034bfbb2b0f4e8a0d3a00f9e17ec1b073b3a8397221e`
- Changed executable tests: `58`, manifest SHA-256 `d8eefa94ed87c03de0545965351de4d800cf76ce1db33b0f62fab0f9ab3c7acc`
- Final executable test corpus: `160`, basename manifest SHA-256 `7ad5f140edc5bc49a348b7b7e36ea266dd82a3075c23ad9997b6e8bc21992b06`
- Signed tarball provider-data manifest: schema `6`, provider files `42`, structureHash `58511a57fb2db5e984ee62857d8079aec6ff800e19226c327c118e7f57ea916b`
- Baked schema-v6 counts: chat `1523/41/10`, image `57/1/1`, classifier `12/5/2`, total `1592`

## Changed-path disposition matrix

| # | Status | Path | Class | Swift disposition |
| --- | --- | --- | --- | --- |
| 1 | M | `packages/ai/CHANGELOG.md` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 2 | M | `packages/ai/README.md` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 3 | M | `packages/ai/package.json` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 4 | D | `packages/ai/scripts/generate-image-models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 5 | M | `packages/ai/scripts/generate-models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 6 | M | `packages/ai/scripts/model-data.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 7 | A | `packages/ai/scripts/openrouter-catalog.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 8 | M | `packages/ai/src/api/anthropic-messages.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 9 | M | `packages/ai/src/api/azure-openai-responses.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 10 | M | `packages/ai/src/api/bedrock-converse-stream.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 11 | A | `packages/ai/src/api/cloudflare-workers-ai-system-one.lazy.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 12 | A | `packages/ai/src/api/cloudflare-workers-ai-system-one.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 13 | M | `packages/ai/src/api/cloudflare.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 14 | M | `packages/ai/src/api/google-generative-ai.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 15 | M | `packages/ai/src/api/google-vertex.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 16 | A | `packages/ai/src/api/llama-cpp-classify.lazy.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 17 | A | `packages/ai/src/api/llama-cpp-classify.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 18 | M | `packages/ai/src/api/mistral-conversations.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 19 | M | `packages/ai/src/api/openai-codex-responses.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 20 | M | `packages/ai/src/api/openai-completions.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 21 | M | `packages/ai/src/api/openai-responses-shared.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 22 | M | `packages/ai/src/api/openai-responses.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 23 | M | `packages/ai/src/api/openrouter-images.lazy.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 24 | M | `packages/ai/src/api/openrouter-images.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 25 | M | `packages/ai/src/api/pi-messages.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 26 | M | `packages/ai/src/api/simple-options.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 27 | A | `packages/ai/src/api/system-one-shared.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 28 | A | `packages/ai/src/api/typesafe-system-one.lazy.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 29 | A | `packages/ai/src/api/typesafe-system-one.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 30 | M | `packages/ai/src/auth/helpers.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 31 | M | `packages/ai/src/auth/oauth/anthropic.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 32 | A | `packages/ai/src/auth/oauth/callback-server.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 33 | M | `packages/ai/src/auth/oauth/load.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 34 | A | `packages/ai/src/auth/oauth/openai-chatgpt.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 35 | M | `packages/ai/src/auth/oauth/openai-codex.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 36 | M | `packages/ai/src/auth/oauth/openrouter.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 37 | M | `packages/ai/src/auth/oauth/radius.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 38 | M | `packages/ai/src/auth/resolve.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 39 | M | `packages/ai/src/auth/types.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 40 | M | `packages/ai/src/bun-oauth.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 41 | M | `packages/ai/src/cli.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 42 | M | `packages/ai/src/env-api-keys.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 43 | D | `packages/ai/src/image-models.generated.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 44 | M | `packages/ai/src/image-models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 45 | M | `packages/ai/src/images-api-registry.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 46 | D | `packages/ai/src/images-models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 47 | M | `packages/ai/src/images.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 48 | M | `packages/ai/src/index.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 49 | M | `packages/ai/src/model-catalog.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 50 | M | `packages/ai/src/models-store.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 51 | M | `packages/ai/src/models.generated.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 52 | M | `packages/ai/src/models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 53 | M | `packages/ai/src/providers/all.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 54 | M | `packages/ai/src/providers/amazon-bedrock.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 55 | M | `packages/ai/src/providers/ant-ling.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 56 | M | `packages/ai/src/providers/anthropic.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 57 | M | `packages/ai/src/providers/azure-openai-responses.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 58 | M | `packages/ai/src/providers/baseten.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 59 | M | `packages/ai/src/providers/cerebras.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 60 | M | `packages/ai/src/providers/cloudflare-ai-gateway.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 61 | M | `packages/ai/src/providers/cloudflare-stream.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 62 | M | `packages/ai/src/providers/cloudflare-workers-ai.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 63 | M | `packages/ai/src/providers/cloudflare-workers-ai.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 64 | M | `packages/ai/src/providers/deepseek.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 65 | M | `packages/ai/src/providers/fireworks.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 66 | M | `packages/ai/src/providers/github-copilot.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 67 | M | `packages/ai/src/providers/google-vertex.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 68 | M | `packages/ai/src/providers/google.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 69 | M | `packages/ai/src/providers/groq.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 70 | M | `packages/ai/src/providers/huggingface.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 71 | M | `packages/ai/src/providers/images/register-builtins.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 72 | M | `packages/ai/src/providers/kimi-coding.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 73 | M | `packages/ai/src/providers/meta.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 74 | M | `packages/ai/src/providers/minimax-cn.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 75 | M | `packages/ai/src/providers/minimax.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 76 | M | `packages/ai/src/providers/mistral.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 77 | M | `packages/ai/src/providers/moonshotai-cn.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 78 | M | `packages/ai/src/providers/moonshotai.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 79 | M | `packages/ai/src/providers/nvidia.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 80 | M | `packages/ai/src/providers/openai-codex.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 81 | M | `packages/ai/src/providers/openai-codex.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 82 | M | `packages/ai/src/providers/openai.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 83 | M | `packages/ai/src/providers/openai.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 84 | M | `packages/ai/src/providers/opencode-go.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 85 | M | `packages/ai/src/providers/opencode.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 86 | M | `packages/ai/src/providers/opencode.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 87 | D | `packages/ai/src/providers/openrouter-images.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 88 | M | `packages/ai/src/providers/openrouter.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 89 | M | `packages/ai/src/providers/openrouter.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 90 | M | `packages/ai/src/providers/qwen-token-plan-cn.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 91 | M | `packages/ai/src/providers/qwen-token-plan-individual.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 92 | M | `packages/ai/src/providers/qwen-token-plan.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 93 | M | `packages/ai/src/providers/radius.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 94 | M | `packages/ai/src/providers/together.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 95 | A | `packages/ai/src/providers/typesafe.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 96 | A | `packages/ai/src/providers/typesafe.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 97 | M | `packages/ai/src/providers/vercel-ai-gateway.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 98 | M | `packages/ai/src/providers/vercel-ai-gateway.ts` | runtime | Reviewed for Swift production parity; applicable behavior is ported or adapted in runtime/provider tests. |
| 99 | M | `packages/ai/src/providers/xai.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 100 | M | `packages/ai/src/providers/xiaomi-token-plan-ams.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 101 | M | `packages/ai/src/providers/xiaomi-token-plan-cn.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 102 | M | `packages/ai/src/providers/xiaomi-token-plan-sgp.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 103 | M | `packages/ai/src/providers/xiaomi.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 104 | M | `packages/ai/src/providers/zai-coding-cn.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 105 | M | `packages/ai/src/providers/zai.models.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 106 | M | `packages/ai/src/types.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 107 | M | `packages/ai/src/utils/headers.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 108 | A | `packages/ai/src/utils/model-operations.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 109 | A | `packages/ai/src/utils/models-error.ts` | catalog/generator | Covered by signed tarball schema-v6 snapshots, provider-data manifest hash, generated Swift registries, and audit parity validators. |
| 110 | R100 | `packages/ai/src/utils/oauth-page.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 111 | M | `packages/ai/src/utils/retry.ts` | package/docs | Recorded as upstream package/docs metadata; public Swift README/PARITY/RELEASE claims remain blocked until runtime acceptance. |
| 112 | M | `packages/ai/test/abort.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 113 | M | `packages/ai/test/anthropic-adaptive-thinking-models.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 114 | M | `packages/ai/test/anthropic-cache-write-1h-cost.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 115 | M | `packages/ai/test/anthropic-empty-thinking-signature-compat.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 116 | M | `packages/ai/test/anthropic-oauth.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 117 | M | `packages/ai/test/anthropic-sse-parsing.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 118 | M | `packages/ai/test/azure-openai-base-url.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 119 | M | `packages/ai/test/bedrock-raw-stop-reason.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 120 | M | `packages/ai/test/cache-retention.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 121 | A | `packages/ai/test/classifier-models.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 122 | A | `packages/ai/test/cloudflare-workers-ai-system-one.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 123 | M | `packages/ai/test/context-overflow.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 124 | M | `packages/ai/test/cross-provider-handoff.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 125 | M | `packages/ai/test/empty.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 126 | M | `packages/ai/test/fetch-option.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 127 | M | `packages/ai/test/fireworks-model-generation.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 128 | M | `packages/ai/test/fireworks-models.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 129 | M | `packages/ai/test/google-raw-stop-reason.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 130 | M | `packages/ai/test/image-model-data.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 131 | M | `packages/ai/test/image-tool-result.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 132 | M | `packages/ai/test/images-models.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 133 | M | `packages/ai/test/images.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 134 | A | `packages/ai/test/llama-cpp-classify.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 135 | M | `packages/ai/test/max-thinking.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 136 | M | `packages/ai/test/mistral-http-transport.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 137 | M | `packages/ai/test/mistral-reasoning-mode.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 138 | M | `packages/ai/test/model-data-validation.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 139 | A | `packages/ai/test/model-types.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 140 | M | `packages/ai/test/models-runtime.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 141 | M | `packages/ai/test/oauth-auth.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 142 | A | `packages/ai/test/oauth-callback-server.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 143 | A | `packages/ai/test/openai-chatgpt-oauth.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 144 | M | `packages/ai/test/openai-codex-oauth.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 145 | M | `packages/ai/test/openai-codex-stream.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 146 | M | `packages/ai/test/openai-completions-prompt-cache.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 147 | A | `packages/ai/test/openai-completions-provider-stream-event.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 148 | M | `packages/ai/test/openai-completions-tool-choice.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 149 | A | `packages/ai/test/openai-responses-chatgpt-sign-in.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 150 | M | `packages/ai/test/openai-responses-compat.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 151 | M | `packages/ai/test/openai-responses-terminal-event.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 152 | A | `packages/ai/test/openai-responses-usage-limit.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 153 | M | `packages/ai/test/openrouter-images.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 154 | M | `packages/ai/test/openrouter-oauth.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 155 | M | `packages/ai/test/pi-messages.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 156 | M | `packages/ai/test/provider-error-body-passthrough.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 157 | M | `packages/ai/test/providers.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 158 | M | `packages/ai/test/radius-oauth.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 159 | M | `packages/ai/test/retry.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 160 | M | `packages/ai/test/sampling-options.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 161 | M | `packages/ai/test/stream.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 162 | M | `packages/ai/test/supports-xhigh.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 163 | M | `packages/ai/test/telemetry-options.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 164 | M | `packages/ai/test/together-models.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 165 | M | `packages/ai/test/tokens.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 166 | M | `packages/ai/test/tool-call-without-result.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 167 | M | `packages/ai/test/total-tokens.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 168 | A | `packages/ai/test/typesafe-system-one.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |
| 169 | M | `packages/ai/test/unicode-surrogate.test.ts` | test | Mapped in v0.99.1 crosswalk with ported/adapted deterministic Swift evidence and exact snapshot validators. |

## Runtime acceptance evidence

Accepted runtime commit: `dc549fe0709128c73d9d8f8f2d5a031c1a6b6482`; CI run `36636114608` completed successfully for `swift-test (ubuntu-latest)` and `static-check`. SHA-specific SBOM artifact `11064291751` has archive SHA-256 `2899c2dffe0d401c4ab20a9fe9834f7a15ee9a11584789373c7cf2168640d308`, inner SBOM SHA-256 `b6056920ebf73e272f0dc74119480dcfd04b769bccb884067e0771e2e91255e5`, CycloneDX 1.5 root `swift-ai@0.99.1`, component count `2`, matching `git.revision`, `git.dirty=false`, and clean OSV/security/license scans.
