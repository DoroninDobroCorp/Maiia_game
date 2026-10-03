#!/usr/bin/env python3
"""Test isolated copies and extracted archives. Never loads the SUR project."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from zipfile import ZipFile

sys.dont_write_bytecode = True
from package_versions import ROOT, SOURCE_FILES, VERSIONS


def run_godot(godot: str, project: Path, *arguments: str) -> str:
    command = [godot, "--path", str(project), "--log-file", str(project / "engine.log"), *arguments]
    result = subprocess.run(command, text=True, capture_output=True, timeout=40)
    output = result.stdout + result.stderr
    errors = ("SCRIPT ERROR", "ERROR:", "[FAIL]")
    if result.returncode != 0 or any(marker in output for marker in errors):
        raise RuntimeError(f"Godot failed for {project.name}:\n{output}")
    return output


def check_project(godot: str, project: Path, test: Path, label: str) -> None:
    shutil.copy2(test, project / "test_learning_game.gd")
    # Explicit log destination; no import/editor pass and no personal profile service.
    output = run_godot(godot, project, "--headless", "--script", "res://test_learning_game.gd")
    summary = next((line for line in output.splitlines() if line.startswith("LEARNING GAME:")), None)
    if not summary or "0 failed" not in summary:
        raise RuntimeError(f"Missing successful test completion for {label}:\n{output}")
    run_godot(godot, project, "--headless", "--quit-after", "3")
    print(f"{label}: {summary}; main-scene boot clean", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="/opt/homebrew/bin/godot")
    parser.add_argument("--screenshots", action="store_true")
    args = parser.parse_args()
    test = ROOT / "tests" / "test_learning_game.gd"
    if not test.exists():
        test = ROOT.parents[1] / "tests" / "test_learning_game.gd"
    manifest = json.loads((ROOT / "archives" / "manifest.json").read_text())
    assert [entry["version"] for entry in manifest["versions"]] == list(VERSIONS)
    with tempfile.TemporaryDirectory(prefix="sur-learning-check-") as temporary:
        work = Path(temporary)
        current = work / "current"
        current.mkdir()
        for filename in SOURCE_FILES:
            shutil.copy2(ROOT / filename, current / filename)
        check_project(args.godot, current, test, "Current 1.0")
        for entry in manifest["versions"]:
            archive = ROOT / entry["source_archive"]
            assert hashlib.sha256(archive.read_bytes()).hexdigest() == entry["sha256"], archive
            with ZipFile(archive) as zipped:
                assert zipped.testzip() is None
                assert len(zipped.namelist()) == len(SOURCE_FILES)
                assert all(".godot" not in Path(n).parts and ".." not in Path(n).parts and not n.startswith("/") for n in zipped.namelist())
                zipped.extractall(work)
            extracted = work / f"station_light_{entry['version']}"
            for name, expected in entry["source_sha256"].items():
                assert hashlib.sha256((extracted / name).read_bytes()).hexdigest() == expected
                assert (extracted / name).read_bytes() == (ROOT / "versions" / entry["version"] / name).read_bytes()
                if name in ("main.gd", "game_state.gd"):
                    assert (extracted / name).read_bytes() == (ROOT / name).read_bytes(), f"Generated {name} differs from current source"
            settings = json.loads((extracted / "lesson.json").read_text())
            assert settings["version"] == entry["version"] and settings["stage"] == entry["stage"]
            check_project(args.godot, extracted, test, f"Archive {entry['version']}")
        if "source_bundle" in manifest:
            source = ROOT / manifest["source_bundle"]["path"]
            assert hashlib.sha256(source.read_bytes()).hexdigest() == manifest["source_bundle"]["sha256"]
            with ZipFile(source) as zipped:
                assert zipped.testzip() is None
                zipped.extractall(work)
            check_project(args.godot, work / "station_light_source", test, "Complete source archive")
        if args.screenshots:
            destination = ROOT / "qa"
            destination.mkdir(exist_ok=True)
            shutil.copy2(ROOT / "tools" / "capture.gd", current / "capture.gd")
            print(run_godot(args.godot, current, "--script", "res://capture.gd", "--", f"--capture-dir={destination}"), end="")
            assert (destination / "start.png").read_bytes() == (destination / "restart.png").read_bytes(), "Restart screenshot differs from fresh start"
    print("PASS: all standalone sources, five version archives and complete source archive.")


if __name__ == "__main__":
    main()
