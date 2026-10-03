"""Promote verified learner snapshots outside nested Godot projects for export."""
import hashlib
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "learning_projects" / "station_light"
TARGET = REPO / "assets" / "learning_starter"
manifest = json.loads((SOURCE / "archives" / "manifest.json").read_text(encoding="utf-8"))
TARGET.mkdir(parents=True, exist_ok=True)
for version in manifest["versions"]:
    original = SOURCE / version["source_archive"]
    data = original.read_bytes()
    assert hashlib.sha256(data).hexdigest() == version["sha256"], original
    destination = TARGET / original.name
    destination.write_bytes(data)
    version["source_archive"] = original.name
    version.pop("project_path", None)
manifest.pop("source_bundle", None)
manifest["distribution"] = "Bundled source snapshots; only verified fixed starter files may be extracted."
(TARGET / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Promoted five checksummed starter archives and export-safe manifest.")
