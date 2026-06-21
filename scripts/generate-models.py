#!/usr/bin/env python3
"""Generate Swift model registry code from upstream pi-ai metadata.

This is a placeholder entrypoint for the full 979-model registry generator. The
initial Swift port ships a hand-curated seed catalog in `ModelsGenerated.swift`;
this script documents where the parity generator belongs and gives future work a
stable invocation path:

    python3 scripts/generate-models.py /tmp/pi-ai/package/dist/models.generated.js \
        Sources/SwiftAI/ModelsGenerated.swift

The upstream JS bundle uses TypeScript object literals rather than plain JSON, so
this should be implemented with a small JS parser or by reusing the Go/Rust port
registry export as an intermediate JSON format.
"""

from __future__ import annotations
import sys

if __name__ == "__main__":
    print(__doc__.strip())
    sys.exit(0)
