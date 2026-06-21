#!/usr/bin/env python3
"""Toolchain-light static checks for swift-ai.

Runs checks that do not require `swift`:
- generated registry/runtime parity audit
- Swift delimiter balance outside string literals
- duplicate private JSONValue extension guard
- TODO/fatalError guard for committed sources
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run_audit() -> None:
    subprocess.run([sys.executable, str(ROOT / "scripts" / "audit-parity.py")], cwd=ROOT, check=True)


def check_delimiters() -> None:
    pairs = {")": "(", "]": "[", "}": "{"}
    for root in [ROOT / "Sources", ROOT / "Tests"]:
        for path in root.rglob("*.swift"):
            text = path.read_text()
            stack: list[str] = []
            in_string = False
            escaped = False
            for index, ch in enumerate(text):
                if ch == '"' and not escaped:
                    in_string = not in_string
                if not in_string:
                    if ch in "([{" :
                        stack.append(ch)
                    elif ch in ")]}":
                        if not stack or stack[-1] != pairs[ch]:
                            raise SystemExit(f"unbalanced {path.relative_to(ROOT)} at {index}: {ch}")
                        stack.pop()
                escaped = (ch == "\\" and not escaped)
                if ch != "\\":
                    escaped = False
            if stack:
                raise SystemExit(f"unclosed delimiters in {path.relative_to(ROOT)}: {stack[-10:]}")
    print("ok: balanced Swift delimiters")


def grep_guard() -> None:
    sources = "\n".join(p.read_text() for root in [ROOT / "Sources", ROOT / "Tests"] for p in root.rglob("*.swift"))
    types = (ROOT / "Sources" / "SwiftAI" / "Types.swift").read_text()
    if "public indirect enum JSONValue" not in types:
        raise SystemExit("JSONValue is recursive and must remain an indirect enum")
    if "public struct StreamOptions: Sendable" not in types:
        raise SystemExit("StreamOptions contains closures and must not synthesize Codable/Equatable")
    images = (ROOT / "Sources" / "SwiftAI" / "Images.swift").read_text()
    if "public struct ImagesOptions: Sendable" not in images:
        raise SystemExit("ImagesOptions contains closures and must not synthesize Codable/Equatable")
    faux = (ROOT / "Sources" / "SwiftAI" / "Providers" / "FauxProvider.swift").read_text()
    if "public nonisolated let models" not in faux:
        raise SystemExit("FauxRegistration.models must remain nonisolated for Swift actor access")
    if "private extension JSONValue" in sources:
        raise SystemExit("private extension JSONValue is disallowed; use public accessors in Types.swift")
    for fragile in ["mapValues(JSONValue.string)", "map(JSONValue.string)"]:
        if fragile in sources:
            raise SystemExit(f"fragile enum-case function reference disallowed: {fragile}")
    for token in ["TODO", "fatalError"]:
        if token in sources:
            raise SystemExit(f"disallowed token in sources: {token}")
    print("ok: source guard checks")


def check_package_manifest() -> None:
    manifest = (ROOT / "Package.swift").read_text()
    required = [
        'name: "swift-ai"',
        '.library(name: "SwiftAI", targets: ["SwiftAI"])',
        '.target(name: "SwiftAI"',
        '.testTarget(name: "SwiftAITests"',
        'https://github.com/apple/swift-crypto.git',
        '.product(name: "Crypto", package: "swift-crypto")',
    ]
    missing = [item for item in required if item not in manifest]
    if missing:
        raise SystemExit("Package.swift missing required SwiftPM declarations: " + ", ".join(missing))
    print("ok: SwiftPM manifest checks")


def check_ci_workflow() -> None:
    workflow = ROOT / ".github" / "workflows" / "ci.yml"
    if not workflow.exists():
        raise SystemExit("missing GitHub Actions workflow: .github/workflows/ci.yml")
    text = workflow.read_text()
    required = ["static-check:", "swift-test:", "make static-check", "make test", "swift-version: '5.9'"]
    missing = [item for item in required if item not in text]
    if missing:
        raise SystemExit("CI workflow missing required entries: " + ", ".join(missing))
    print("ok: CI workflow checks")


def main() -> int:
    run_audit()
    check_delimiters()
    grep_guard()
    check_package_manifest()
    check_ci_workflow()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
