# Release parity record

This file is the durable release-audit ledger for `swift-ai`. It must be updated as part of every future upstream `@earendil-works/pi-ai` release parity commit before the work is reported complete.

## Current upstream parity baseline

- Upstream package: `@earendil-works/pi-ai`
- Current upstream release: `v0.84.2`
- Current upstream tag commit: `914cf1472e715297caa30db4b9535d534a9eb718`
- Previous accepted upstream release: `v0.84.1`
- Previous accepted upstream tag commit: `53fa77ccd8a279eb87e92294ef3687b03ff80112`
- Previous accepted Swift baseline: `a960b0a27ff8b7feaaeb4acd0d3eb5b30d9e56d4`
- Verified npm artifact SHA-256: `0262785a76b0eb2eec596cd8a7ab2ee23eef89d2ef1bb1211c4f0a1944dacf41`
- Swift parity branch: `main`
- Current Swift parity commits for v0.84.2:
  - `9acf91f2c001761f50d7e5f72af5eefc62504b71` — `Sync upstream v0.84.2 parity`
  - This evidence commit — records green hosted CI evidence for `9acf91f`.

## Exact upstream delta

Release-only audit scope: `packages/ai` diff from `53fa77ccd8a279eb87e92294ef3687b03ff80112` to `914cf1472e715297caa30db4b9535d534a9eb718`.

Exact changed-path count: **42**.

Changed test paths: **21** total = **18 modified + 3 new** (`cloudflare-gateway-binding.test.ts`, `mistral-http-transport.test.ts`, `openai-responses-namespace.test.ts`).

The detailed disposition matrix is in [`docs/upstream-v0.84.2-audit.md`](docs/upstream-v0.84.2-audit.md). The cumulative whole-corpus test crosswalk is in [`docs/upstream-v0.84.2-test-crosswalk.md`](docs/upstream-v0.84.2-test-crosswalk.md) and covers all **131** upstream `packages/ai/test/*.test.ts` files.

## Exact catalog parity

Text catalog:

- Swift source snapshot: `scripts/models.v0.84.2.json`
- Exact upstream comparator source: `scripts/upstream-models.914cf14.json`
- Embedded Swift registry: `Sources/SwiftAI/ModelsGenerated.swift`
- Full records: `1267/1267`
- Providers: `39`
- APIs: `9`
- Full-record delta vs committed v0.84.1 snapshot: `+71/-24/85 changed`

Image catalog:

- Swift source snapshot: `scripts/image-models.v0.84.2.json`
- Exact upstream comparator source: `scripts/upstream-image-models.914cf14.json`
- Embedded Swift registry: `Sources/SwiftAI/ImageModelsGenerated.swift`
- Full records: `45/45`
- Providers: `1`
- APIs: `1`
- Full-record delta vs committed v0.84.1 snapshot: `+3/0/0 changed`

Expected comparator output:

```text
ok: 1267 text models / 39 providers / 9 APIs; 45 image models / 1 providers / 1 APIs; text delta +71/-24/85 changed; image delta +3/-0/0 changed
```

## Swift implementation, adaptations, and N/A decisions

Implemented/adapted:

- Regenerated v0.84.2 text and image catalogs from the verified npm artifact.
- Extended full-record audit/self-test gates to v0.84.2 text and image deltas.
- Added runtime/test coverage for strict JSON-schema tool conversion and optional non-nullable null omission.
- Added Kimi runtime `User-Agent` and Codex SSE `User-Agent` handling via `AIUtilities.piUserAgent()`.
- Added Responses/Codex `supportsAdditionalTools`, message-anchored `additional_tools`, tool-search fallback arguments, function/custom tool-call namespace preservation, and `AssistantMessage.endTurn` parsing.
- Added Mistral injectable raw streaming transport seam with URLSession fallback, `x-affinity`, bounded non-2xx response bodies, timeout/abort handling, and UTF-8-safe SSE chunk framing; focused tests cover byte-split UTF-8, headers, status/body, timeout, abort, usage, and raw stops.
- Capped GitHub Copilot policy/model update concurrency at 4 structured tasks with cancellation-safe scheduling and max-in-flight tests.
- Added retry classifier coverage for `exceeded request buffer limit while retrying upstream` and mixed-case DeepSeek/max_tokens focused tests.
- Preserved/validated case-insensitive DeepSeek and `max_tokens` compatibility via exact catalog metadata and request builders.
- Preserved Google/Vertex STOP vs MAX_TOKENS/raw reason behavior in parser tests.
- Added Bedrock replay sanitization for empty argument keys without mutating original streamed args.
- Preserved streaming usage across parser terminal/final events.

N/A/adapted:

- Cloudflare `createGatewayBindingFetch` is a Cloudflare Workers AI Gateway binding object adapter. Swift has no Workers binding object in SwiftPM core; portable routing remains represented by base URL/env routing and pluggable request transports.
- JS lazy module loading/package wiring is not a SwiftPM runtime behavior; Swift uses static modules.

## Tests and gates

Local validation for v0.84.2 parity work uses Swift `6.3.2`:

```bash
swift build -Xswiftc -warnings-as-errors
swift test
for i in 1 2 3; do swift test; done
make check
python3 scripts/audit-parity.py
python3 scripts/audit-parity.py --self-test
python3 scripts/static-check.py
grep -R "XCTSkip" -n Tests || true
```

Latest local results before this commit:

- `swift build -Xswiftc -warnings-as-errors`: passed.
- focused v0.84.2 tests: passed (`8` tests, including Copilot concurrency and Mistral wire tests).
- `swift test`: `240` tests, `0` failures.
- deterministic `swift test` ×3: passed (`240` tests each run).
- `make check`: passed (`240` tests, `0` failures).
- `scripts/audit-parity.py`: passed with exact v0.84.2 full-record counts and text/image deltas.
- `scripts/audit-parity.py --self-test`: passed, metadata fault injection caught.
- `scripts/static-check.py`: passed, including self-test.
- hidden skip scan: no `XCTSkip` matches.

GitHub Actions evidence for `9acf91f2c001761f50d7e5f72af5eefc62504b71`:

- Run: <https://github.com/rcarmo/swift-ai/actions/runs/32500449112>
- Status: `completed`
- Conclusion: `success`
- Jobs:
  - `swift-test (ubuntu-latest)`: success
  - `swift-test (macos-14)`: success
  - `static-check`: success

Fresh GitHub Actions evidence for this final evidence commit must be captured from the pushed commit and reported with the final handoff.

## Future release-audit checklist

1. Pin the exact upstream tag and SHA.
2. Diff only from the last accepted upstream tag to the new official tag.
3. Record exact changed path count and disposition matrix.
4. Regenerate text and image snapshots from the exact tag/artifact.
5. Update comparator sources and expected counts/deltas.
6. Implement all applicable Swift production deltas with executable tests.
7. Document every adaptation and N/A decision here and in the per-release audit doc.
8. Run local gates and require green GitHub Actions on Ubuntu, macOS, and static-check.
9. Commit/push cleanly as Rui Carmo.
