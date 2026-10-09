#!/usr/bin/env python3
"""Resolve and initialise swift-ai's portable project-owned scratch hierarchy."""
from __future__ import annotations

import argparse
import os
import tempfile
from pathlib import Path

PROJECT = "swift-ai"
ORIGINAL_TMPDIR = os.environ.get("PROJECT_ORIGINAL_TMPDIR", os.environ.get("TMPDIR", ""))


def _project_name_valid(name: str) -> bool:
    return bool(name) and name[0] not in ".-" and all(character.isalnum() or character in "._-" for character in name)


def _path_usable(path: Path, *, require_project_name: bool = False) -> bool:
    if not path.is_absolute() or ".." in path.parts or (require_project_name and path.name != PROJECT):
        return False
    current = path
    while True:
        if current.is_symlink() and str(current) != "/workspace":
            return False
        if current == current.parent:
            break
        current = current.parent
    if path.exists():
        return path.is_dir() and os.access(path, os.W_OK | os.X_OK) and path.stat().st_uid == os.getuid()
    parent = path.parent
    while not parent.exists():
        if parent.is_symlink():
            return False
        parent = parent.parent
    return parent.is_dir() and os.access(parent, os.W_OK | os.X_OK)


def _is_ci() -> bool:
    if os.environ.get("CI", "").lower() not in {"", "0", "false"}:
        return True
    return any(os.environ.get(name, "").lower() == "true" for name in ["GITHUB_ACTIONS", "GITLAB_CI", "TF_BUILD", "CIRCLECI"])


def _system_temp() -> Path:
    return Path("/tmp") if os.name == "posix" else Path(tempfile.gettempdir())


def resolve_project_root(
    root_override: str | None = None,
    base_override: str | None = None,
    *,
    workspace_base: Path = Path("/workspace/tmp"),
    platform_temp: Path | None = None,
    ci: bool | None = None,
    original_tmpdir: str | None = None,
) -> Path:
    if not _project_name_valid(PROJECT):
        raise RuntimeError("invalid canonical project name")

    if root_override is None and "PROJECT_TMP_ROOT" in os.environ:
        root_override = os.environ["PROJECT_TMP_ROOT"]
    if base_override is None and "PROJECT_TMP_BASE" in os.environ:
        base_override = os.environ["PROJECT_TMP_BASE"]

    explicit_base_root: Path | None = None
    if base_override is not None:
        if not base_override:
            raise RuntimeError("PROJECT_TMP_BASE must not be empty")
        base = Path(base_override.rstrip("/"))
        explicit_base_root = base / PROJECT
        if not _path_usable(explicit_base_root, require_project_name=True):
            raise RuntimeError("PROJECT_TMP_BASE must be a usable absolute base")

    if root_override is not None:
        if not root_override:
            raise RuntimeError("PROJECT_TMP_ROOT must not be empty")
        candidate = Path(root_override.rstrip("/"))
        if not _path_usable(candidate, require_project_name=True):
            raise RuntimeError("PROJECT_TMP_ROOT must be a usable absolute project-named directory, not a symlink")
        if explicit_base_root is not None and candidate != explicit_base_root:
            raise RuntimeError("conflicting PROJECT_TMP_BASE and PROJECT_TMP_ROOT")
        return candidate
    if explicit_base_root is not None:
        return explicit_base_root

    in_ci = _is_ci() if ci is None else ci
    system_temp = platform_temp or _system_temp()
    if in_ci:
        inherited_tmp = ORIGINAL_TMPDIR if original_tmpdir is None else original_tmpdir
        bases = [os.environ.get("RUNNER_TEMP", ""), inherited_tmp, str(system_temp)]
    else:
        bases = [str(workspace_base), str(system_temp)]

    seen: set[str] = set()
    for raw_base in bases:
        if not raw_base or raw_base in seen:
            continue
        seen.add(raw_base)
        candidate = Path(raw_base.rstrip("/")) / PROJECT
        if _path_usable(candidate, require_project_name=True):
            return candidate
    raise RuntimeError("no writable project-owned temporary root available")


def initialise(root: Path) -> None:
    paths = [root, root / "cache", root / "build", root / "tests", root / "logs", root / "runs"]
    for path in paths:
        if not _path_usable(path):
            raise RuntimeError(f"unsafe scratch path: {path}")
    for path in paths[1:]:
        path.mkdir(parents=True, exist_ok=True)


def configured_run_tmp(purpose: str = "direct") -> Path:
    root_value = os.environ.get("SWIFT_AI_TMP_ROOT") or os.environ.get("PROJECT_TMP_ROOT")
    root = resolve_project_root(root_value if root_value else None).resolve()
    configured = os.environ.get("SWIFT_AI_RUN_TMP")
    if configured:
        run_tmp = Path(configured).resolve()
    else:
        run_id = os.environ.get("RUN_ID") or f"pid-{os.getpid()}"
        run_tmp = root / "runs" / purpose / run_id / "tmp"
    expected = (root / "runs").resolve()
    try:
        run_tmp.relative_to(expected)
    except ValueError as error:
        raise RuntimeError(f"run scratch must stay beneath {expected}: {run_tmp}") from error
    if run_tmp.exists() and (run_tmp.is_symlink() or not run_tmp.is_dir()):
        raise RuntimeError(f"run scratch must be a real directory: {run_tmp}")
    run_tmp.mkdir(parents=True, exist_ok=True)
    return run_tmp


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["root", "paths", "init"])
    parser.add_argument("--root")
    parser.add_argument("--base")
    args = parser.parse_args()
    root = resolve_project_root(args.root, args.base)
    if args.action == "init":
        initialise(root)
    if args.action == "root":
        print(root)
    else:
        print(f"PROJECT_TMP_ROOT={root}")
        print(f"CACHE_ROOT={root / 'cache'}")
        print(f"BUILD_ROOT={root / 'build'}")
        print(f"TEST_ROOT={root / 'tests'}")
        print(f"LOG_ROOT={root / 'logs'}")
        print(f"RUN_ROOT={root / 'runs'}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        raise SystemExit(str(error)) from error
