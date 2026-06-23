#!/usr/bin/env python3
"""Static parity audit for the SwiftPM registry/runtime surface.

Checks that generated upstream model registries match the expected pi-ai/go-ai
v0.80.2 counts, that every generated API/provider raw value is represented in
Swift source enums, and that every generated API has a bootstrap registration.
This is intentionally toolchain-light so it can run even in containers without
`swift` installed.
"""
from __future__ import annotations

import base64
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXT_MODELS = ROOT / "scripts" / "models.v0.80.2.json"
IMAGE_MODELS = ROOT / "scripts" / "image-models.v0.80.2.json"
STATUS = ROOT / "STATUS.json"
TYPES = ROOT / "Sources" / "SwiftAI" / "Types.swift"
IMAGES = ROOT / "Sources" / "SwiftAI" / "Images.swift"
REGISTRY = ROOT / "Sources" / "SwiftAI" / "Registry.swift"
MODELS_GENERATED = ROOT / "Sources" / "SwiftAI" / "ModelsGenerated.swift"
IMAGE_MODELS_GENERATED = ROOT / "Sources" / "SwiftAI" / "ImageModelsGenerated.swift"
SWIFT_STATUS = ROOT / "Sources" / "SwiftAI" / "Status.swift"

EXPECTED_TEXT_MODELS = 999
EXPECTED_TEXT_PROVIDERS = 35
EXPECTED_IMAGE_MODELS = 34
EXPECTED_IMAGE_PROVIDERS = 1
REQUIRED_SOURCES = [
    "Sources/SwiftAI/Providers/OpenAICompletionsProvider.swift",
    "Sources/SwiftAI/Providers/OpenAIResponsesProvider.swift",
    "Sources/SwiftAI/Providers/AnthropicMessagesProvider.swift",
    "Sources/SwiftAI/Providers/GoogleGenerativeAIProvider.swift",
    "Sources/SwiftAI/Providers/GoogleGeminiCLIProvider.swift",
    "Sources/SwiftAI/Providers/MistralConversationsProvider.swift",
    "Sources/SwiftAI/Providers/OpenRouterImagesProvider.swift",
    "Sources/SwiftAI/Providers/BedrockProvider.swift",
    "Sources/SwiftAI/OAuth.swift",
    "Sources/SwiftAI/AzureHelpers.swift",
    "Sources/SwiftAI/Harness.swift",
    "Sources/SwiftAI/PartialJSON.swift",
    "Sources/SwiftAI/Retry.swift",
    "docs/TRANSPORTS.md",
    "docs/USAGE.md",
]


def enum_cases(path: Path) -> dict[str, str]:
    return dict(re.findall(r'case\s+(\w+)\s*=\s*"([^"]+)"', path.read_text()))


def raw_values(*paths: Path) -> set[str]:
    out: set[str] = set()
    for path in paths:
        out.update(enum_cases(path).values())
    return out


def embedded_registry(path: Path) -> list[dict]:
    match = re.search(r'encodedRegistry\s*=\s*#"""\n(.*?)\n"""#', path.read_text(), re.S)
    if not match:
        raise SystemExit(f"missing embedded registry in {path.relative_to(ROOT)}")
    compact = "".join(match.group(1).split())
    return json.loads(base64.b64decode(compact))


def registered_api_raw_values() -> tuple[set[str], set[str]]:
    registry = REGISTRY.read_text()
    text_cases = enum_cases(TYPES)
    image_cases = enum_cases(IMAGES)
    text_registered_cases = set(re.findall(r'APIProvider\(api:\s*\.(\w+)', registry))
    image_registered_cases = set(re.findall(r'ImagesAPIProvider\(api:\s*\.(\w+)', registry))
    return (
        {text_cases[c] for c in text_registered_cases if c in text_cases},
        {image_cases[c] for c in image_registered_cases if c in image_cases},
    )


def main() -> int:
    text = json.loads(TEXT_MODELS.read_text())
    images = json.loads(IMAGE_MODELS.read_text())
    status = json.loads(STATUS.read_text())
    swift_status = SWIFT_STATUS.read_text()
    embedded_text = embedded_registry(MODELS_GENERATED)
    embedded_images = embedded_registry(IMAGE_MODELS_GENERATED)
    raw = raw_values(TYPES, IMAGES)

    failures: list[str] = []
    text_providers = {m["provider"] for m in text}
    text_apis = {m["api"] for m in text}
    image_providers = {m["provider"] for m in images}
    image_apis = {m["api"] for m in images}

    checks = [
        (len(text), EXPECTED_TEXT_MODELS, "text model count"),
        (len(embedded_text), len(text), "embedded text model count"),
        (len(text_providers), EXPECTED_TEXT_PROVIDERS, "text provider count"),
        (len(images), EXPECTED_IMAGE_MODELS, "image model count"),
        (len(embedded_images), len(images), "embedded image model count"),
        (len(image_providers), EXPECTED_IMAGE_PROVIDERS, "image provider count"),
        (status["registries"]["textModels"], len(text), "STATUS text model count"),
        (status["registries"]["textProviders"], len(text_providers), "STATUS text provider count"),
        (status["registries"]["textAPIs"], len(text_apis), "STATUS text API count"),
        (status["registries"]["imageModels"], len(images), "STATUS image model count"),
        (status["registries"]["imageProviders"], len(image_providers), "STATUS image provider count"),
        (status["registries"]["imageAPIs"], len(image_apis), "STATUS image API count"),
    ]
    for got, want, label in checks:
        if got != want:
            failures.append(f"{label}: got {got}, want {want}")

    text_ids = {(m["provider"], m["id"]) for m in text}
    embedded_text_ids = {(m["provider"], m["id"]) for m in embedded_text}
    if text_ids != embedded_text_ids:
        failures.append("embedded text registry IDs differ from source JSON")
    image_ids = {(m["provider"], m["id"]) for m in images}
    embedded_image_ids = {(m["provider"], m["id"]) for m in embedded_images}
    if image_ids != embedded_image_ids:
        failures.append("embedded image registry IDs differ from source JSON")

    missing = sorted((text_providers | text_apis | image_providers | image_apis) - raw)
    if missing:
        failures.append("missing Swift enum raw values: " + ", ".join(missing))

    swift_status_checks = {
        "upstreamVersion": status["upstream"]["version"],
        "textModelCount": str(len(text)),
        "textProviderCount": str(len(text_providers)),
        "textAPICount": str(len(text_apis)),
        "imageModelCount": str(len(images)),
        "imageProviderCount": str(len(image_providers)),
        "imageAPICount": str(len(image_apis)),
    }
    for key, expected in swift_status_checks.items():
        if expected not in swift_status:
            failures.append(f"SwiftAIStatus missing/aligned value for {key}: {expected}")

    usage_doc = status.get("usageDocumentation")
    if not usage_doc or not (ROOT / usage_doc).exists():
        failures.append("STATUS usageDocumentation is missing or points to a missing file")
    transport_doc = status.get("transportDocumentation")
    if not transport_doc or not (ROOT / transport_doc).exists():
        failures.append("STATUS transportDocumentation is missing or points to a missing file")
    transport_protocols = {item.get("protocol") for item in status.get("pluggableTransports", [])}
    for protocol in ["BedrockTransport", "CodexTransport"]:
        if protocol not in transport_protocols:
            failures.append(f"STATUS missing pluggable transport protocol: {protocol}")
        elif transport_doc and protocol not in (ROOT / transport_doc).read_text():
            failures.append(f"transport docs do not mention protocol: {protocol}")

    missing_sources = [path for path in REQUIRED_SOURCES if not (ROOT / path).exists()]
    if missing_sources:
        failures.append("missing required parity source files: " + ", ".join(missing_sources))

    registered_text_apis, registered_image_apis = registered_api_raw_values()
    missing_text_runtime = sorted(text_apis - registered_text_apis)
    missing_image_runtime = sorted(image_apis - registered_image_apis)
    if missing_text_runtime:
        failures.append("missing text API bootstrap registrations: " + ", ".join(missing_text_runtime))
    if missing_image_runtime:
        failures.append("missing image API bootstrap registrations: " + ", ".join(missing_image_runtime))

    status_oauth = set(status.get("oauthProviders", []))
    registry_text = REGISTRY.read_text()
    oauth_registered = set(re.findall(r'OAuthRegistry\.shared\.register\((\w+)\(', registry_text))
    oauth_class_to_id = {
        "GitHubCopilotOAuthProvider": "github-copilot",
        "OpenAICodexOAuthProvider": "openai-codex",
        "AnthropicOAuthProvider": "anthropic",
        "GoogleGeminiCLIOAuthProvider": "google-gemini-cli",
        "GoogleAntigravityOAuthProvider": "google-antigravity",
    }
    registered_oauth_ids = {oauth_class_to_id[name] for name in oauth_registered if name in oauth_class_to_id}
    if status_oauth != registered_oauth_ids:
        failures.append("STATUS oauthProviders differ from bootstrap registrations: status=" + ",".join(sorted(status_oauth)) + " registered=" + ",".join(sorted(registered_oauth_ids)))

    status_bundled = set(status.get("bundledRuntimeProviders", []))
    # STATUS labels Codex as SSE to distinguish it from optional WebSocket transport.
    normalized_status_bundled = {"openai-codex-responses" if x == "openai-codex-responses-sse" else x for x in status_bundled}
    missing_status_runtime = sorted(text_apis - normalized_status_bundled - {"bedrock-converse-stream"})
    if missing_status_runtime:
        failures.append("STATUS bundledRuntimeProviders missing generated APIs: " + ", ".join(missing_status_runtime))
    if "openrouter-images" not in status.get("bundledRuntimeProviders", []):
        failures.append("STATUS bundledRuntimeProviders missing image API: openrouter-images")

    if failures:
        for failure in failures:
            print("FAIL:", failure)
        return 1
    print(
        f"ok: {len(text)} text models / {len(text_providers)} providers / {len(text_apis)} APIs; "
        f"{len(images)} image models / {len(image_providers)} providers / {len(image_apis)} APIs"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
