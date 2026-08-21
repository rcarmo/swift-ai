#!/usr/bin/env python3
"""Static parity audit for the SwiftPM registry/runtime surface.

Checks that generated upstream model registries match the expected pi-ai
v0.84.2 counts, that every generated API/provider raw value is represented in
Swift source enums, and that every generated API has a bootstrap registration.
This is intentionally toolchain-light so it can run even in containers without
`swift` installed.
"""
from __future__ import annotations

import base64
import copy
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXT_MODELS = ROOT / "scripts" / "models.v0.84.2.json"
UPSTREAM_TEXT_MODELS = ROOT / "scripts" / "upstream-models.914cf14.json"
PREVIOUS_TEXT_MODELS = ROOT / "scripts" / "models.v0.84.1.json"
IMAGE_MODELS = ROOT / "scripts" / "image-models.v0.84.2.json"
UPSTREAM_IMAGE_MODELS = ROOT / "scripts" / "upstream-image-models.914cf14.json"
PREVIOUS_IMAGE_MODELS = ROOT / "scripts" / "image-models.v0.84.1.json"
STATUS = ROOT / "STATUS.json"
TYPES = ROOT / "Sources" / "SwiftAI" / "Types.swift"
IMAGES = ROOT / "Sources" / "SwiftAI" / "Images.swift"
REGISTRY = ROOT / "Sources" / "SwiftAI" / "Registry.swift"
MODELS_GENERATED = ROOT / "Sources" / "SwiftAI" / "ModelsGenerated.swift"
IMAGE_MODELS_GENERATED = ROOT / "Sources" / "SwiftAI" / "ImageModelsGenerated.swift"
SWIFT_STATUS = ROOT / "Sources" / "SwiftAI" / "Status.swift"

EXPECTED_TEXT_MODELS = 1267
EXPECTED_TEXT_PROVIDERS = 39
EXPECTED_IMAGE_MODELS = 45
EXPECTED_IMAGE_PROVIDERS = 1
EXPECTED_TEXT_ADDED = 71
EXPECTED_TEXT_REMOVED = 24
EXPECTED_TEXT_CHANGED = 85
EXPECTED_IMAGE_ADDED = 3
EXPECTED_IMAGE_REMOVED = 0
EXPECTED_IMAGE_CHANGED = 0
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
    "docs/upstream-parity-gaps.md",
    "docs/local-tests-shared.md",
    "docs/upstream-tests-source.md",
    "docs/upstream-tests-parity.md",
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


def model_key(model: dict) -> tuple[str, str]:
    return (str(model.get("provider")), str(model.get("id")))


def keyed_records(records: list[dict], label: str) -> dict[tuple[str, str], dict]:
    out: dict[tuple[str, str], dict] = {}
    for record in records:
        key = model_key(record)
        if key in out:
            raise SystemExit(f"duplicate model key in {label}: {key[0]}/{key[1]}")
        out[key] = record
    return out


def normalize_model(model: dict) -> dict:
    model = copy.deepcopy(model)
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


def normalize_records(records: list[dict]) -> list[dict]:
    return [normalize_model(record) for record in records]


def describe_record_differences(left: dict[tuple[str, str], dict], right: dict[tuple[str, str], dict], limit: int = 10) -> str:
    missing = sorted(right.keys() - left.keys())[:limit]
    extra = sorted(left.keys() - right.keys())[:limit]
    changed = sorted(key for key in left.keys() & right.keys() if left[key] != right[key])[:limit]
    parts = []
    if missing:
        parts.append("missing=" + repr(missing))
    if extra:
        parts.append("extra=" + repr(extra))
    if changed:
        parts.append("changed=" + repr(changed))
    return " ".join(parts) or "record content differs"


def require_full_record_equal(failures: list[str], left: list[dict], right: list[dict], label: str) -> None:
    left_map = keyed_records(left, label + " left")
    right_map = keyed_records(right, label + " right")
    if left_map != right_map:
        failures.append(f"{label}: full records differ ({describe_record_differences(left_map, right_map)})")


def record_delta_counts(previous: list[dict], current: list[dict]) -> tuple[int, int, int]:
    previous_map = keyed_records(previous, "previous text catalog")
    current_map = keyed_records(current, "current text catalog")
    added = current_map.keys() - previous_map.keys()
    removed = previous_map.keys() - current_map.keys()
    changed = {key for key in current_map.keys() & previous_map.keys() if current_map[key] != previous_map[key]}
    return (len(added), len(removed), len(changed))


def main() -> int:
    self_test = "--self-test" in sys.argv[1:]
    failures, summary = collect_failures(self_test_mutation=False)
    if self_test:
        mutated_failures, _ = collect_failures(self_test_mutation=True)
        if not any("full records differ" in failure for failure in mutated_failures):
            failures.append("self-test metadata mutation did not trigger full-record comparator")

    if failures:
        for failure in failures:
            print("FAIL:", failure)
        return 1
    suffix = "; self-test metadata mutation caught" if self_test else ""
    print(
        f"ok: {summary['text_models']} text models / {summary['text_providers']} providers / {summary['text_apis']} APIs; "
        f"{summary['image_models']} image models / {summary['image_providers']} providers / {summary['image_apis']} APIs; "
        f"text delta +{summary['text_added']}/-{summary['text_removed']}/{summary['text_changed']} changed; "
        f"image delta +{summary['image_added']}/-{summary['image_removed']}/{summary['image_changed']} changed" + suffix
    )
    return 0


def collect_failures(self_test_mutation: bool = False) -> tuple[list[str], dict[str, int]]:
    text = json.loads(TEXT_MODELS.read_text())
    upstream_text = json.loads(UPSTREAM_TEXT_MODELS.read_text())
    previous_text = json.loads(PREVIOUS_TEXT_MODELS.read_text())
    images = json.loads(IMAGE_MODELS.read_text())
    upstream_images = json.loads(UPSTREAM_IMAGE_MODELS.read_text())
    previous_images = json.loads(PREVIOUS_IMAGE_MODELS.read_text())
    if self_test_mutation:
        text = copy.deepcopy(text)
        text[0]["name"] = str(text[0].get("name", "")) + " fault-injected"

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

    require_full_record_equal(failures, text, upstream_text, "current text snapshot vs exact-tag upstream snapshot")
    normalized_text = normalize_records(text)
    require_full_record_equal(failures, embedded_text, normalized_text, "embedded text registry vs normalized current snapshot")
    require_full_record_equal(failures, images, upstream_images, "current image snapshot vs exact-tag upstream snapshot")
    require_full_record_equal(failures, embedded_images, images, "embedded image registry vs current image snapshot")
    text_added, text_removed, text_changed = record_delta_counts(previous_text, text)
    if (text_added, text_removed, text_changed) != (EXPECTED_TEXT_ADDED, EXPECTED_TEXT_REMOVED, EXPECTED_TEXT_CHANGED):
        failures.append(
            f"v0.84.1..v0.84.2 text full-record delta: got +{text_added}/-{text_removed}/{text_changed} changed, "
            f"want +{EXPECTED_TEXT_ADDED}/-{EXPECTED_TEXT_REMOVED}/{EXPECTED_TEXT_CHANGED} changed"
        )
    image_added, image_removed, image_changed = record_delta_counts(previous_images, images)
    if (image_added, image_removed, image_changed) != (EXPECTED_IMAGE_ADDED, EXPECTED_IMAGE_REMOVED, EXPECTED_IMAGE_CHANGED):
        failures.append(
            f"v0.84.1..v0.84.2 image full-record delta: got +{image_added}/-{image_removed}/{image_changed} changed, "
            f"want +{EXPECTED_IMAGE_ADDED}/-{EXPECTED_IMAGE_REMOVED}/{EXPECTED_IMAGE_CHANGED} changed"
        )

    text_ids = {(m["provider"], m["id"]) for m in text}
    upstream_text_ids = {(m["provider"], m["id"]) for m in upstream_text}
    embedded_text_ids = {(m["provider"], m["id"]) for m in embedded_text}
    if len(upstream_text_ids) != EXPECTED_TEXT_MODELS:
        failures.append(f"upstream exact-tag provider/id pairs: got {len(upstream_text_ids)}, want {EXPECTED_TEXT_MODELS}")
    if text_ids != upstream_text_ids:
        missing = sorted(upstream_text_ids - text_ids)[:20]
        extra = sorted(text_ids - upstream_text_ids)[:20]
        failures.append(f"Swift snapshot differs from upstream exact-tag catalog: missing={missing} extra={extra}")
    representative_ids = {
        ("kimi-coding", "k3"),
        ("moonshotai", "kimi-k3"),
        ("openrouter", "moonshotai/kimi-k3"),
        ("openrouter", "meta/muse-spark-1.1"),
        ("vercel-ai-gateway", "anthropic/claude-opus-5"),
        ("vercel-ai-gateway", "moonshotai/kimi-k3"),
        ("vercel-ai-gateway", "thinkingmachines/inkling"),
        ("qwen-token-plan", "qwen3.8-max"),
        ("qwen-token-plan-cn", "qwen3.8-max"),
        ("qwen-token-plan-individual", "qwen3.8-max"),
        ("qwen-token-plan-individual", "deepseek-v4-flash-0731"),
        ("opencode-go", "grok-4.5"),
        ("baseten", "moonshotai/Kimi-K2.5"),
        ("google", "gemini-2.5-computer-use-preview-10-2025"),
        ("openrouter", "inclusionai/ling-3.0-flash"),
    }
    missing_representatives = sorted(representative_ids - upstream_text_ids)
    if missing_representatives:
        failures.append(f"upstream exact-tag representatives missing: {missing_representatives}")
    if text_ids != embedded_text_ids:
        failures.append("embedded text registry IDs differ from source JSON")
    image_ids = {(m["provider"], m["id"]) for m in images}
    upstream_image_ids = {(m["provider"], m["id"]) for m in upstream_images}
    if len(upstream_image_ids) != EXPECTED_IMAGE_MODELS:
        failures.append(f"upstream exact-tag image provider/id pairs: got {len(upstream_image_ids)}, want {EXPECTED_IMAGE_MODELS}")
    if image_ids != upstream_image_ids:
        missing = sorted(upstream_image_ids - image_ids)[:20]
        extra = sorted(image_ids - upstream_image_ids)[:20]
        failures.append(f"Swift image snapshot differs from upstream exact-tag catalog: missing={missing} extra={extra}")
    representative_image_ids = {
        ("openrouter", "krea/krea-2-large"),
        ("openrouter", "openrouter/auto-beta"),
        ("openrouter", "microsoft/mai-image-2.5-pro"),
        ("openrouter", "qwen/qwen-image-3-pro"),
    }
    missing_image_representatives = sorted(representative_image_ids - upstream_image_ids)
    if missing_image_representatives:
        failures.append(f"upstream exact-tag image representatives missing: {missing_image_representatives}")
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
        "RadiusOAuthProvider": "radius",
        "XAIOAuthProvider": "xai",
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

    summary = {
        "text_models": len(text),
        "text_providers": len(text_providers),
        "text_apis": len(text_apis),
        "image_models": len(images),
        "image_providers": len(image_providers),
        "image_apis": len(image_apis),
        "text_added": text_added,
        "text_removed": text_removed,
        "text_changed": text_changed,
        "image_added": image_added,
        "image_removed": image_removed,
        "image_changed": image_changed,
    }
    return failures, summary


if __name__ == "__main__":
    raise SystemExit(main())
