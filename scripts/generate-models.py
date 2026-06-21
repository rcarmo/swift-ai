#!/usr/bin/env python3
"""Generate Sources/SwiftAI/ModelsGenerated.swift from exported go-ai model JSON.

Usage:
    python3 scripts/generate-models.py scripts/models.v0.79.9.json Sources/SwiftAI/ModelsGenerated.swift

The input JSON is produced from the audited Go registry:

    cd /workspace/projects/go-ai
    go run /tmp/export-go-ai-models.go > /workspace/projects/swift-ai/scripts/models.v0.79.9.json
"""
from __future__ import annotations

import base64
import json
import sys
from pathlib import Path


def chunks(s: str, n: int = 76):
    for i in range(0, len(s), n):
        yield s[i:i+n]


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    models = json.loads(src.read_text())
    providers = sorted({m["provider"] for m in models})
    encoded = base64.b64encode(json.dumps(models, separators=(",", ":"), sort_keys=True).encode()).decode()
    body = "\n".join(chunks(encoded))
    dst.write_text(f'''import Foundation

// Generated from @earendil-works/pi-ai/go-ai v0.79.9 model registry.
// Source JSON: scripts/models.v0.79.9.json

public enum BuiltinModels {{
    public static let upstreamVersion = "0.79.9"
    public static let modelCount = {len(models)}
    public static let providerCount = {len(providers)}

    private static let encodedRegistry = #"""
{body}
"""#

    public static func all() throws -> [Model] {{
        let compact = encodedRegistry.split(whereSeparator: \\.isNewline).joined()
        guard let data = Data(base64Encoded: compact) else {{ throw AIError.invalidResponse("invalid embedded model registry") }}
        return try JSONDecoder().decode([Model].self, from: data)
    }}

    public static func registerAll() async {{
        do {{
            for model in try all() {{ await AIRegistry.shared.register(model) }}
        }} catch {{
            assertionFailure("failed to decode embedded model registry: \\(error)")
        }}
    }}
}}
''')
    print(f"wrote {dst}: {len(models)} models / {len(providers)} providers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
