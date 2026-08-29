#!/usr/bin/env python3
"""Generate, validate, and scan a CycloneDX SBOM for swift-ai.

Artifacts are generated under .artifacts/sbom/ and are intentionally not
committed. Inputs are Package.swift, tracked Package.resolved, SwiftPM's
show-dependencies JSON graph, Git revision state, and a pinned local policy.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "scripts" / "sbom-policy.json"
OUT_DIR = ROOT / ".artifacts" / "sbom"
TOOLS_DIR = ROOT / ".artifacts" / "tools"
OSV_BIN = TOOLS_DIR / "bin" / "osv-scanner"
SBOM_PATH = OUT_DIR / "swift-ai.cdx.json"
SHA_PATH = OUT_DIR / "swift-ai.cdx.json.sha256"
OSV_RAW_PATH = OUT_DIR / "osv-scanner.json"
SCAN_PATH = OUT_DIR / "swift-ai-security-scan.json"
LICENSE_PATH = OUT_DIR / "swift-ai-license-review.json"


def run(args: list[str], *, capture: bool = True, check: bool = True, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=ROOT, text=True, capture_output=capture, check=check, env=env)


def load_json(path: Path) -> Any:
    return json.loads(path.read_text())


def stable_json(data: Any) -> str:
    return json.dumps(data, indent=2, sort_keys=True, separators=(",", ": ")) + "\n"


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def policy() -> dict[str, Any]:
    return load_json(POLICY_PATH)


def package_name() -> str:
    manifest = (ROOT / "Package.swift").read_text()
    match = re.search(r'name:\s*"([^"]+)"', manifest)
    if not match:
        raise SystemExit("Package.swift missing package name")
    return match.group(1)


def package_version() -> str:
    status = load_json(ROOT / "STATUS.json")
    return status.get("upstream", {}).get("version", "0.0.0")


def git_revision() -> str:
    return run(["git", "rev-parse", "HEAD"]).stdout.strip()


def git_dirty() -> bool:
    return bool(run(["git", "status", "--porcelain"]).stdout.strip())


def package_resolved() -> dict[str, Any]:
    path = ROOT / "Package.resolved"
    if not path.exists():
        raise SystemExit("Package.resolved is required and must be tracked for SBOM generation")
    return load_json(path)


def resolved_pin_map() -> dict[str, dict[str, Any]]:
    return {pin["identity"]: pin for pin in package_resolved().get("pins", [])}


def swift_dependency_graph() -> dict[str, Any]:
    swift = os.environ.get("SWIFT", "swift")
    result = run([swift, "package", "show-dependencies", "--format", "json"])
    graph = json.loads(result.stdout)
    if graph.get("name") != package_name():
        raise SystemExit("SwiftPM dependency graph root name does not match Package.swift name")
    graph["identity"] = package_name()
    return graph


def purl_for(identity: str, version: str | None) -> str:
    base = f"pkg:swift/{identity}"
    return f"{base}@{version}" if version else base


def component_ref(identity: str, version: str | None, revision: str | None = None) -> str:
    return f"pkg:swift/{identity}@{version or revision or 'unspecified'}"


def flatten_graph(node: dict[str, Any]) -> dict[str, set[str]]:
    edges: dict[str, set[str]] = {}

    def walk(current: dict[str, Any]) -> None:
        identity = current["identity"]
        children = current.get("dependencies", []) or []
        edges.setdefault(identity, set()).update(child["identity"] for child in children)
        for child in children:
            walk(child)

    walk(node)
    return edges


def build_components(pol: dict[str, Any], graph: dict[str, Any]) -> list[dict[str, Any]]:
    pins = resolved_pin_map()
    graph_edges = flatten_graph(graph)
    graph_identities = set(graph_edges) - {package_name()}
    pin_identities = set(pins)
    if graph_identities != pin_identities:
        raise SystemExit(f"SwiftPM graph identities differ from Package.resolved: graph={sorted(graph_identities)} pins={sorted(pin_identities)}")
    components: list[dict[str, Any]] = []
    for identity in sorted(pin_identities):
        pin = pins[identity]
        state = pin.get("state", {})
        version = state.get("version")
        revision = state.get("revision")
        license_id = pol.get("componentLicenses", {}).get(identity, "UNKNOWN")
        components.append({
            "type": "library",
            "bom-ref": component_ref(identity, version, revision),
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
        })
    return components


def build_dependencies(graph: dict[str, Any]) -> list[dict[str, Any]]:
    pins = resolved_pin_map()
    root_name = package_name()
    root_ref = component_ref(root_name, package_version())
    edges = flatten_graph(graph)
    out: list[dict[str, Any]] = []
    for identity in sorted(edges):
        ref = root_ref if identity == root_name else component_ref(identity, pins[identity].get("state", {}).get("version"), pins[identity].get("state", {}).get("revision"))
        depends = []
        for child in sorted(edges[identity]):
            state = pins[child].get("state", {})
            depends.append(component_ref(child, state.get("version"), state.get("revision")))
        out.append({"ref": ref, "dependsOn": depends})
    return out


def build_sbom() -> dict[str, Any]:
    pol = policy()
    graph = swift_dependency_graph()
    root_name = package_name()
    root_version = package_version()
    root_ref = component_ref(root_name, root_version)
    dirty = git_dirty()
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": "urn:uuid:00000000-0000-5000-8000-000000000001",
        "version": 1,
        "metadata": {
            "timestamp": "1970-01-01T00:00:00Z",
            "tools": [
                {"vendor": "swift-ai", "name": pol["toolName"], "version": pol["toolVersion"]},
                {"vendor": "Google", "name": "osv-scanner", "version": pol["osvScannerVersion"]},
            ],
            "component": {
                "type": "library",
                "bom-ref": root_ref,
                "name": root_name,
                "version": root_version,
                "purl": root_ref,
                "licenses": [{"license": {"id": pol.get("rootLicense", "UNKNOWN")}}],
                "properties": [
                    {"name": "git.revision", "value": git_revision()},
                    {"name": "git.dirty", "value": str(dirty).lower()},
                    {"name": "swift.package.resolution", "value": "Package.resolved"},
                ],
            },
        },
        "components": build_components(pol, graph),
        "dependencies": build_dependencies(graph),
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


def validate_waivers(pol: dict[str, Any], vulnerabilities: list[dict[str, Any]], today: dt.date | None = None) -> set[str]:
    today = today or dt.date.today()
    allowed_ids = {v.get("id") for v in vulnerabilities}
    waived: set[str] = set()
    for waiver in pol.get("waivers", []):
        required = ["id", "owner", "rationale", "mitigation", "expires"]
        missing = [field for field in required if not waiver.get(field)]
        if missing:
            raise SystemExit("waiver missing required fields: " + ", ".join(missing))
        try:
            expires = dt.date.fromisoformat(waiver["expires"])
        except ValueError as exc:
            raise SystemExit(f"waiver {waiver.get('id')} has invalid expiry") from exc
        if expires < today:
            raise SystemExit(f"waiver expired: {waiver['id']}")
        if waiver["id"] not in allowed_ids:
            raise SystemExit(f"waiver does not match current finding: {waiver['id']}")
        waived.add(waiver["id"])
    return waived


def validate_sbom() -> dict[str, Any]:
    pol = policy()
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
    root_props = {p.get("name"): p.get("value") for p in bom.get("metadata", {}).get("component", {}).get("properties", [])}
    if root_props.get("git.revision") != git_revision():
        raise SystemExit(f"SBOM git.revision {root_props.get('git.revision')} does not match HEAD {git_revision()}")
    if root_props.get("git.dirty") != str(git_dirty()).lower():
        raise SystemExit("SBOM git.dirty does not match current working tree state")
    dependencies = bom.get("dependencies") or []
    edge_map = {item.get("ref"): set(item.get("dependsOn", [])) for item in dependencies}
    root_ref = component_ref(package_name(), package_version())
    if root_ref not in edge_map:
        raise SystemExit("SBOM missing root dependency edge")
    if len(edge_map[root_ref]) != len(pol.get("directDependencies", [])):
        raise SystemExit("SBOM root dependency edge does not match direct dependency policy")
    raw = text.lower()
    for forbidden in ["/workspace", str(Path.home()).lower(), "ghp_", "github_piclaw_bot"]:
        if forbidden and forbidden in raw:
            raise SystemExit(f"SBOM contains forbidden path/secret marker: {forbidden}")
    names = {component.get("name") for component in components}
    missing_direct = sorted(set(pol.get("directDependencies", [])) - names)
    if missing_direct:
        raise SystemExit("SBOM missing direct dependencies: " + ", ".join(missing_direct))
    allowed = set(pol.get("allowedLicenses", []))
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


def ensure_osv_scanner() -> str:
    pol = policy()
    version = pol["osvScannerVersion"]
    if OSV_BIN.exists():
        out = run([str(OSV_BIN), "--version"]).stdout
        if f"osv-scanner version: {version}" in out:
            return str(OSV_BIN)
    (TOOLS_DIR / "bin").mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update({
        "GOBIN": str(TOOLS_DIR / "bin"),
        "GOPATH": str(TOOLS_DIR / "gopath"),
        "GOMODCACHE": str(TOOLS_DIR / "gomod"),
    })
    run(["go", "install", f"github.com/google/osv-scanner/v2/cmd/osv-scanner@v{version}"], capture=False, env=env)
    out = run([str(OSV_BIN), "--version"]).stdout
    if f"osv-scanner version: {version}" not in out:
        raise SystemExit("installed osv-scanner version does not match policy")
    return str(OSV_BIN)


def osv_scan() -> dict[str, Any]:
    scanner = ensure_osv_scanner()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    result = run([scanner, "scan", "source", "--format", "json", "--output-file", str(OSV_RAW_PATH), "."], check=False)
    if result.returncode not in (0, 1):
        raise SystemExit(f"osv-scanner failed with exit code {result.returncode}\n{result.stderr}")
    if not OSV_RAW_PATH.exists():
        raise SystemExit("osv-scanner did not write JSON output")
    return load_json(OSV_RAW_PATH)


def flatten_vulnerabilities(osv: dict[str, Any]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    for result in osv.get("results", []) or []:
        for package in result.get("packages", []) or []:
            pkg = package.get("package", {})
            for vuln in package.get("vulnerabilities", []) or []:
                severity = authoritative_severity(vuln)
                findings.append({
                    "id": vuln.get("id"),
                    "summary": vuln.get("summary"),
                    "package": pkg.get("name"),
                    "version": pkg.get("version"),
                    "severity": severity,
                    "severityScore": severity_score(severity),
                    "severityUnparseable": severity_score(severity) is None and str(severity).lower() not in {"low", "moderate", "medium", "high", "critical"},
                })
    return findings


def authoritative_severity(vuln: dict[str, Any]) -> str:
    database_specific = vuln.get("database_specific") if isinstance(vuln.get("database_specific"), dict) else {}
    for key in ["severity", "cvss"]:
        value = database_specific.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    severities = vuln.get("severity") or []
    for item in severities:
        if not isinstance(item, dict):
            continue
        score = item.get("score")
        if isinstance(score, str) and score.strip():
            return score.strip()
        typ = item.get("type")
        if isinstance(typ, str) and typ.strip():
            return typ.strip()
    return "unknown"


def cvss_score(vector: str) -> float | None:
    if not vector.startswith("CVSS:3."):
        return None
    metrics = dict(part.split(":", 1) for part in vector.split("/")[1:] if ":" in part)
    weights = {
        "AV": {"N": 0.85, "A": 0.62, "L": 0.55, "P": 0.2},
        "AC": {"L": 0.77, "H": 0.44},
        "PRU": {"N": 0.85, "L": 0.62, "H": 0.27},
        "PRC": {"N": 0.85, "L": 0.68, "H": 0.5},
        "UI": {"N": 0.85, "R": 0.62},
        "CIA": {"H": 0.56, "L": 0.22, "N": 0.0},
    }
    try:
        scope_changed = metrics["S"] == "C"
        av = weights["AV"][metrics["AV"]]
        ac = weights["AC"][metrics["AC"]]
        pr = weights["PRC" if scope_changed else "PRU"][metrics["PR"]]
        ui = weights["UI"][metrics["UI"]]
        c = weights["CIA"][metrics["C"]]
        i = weights["CIA"][metrics["I"]]
        a = weights["CIA"][metrics["A"]]
    except KeyError:
        return None
    exploitability = 8.22 * av * ac * pr * ui
    impact_sub_score = 1 - ((1 - c) * (1 - i) * (1 - a))
    if not scope_changed:
        impact = 6.42 * impact_sub_score
        if impact <= 0:
            return 0.0
        raw = min(impact + exploitability, 10.0)
    else:
        impact = 7.52 * (impact_sub_score - 0.029) - 3.25 * ((impact_sub_score - 0.02) ** 15)
        if impact <= 0:
            return 0.0
        raw = min(1.08 * (impact + exploitability), 10.0)
    return min(10.0, (int(raw * 10 + 0.999999) / 10.0))


def severity_score(value: Any) -> float | None:
    text = str(value or "").strip()
    lowered = text.lower()
    labels = {"low": 3.9, "moderate": 6.9, "medium": 6.9, "high": 8.9, "critical": 10.0}
    if lowered in labels:
        return labels[lowered]
    try:
        return float(text)
    except ValueError:
        return cvss_score(text)


def is_high_or_critical(finding: dict[str, Any]) -> bool:
    value = finding.get("severity", "unknown")
    lowered = str(value).lower()
    if lowered in {"high", "critical"}:
        return True
    score = severity_score(value)
    if score is None:
        return True
    return score >= 7.0


def run_self_tests() -> None:
    cases = [
        ({"severity": "HIGH"}, True),
        ({"severity": "CRITICAL"}, True),
        ({"severity": "7.0"}, True),
        ({"severity": "6.9"}, False),
        ({"severity": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"}, True),
        ({"severity": "CVSS:3.1/AV:L/AC:H/PR:H/UI:R/S:U/C:L/I:N/A:N"}, False),
        ({"severity": "unknown"}, True),
        ({"severity": "not-a-score"}, True),
    ]
    for finding, expected in cases:
        got = is_high_or_critical(finding)
        if got != expected:
            raise SystemExit(f"severity self-test failed for {finding}: got {got}, want {expected}")
    vuln = [{"id": "OSV-1", "severity": "critical"}]
    try:
        validate_waivers({"waivers": [{"id": "OSV-1", "owner": "security", "rationale": "accepted", "mitigation": "upgrade scheduled", "expires": "2099-01-01"}]}, vuln, today=dt.date(2026, 1, 1))
    except SystemExit as exc:
        raise SystemExit("valid waiver self-test failed") from exc
    for bad in [
        {"id": "OSV-1", "owner": "security", "rationale": "accepted", "expires": "2099-01-01"},
        {"id": "OSV-1", "owner": "security", "rationale": "accepted", "mitigation": "upgrade", "expires": "2020-01-01"},
    ]:
        try:
            validate_waivers({"waivers": [bad]}, vuln, today=dt.date(2026, 1, 1))
        except SystemExit:
            continue
        raise SystemExit(f"invalid waiver self-test failed open: {bad}")
    print("ok: SBOM severity/waiver self-tests passed")


def scan_sbom() -> None:
    run_self_tests()
    pol = policy()
    bom = validate_sbom()
    osv = osv_scan()
    vulnerabilities = flatten_vulnerabilities(osv)
    high_or_critical = [item for item in vulnerabilities if is_high_or_critical(item)]
    waived = validate_waivers(pol, high_or_critical)
    unwaived = [item for item in high_or_critical if item.get("id") not in waived]
    scan = {
        "tool": {"name": "osv-scanner", "version": pol["osvScannerVersion"], "mode": "pinned-real-osv-db"},
        "status": "pass" if not unwaived else "fail",
        "components": len(bom.get("components", [])),
        "rawOutput": str(OSV_RAW_PATH.relative_to(ROOT)),
        "vulnerabilities": vulnerabilities,
        "highOrCritical": high_or_critical,
        "waived": sorted(waived),
    }
    SCAN_PATH.write_text(stable_json(scan))
    if unwaived:
        raise SystemExit("security scan failed: high/critical advisories require owner/rationale/mitigation/expiry: " + ", ".join(str(item.get("id")) for item in unwaived))
    print(f"ok: SBOM valid ({len(bom.get('components', []))} components)")
    print(f"ok: license review passed -> {LICENSE_PATH.relative_to(ROOT)}")
    print(f"ok: OSV vulnerability scan passed -> {SCAN_PATH.relative_to(ROOT)}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["generate", "check", "scan"])
    args = parser.parse_args(argv)
    if args.action == "generate":
        write_artifacts()
    elif args.action == "check":
        validate_sbom()
        print("ok: SBOM checksum/schema/components/provenance/graph/license checks passed")
    else:
        scan_sbom()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
