# pi-ai v1.1.0 candidate audit

Pinned official tag `abe508e1b89912adde45528136c3221eb69acdd7`, compared with v1.0.1 `a7229ddc21810d6245105978033b7df645ecc2f7`.

Exact scope: 82 changed paths, 38 changed test paths, 174 whole-corpus paths. This one-hour candidate is not accepted release parity. Rows marked `pending` still need individual production/test disposition.

| # | Changed path | Disposition |
|---|---|---|
| 1 | `M packages/ai/CHANGELOG.md` | reference -- native version/docs updated; JS packaging excluded |
| 2 | `M packages/ai/README.md` | reference -- native version/docs updated; JS packaging excluded |
| 3 | `M packages/ai/package.json` | reference -- native version/docs updated; JS packaging excluded |
| 4 | `A packages/ai/scripts/ai-gateway-pricing.ts` | pending -- exact behaviour/test audit required |
| 5 | `M packages/ai/scripts/generate-models.ts` | pending -- exact behaviour/test audit required |
| 6 | `M packages/ai/scripts/openrouter-catalog.ts` | pending -- exact behaviour/test audit required |
| 7 | `A packages/ai/src/api/azure-openai-config.ts` | pending -- exact behaviour/test audit required |
| 8 | `M packages/ai/src/api/azure-openai-responses.ts` | pending -- exact behaviour/test audit required |
| 9 | `M packages/ai/src/api/bedrock-converse-stream.ts` | pending -- exact behaviour/test audit required |
| 10 | `A packages/ai/src/api/classifier-shared.ts` | ported candidate -- OpenAIDecisionsProvider; V110ParityTests; live verification excluded |
| 11 | `M packages/ai/src/api/cloudflare-workers-ai-system-one.ts` | pending -- exact behaviour/test audit required |
| 12 | `M packages/ai/src/api/lazy.ts` | pending -- exact behaviour/test audit required |
| 13 | `M packages/ai/src/api/llama-cpp-classify.ts` | pending -- exact behaviour/test audit required |
| 14 | `M packages/ai/src/api/mistral-conversations.ts` | pending -- exact behaviour/test audit required |
| 15 | `M packages/ai/src/api/openai-codex-responses.ts` | pending -- exact behaviour/test audit required |
| 16 | `M packages/ai/src/api/openai-completions.ts` | pending -- exact behaviour/test audit required |
| 17 | `A packages/ai/src/api/openai-decisions.lazy.ts` | ported candidate -- OpenAIDecisionsProvider; V110ParityTests; live verification excluded |
| 18 | `A packages/ai/src/api/openai-decisions.ts` | ported candidate -- OpenAIDecisionsProvider; V110ParityTests; live verification excluded |
| 19 | `M packages/ai/src/api/openai-responses.ts` | pending -- exact behaviour/test audit required |
| 20 | `M packages/ai/src/api/simple-options.ts` | ported candidate -- thinking-level sampling merge; V110ParityTests |
| 21 | `M packages/ai/src/api/system-one-shared.ts` | pending -- exact behaviour/test audit required |
| 22 | `M packages/ai/src/api/typesafe-system-one.ts` | pending -- exact behaviour/test audit required |
| 23 | `M packages/ai/src/auth/oauth/anthropic.ts` | pending -- exact behaviour/test audit required |
| 24 | `M packages/ai/src/auth/oauth/openai-chatgpt.ts` | pending -- exact behaviour/test audit required |
| 25 | `M packages/ai/src/auth/oauth/openai-codex.ts` | pending -- exact behaviour/test audit required |
| 26 | `M packages/ai/src/auth/resolve.ts` | pending -- exact behaviour/test audit required |
| 27 | `M packages/ai/src/auth/types.ts` | pending -- exact behaviour/test audit required |
| 28 | `M packages/ai/src/env-api-keys.ts` | pending -- exact behaviour/test audit required |
| 29 | `M packages/ai/src/models.generated.ts` | pending -- exact behaviour/test audit required |
| 30 | `M packages/ai/src/models.ts` | pending -- exact behaviour/test audit required |
| 31 | `M packages/ai/src/providers/all.ts` | adapted candidate -- typed registries and Azure route; integration audit incomplete |
| 32 | `D packages/ai/src/providers/azure-openai-responses.models.ts` | adapted candidate -- typed registries and Azure route; integration audit incomplete |
| 33 | `D packages/ai/src/providers/azure-openai-responses.ts` | adapted candidate -- typed registries and Azure route; integration audit incomplete |
| 34 | `A packages/ai/src/providers/azure.models.ts` | adapted candidate -- typed registries and Azure route; integration audit incomplete |
| 35 | `A packages/ai/src/providers/azure.ts` | adapted candidate -- typed registries and Azure route; integration audit incomplete |
| 36 | `M packages/ai/src/providers/faux.ts` | pending -- exact behaviour/test audit required |
| 37 | `M packages/ai/src/providers/openai.ts` | pending -- exact behaviour/test audit required |
| 38 | `M packages/ai/src/providers/radius.ts` | pending -- exact behaviour/test audit required |
| 39 | `M packages/ai/src/types.ts` | pending -- exact behaviour/test audit required |
| 40 | `M packages/ai/src/utils/estimate.ts` | pending -- exact behaviour/test audit required |
| 41 | `M packages/ai/src/utils/event-stream.ts` | pending -- exact behaviour/test audit required |
| 42 | `M packages/ai/src/utils/model-operations.ts` | pending -- exact behaviour/test audit required |
| 43 | `M packages/ai/src/utils/provider-retry.ts` | pending -- exact behaviour/test audit required |
| 44 | `M packages/ai/src/utils/retry.ts` | pending -- exact behaviour/test audit required |
| 45 | `M packages/ai/test/abort.test.ts` | pending -- exact behaviour/test audit required |
| 46 | `M packages/ai/test/anthropic-adaptive-thinking-models.test.ts` | pending -- exact behaviour/test audit required |
| 47 | `M packages/ai/test/anthropic-oauth.test.ts` | pending -- exact behaviour/test audit required |
| 48 | `M packages/ai/test/azure-openai-base-url.test.ts` | pending -- exact behaviour/test audit required |
| 49 | `A packages/ai/test/azure-openai-completions.test.ts` | pending -- exact behaviour/test audit required |
| 50 | `M packages/ai/test/azure-openai-responses-reasoning-replay.test.ts` | pending -- exact behaviour/test audit required |
| 51 | `M packages/ai/test/azure-openai-tool-choice.test.ts` | pending -- exact behaviour/test audit required |
| 52 | `M packages/ai/test/bedrock-thinking-payload.test.ts` | pending -- exact behaviour/test audit required |
| 53 | `M packages/ai/test/classifier-models.test.ts` | pending -- exact behaviour/test audit required |
| 54 | `M packages/ai/test/context-estimate.test.ts` | pending -- exact behaviour/test audit required |
| 55 | `M packages/ai/test/context-overflow.test.ts` | pending -- exact behaviour/test audit required |
| 56 | `M packages/ai/test/cross-provider-handoff.test.ts` | pending -- exact behaviour/test audit required |
| 57 | `M packages/ai/test/empty.test.ts` | pending -- exact behaviour/test audit required |
| 58 | `M packages/ai/test/event-stream.test.ts` | pending -- exact behaviour/test audit required |
| 59 | `M packages/ai/test/faux-provider.test.ts` | pending -- exact behaviour/test audit required |
| 60 | `M packages/ai/test/image-tool-result.test.ts` | pending -- exact behaviour/test audit required |
| 61 | `M packages/ai/test/mistral-raw-stop-reason.test.ts` | pending -- exact behaviour/test audit required |
| 62 | `A packages/ai/test/model-cost-tiers.test.ts` | pending -- exact behaviour/test audit required |
| 63 | `M packages/ai/test/models-runtime.test.ts` | pending -- exact behaviour/test audit required |
| 64 | `M packages/ai/test/openai-chatgpt-oauth.test.ts` | pending -- exact behaviour/test audit required |
| 65 | `M packages/ai/test/openai-codex-oauth.test.ts` | pending -- exact behaviour/test audit required |
| 66 | `M packages/ai/test/openai-codex-stream.test.ts` | pending -- exact behaviour/test audit required |
| 67 | `M packages/ai/test/openai-completions-empty-tools.test.ts` | pending -- exact behaviour/test audit required |
| 68 | `A packages/ai/test/openai-decisions.test.ts` | ported candidate -- OpenAIDecisionsProvider; V110ParityTests; live verification excluded |
| 69 | `M packages/ai/test/openai-responses-namespace.test.ts` | pending -- exact behaviour/test audit required |
| 70 | `M packages/ai/test/openai-responses-tool-result-images.test.ts` | pending -- exact behaviour/test audit required |
| 71 | `M packages/ai/test/provider-retry.test.ts` | pending -- exact behaviour/test audit required |
| 72 | `M packages/ai/test/radius-provider.test.ts` | pending -- exact behaviour/test audit required |
| 73 | `M packages/ai/test/responseid.test.ts` | pending -- exact behaviour/test audit required |
| 74 | `M packages/ai/test/retry.test.ts` | pending -- exact behaviour/test audit required |
| 75 | `M packages/ai/test/sampling-options.test.ts` | ported candidate -- thinking-level sampling merge; V110ParityTests |
| 76 | `M packages/ai/test/stream.test.ts` | pending -- exact behaviour/test audit required |
| 77 | `M packages/ai/test/supports-xhigh.test.ts` | pending -- exact behaviour/test audit required |
| 78 | `M packages/ai/test/tokens.test.ts` | pending -- exact behaviour/test audit required |
| 79 | `M packages/ai/test/tool-call-without-result.test.ts` | pending -- exact behaviour/test audit required |
| 80 | `M packages/ai/test/total-tokens.test.ts` | pending -- exact behaviour/test audit required |
| 81 | `M packages/ai/test/typesafe-system-one.test.ts` | pending -- exact behaviour/test audit required |
| 82 | `M packages/ai/test/unicode-surrogate.test.ts` | pending -- exact behaviour/test audit required |
