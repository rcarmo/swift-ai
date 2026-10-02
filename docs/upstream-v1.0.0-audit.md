# Upstream v1.0.0 audit

Runtime-candidate evidence only. Publication/tag/release is blocked until auditor acceptance.

## Verified release inputs

- npm package: `@earendil-works/pi-ai@1.0.0`
- npm tarball SHA-256: `f39b99c29b8598f175b10840e5d2a81983e7c0ce5cae4d7df83a1007447d2c2b`
- upstream commit: `a13d35a742c6ef8462812a28fbe1d8c8b7431c32`
- Previous accepted upstream commit: `005af57d88ee23b33778f343a9595b32e67ff788`
- Changed paths: `8`, diff `+192/-14`, manifest SHA-256 `b8db49581470036b68078ac093dc6b41eaa92222647b14cf44a92b870d54eab4`
- Changed executable tests: `3`, manifest SHA-256 `fbe3c63453261a58352b5e238f5f9488f33a13016485c7e3a49cce17bfdaaca2`
- Final executable test corpus: `171`, basename manifest SHA-256 `9d24da3ede393a95a7131b1c9ac494f57d8165161d6eb581109c86809131abfc`
- Signed tarball provider-data manifest: schema `6`, provider files `42`, structureHash `235f2f320916ab6b0d7193e0bf66ec7983e9bc05abeddd7264923fb1e7eaf76e`
- Baked schema-v6 counts: chat `1532/41/10`, image `57/1/1`, classifier `15/5/2`, total `1604`

## Changed-path disposition matrix

| # | Status | Path | Class | Swift disposition |
| --- | --- | --- | --- | --- |
| 1 | M | `packages/ai/CHANGELOG.md` | package/docs | Recorded as package/docs metadata; publication remains blocked. |
| 2 | M | `packages/ai/package.json` | package/docs | Recorded as package metadata and version/provenance update. |
| 3 | M | `packages/ai/src/api/openai-responses-shared.ts` | runtime | Ported: Responses grammar replay uses a capability/transcript-resolved grammar map for declarations, assistant items and tool outputs. |
| 4 | M | `packages/ai/src/auth/oauth/anthropic.ts` | runtime | Ported/adapted: Anthropic OAuth browser/copy-code flows, exact constants, JSON token POST, parser, cancellation and redaction via Swift callback adapter. |
| 5 | M | `packages/ai/src/utils/oauth-page.ts` | UI helper | Adapted/N/A: Swift package has callback decision utility but no bound callback page renderer; no server/renderer invented solely for branding. |
| 6 | M | `packages/ai/test/anthropic-oauth.test.ts` | test | Ported deterministic production-path OAuth tests. |
| 7 | M | `packages/ai/test/constrained-sampling.test.ts` | test | Ported Responses grammar replay tests. |
| 8 | M | `packages/ai/test/oauth-callback-server.test.ts` | test | Adapted: decision behavior retained; SVG page branding N/A for this package surface. |

## Separate classifier contract follow-up

This is a user-directed portability follow-up, not part of the 8-path upstream delta. It is intentionally tracked separately in evidence.

- Enforces System One object-state wire contract while preserving the public `JSONValue` API and adding an object-safe initializer.
- Preserves bool-to-`noul` wire mapping and public bool probability output.
- Requires bool criteria to include both `true` and `false` for System One wire requests.
- Requires finite choice probabilities/confidence and finite score/confidence.
- Parses usage before answer semantics and preserves valid billed usage on structurally valid JSON with semantic answer errors; invalid/trailing/truncated whole JSON returns stable error with no hook/no usage.
- Treats malformed usage as optional and ignored; fractional/out-of-range usage and total-token overflow do not trap. Native Foundation/Swift `Double` cannot represent whole-body JSON numeric overflow such as `1e400`, so those bodies fail whole-JSON decode and intentionally do not recover usage.
- Implements deterministic production classify transport for TypeSafe and Cloudflare envelopes through `SwiftAI.classify`, the existing retry/cancel/header/env/hook pattern, option-scoped request transport injection, case-insensitive header nil suppression, timestamping, and absolute HTTP(S) URL validation.
- Llama classifier provider is outside the current two-API Swift surface and remains N/A for this lane.

## Final correction receipts

- Removed invalid-whole-JSON usage salvage; billing usage is retained only after full structural decode succeeds and answer semantics fail.
- Replaced unsafe numeric usage casts with `Int(exactly:)` and total overflow checks.
- Hardened Anthropic OAuth error redaction so invalid JSON and transport errors do not echo request secrets or response credentials.
- Corrected Responses assistant item-ID gating: same-source mismatched prefixes omit IDs; foreign function replay retains historical `fc_` normalization; grammar replay expects `ctc_`.
- Proved TypeSafe and Cloudflare classifier production paths through `SwiftAI.classify`, not only helper methods.
- Final local evidence: focused auditor/runtime filter green (`14` auditor-filter tests independently, local `15` broader focused tests), full tests `299/0`, strict build green, audit/self-test/static/diff green, SBOM/license/OSV green.
