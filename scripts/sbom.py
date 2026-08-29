#!/usr/bin/env python3
"""Generate and validate a reproducible CycloneDX SBOM for swift-ai.

The generated artifact is intentionally kept out of git under .artifacts/sbom/.
It is derived from Package.swift, Package.resolved, and a pinned local policy file;
no network, secrets, absolute paths, or environment-dependent fields are used.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "scripts" / "sbom-policy.json"
OUT_DIR = ROOT / ".artifacts" / "sbom"
SBOM_PATH = OUT_DIR / "swift-ai.cdx.json"
SHA_PATH = OUT_DIR / "swift-ai.cdx.json.sha256"
SCAN_PATH = OUT_DIR / "swift-ai-security-scan.json"
LICENSE_PATH = OUT_DIR / "swift-ai-license-review.json"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text())


def stable_json(data: Any) -> str:
    return json.dumps(data, indent=2, sort_keys=True, separators=(",", ": ")) + "\n"


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def package_name() -> str:
    manifest = (ROOT / "Package.swift").read_text()
    match = re.search(r'name:\s*"([^"]+)"', manifest)
    if not match:
        raise SystemExit("Package.swift missing package name")
    return match.group(1)


def package_version() -> str:
    status = load_json(ROOT / "STATUS.json")
    return status.get("upstream", {}).get("version", "0.0.0")


def package_resolved() -> dict[str, Any]:
    path = ROOT / "Package.resolved"
    if not path.exists():
        raise SystemExit("Package.resolved is required for SBOM generation; run swift package resolve and keep the lockfile available locally")
    return load_json(path)


def purl_for(identity: str, version: str | None) -> str:
    base = f"pkg:swift/{identity}"
    return f"{base}@{version}" if version else base


def build_components(policy: dict[str, Any]) -> list[dict[str, Any]]:
    resolved = package_resolved()
    components: list[dict[str, Any]] = []
    for pin in sorted(resolved.get("pins", []), key=lambda item: item.get("identity", "")):
        identity = pin["identity"]
        state = pin.get("state", {})
        version = state.get("version")
        revision = state.get("revision")
        license_id = policy.get("componentLicenses", {}).get(identity, "UNKNOWN")
        component = {
            "type": "library",
            "bom-ref": f"pkg:swift/{identity}@{version or revision}",
            "name": identity,
            "version": version or revision,
            "purl": purl_for(identity, version or revision),
            "externalReferences": [{"type": "vcs", "url": pin.get("location", "")}],
            "licenses": [{"license": {"id": license_id}}],
            "properties": [
                {"name": "swift.package.identity", "value": identity},
                {"name": "swift.package.kind", "value": pin.get("kind", "")},
                {"name": "swift.package.revision", "value": revision or ""},
            ],
        }
        components.append(component)
    return components


def build_sbom() -> dict[str, Any]:
    policy = load_json(POLICY_PATH)
    root_name = package_name()
    root_version = package_version()
    root_ref = f"pkg:swift/{root_name}@{root_version}"
    components = build_components(policy)
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": "urn:uuid:00000000-0000-5000-8000-000000000001",
        "version": 1,
        "metadata": {
            "timestamp": "1970-01-01T00:00:00Z",
            "tools": [{"vendor": "swift-ai", "name": policy["toolName"], "version": policy["toolVersion"]}],
            "component": {
                "type": "library",
                "bom-ref": root_ref,
                "name": root_name,
                "version": root_version,
                "purl": root_ref,
                "licenses": [{"license": {"id": policy.get("rootLicense", "UNKNOWN")}}],
                "properties": [
                    {"name": "source.revision", "value": "recorded-in-RELEASE.md-and-CI"},
                    {"name": "swift.package.resolution", "value": "Package.resolved"},
                ],
            },
        },
        "components": components,
        "dependencies": [{"ref": root_ref, "dependsOn": [component["bom-ref"] for component in components]}],
    }


def write_artifacts() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    text = stable_json(build_sbom())
    SBOM_PATH.write_text(text)
    digest = sha256_text(text)
    SHA_PATH.write_text(f"{digest}  {SBOM_PATH.name}\n")
    print(f"wrote {SBOM_PATH.relative_to(ROOT)}")
    print(f"wrote {SHA_PATH.relative_to(ROOT)}")
    print(f"sha256 {digest}")


def validate_sbom() -> dict[str, Any]:
    policy = load_json(POLICY_PATH)
    if not SBOM_PATH.exists() or not SHA_PATH.exists():
        raise SystemExit("SBOM artifacts missing; run make sbom")
    text = SBOM_PATH.read_text()
    digest = sha256_text(text)
    recorded = SHA_PATH.read_text().split()[0]
    if digest != recorded:
        raise SystemExit(f"SBOM checksum mismatch: got {digest}, recorded {recorded}")
    bom = json.loads(text)
    if bom.get("bomFormat") != "CycloneDX" or bom.get("specVersion") != "1.5":
        raise SystemExit("SBOM must be CycloneDX 1.5 JSON")
    components = bom.get("components")
    if not isinstance(components, list) or not components:
        raise SystemExit("SBOM components must be non-empty")
    resolved_pins = package_resolved().get("pins", [])
    if len(components) != len(resolved_pins):
        raise SystemExit(f"SBOM component count {len(components)} != Package.resolved pin count {len(resolved_pins)}")
    raw = text.lower()
    for forbidden in ["/workspace", str(Path.home()).lower(), "ghp_", "github_piclaw_bot"]:
        if forbidden and forbidden in raw:
            raise SystemExit(f"SBOM contains forbidden path/secret marker: {forbidden}")
    names = {component.get("name") for component in components}
    missing_direct = sorted(set(policy.get("directDependencies", [])) - names)
    if missing_direct:
        raise SystemExit("SBOM missing direct dependencies: " + ", ".join(missing_direct))
    allowed = set(policy.get("allowedLicenses", []))
    unknown_or_bad: list[str] = []
    for component in components:
        licenses = component.get("licenses") or []
        license_id = licenses[0].get("license", {}).get("id") if licenses else None
        if license_id not in allowed:
            unknown_or_bad.append(f"{component.get('name')}:{license_id or 'UNKNOWN'}")
    license_result = {
        "status": "pass" if not unknown_or_bad else "fail",
        "allowedLicenses": sorted(allowed),
        "components": sorted(component.get("name") for component in components),
        "unknownOrIncompatible": unknown_or_bad,
    }
    LICENSE_PATH.write_text(stable_json(license_result))
    if unknown_or_bad:
        raise SystemExit("license review failed: " + ", ".join(unknown_or_bad))
    return bom


def scan_sbom() -> None:
    policy = load_json(POLICY_PATH)
    bom = validate_sbom()
    advisories = policy.get("advisories", [])
    high_or_critical = [item for item in advisories if str(item.get("severity", "")).lower() in {"high", "critical"}]
    scan = {
        "tool": {"name": policy["toolName"], "version": policy["toolVersion"], "mode": "pinned-local-policy"},
        "status": "pass" if not high_or_critical else "fail",
        "components": len(bom.get("components", [])),
        "advisories": advisories,
        "highOrCritical": high_or_critical,
        "waivers": policy.get("waivers", []),
    }
    SCAN_PATH.write_text(stable_json(scan))
    if high_or_critical:
        raise SystemExit("security scan failed: high/critical advisories require owner/rationale/expiry")
    print(f"ok: SBOM valid ({len(bom.get('components', []))} components)")
    print(f"ok: license review passed -> {LICENSE_PATH.relative_to(ROOT)}")
    print(f"ok: vulnerability scan passed -> {SCAN_PATH.relative_to(ROOT)}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["generate", "check", "scan"])
    args = parser.parse_args(argv)
    if args.action == "generate":
        write_artifacts()
    elif args.action == "check":
        validate_sbom()
        print("ok: SBOM checksum/schema/components/license checks passed")
    else:
        scan_sbom()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
