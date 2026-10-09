#!/usr/bin/env python3
"""Validate and render pinned schema-v6 pi-ai provider data.

Inputs are either the verified npm tarball bytes or an explicit provider-data
folder containing `.manifest.json` plus the 42 provider JSON shards. Flattened
precomputed record files are never used as authority.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

from project_tmp import configured_run_tmp

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_TARBALL_SHA256 = "6caab33cec57480ed02c57fe37428a030a77cc2a0662814b435a5cf8932ad829"
EXPECTED_SCHEMA = 6
EXPECTED_COUNTS = {"chat": 1563, "image": 61, "classifier": 26}
EXPECTED_PROVIDERS = {"chat": 41, "image": 1, "classifier": 6}
EXPECTED_APIS = {"chat": 10, "image": 1, "classifier": 3}
EXPECTED_TOTAL = 1650
EXPECTED_PROVIDER_FILES = 42
EXPECTED_GENERATED_AT = "2026-10-07T22:01:28.515Z"
EXPECTED_STRUCTURE_HASH = "080cfcf6bdd13064ce2362f26e4902c31503b675fd06a8c4685c04a0333bc465"
MODALITIES = {"text", "image"}
REQUIRED_MANIFEST = {"schemaVersion", "generatedAt", "structureHash", "files"}


def temporary_directory(prefix: str) -> tempfile.TemporaryDirectory[str]:
    try:
        root = configured_run_tmp("model-data")
    except RuntimeError as error:
        raise SystemExit(str(error)) from error
    return tempfile.TemporaryDirectory(prefix=prefix, dir=root)


def load_json(path: Path):
    return json.loads(path.read_text())


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_jsonl(path: Path, values: list[dict]) -> None:
    path.write_text("".join(json.dumps(item, sort_keys=True, separators=(",", ":")) + "\n" for item in values))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def provider_data_from_tarball(tarball: Path) -> tempfile.TemporaryDirectory[str]:
    digest = sha256(tarball)
    if digest != EXPECTED_TARBALL_SHA256:
        raise SystemExit(f"tarball sha256: got {digest}, want {EXPECTED_TARBALL_SHA256}")
    temp = temporary_directory("provider-data-")
    root = Path(temp.name)
    with tarfile.open(tarball, "r:gz") as archive:
        members = [m for m in archive.getmembers() if m.name.startswith("package/dist/providers/data/") and m.isfile()]
        archive.extractall(root, members=members)
    data_dir = root / "package/dist/providers/data"
    if not data_dir.exists():
        temp.cleanup()
        raise SystemExit("tarball does not contain package/dist/providers/data")
    temp.data_dir = data_dir  # type: ignore[attr-defined]
    return temp


def require_string(record: dict, field: str, label: str) -> None:
    if not isinstance(record.get(field), str) or not record[field]:
        raise SystemExit(f"{label} missing required string field {field}")


def require_positive_int(record: dict, field: str, label: str) -> None:
    value = record.get(field)
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise SystemExit(f"{label} field {field} must be a positive integer")


def validate_cost(record: dict, label: str) -> None:
    cost = record.get("cost")
    if not isinstance(cost, dict):
        raise SystemExit(f"{label} missing cost object")
    for field in ["input", "output", "cacheRead", "cacheWrite"]:
        value = cost.get(field)
        if not isinstance(value, (int, float)) or not math.isfinite(float(value)):
            raise SystemExit(f"{label} cost.{field} must be a finite number")


def validate_modalities(values, label: str, field: str, require_image: bool = False) -> None:
    if not isinstance(values, list) or not values:
        raise SystemExit(f"{label} {field} must be a non-empty array")
    unknown = [value for value in values if value not in MODALITIES]
    if unknown:
        raise SystemExit(f"{label} {field} contains unsupported modalities: {unknown}")
    if require_image and "image" not in values:
        raise SystemExit(f"{label} {field} must include image")


def validate_record(record: dict, kind: str, label: str) -> None:
    for field in ["id", "name", "api", "provider"]:
        require_string(record, field, label)
    if "baseUrl" in record and not isinstance(record["baseUrl"], str):
        raise SystemExit(f"{label} baseUrl must be a string when present")
    if record.get("type", "chat") != kind:
        raise SystemExit(f"{label} type mismatch: got {record.get('type')!r}, want {kind!r}")
    validate_cost(record, label)
    validate_modalities(record.get("input"), label, "input")
    if kind == "chat":
        require_positive_int(record, "contextWindow", label)
        require_positive_int(record, "maxTokens", label)
    elif kind == "image":
        validate_modalities(record.get("output"), label, "output", require_image=True)
    elif kind == "classifier":
        require_positive_int(record, "contextWindow", label)
    else:
        raise SystemExit(f"unsupported record kind: {kind}")


def validate_manifest(data_dir: Path) -> dict:
    manifest_path = data_dir / ".manifest.json"
    if not manifest_path.exists():
        raise SystemExit("provider-data manifest missing")
    manifest = load_json(manifest_path)
    missing = REQUIRED_MANIFEST - set(manifest)
    if missing:
        raise SystemExit(f"provider-data manifest missing required fields: {sorted(missing)}")
    if manifest.get("schemaVersion") != EXPECTED_SCHEMA:
        raise SystemExit(f"provider-data schemaVersion: got {manifest.get('schemaVersion')}, want {EXPECTED_SCHEMA}")
    if manifest.get("generatedAt") != EXPECTED_GENERATED_AT:
        raise SystemExit(f"provider-data generatedAt: got {manifest.get('generatedAt')}, want {EXPECTED_GENERATED_AT}")
    if manifest.get("structureHash") != EXPECTED_STRUCTURE_HASH:
        raise SystemExit(f"provider-data structureHash: got {manifest.get('structureHash')}, want {EXPECTED_STRUCTURE_HASH}")
    files = manifest.get("files")
    if not isinstance(files, dict) or len(files) != EXPECTED_PROVIDER_FILES:
        raise SystemExit(f"provider-data files: got {len(files) if isinstance(files, dict) else 'invalid'}, want {EXPECTED_PROVIDER_FILES}")
    actual_files = sorted(path.name for path in data_dir.glob("*.json") if path.name != ".manifest.json")
    if actual_files != sorted(files):
        raise SystemExit("provider-data manifest file identity does not match shard directory")
    for name, expected in sorted(files.items()):
        if not isinstance(expected, str) or len(expected) != 64:
            raise SystemExit(f"provider-data {name} manifest digest is invalid")
        digest = sha256(data_dir / name)
        if digest != expected:
            raise SystemExit(f"provider-data {name} sha256: got {digest}, want {expected}")
    return manifest


def derive_records(data_dir: Path) -> dict[str, list[dict]]:
    out: dict[str, list[dict]] = {"chat": [], "image": [], "classifier": []}
    seen: set[tuple[str, str, str]] = set()
    for shard in sorted(path for path in data_dir.glob("*.json") if path.name != ".manifest.json"):
        data = load_json(shard)
        if not isinstance(data, dict):
            raise SystemExit(f"provider shard {shard.name} must be an object")
        for api, entries in data.items():
            if not isinstance(api, str) or not isinstance(entries, dict):
                raise SystemExit(f"provider shard {shard.name} has invalid API map")
            for key, record in entries.items():
                if not isinstance(record, dict):
                    raise SystemExit(f"provider shard {shard.name} record {key} must be an object")
                kind = record.get("type", "chat")
                label = f"{shard.name}:{api}:{key}"
                validate_record(record, kind, label)
                expected_provider = shard.name[:-5]
                if record["provider"] != expected_provider:
                    raise SystemExit(f"{label} provider field {record['provider']!r} does not match shard {expected_provider!r}")
                if record["api"] != api:
                    raise SystemExit(f"{label} api field does not match containing API")
                expected_key = f"{kind}:{record['id']}"
                if key != expected_key:
                    raise SystemExit(f"{label} key mismatch: got {key}, want {expected_key}")
                dedupe = (kind, record["provider"], record["id"])
                if dedupe in seen:
                    raise SystemExit(f"duplicate provider/id/type record: {dedupe}")
                seen.add(dedupe)
                out[kind].append(record)
    for kind, records in out.items():
        if len(records) != EXPECTED_COUNTS[kind]:
            raise SystemExit(f"{kind} count: got {len(records)}, want {EXPECTED_COUNTS[kind]}")
        providers = {record["provider"] for record in records}
        apis = {record["api"] for record in records}
        if len(providers) != EXPECTED_PROVIDERS[kind]:
            raise SystemExit(f"{kind} provider count: got {len(providers)}, want {EXPECTED_PROVIDERS[kind]}")
        if len(apis) != EXPECTED_APIS[kind]:
            raise SystemExit(f"{kind} API count: got {len(apis)}, want {EXPECTED_APIS[kind]}")
    if sum(len(records) for records in out.values()) != EXPECTED_TOTAL:
        raise SystemExit("total record count mismatch")
    return out


def inject_fault(data_dir: Path, fault: str) -> tempfile.TemporaryDirectory[str]:
    temp = temporary_directory("provider-fault-")
    dst = Path(temp.name) / "data"
    shutil.copytree(data_dir, dst)
    if fault == "missing-file":
        next(path for path in dst.glob("*.json") if path.name != ".manifest.json").unlink()
    elif fault == "source-hash":
        target = next(path for path in dst.glob("*.json") if path.name != ".manifest.json")
        target.write_text(target.read_text() + "\n")
    elif fault == "manifest-schema":
        manifest = load_json(dst / ".manifest.json"); manifest["schemaVersion"] = 5; write_json(dst / ".manifest.json", manifest)
    elif fault == "bogus-modality":
        mutate_first(dst, "chat", lambda record: record.update({"input": ["audio"]}))
    elif fault == "missing-cost":
        mutate_first(dst, "chat", lambda record: record.pop("cost", None))
    elif fault == "image-output-text":
        mutate_first(dst, "image", lambda record: record.update({"output": ["text"]}))
    elif fault == "missing-chat-cap":
        mutate_first(dst, "chat", lambda record: record.pop("contextWindow", None))
    elif fault == "duplicate":
        mutate_first(dst, "chat", lambda record: record.update({"id": "amazon.nova-lite-v1:0"}))
    elif fault == "late-classifier":
        mutate_first(dst, "classifier", lambda record: record.update({"api": "openai-completions"}))
    else:
        raise SystemExit(f"unknown fault {fault}")
    if fault not in {"missing-file", "source-hash", "manifest-schema"}:
        refresh_manifest_hashes(dst)
    temp.data_dir = dst  # type: ignore[attr-defined]
    return temp


def refresh_manifest_hashes(data_dir: Path) -> None:
    manifest = load_json(data_dir / ".manifest.json")
    for name in list(manifest.get("files", {})):
        path = data_dir / name
        if path.exists():
            manifest["files"][name] = sha256(path)
    write_json(data_dir / ".manifest.json", manifest)


def mutate_first(data_dir: Path, kind: str, mutate) -> None:
    for shard in sorted(path for path in data_dir.glob("*.json") if path.name != ".manifest.json"):
        data = load_json(shard)
        changed = False
        for entries in data.values():
            for record in entries.values():
                if record.get("type", "chat") == kind:
                    mutate(record); changed = True; break
            if changed: break
        if changed:
            write_json(shard, data)
            return
    raise SystemExit(f"no {kind} record to mutate")


def render_stage(records: dict[str, list[dict]], manifest: dict, stage: Path) -> None:
    scripts = stage / "scripts"
    generated = stage / "generated"
    scripts.mkdir(parents=True)
    generated.mkdir(parents=True)
    specs = {
        "chat": ("models.v1.1.0.json", "upstream-models.abe508e.json", "ModelsGenerated.swift"),
        "image": ("image-models.v1.1.0.json", "upstream-image-models.abe508e.json", "ImageModelsGenerated.swift"),
        "classifier": ("classifier-models.v1.1.0.json", "upstream-classifier-models.abe508e.json", "ClassifierModelsGenerated.swift"),
    }
    for kind, (current, upstream, swift_name) in specs.items():
        for name in [current, upstream]:
            write_json(scripts / name, records[kind])
            write_jsonl(scripts / f"{name}l", records[kind])
        subprocess.run([sys.executable, str(ROOT / "scripts/generate-models.py"), str(scripts / current), str(generated / swift_name)], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    write_json(scripts / "provider-data-manifest.v1.1.0.json", manifest)


def publish_stage(stage: Path, output_root: Path, generated_root: Path) -> None:
    files = list((stage / "scripts").iterdir())
    files += list((stage / "generated").iterdir())
    for path in files:
        if not path.exists() or path.stat().st_size == 0:
            raise SystemExit(f"staged output missing or empty: {path}")
    output_root.mkdir(parents=True, exist_ok=True)
    generated_root.mkdir(parents=True, exist_ok=True)
    for path in (stage / "scripts").iterdir():
        shutil.copy2(path, output_root / path.name)
    for path in (stage / "generated").iterdir():
        shutil.copy2(path, generated_root / path.name)


def main() -> int:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--tarball", type=Path)
    source.add_argument("--provider-data-dir", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--output-root", type=Path, default=ROOT / "scripts")
    parser.add_argument("--generated-root", type=Path, default=ROOT / "Sources/SwiftAI/Models/Generated")
    parser.add_argument("--fault", choices=["missing-file", "source-hash", "manifest-schema", "bogus-modality", "missing-cost", "image-output-text", "missing-chat-cap", "duplicate", "late-classifier", "render-format"])
    args = parser.parse_args()

    temp_source = None
    if args.tarball:
        temp_source = provider_data_from_tarball(args.tarball)
        data_dir = temp_source.data_dir  # type: ignore[attr-defined]
    else:
        data_dir = args.provider_data_dir
    fault_temp = None
    render_fault = args.fault == "render-format"
    if args.fault and not render_fault:
        fault_temp = inject_fault(data_dir, args.fault)
        data_dir = fault_temp.data_dir  # type: ignore[attr-defined]

    manifest = validate_manifest(data_dir)
    records = derive_records(data_dir)
    if not args.validate_only:
        with temporary_directory("model-render-") as tmp:
            stage = Path(tmp)
            render_stage(records, manifest, stage)
            if render_fault:
                raise SystemExit("injected render/format fault after staging; accepted outputs were not replaced")
            publish_stage(stage, args.output_root, args.generated_root)
    print("ok: verified pinned schema6 provider data rendered 1563/61/26 records")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
