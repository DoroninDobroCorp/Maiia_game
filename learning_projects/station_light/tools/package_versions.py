#!/usr/bin/env python3
"""Rebuild prepared source snapshots; never includes Godot caches or personal work."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
SOURCE_FILES = ("project.godot", "main.tscn", "main.gd", "game_state.gd", "lesson.json", "README.md", "AUTHORSHIP.json")
VERSIONS = ("0.1", "0.2", "0.3", "0.4", "1.0")


def write_zip(destination: Path, entries: dict[str, bytes]) -> str:
    with ZipFile(destination, "w", compression=ZIP_DEFLATED) as archive:
        for name, data in sorted(entries.items()):
            info = ZipInfo(name, date_time=(2026, 10, 2, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    return hashlib.sha256(destination.read_bytes()).hexdigest()


def main() -> None:
    archives = ROOT / "archives"
    archives.mkdir(exist_ok=True)
    manifest: dict = {
        "schema_version": 1,
        "starter_project_id": "station_arcade_starter",
        "kind": "prepared_learning_starter",
        "title": "Собери свет для станции",
        "engine_tested": "Godot 4.7.2",
        "entry_project": "project.godot",
        "authorship": "AUTHORSHIP.json",
        "launch_registration": "Not performed; owned by the SUR launcher integration.",
        "versions": [],
    }
    for version in VERSIONS:
        settings_text = (ROOT / "version_configs" / f"{version}.json").read_text()
        settings = json.loads(settings_text)
        assert settings["version"] == version
        assert len(settings["lights"]) == 3
        target = ROOT / "versions" / version
        target.mkdir(parents=True, exist_ok=True)
        entries = {}
        file_hashes = {}
        for name in SOURCE_FILES:
            data = (ROOT / name).read_bytes()
            if name == "lesson.json":
                data = settings_text.encode()
            elif name == "project.godot":
                data = data.replace(b'config/version="1.0"', f'config/version="{version}"'.encode())
            (target / name).write_bytes(data)
            entries[f"station_light_{version}/{name}"] = data
            file_hashes[name] = hashlib.sha256(data).hexdigest()
        archive_name = f"station_light_{version}.zip"
        checksum = write_zip(archives / archive_name, entries)
        manifest["versions"].append({
            "version": version,
            "stage": settings["stage"],
            "project_path": f"versions/{version}/project.godot",
            "source_archive": f"archives/{archive_name}",
            "sha256": checksum,
            "source_sha256": file_hashes,
        })
    # Complete distributable source bundle: code, lessons, snapshots and test tools.
    bundle: dict[str, bytes] = {f"station_light_source/{name}": (ROOT / name).read_bytes() for name in SOURCE_FILES}
    for folder in ("version_configs", "tools", "versions"):
        for path in sorted((ROOT / folder).rglob("*")):
            if path.is_file() and not any(part in {".godot", "__pycache__"} for part in path.parts) and path.suffix != ".pyc":
                bundle[f"station_light_source/{path.relative_to(ROOT).as_posix()}"] = path.read_bytes()
    test = ROOT / "tests" / "test_learning_game.gd"
    if not test.exists():
        test = ROOT.parents[1] / "tests" / "test_learning_game.gd"
    bundle["station_light_source/tests/test_learning_game.gd"] = test.read_bytes()
    # Include version ZIPs and their manifest so the unpacked bundle's check.py works.
    # This embedded manifest intentionally omits the checksum of its own outer ZIP.
    for entry in manifest["versions"]:
        bundle[f"station_light_source/{entry['source_archive']}"] = (ROOT / entry["source_archive"]).read_bytes()
    bundle["station_light_source/archives/manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
    name = "station_light_source.zip"
    manifest["source_bundle"] = {"path": f"archives/{name}", "sha256": write_zip(archives / name, bundle)}
    (archives / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print("Packaged five independent Godot projects and six reproducible source archives.")


if __name__ == "__main__":
    main()
