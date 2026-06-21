#!/usr/bin/env python3
"""Static parity audit for the SwiftPM registry surface.

Checks that generated upstream model registries match the expected pi-ai/go-ai
v0.79.9 counts and that every generated API/provider raw value is represented in
Swift source enums. This is intentionally toolchain-light so it can run even in
containers without `swift` installed.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXT_MODELS = ROOT / "scripts" / "models.v0.79.9.json"
IMAGE_MODELS = ROOT / "scripts" / "image-models.v0.79.9.json"
TYPES = ROOT / "Sources" / "SwiftAI" / "Types.swift"
IMAGES = ROOT / "Sources" / "SwiftAI" / "Images.swift"

EXPECTED_TEXT_MODELS = 979
EXPECTED_TEXT_PROVIDERS = 35
EXPECTED_IMAGE_MODELS = 34
EXPECTED_IMAGE_PROVIDERS = 1


def raw_values(*paths: Path) -> set[str]:
    out: set[str] = set()
    for path in paths:
        out.update(re.findall(r'case\s+\w+\s*=\s*"([^"]+)"', path.read_text()))
    return out


def main() -> int:
    text = json.loads(TEXT_MODELS.read_text())
    images = json.loads(IMAGE_MODELS.read_text())
    raw = raw_values(TYPES, IMAGES)

    failures: list[str] = []
    text_providers = {m["provider"] for m in text}
    text_apis = {m["api"] for m in text}
    image_providers = {m["provider"] for m in images}
    image_apis = {m["api"] for m in images}

    checks = [
        (len(text), EXPECTED_TEXT_MODELS, "text model count"),
        (len(text_providers), EXPECTED_TEXT_PROVIDERS, "text provider count"),
        (len(images), EXPECTED_IMAGE_MODELS, "image model count"),
        (len(image_providers), EXPECTED_IMAGE_PROVIDERS, "image provider count"),
    ]
    for got, want, label in checks:
        if got != want:
            failures.append(f"{label}: got {got}, want {want}")

    missing = sorted((text_providers | text_apis | image_providers | image_apis) - raw)
    if missing:
        failures.append("missing Swift enum raw values: " + ", ".join(missing))

    if failures:
        for failure in failures:
            print("FAIL:", failure)
        return 1
    print(f"ok: {len(text)} text models / {len(text_providers)} providers; {len(images)} image models / {len(image_providers)} providers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
