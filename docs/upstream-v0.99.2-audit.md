# Upstream v0.99.2 audit

Runtime-candidate evidence only. Publication is blocked until auditor acceptance.

## Verified release inputs

- npm package: `@earendil-works/pi-ai@0.99.2`
- npm tarball SHA-256: `0b3df8791b488216f309d908789294a744bb61bbaad123d94098e56df9538d25`
- npm/gitHead and upstream commit: `005af57d88ee23b33778f343a9595b32e67ff788`
- Previous accepted upstream commit: `d86654abb8862e201933517d6f1fce9f88dd117f`
- Changed paths: `15`, diff `+726/-77`, manifest SHA-256 `53b2c290d902bb8d79c87e035b87c52a13b97617849ea85b51c8e2b11133cc15`
- Changed executable tests: `6`, manifest SHA-256 `1ad16f63dc47b019cdcf4fdf7029c86785f4cbac38158e7fb63db963ce9ce66d`
- Final executable test corpus: `171`, basename manifest SHA-256 `9d24da3ede393a95a7131b1c9ac494f57d8165161d6eb581109c86809131abfc`
- Signed tarball provider-data manifest: schema `6`, provider files `42`, structureHash `3e97a64c71ef31a515f668d9fbc653d49b3ece171d88bfd103001e963497661f`
- Baked schema-v6 counts: chat `1529/41/10`, image `57/1/1`, classifier `15/5/2`, total `1601`

## Changed-path disposition matrix

| # | Status | Path | Class | Swift disposition |
| --- | --- | --- | --- | --- |
| 1 | M | `packages/ai/CHANGELOG.md` | package/docs | Recorded as package/docs metadata; publication remains blocked. |
| 2 | M | `packages/ai/README.md` | package/docs | Recorded as package/docs metadata; publication remains blocked. |
| 3 | M | `packages/ai/package.json` | package/docs | Recorded as package/docs metadata; publication remains blocked. |
| 4 | M | `packages/ai/src/api/anthropic-messages.ts` | runtime | Port deterministic Anthropic federation/auth-cache/strict-schema/eager-tool behavior; SDK constructor mechanics adapted and live credentials live-only. |
| 5 | M | `packages/ai/src/api/constrained-sampling.ts` | runtime | Port deterministic Anthropic federation/auth-cache/strict-schema/eager-tool behavior; SDK constructor mechanics adapted and live credentials live-only. |
| 6 | M | `packages/ai/src/env-api-keys.ts` | runtime | Port deterministic Anthropic federation/auth-cache/strict-schema/eager-tool behavior; SDK constructor mechanics adapted and live credentials live-only. |
| 7 | M | `packages/ai/src/providers/anthropic.ts` | runtime | Port deterministic Anthropic federation/auth-cache/strict-schema/eager-tool behavior; SDK constructor mechanics adapted and live credentials live-only. |
| 8 | M | `packages/ai/src/utils/overflow.ts` | runtime | Port Z.AI CN overflow detection with deterministic Swift overflow test. |
| 9 | M | `packages/ai/src/utils/provider-retry.ts` | runtime | Port invalid Retry-After fallback behavior with deterministic Swift retry-policy test. |
| 10 | M | `packages/ai/test/anthropic-eager-tool-input-compat.test.ts` | runtime | Port deterministic Anthropic federation/auth-cache/strict-schema/eager-tool behavior; SDK constructor mechanics adapted and live credentials live-only. |
| 11 | A | `packages/ai/test/anthropic-federation-sdk.test.ts` | runtime | Port deterministic Anthropic federation/auth-cache/strict-schema/eager-tool behavior; SDK constructor mechanics adapted and live credentials live-only. |
| 12 | A | `packages/ai/test/anthropic-federation.test.ts` | runtime | Port deterministic Anthropic federation/auth-cache/strict-schema/eager-tool behavior; SDK constructor mechanics adapted and live credentials live-only. |
| 13 | A | `packages/ai/test/anthropic-strict-tool-schema.test.ts` | runtime | Port deterministic Anthropic federation/auth-cache/strict-schema/eager-tool behavior; SDK constructor mechanics adapted and live credentials live-only. |
| 14 | A | `packages/ai/test/models-entry.test.ts` | test | N/A for Swift runtime: JS `./models` module-loader/export mechanics are package-surface only; SwiftPM manifest/static source-layout checks are architecture evidence and no live credentials/network are involved. |
| 15 | M | `packages/ai/test/overflow.test.ts` | test | Mapped in v0.99.2 crosswalk with ported/adapted/N/A evidence. |
