#!/usr/bin/env python3
"""Generate Sources/SwiftAI/ModelsGenerated.swift from exported go-ai model JSON.

Usage:
    python3 scripts/generate-models.py scripts/models.v0.80.3.json Sources/SwiftAI/ModelsGenerated.swift

The input JSON is produced from the audited Go registry:

    cd /workspace/projects/go-ai
    go run /tmp/export-go-ai-models.go > /workspace/projects/swift-ai/scripts/models.v0.80.3.json
"""
from __future__ import annotations

import base64
import json
import re
import sys
from pathlib import Path


def chunks(s: str, n: int = 76):
    for i in range(0, len(s), n):
        yield s[i:i+n]


def normalize_model(model: dict) -> dict:
    model = dict(model)
    compat = model.pop("compat", None)
    if isinstance(compat, dict):
        api = model.get("api")
        if api == "openai-completions":
            model["completionsCompat"] = compat
        elif api in ("openai-responses", "azure-openai-responses", "openai-codex-responses"):
            model["responsesCompat"] = compat
        elif api == "anthropic-messages":
            model["anthropicCompat"] = compat
        else:
            model["compat"] = compat
    return model


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    models = json.loads(src.read_text())
    if isinstance(models, dict):
        models = [dict(model, provider=provider, id=model_id) for provider, provider_models in models.items() for model_id, model in provider_models.items()]
    models = [normalize_model(m) for m in models]
    match = re.search(r"v(\d+(?:\.\d+)+)", src.name)
    version = match.group(1) if match else "0.80.3"
    providers = sorted({m["provider"] for m in models})
    encoded = base64.b64encode(json.dumps(models, separators=(",", ":"), sort_keys=True).encode()).decode()
    body = "\n".join(chunks(encoded))
    dst.write_text(f'''import Foundation

// Generated from @earendil-works/pi-ai/go-ai v{version} model registry.
// Source JSON: scripts/{src.name}

public enum BuiltinModels {{
    public static let upstreamVersion = "{version}"
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
