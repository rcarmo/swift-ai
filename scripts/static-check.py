#!/usr/bin/env python3
"""Toolchain-light static checks for swift-ai.

Runs checks that do not require `swift`:
- generated registry/runtime parity audit
- Swift delimiter balance outside string literals
- duplicate private JSONValue extension guard
- TODO/fatalError guard for committed sources
- XCTest hygiene for deterministic tests (no hidden skips, assertions present)
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run_audit() -> None:
    subprocess.run([sys.executable, str(ROOT / "scripts" / "audit-parity.py")], cwd=ROOT, check=True)
    subprocess.run([sys.executable, str(ROOT / "scripts" / "audit-parity.py"), "--self-test"], cwd=ROOT, check=True)


def check_delimiters() -> None:
    pairs = {")": "(", "]": "[", "}": "{"}
    for root in [ROOT / "Sources", ROOT / "Tests"]:
        for path in root.rglob("*.swift"):
            text = path.read_text()
            stack: list[str] = []
            in_string = False
            escaped = False
            raw_hashes = 0
            index = 0
            while index < len(text):
                ch = text[index]
                if not in_string and ch == '#':
                    hash_count = 0
                    while index + hash_count < len(text) and text[index + hash_count] == '#':
                        hash_count += 1
                    if index + hash_count < len(text) and text[index + hash_count] == '"':
                        in_string = True
                        raw_hashes = hash_count
                        index += hash_count + 1
                        continue
                if ch == '"' and not escaped:
                    if raw_hashes:
                        if text[index + 1:index + 1 + raw_hashes] == '#' * raw_hashes:
                            in_string = False
                            index += raw_hashes + 1
                            raw_hashes = 0
                            escaped = False
                            continue
                    else:
                        in_string = not in_string
                if not in_string:
                    if ch in "([{" :
                        stack.append(ch)
                    elif ch in ")]}":
                        if not stack or stack[-1] != pairs[ch]:
                            raise SystemExit(f"unbalanced {path.relative_to(ROOT)} at {index}: {ch}")
                        stack.pop()
                escaped = (ch == "\\" and not escaped and raw_hashes == 0)
                if ch != "\\":
                    escaped = False
                index += 1
            if stack:
                raise SystemExit(f"unclosed delimiters in {path.relative_to(ROOT)}: {stack[-10:]}")
    print("ok: balanced Swift delimiters")


def grep_guard() -> None:
    sources = "\n".join(p.read_text() for root in [ROOT / "Sources", ROOT / "Tests"] for p in root.rglob("*.swift"))
    types = (ROOT / "Sources" / "SwiftAI" / "Core" / "Types.swift").read_text()
    if "public indirect enum JSONValue" not in types:
        raise SystemExit("JSONValue is recursive and must remain an indirect enum")
    if "public struct StreamOptions: Sendable" not in types:
        raise SystemExit("StreamOptions contains closures and must not synthesize Codable/Equatable")
    images = (ROOT / "Sources" / "SwiftAI" / "Core" / "Images.swift").read_text()
    if "public struct ImagesOptions: Sendable" not in images:
        raise SystemExit("ImagesOptions contains closures and must not synthesize Codable/Equatable")
    faux = (ROOT / "Sources" / "SwiftAI" / "Providers" / "FauxProvider.swift").read_text()
    if "public nonisolated let models" not in faux:
        raise SystemExit("FauxRegistration.models must remain nonisolated for Swift actor access")
    if "private extension JSONValue" in sources:
        raise SystemExit("private extension JSONValue is disallowed; use public accessors in Types.swift")
    for fragile in ["mapValues(JSONValue.string)", "map(JSONValue.string)", "?? nil"]:
        if fragile in sources:
            raise SystemExit(f"fragile Swift pattern disallowed: {fragile}")
    for token in ["TODO", "fatalError"]:
        if token in sources:
            raise SystemExit(f"disallowed token in sources: {token}")
    print("ok: source guard checks")


def check_project_temp_policy() -> None:
    makefile = (ROOT / "Makefile").read_text()
    agents = (ROOT / "AGENTS.md").read_text()
    required_make = [
        "PROJECT_TMP_RESOLVER := $(CURDIR)/scripts/project_tmp.py",
        "PROJECT_TMP_BASE_ORIGIN := $(origin PROJECT_TMP_BASE)",
        "override PROJECT_TMP_ROOT :=",
        "--scratch-path $(SWIFTPM_BUILD_ROOT)",
        "--cache-path $(SWIFTPM_CACHE_ROOT)",
        "SWIFT_AI_TEST_RUN_ROOT",
        "TMPDIR := $(RUN_TMP)",
        "python3 scripts/test-project-tmp.py",
    ]
    missing_make = [item for item in required_make if item not in makefile]
    if missing_make:
        raise SystemExit("Makefile missing project-owned temp routing: " + ", ".join(missing_make))
    required_agents = ["PROJECT_TMP_BASE", "/workspace/tmp/swift-ai", "${RUNNER_TEMP}/swift-ai", "tests/", "logs/", "runs/<purpose>/<run-id>/test-fs", "make tmp-init"]
    missing_agents = [item for item in required_agents if item not in agents]
    if missing_agents:
        raise SystemExit("AGENTS.md missing project temp policy: " + ", ".join(missing_agents))
    for path in (ROOT / "Tests").rglob("*.swift"):
        text = path.read_text()
        if "FileManager.default.temporaryDirectory" in text or "NSTemporaryDirectory()" in text:
            raise SystemExit(f"test bypasses SwiftAITestScratch: {path.relative_to(ROOT)}")
    validator = (ROOT / "scripts" / "validate-model-data.py").read_text()
    if 'tempfile.TemporaryDirectory(prefix=prefix, dir=root)' not in validator or 'configured_run_tmp("model-data")' not in validator:
        raise SystemExit("model validator temp directories are not project-owned")
    print("ok: project-owned cache/temp policy")


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


def _extract_test_body(lines: list[str], start: int) -> str:
    depth = 0
    started = False
    body: list[str] = []
    for line in lines[start:]:
        body.append(line)
        for ch in line:
            if ch == "{":
                depth += 1
                started = True
            elif ch == "}":
                depth -= 1
                if started and depth <= 0:
                    return "\n".join(body)
    return "\n".join(body)


def _collect_yaml_literal_blocks(text: str, key: str = "run") -> list[str]:
    lines = text.splitlines()
    blocks: list[str] = []
    index = 0
    pattern = re.compile(rf"^(?P<indent>\s*){re.escape(key)}:\s*\|\s*$")
    while index < len(lines):
        match = pattern.match(lines[index])
        if not match:
            index += 1
            continue
        base_indent = len(match.group("indent"))
        index += 1
        block_lines: list[str] = []
        while index < len(lines):
            line = lines[index]
            if line.strip() and len(line) - len(line.lstrip(" ")) <= base_indent:
                break
            block_lines.append(line[base_indent + 2:] if len(line) >= base_indent + 2 else "")
            index += 1
        blocks.append("\n".join(block_lines))
    return blocks


def _bash_syntax_check(script: str, label: str) -> None:
    # GitHub expression interpolation happens before bash runs. Replace expressions with
    # inert text so local syntax checks validate the shell structure around them.
    scrubbed = re.sub(r"\$\{\{[^}]+\}\}", "GITHUB_EXPR", script)
    subprocess.run(["bash", "-n"], input=scrubbed, text=True, cwd=ROOT, check=True)


def _validate_native_tag_policy(ref: dict | None, tag_object: dict | None, runtime_ref: str, tag: str = "v0.99.2") -> None:
    expected_tagger = {"name": "Rui Carmo", "email": "rui.carmo@gmail.com"}
    if not ref:
        raise SystemExit(f"native release tag {tag} is missing or cannot be read")
    ref_object = ref.get("object") or {}
    if ref_object.get("type") != "tag":
        raise SystemExit(f"native release tag {tag} must be an annotated tag object, got {ref_object.get('type')!r}")
    if not tag_object:
        raise SystemExit(f"native release tag {tag} tag object is missing or cannot be read")
    tagger = tag_object.get("tagger") or {}
    if tagger.get("name") != expected_tagger["name"] or tagger.get("email") != expected_tagger["email"]:
        raise SystemExit(
            f"native release tag {tag} tagger must be {expected_tagger['name']} <{expected_tagger['email']}>, "
            f"got {tagger.get('name')!r} <{tagger.get('email')!r}>"
        )
    target = tag_object.get("object") or {}
    if target.get("type") != "commit":
        raise SystemExit(f"native release tag {tag} must target a commit, got {target.get('type')!r}")
    if target.get("sha") != runtime_ref:
        raise SystemExit(f"native release tag {tag} targets {target.get('sha')}, expected {runtime_ref}")


def _expect_native_tag_policy_failure(label: str, ref: dict | None, tag_object: dict | None, runtime_ref: str) -> None:
    try:
        _validate_native_tag_policy(ref, tag_object, runtime_ref)
    except SystemExit:
        return
    raise SystemExit(f"native tag policy simulation should reject {label}")


def check_native_tag_policy_simulation() -> None:
    runtime = "379018acd61375462d02a971e5283be6b009d33e"
    tag_sha = "1111111111111111111111111111111111111111"
    exact_ref = {"object": {"type": "tag", "sha": tag_sha}}
    exact_tag = {
        "tagger": {"name": "Rui Carmo", "email": "rui.carmo@gmail.com"},
        "object": {"type": "commit", "sha": runtime},
    }
    _expect_native_tag_policy_failure("absent tag", None, None, runtime)
    _expect_native_tag_policy_failure("lightweight tag", {"object": {"type": "commit", "sha": runtime}}, None, runtime)
    _expect_native_tag_policy_failure(
        "wrong tagger",
        exact_ref,
        {"tagger": {"name": "github-actions[bot]", "email": "41898282+github-actions[bot]@users.noreply.github.com"}, "object": {"type": "commit", "sha": runtime}},
        runtime,
    )
    _expect_native_tag_policy_failure(
        "wrong target",
        exact_ref,
        {"tagger": {"name": "Rui Carmo", "email": "rui.carmo@gmail.com"}, "object": {"type": "commit", "sha": "0" * 40}},
        runtime,
    )
    _validate_native_tag_policy(exact_ref, exact_tag, runtime)
    print("ok: native tag policy simulations")


def check_xctest_hygiene() -> None:
    assertion_tokens = ["XCTAssert", "XCTFail", "XCTUnwrap", "XCTSkip", "#expect", "try await SwiftAI.complete"]
    for path in (ROOT / "Tests").rglob("*.swift"):
        text = path.read_text()
        rel = path.relative_to(ROOT)
        if path.name != "LiveGatedTests.swift" and re.search(r"\bXCTSkip(?:Unless|If)?\b", text):
            raise SystemExit(f"deterministic test file must not skip tests: {rel}")
        lines = text.splitlines()
        for index, line in enumerate(lines):
            match = re.search(r"\bfunc\s+(test\w+)\s*\(", line)
            if not match:
                continue
            body = _extract_test_body(lines, index)
            if not any(token in body for token in assertion_tokens):
                raise SystemExit(f"test has no assertions or explicit completion check: {rel}:{index + 1} {match.group(1)}")
    print("ok: XCTest hygiene checks")


def check_ci_workflow() -> None:
    workflow = ROOT / ".github" / "workflows" / "ci.yml"
    if not workflow.exists():
        raise SystemExit("missing GitHub Actions workflow: .github/workflows/ci.yml")
    text = workflow.read_text()
    required = ["static-check:", "swift-test:", "make check", "swift --version"]
    missing = [item for item in required if item not in text]
    if missing:
        raise SystemExit("CI workflow missing required entries: " + ", ".join(missing))
    for idx, block in enumerate(_collect_yaml_literal_blocks(text), start=1):
        _bash_syntax_check(block, f"ci.yml run block {idx}")

    publish = ROOT / ".github" / "workflows" / "publish-sbom-release.yml"
    if not publish.exists():
        raise SystemExit("missing GitHub Actions workflow: .github/workflows/publish-sbom-release.yml")
    publish_text = publish.read_text()
    publish_required = [
        "release_kind:",
        '*) echo "release_kind must be upstream or native',
        'expected_tag="v${{ inputs.upstream_version }}"',
        'gh_api(f"git/ref/tags/{tag}")',
        'ref_object.get("type") != "tag"',
        'expected_tagger = {"name": "Rui Carmo", "email": "rui.carmo@gmail.com"}',
        'target.get("type") != "commit"',
        'target.get("sha") != runtime_ref',
        'gh release create "$tag" --verify-tag',
        "swift-ai v${upstream_version}",
        "SBOM for @earendil-works/pi-ai v${upstream_version}",
    ]
    missing_publish = [item for item in publish_required if item not in publish_text]
    if missing_publish:
        raise SystemExit("publish workflow missing required native/upstream release entries: " + ", ".join(missing_publish))
    forbidden_native = [
        'git tag -a "$tag"',
        'git push origin "refs/tags/${tag}"',
        'github-actions[bot]',
        '41898282+github-actions[bot]@users.noreply.github.com',
    ]
    present_forbidden = [item for item in forbidden_native if item in publish_text]
    if present_forbidden:
        raise SystemExit("publish workflow must not create/push native tags: " + ", ".join(present_forbidden))
    for idx, block in enumerate(_collect_yaml_literal_blocks(publish_text), start=1):
        _bash_syntax_check(block, f"publish-sbom-release.yml run block {idx}")
    print("ok: CI workflow checks")


def main() -> int:
    run_audit()
    check_delimiters()
    grep_guard()
    check_project_temp_policy()
    check_package_manifest()
    check_ci_workflow()
    check_native_tag_policy_simulation()
    check_xctest_hygiene()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
