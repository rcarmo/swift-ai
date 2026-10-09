#!/usr/bin/env python3
"""Deterministic self-test for the portable project scratch resolver."""
from __future__ import annotations

import os
import tempfile
from pathlib import Path
from unittest.mock import patch

from project_tmp import PROJECT, initialise, resolve_project_root


def require(actual: Path, expected: Path, label: str) -> None:
    if actual != expected:
        raise SystemExit(f"{label}: got {actual}, want {expected}")


def main() -> int:
    configured = os.environ.get("SWIFT_AI_RUN_TMP")
    if not configured:
        raise SystemExit("SWIFT_AI_RUN_TMP is required")
    parent = Path(configured) / "resolver-self-test"
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=parent, prefix="cases-") as raw:
        sandbox = Path(raw)
        workspace = sandbox / "workspace"
        runner = sandbox / "runner"
        original_tmp = sandbox / "original-tmp"
        platform = sandbox / "platform"
        explicit_base = sandbox / "explicit-base"
        explicit_root = explicit_base / PROJECT
        for path in [workspace, runner, original_tmp, platform, explicit_base]:
            path.mkdir(parents=True)

        clean = {"PROJECT_TMP_ROOT": "", "PROJECT_TMP_BASE": "", "CI": "", "RUNNER_TEMP": "", "TMPDIR": ""}
        with patch.dict(os.environ, clean, clear=False):
            os.environ.pop("PROJECT_TMP_ROOT", None)
            os.environ.pop("PROJECT_TMP_BASE", None)
            require(resolve_project_root(str(explicit_root), None, workspace_base=workspace, platform_temp=platform, ci=False), explicit_root, "root override")
            require(resolve_project_root(None, str(explicit_base), workspace_base=workspace, platform_temp=platform, ci=False), explicit_root, "base override")
            require(resolve_project_root(str(explicit_root), str(explicit_base), workspace_base=workspace, platform_temp=platform, ci=False), explicit_root, "matching overrides")
            try:
                resolve_project_root(str(explicit_root), str(sandbox / "other-base"), workspace_base=workspace, platform_temp=platform, ci=False)
            except RuntimeError:
                pass
            else:
                raise SystemExit("conflicting overrides were accepted")
            try:
                resolve_project_root(str(sandbox / "wrong-name"), None, workspace_base=workspace, platform_temp=platform, ci=False)
            except RuntimeError:
                pass
            else:
                raise SystemExit("invalid root override was accepted")

            require(resolve_project_root(None, None, workspace_base=workspace, platform_temp=platform, ci=False), workspace / PROJECT, "local workspace")
            initialise(workspace / PROJECT)
            for name in ["cache", "build", "tests", "logs", "runs"]:
                if not (workspace / PROJECT / name).is_dir():
                    raise SystemExit(f"initialise omitted {name}")

            blocked_workspace = sandbox / "workspace-file"
            blocked_workspace.write_text("blocked")
            require(resolve_project_root(None, None, workspace_base=blocked_workspace, platform_temp=platform, ci=False), platform / PROJECT, "local platform temp")

            with patch.dict(os.environ, {"RUNNER_TEMP": str(runner)}, clear=False):
                require(resolve_project_root(None, None, workspace_base=workspace, platform_temp=platform, ci=True, original_tmpdir=str(original_tmp)), runner / PROJECT, "CI runner")
            blocked_runner = sandbox / "runner-file"
            blocked_runner.write_text("blocked")
            with patch.dict(os.environ, {"RUNNER_TEMP": str(blocked_runner)}, clear=False):
                require(resolve_project_root(None, None, workspace_base=workspace, platform_temp=platform, ci=True, original_tmpdir=str(original_tmp)), original_tmp / PROJECT, "CI original TMPDIR")
            blocked_original = sandbox / "original-file"
            blocked_original.write_text("blocked")
            with patch.dict(os.environ, {"RUNNER_TEMP": str(blocked_runner)}, clear=False):
                require(resolve_project_root(None, None, workspace_base=workspace, platform_temp=platform, ci=True, original_tmpdir=str(blocked_original)), platform / PROJECT, "CI platform temp")

    print("ok: portable project temp root/base overrides, CI/local precedence and hierarchy")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
