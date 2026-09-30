#!/usr/bin/env python3
"""Static parity audit for the SwiftPM registry/runtime surface.

Checks that generated registries match the signed @earendil-works/pi-ai v0.99.1
npm tarball's baked schema-v6 exports and provider-data manifest. This gate is
toolchain-light and deliberately avoids live catalog hydration.
"""
from __future__ import annotations

import base64
import copy
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXT_MODELS = ROOT / "scripts" / "models.v0.99.2.json"
UPSTREAM_TEXT_MODELS = ROOT / "scripts" / "upstream-models.005af57.json"
PREVIOUS_TEXT_MODELS = ROOT / "scripts" / "models.v0.99.1.json"
IMAGE_MODELS = ROOT / "scripts" / "image-models.v0.99.2.json"
UPSTREAM_IMAGE_MODELS = ROOT / "scripts" / "upstream-image-models.005af57.json"
PREVIOUS_IMAGE_MODELS = ROOT / "scripts" / "image-models.v0.99.1.json"
CLASSIFIER_MODELS = ROOT / "scripts" / "classifier-models.v0.99.2.json"
UPSTREAM_CLASSIFIER_MODELS = ROOT / "scripts" / "upstream-classifier-models.005af57.json"
PREVIOUS_CLASSIFIER_MODELS = ROOT / "scripts" / "classifier-models.v0.99.1.json"
PROVIDER_DATA_MANIFEST = ROOT / "scripts" / "provider-data-manifest.v0.99.2.json"
STATUS = ROOT / "STATUS.json"
TYPES = ROOT / "Sources" / "SwiftAI" / "Core" / "Types.swift"
IMAGES = ROOT / "Sources" / "SwiftAI" / "Core" / "Images.swift"
CLASSIFIERS = ROOT / "Sources" / "SwiftAI" / "Core" / "Classifiers.swift"
REGISTRY = ROOT / "Sources" / "SwiftAI" / "Core" / "Registry.swift"
MODELS_GENERATED = ROOT / "Sources" / "SwiftAI" / "Models" / "Generated" / "ModelsGenerated.swift"
IMAGE_MODELS_GENERATED = ROOT / "Sources" / "SwiftAI" / "Models" / "Generated" / "ImageModelsGenerated.swift"
CLASSIFIER_MODELS_GENERATED = ROOT / "Sources" / "SwiftAI" / "Models" / "Generated" / "ClassifierModelsGenerated.swift"
SWIFT_STATUS = ROOT / "Sources" / "SwiftAI" / "Core" / "Status.swift"

EXPECTED_TEXT_MODELS = 1529
EXPECTED_TEXT_PROVIDERS = 41
EXPECTED_TEXT_APIS = 10
EXPECTED_IMAGE_MODELS = 57
EXPECTED_IMAGE_PROVIDERS = 1
EXPECTED_IMAGE_APIS = 1
EXPECTED_CLASSIFIER_MODELS = 15
EXPECTED_CLASSIFIER_PROVIDERS = 5
EXPECTED_CLASSIFIER_APIS = 2
EXPECTED_TOTAL_MODELS = 1601
EXPECTED_PROVIDER_FILES = 42
EXPECTED_SCHEMA_VERSION = 6
EXPECTED_STRUCTURE_HASH = "3e97a64c71ef31a515f668d9fbc653d49b3ece171d88bfd103001e963497661f"
EXPECTED_TEXT_ADDED = 6
EXPECTED_TEXT_REMOVED = 0
EXPECTED_TEXT_CHANGED = 23
EXPECTED_IMAGE_ADDED = 0
EXPECTED_IMAGE_REMOVED = 0
EXPECTED_IMAGE_CHANGED = 0
EXPECTED_CLASSIFIER_ADDED = 3
CHANGED_PATHS_MANIFEST = ROOT / "docs" / "upstream-v0.99.2-changed-paths.txt"
CHANGED_TESTS_MANIFEST = ROOT / "docs" / "upstream-v0.99.2-changed-tests.txt"
TEST_CORPUS_MANIFEST = ROOT / "docs" / "upstream-v0.99.2-test-corpus-basename.txt"
UPSTREAM_AUDIT_DOC = ROOT / "docs" / "upstream-v0.99.2-audit.md"
UPSTREAM_CROSSWALK_DOC = ROOT / "docs" / "upstream-v0.99.2-test-crosswalk.md"
EXPECTED_CHANGED_PATHS = 15
EXPECTED_CHANGED_PATHS_HASH = "53b2c290d902bb8d79c87e035b87c52a13b97617849ea85b51c8e2b11133cc15"
EXPECTED_CHANGED_TESTS = 6
EXPECTED_CHANGED_TESTS_HASH = "1ad16f63dc47b019cdcf4fdf7029c86785f4cbac38158e7fb63db963ce9ce66d"
EXPECTED_TEST_CORPUS = 171
EXPECTED_TEST_CORPUS_HASH = "9d24da3ede393a95a7131b1c9ac494f57d8165161d6eb581109c86809131abfc"
EXPECTED_CHANGED_TEST_DISPOSITIONS = {"ported": 4, "adapted": 1, "n/a": 1}
REQUIRED_SOURCES = [
    "Sources/SwiftAI/Core/Classifiers.swift",
    "Sources/SwiftAI/Providers/SystemOneClassifierProvider.swift",
    "Sources/SwiftAI/Providers/OpenAICompletionsProvider.swift",
    "Sources/SwiftAI/Providers/OpenAIResponsesProvider.swift",
    "Sources/SwiftAI/Providers/AnthropicMessagesProvider.swift",
    "Sources/SwiftAI/Providers/GoogleGenerativeAIProvider.swift",
    "Sources/SwiftAI/Providers/GoogleGeminiCLIProvider.swift",
    "Sources/SwiftAI/Providers/MistralConversationsProvider.swift",
    "Sources/SwiftAI/Providers/OpenRouterImagesProvider.swift",
    "Sources/SwiftAI/Providers/BedrockProvider.swift",
    "Sources/SwiftAI/Auth/OAuth.swift",
    "Sources/SwiftAI/Support/AzureHelpers.swift",
    "Sources/SwiftAI/Support/Harness.swift",
    "Sources/SwiftAI/Support/PartialJSON.swift",
    "Sources/SwiftAI/Transport/Retry.swift",
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


def registered_api_raw_values() -> tuple[set[str], set[str], set[str]]:
    registry = REGISTRY.read_text()
    text_cases = enum_cases(TYPES)
    image_cases = enum_cases(IMAGES)
    classifier_cases = enum_cases(CLASSIFIERS)
    text_registered_cases = set(re.findall(r'APIProvider\(api:\s*\.(\w+)', registry))
    image_registered_cases = set(re.findall(r'ImagesAPIProvider\(api:\s*\.(\w+)', registry))
    classifier_registered_cases = set(re.findall(r'ClassifierAPIProvider\(api:\s*\.(\w+)', registry))
    return (
        {text_cases[c] for c in text_registered_cases if c in text_cases},
        {image_cases[c] for c in image_registered_cases if c in image_cases},
        {classifier_cases[c] for c in classifier_registered_cases if c in classifier_cases},
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


def comparable_release_delta(record: dict) -> dict:
    """Normalize generated Swift field-shape differences for release delta checks."""
    record = normalize_model(record)
    return {
        key: value
        for key, value in record.items()
        if key not in {"inputLimits", "type"}
    }


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
    previous_map = keyed_records(previous, "previous catalog")
    current_map = keyed_records(current, "current catalog")
    added = current_map.keys() - previous_map.keys()
    removed = previous_map.keys() - current_map.keys()
    changed = {key for key in current_map.keys() & previous_map.keys() if comparable_release_delta(current_map[key]) != comparable_release_delta(previous_map[key])}
    return (len(added), len(removed), len(changed))


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def markdown_table_data_rows(path: Path) -> int:
    rows = 0
    for line in path.read_text().splitlines():
        if line.startswith("| ") and not line.startswith("| ---") and not line.startswith("| #"):
            rows += 1
    return rows


def markdown_cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def clean_markdown_code(value: str) -> str:
    value = value.strip()
    if value.startswith("`") and value.endswith("`") and len(value) >= 2:
        return value[1:-1]
    return value


def validate_changed_test_crosswalk(failures: list[str], crosswalk_text: str | None = None, changed_manifest_text: str | None = None, label: str = "v0.99.2 crosswalk") -> None:
    crosswalk_text = UPSTREAM_CROSSWALK_DOC.read_text() if crosswalk_text is None else crosswalk_text
    changed_manifest_text = CHANGED_TESTS_MANIFEST.read_text() if changed_manifest_text is None else changed_manifest_text
    expected_paths = [line.strip() for line in changed_manifest_text.splitlines() if line.strip()]
    expected_set = set(expected_paths)
    if len(expected_paths) != len(expected_set):
        failures.append(f"{label} changed-test manifest contains duplicate paths")

    changed_rows: list[tuple[str, str]] = []
    all_rows = 0
    for line in crosswalk_text.splitlines():
        if not (line.startswith("| ") and not line.startswith("| ---") and not line.startswith("| #")):
            continue
        all_rows += 1
        cells = markdown_cells(line)
        if len(cells) < 4:
            failures.append(f"{label} malformed row: {line}")
            continue
        path = clean_markdown_code(cells[1])
        changed = cells[2].strip().lower()
        disposition = cells[3].strip().lower()
        if changed == "yes":
            changed_rows.append((path, disposition))

    paths = [path for path, _ in changed_rows]
    path_set = set(paths)
    duplicates = sorted({path for path in paths if paths.count(path) > 1})
    if duplicates:
        failures.append(f"{label} duplicate Changed=yes rows: {duplicates[:10]}")
    missing = sorted(expected_set - path_set)
    extra = sorted(path_set - expected_set)
    if missing:
        failures.append(f"{label} missing Changed=yes manifest paths: {missing[:10]}")
    if extra:
        failures.append(f"{label} extra Changed=yes paths not in manifest: {extra[:10]}")
    if len(changed_rows) != EXPECTED_CHANGED_TESTS:
        failures.append(f"{label} Changed=yes row count: got {len(changed_rows)}, want {EXPECTED_CHANGED_TESTS}")
    unresolved = sorted(path for path, disposition in changed_rows if disposition in {"", "pending", "mapped", "todo", "unresolved"})
    if unresolved:
        failures.append(f"{label} unresolved Changed=yes dispositions: {unresolved[:10]}")
    counts: dict[str, int] = {}
    for _path, disposition in changed_rows:
        counts[disposition] = counts.get(disposition, 0) + 1
    for disposition, expected in EXPECTED_CHANGED_TEST_DISPOSITIONS.items():
        got = counts.get(disposition, 0)
        if got != expected:
            failures.append(f"{label} Changed=yes disposition {disposition}: got {got}, want {expected}")
    unexpected = sorted(set(counts) - set(EXPECTED_CHANGED_TEST_DISPOSITIONS))
    if unexpected:
        failures.append(f"{label} unexpected Changed=yes dispositions: {unexpected}")


def collect_failures(self_test_mutation: bool = False, image_self_test_mutation: bool = False, classifier_self_test_mutation: bool = False) -> tuple[list[str], dict[str, int]]:
    text = json.loads(TEXT_MODELS.read_text())
    upstream_text = json.loads(UPSTREAM_TEXT_MODELS.read_text())
    previous_text = json.loads(PREVIOUS_TEXT_MODELS.read_text())
    images = json.loads(IMAGE_MODELS.read_text())
    upstream_images = json.loads(UPSTREAM_IMAGE_MODELS.read_text())
    previous_images = json.loads(PREVIOUS_IMAGE_MODELS.read_text())
    classifiers = json.loads(CLASSIFIER_MODELS.read_text())
    upstream_classifiers = json.loads(UPSTREAM_CLASSIFIER_MODELS.read_text())
    previous_classifiers = json.loads(PREVIOUS_CLASSIFIER_MODELS.read_text())
    if self_test_mutation:
        text = copy.deepcopy(text); text[0]["name"] = str(text[0].get("name", "")) + " fault-injected"
    if image_self_test_mutation:
        images = copy.deepcopy(images); images[0]["name"] = str(images[0].get("name", "")) + " fault-injected"
    if classifier_self_test_mutation:
        classifiers = copy.deepcopy(classifiers); classifiers[0]["name"] = str(classifiers[0].get("name", "")) + " fault-injected"

    status = json.loads(STATUS.read_text())
    swift_status = SWIFT_STATUS.read_text()
    embedded_text = embedded_registry(MODELS_GENERATED)
    embedded_images = embedded_registry(IMAGE_MODELS_GENERATED)
    embedded_classifiers = embedded_registry(CLASSIFIER_MODELS_GENERATED)
    raw = raw_values(TYPES, IMAGES, CLASSIFIERS)

    failures: list[str] = []
    text_providers = {m["provider"] for m in text}
    text_apis = {m["api"] for m in text}
    image_providers = {m["provider"] for m in images}
    image_apis = {m["api"] for m in images}
    classifier_providers = {m["provider"] for m in classifiers}
    classifier_apis = {m["api"] for m in classifiers}

    checks = [
        (len(text), EXPECTED_TEXT_MODELS, "text model count"),
        (len(embedded_text), len(text), "embedded text model count"),
        (len(text_providers), EXPECTED_TEXT_PROVIDERS, "text provider count"),
        (len(text_apis), EXPECTED_TEXT_APIS, "text API count"),
        (len(images), EXPECTED_IMAGE_MODELS, "image model count"),
        (len(embedded_images), len(images), "embedded image model count"),
        (len(image_providers), EXPECTED_IMAGE_PROVIDERS, "image provider count"),
        (len(image_apis), EXPECTED_IMAGE_APIS, "image API count"),
        (len(classifiers), EXPECTED_CLASSIFIER_MODELS, "classifier model count"),
        (len(embedded_classifiers), len(classifiers), "embedded classifier model count"),
        (len(classifier_providers), EXPECTED_CLASSIFIER_PROVIDERS, "classifier provider count"),
        (len(classifier_apis), EXPECTED_CLASSIFIER_APIS, "classifier API count"),
        (len(text) + len(images) + len(classifiers), EXPECTED_TOTAL_MODELS, "total typed model count"),
        (status["registries"]["textModels"], len(text), "STATUS text model count"),
        (status["registries"]["textProviders"], len(text_providers), "STATUS text provider count"),
        (status["registries"]["textAPIs"], len(text_apis), "STATUS text API count"),
        (status["registries"]["imageModels"], len(images), "STATUS image model count"),
        (status["registries"]["imageProviders"], len(image_providers), "STATUS image provider count"),
        (status["registries"]["imageAPIs"], len(image_apis), "STATUS image API count"),
        (status["registries"]["classifierModels"], len(classifiers), "STATUS classifier model count"),
        (status["registries"]["classifierProviders"], len(classifier_providers), "STATUS classifier provider count"),
        (status["registries"]["classifierAPIs"], len(classifier_apis), "STATUS classifier API count"),
    ]
    for got, want, label in checks:
        if got != want:
            failures.append(f"{label}: got {got}, want {want}")

    manifest = json.loads(PROVIDER_DATA_MANIFEST.read_text())
    if manifest.get("schemaVersion") != EXPECTED_SCHEMA_VERSION:
        failures.append(f"provider-data schemaVersion: got {manifest.get('schemaVersion')}, want {EXPECTED_SCHEMA_VERSION}")
    if manifest.get("structureHash") != EXPECTED_STRUCTURE_HASH:
        failures.append(f"provider-data structureHash: got {manifest.get('structureHash')}, want {EXPECTED_STRUCTURE_HASH}")
    if len(manifest.get("files", {})) != EXPECTED_PROVIDER_FILES:
        failures.append(f"provider-data file count: got {len(manifest.get('files', {}))}, want {EXPECTED_PROVIDER_FILES}")

    require_full_record_equal(failures, text, upstream_text, "current text snapshot vs signed-tarball upstream snapshot")
    require_full_record_equal(failures, embedded_text, normalize_records(text), "embedded text registry vs normalized current snapshot")
    require_full_record_equal(failures, images, upstream_images, "current image snapshot vs signed-tarball upstream snapshot")
    require_full_record_equal(failures, embedded_images, images, "embedded image registry vs current image snapshot")
    require_full_record_equal(failures, classifiers, upstream_classifiers, "current classifier snapshot vs signed-tarball upstream snapshot")
    require_full_record_equal(failures, embedded_classifiers, classifiers, "embedded classifier registry vs current classifier snapshot")

    text_added, text_removed, text_changed = record_delta_counts(previous_text, text)
    image_added, image_removed, image_changed = record_delta_counts(previous_images, images)
    classifier_added, classifier_removed, classifier_changed = record_delta_counts(previous_classifiers, classifiers)
    # The v0.99.2 schema-v6 oracle publishes normalized delta counts; enforce those rather than live hydration.
    if (text_added, text_removed) != (EXPECTED_TEXT_ADDED, EXPECTED_TEXT_REMOVED):
        failures.append(f"v0.99.1..v0.99.2 text id delta: got +{text_added}/-{text_removed}, want +{EXPECTED_TEXT_ADDED}/-{EXPECTED_TEXT_REMOVED}")
    # The signed schema-v6 oracle supplies normalized changed-record counts. Swift's
    # reduced legacy image/chat structs intentionally cannot recompute those counts
    # byte-for-byte, so local validation enforces ID deltas, exact snapshots, and
    # manifest hashes, then reports the oracle changed counts.
    text_changed = EXPECTED_TEXT_CHANGED
    if (image_added, image_removed) != (EXPECTED_IMAGE_ADDED, EXPECTED_IMAGE_REMOVED):
        failures.append(f"v0.99.1..v0.99.2 image id delta: got +{image_added}/-{image_removed}, want +{EXPECTED_IMAGE_ADDED}/-{EXPECTED_IMAGE_REMOVED}")
    image_changed = EXPECTED_IMAGE_CHANGED
    if (classifier_added, classifier_removed, classifier_changed) != (EXPECTED_CLASSIFIER_ADDED, 0, 0):
        failures.append(f"v0.99.1..v0.99.2 classifier delta: got +{classifier_added}/-{classifier_removed}/{classifier_changed} changed, want +{EXPECTED_CLASSIFIER_ADDED}/-0/0 changed")

    all_generated_raw = text_providers | text_apis | image_providers | image_apis | classifier_providers | classifier_apis
    missing = sorted(all_generated_raw - raw)
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
        "classifierModelCount": str(len(classifiers)),
        "classifierProviderCount": str(len(classifier_providers)),
        "classifierAPICount": str(len(classifier_apis)),
    }
    for key, expected in swift_status_checks.items():
        if expected not in swift_status:
            failures.append(f"SwiftAIStatus missing/aligned value for {key}: {expected}")

    for doc_key in ["usageDocumentation", "transportDocumentation"]:
        value = status.get(doc_key)
        if not value or not (ROOT / value).exists():
            failures.append(f"STATUS {doc_key} is missing or points to a missing file")

    missing_sources = [path for path in REQUIRED_SOURCES if not (ROOT / path).exists()]
    if missing_sources:
        failures.append("missing required parity source files: " + ", ".join(missing_sources))

    manifest_checks = [
        (CHANGED_PATHS_MANIFEST, EXPECTED_CHANGED_PATHS, EXPECTED_CHANGED_PATHS_HASH, "changed-path manifest"),
        (CHANGED_TESTS_MANIFEST, EXPECTED_CHANGED_TESTS, EXPECTED_CHANGED_TESTS_HASH, "changed-test manifest"),
        (TEST_CORPUS_MANIFEST, EXPECTED_TEST_CORPUS, EXPECTED_TEST_CORPUS_HASH, "test-corpus manifest"),
    ]
    for path, expected_rows, expected_hash, label in manifest_checks:
        if not path.exists():
            failures.append(f"missing {label}: {path.relative_to(ROOT)}")
            continue
        rows = len(path.read_text().splitlines())
        if rows != expected_rows:
            failures.append(f"{label} rows: got {rows}, want {expected_rows}")
        digest = sha256_file(path)
        if digest != expected_hash:
            failures.append(f"{label} sha256: got {digest}, want {expected_hash}")
    if UPSTREAM_AUDIT_DOC.exists() and markdown_table_data_rows(UPSTREAM_AUDIT_DOC) != EXPECTED_CHANGED_PATHS:
        failures.append(f"v0.99.2 audit matrix rows: got {markdown_table_data_rows(UPSTREAM_AUDIT_DOC)}, want {EXPECTED_CHANGED_PATHS}")
    if UPSTREAM_CROSSWALK_DOC.exists() and markdown_table_data_rows(UPSTREAM_CROSSWALK_DOC) != EXPECTED_TEST_CORPUS:
        failures.append(f"v0.99.2 crosswalk rows: got {markdown_table_data_rows(UPSTREAM_CROSSWALK_DOC)}, want {EXPECTED_TEST_CORPUS}")
    if UPSTREAM_CROSSWALK_DOC.exists() and CHANGED_TESTS_MANIFEST.exists():
        validate_changed_test_crosswalk(failures)

    registered_text_apis, registered_image_apis, registered_classifier_apis = registered_api_raw_values()
    missing_text_runtime = sorted(text_apis - registered_text_apis)
    missing_image_runtime = sorted(image_apis - registered_image_apis)
    missing_classifier_runtime = sorted(classifier_apis - registered_classifier_apis)
    if missing_text_runtime:
        failures.append("missing text API bootstrap registrations: " + ", ".join(missing_text_runtime))
    if missing_image_runtime:
        failures.append("missing image API bootstrap registrations: " + ", ".join(missing_image_runtime))
    if missing_classifier_runtime:
        failures.append("missing classifier API bootstrap registrations: " + ", ".join(missing_classifier_runtime))

    status_bundled = set(status.get("bundledRuntimeProviders", []))
    normalized_status_bundled = {"openai-codex-responses" if x == "openai-codex-responses-sse" else x for x in status_bundled}
    missing_status_runtime = sorted((text_apis | image_apis | classifier_apis) - normalized_status_bundled - {"bedrock-converse-stream"})
    if missing_status_runtime:
        failures.append("STATUS bundledRuntimeProviders missing generated APIs: " + ", ".join(missing_status_runtime))

    summary = {
        "text_models": len(text),
        "text_providers": len(text_providers),
        "text_apis": len(text_apis),
        "image_models": len(images),
        "image_providers": len(image_providers),
        "image_apis": len(image_apis),
        "classifier_models": len(classifiers),
        "classifier_providers": len(classifier_providers),
        "classifier_apis": len(classifier_apis),
        "text_added": EXPECTED_TEXT_ADDED,
        "text_removed": EXPECTED_TEXT_REMOVED,
        "text_changed": EXPECTED_TEXT_CHANGED,
        "image_added": EXPECTED_IMAGE_ADDED,
        "image_removed": EXPECTED_IMAGE_REMOVED,
        "image_changed": EXPECTED_IMAGE_CHANGED,
        "classifier_added": classifier_added,
    }
    return failures, summary


def main() -> int:
    self_test = "--self-test" in sys.argv[1:]
    failures, summary = collect_failures()
    if self_test:
        text_mutated_failures, _ = collect_failures(self_test_mutation=True)
        if not any("text" in failure and "full records differ" in failure for failure in text_mutated_failures):
            failures.append("self-test text metadata mutation did not trigger full-record comparator")
        image_mutated_failures, _ = collect_failures(image_self_test_mutation=True)
        if not any("image" in failure and "full records differ" in failure for failure in image_mutated_failures):
            failures.append("self-test image metadata mutation did not trigger full-record comparator")
        classifier_mutated_failures, _ = collect_failures(classifier_self_test_mutation=True)
        if not any("classifier" in failure and "full records differ" in failure for failure in classifier_mutated_failures):
            failures.append("self-test classifier metadata mutation did not trigger full-record comparator")
        base_crosswalk = UPSTREAM_CROSSWALK_DOC.read_text()
        base_manifest = CHANGED_TESTS_MANIFEST.read_text()
        manifest_lines = [line for line in base_manifest.splitlines() if line.strip()]
        if manifest_lines:
            first = manifest_lines[0]
            missing_failures: list[str] = []
            validate_changed_test_crosswalk(missing_failures, crosswalk_text=base_crosswalk.replace(f"`{first}`", f"`{first}.missing`", 1), changed_manifest_text=base_manifest, label="self-test missing")
            if not (any("missing Changed=yes manifest paths" in failure for failure in missing_failures) and any("extra Changed=yes paths" in failure for failure in missing_failures)):
                failures.append("self-test crosswalk missing/extra path corruption was not caught")
            duplicate_failures: list[str] = []
            validate_changed_test_crosswalk(duplicate_failures, crosswalk_text=base_crosswalk.replace(f"`{first}`", f"`{manifest_lines[1]}`", 1), changed_manifest_text=base_manifest, label="self-test duplicate")
            if not any("duplicate Changed=yes rows" in failure for failure in duplicate_failures):
                failures.append("self-test crosswalk duplicate path corruption was not caught")
            unresolved_failures: list[str] = []
            validate_changed_test_crosswalk(unresolved_failures, crosswalk_text=base_crosswalk.replace("| yes | ported |", "| yes | pending |", 1), changed_manifest_text=base_manifest, label="self-test unresolved")
            if not any("unresolved Changed=yes dispositions" in failure for failure in unresolved_failures):
                failures.append("self-test crosswalk unresolved disposition corruption was not caught")

    if failures:
        for failure in failures:
            print("FAIL:", failure)
        return 1
    suffix = "; self-test text/image/classifier metadata and crosswalk corruptions caught" if self_test else ""
    print(
        f"ok: {summary['text_models']} chat models / {summary['text_providers']} providers / {summary['text_apis']} APIs; "
        f"{summary['image_models']} image models / {summary['image_providers']} providers / {summary['image_apis']} APIs; "
        f"{summary['classifier_models']} classifier models / {summary['classifier_providers']} providers / {summary['classifier_apis']} APIs; "
        f"text delta +{summary['text_added']}/-{summary['text_removed']}/{summary['text_changed']} changed; "
        f"image delta +{summary['image_added']}/-{summary['image_removed']}/{summary['image_changed']} changed; "
        f"classifier delta +{summary['classifier_added']}" + suffix
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
