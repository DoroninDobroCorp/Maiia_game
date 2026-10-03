class_name BackupService
extends RefCounted

## A portable family backup is a directory with manifest.json, snapshot.json,
## media/* and launch_media/{versions,working}/*. The folder is portable without
## unpacking user project archives. Launch registrations remain machine-local.
const ArtifactServiceScript = preload("res://scripts/services/artifact_service.gd")
const SaveServiceScript = preload("res://scripts/services/save_service.gd")
const FORMAT := "sur_family_backup"
const MAX_METADATA_BYTES := 16 * 1024 * 1024
const MAX_MEDIA_FILES := 10000
const MAX_TOTAL_BYTES := 2 * 1024 * 1024 * 1024
static var LAUNCH_DIR := "user://launch_registry"
const PRIVATE_KEYS := ["launch_registry", "launch_entries", "trusted_launches", "registered_launches", "source_path", "absolute_path", "file_path", "executable_path", "managed_path", "launch_path", "path", "recovery_notice", "read_only"]

## Optional callback runs on the calling thread: (phase, done, total) -> bool.
## Return false to cancel. Counts are local to each phase; total 0 means unknown.
## Checkpoints do not access Nodes and never commit a SaveService transaction.
static func export_family_backup(state: Dictionary, destination: String, progress: Callable = Callable()) -> Dictionary:
	if not _snapshot_shape_valid(state):
		return {"ok": false, "reason": "invalid_backup_state"}
	if destination.strip_edges().is_empty() or FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(destination)):
		return {"ok": false, "reason": "backup_destination_exists_or_empty"}
	if not _checkpoint(progress, "export_prepare", 0, 1):
		return {"ok": false, "reason": "cancelled"}
	var staging := destination + ".pending-" + str(Time.get_ticks_usec())
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staging.path_join("media")))
	if err != OK:
		return {"ok": false, "reason": "backup_directory_failed"}
	var snapshot: Dictionary = _portable(state)
	var manifest := {"format": FORMAT, "version": 1, "created_at": Time.get_datetime_string_from_system(),
		"snapshot_file": "snapshot.json", "media": [], "launch_media": [], "missing_media": [], "launch_registration_required": true}
	var seen: Dictionary = {}
	var total_bytes := 0
	var artifacts: Dictionary = snapshot.get("phase_b", {}).get("artifacts", {})
	var inspected := 0
	for record_value in artifacts.values():
		if not _checkpoint(progress, "export_media", inspected, artifacts.size()):
			return _cancel_export(staging)
		inspected += 1
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		var file_name := str(record.get("media_file", ""))
		if bool(record.get("media_deleted", false)) or file_name.is_empty():
			continue
		if not ArtifactServiceScript.is_managed_filename(file_name):
			_remove_tree(staging)
			return {"ok": false, "reason": "unsafe_media_filename"}
		if seen.has(file_name):
			continue
		seen[file_name] = true
		var source := ArtifactServiceScript.ARTIFACT_DIR.path_join(file_name)
		if not FileAccess.file_exists(source):
			manifest.missing_media.append(file_name)
			continue
		var size := _file_size(source)
		total_bytes += size
		if size < 0 or size > ArtifactServiceScript.MAX_PROJECT_BYTES or total_bytes > MAX_TOTAL_BYTES or seen.size() > MAX_MEDIA_FILES:
			_remove_tree(staging)
			return {"ok": false, "reason": "backup_size_limit"}
		var target := staging.path_join("media").path_join(file_name)
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target)) != OK:
			_remove_tree(staging)
			return {"ok": false, "reason": "backup_media_copy_failed"}
		var checksum := FileAccess.get_sha256(source)
		if checksum.is_empty() or checksum != FileAccess.get_sha256(target):
			_remove_tree(staging)
			return {"ok": false, "reason": "backup_media_verification_failed"}
		manifest.media.append({"file": file_name, "byte_size": size, "sha256": checksum})
	if not _checkpoint(progress, "export_media", inspected, artifacts.size()):
		return _cancel_export(staging)
	var launch_files := _collect_launch_files(progress)
	if not launch_files.ok:
		_remove_tree(staging)
		return launch_files
	for name in launch_files.files:
		if not _checkpoint(progress, "export_launch", manifest.launch_media.size(), launch_files.files.size()):
			return _cancel_export(staging)
		var source: String = LAUNCH_DIR.path_join(name)
		var target: String = staging.path_join("launch_media").path_join(name)
		var size := _file_size(source)
		total_bytes += maxi(0, size)
		if size < 0 or size > ArtifactServiceScript.MAX_PROJECT_BYTES or total_bytes > MAX_TOTAL_BYTES or seen.size() + manifest.launch_media.size() >= MAX_MEDIA_FILES:
			_remove_tree(staging)
			return {"ok": false, "reason": "backup_size_limit"}
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir())) != OK or DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target)) != OK:
			_remove_tree(staging)
			return {"ok": false, "reason": "backup_launch_copy_failed"}
		var checksum := FileAccess.get_sha256(source)
		if checksum.is_empty() or checksum != FileAccess.get_sha256(target):
			_remove_tree(staging)
			return {"ok": false, "reason": "backup_launch_verification_failed"}
		manifest.launch_media.append({"file": name, "byte_size": size, "sha256": checksum, "unix_permissions": FileAccess.get_unix_permissions(source)})
	if not _checkpoint(progress, "export_launch", manifest.launch_media.size(), launch_files.files.size()) or not _checkpoint(progress, "export_metadata", 0, 2):
		return _cancel_export(staging)
	if not _write_json(staging.path_join("snapshot.json"), snapshot):
		_remove_tree(staging)
		return {"ok": false, "reason": "backup_snapshot_failed"}
	manifest["snapshot_sha256"] = FileAccess.get_sha256(staging.path_join("snapshot.json"))
	if not _checkpoint(progress, "export_metadata", 1, 2):
		return _cancel_export(staging)
	if not _write_json(staging.path_join("manifest.json"), manifest):
		_remove_tree(staging)
		return {"ok": false, "reason": "backup_manifest_failed"}
	if not _checkpoint(progress, "export_metadata", 2, 2) or not _checkpoint(progress, "export_commit", 0, 1):
		return _cancel_export(staging)
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(staging), ProjectSettings.globalize_path(destination)) != OK:
		_remove_tree(staging)
		return {"ok": false, "reason": "backup_commit_failed"}
	return {"ok": true, "media_count": manifest.media.size(), "launch_file_count": manifest.launch_media.size(), "total_bytes": total_bytes, "missing_media": manifest.missing_media.duplicate(), "backup_path": destination}

## Returns a candidate state for the caller's SaveService transaction. Existing
## metadata/files are never overwritten; a failed verification makes no changes.
static func import_family_backup(source_directory: String, progress: Callable = Callable()) -> Dictionary:
	if not _checkpoint(progress, "import_validate", 0, 1):
		return {"ok": false, "reason": "cancelled"}
	var manifest := _read_json(source_directory.path_join("manifest.json"))
	if manifest.get("format") != FORMAT or manifest.get("version") != 1 or not manifest.get("media") is Array or manifest.media.size() > MAX_MEDIA_FILES:
		return {"ok": false, "reason": "invalid_backup_manifest"}
	var snapshot_path := source_directory.path_join("snapshot.json")
	if FileAccess.get_sha256(snapshot_path) != str(manifest.get("snapshot_sha256", "")):
		return {"ok": false, "reason": "backup_snapshot_checksum_failed"}
	var snapshot := _read_json(snapshot_path)
	if snapshot.is_empty() or not SaveServiceScript._is_supported_schema(snapshot):
		return {"ok": false, "reason": "unsupported_backup_schema"}
	if not _snapshot_shape_valid(snapshot):
		return {"ok": false, "reason": "invalid_backup_state"}
	if JSON.stringify(_portable(snapshot)) != JSON.stringify(snapshot):
		return {"ok": false, "reason": "backup_contains_private_paths"}
	if not manifest.get("missing_media", []) is Array or not manifest.get("launch_media", []) is Array:
		return {"ok": false, "reason": "invalid_backup_manifest"}
	var seen: Dictionary = {}
	var total_bytes := 0
	for value in manifest.media:
		if not _checkpoint(progress, "import_media_validate", seen.size(), manifest.media.size()):
			return {"ok": false, "reason": "cancelled"}
		if not value is Dictionary:
			return {"ok": false, "reason": "invalid_backup_media"}
		var name := str(value.get("file", ""))
		if not ArtifactServiceScript.is_managed_filename(name) or seen.has(name):
			return {"ok": false, "reason": "unsafe_media_filename"}
		seen[name] = value
		var media_path := source_directory.path_join("media").path_join(name)
		var size := _file_size(media_path)
		total_bytes += maxi(0, size)
		if size < 0 or size > ArtifactServiceScript.MAX_PROJECT_BYTES or size != value.get("byte_size", -1) or total_bytes > MAX_TOTAL_BYTES:
			return {"ok": false, "reason": "backup_media_size_failed"}
		if FileAccess.get_sha256(media_path) != str(value.get("sha256", "")):
			return {"ok": false, "reason": "backup_media_checksum_failed"}
	var launch_seen: Dictionary = {}
	for value in manifest.get("launch_media", []):
		if not _checkpoint(progress, "import_launch_validate", launch_seen.size(), manifest.launch_media.size()):
			return {"ok": false, "reason": "cancelled"}
		if not value is Dictionary:
			return {"ok": false, "reason": "invalid_backup_launch_media"}
		var name := str(value.get("file", ""))
		if not _safe_launch_relative(name) or launch_seen.has(name):
			return {"ok": false, "reason": "unsafe_launch_filename"}
		launch_seen[name] = value
		var launch_path := source_directory.path_join("launch_media").path_join(name)
		var size := _file_size(launch_path)
		total_bytes += maxi(0, size)
		if size < 0 or size > ArtifactServiceScript.MAX_PROJECT_BYTES or size != value.get("byte_size", -1) or total_bytes > MAX_TOTAL_BYTES or seen.size() + launch_seen.size() > MAX_MEDIA_FILES:
			return {"ok": false, "reason": "backup_launch_size_failed"}
		if FileAccess.get_sha256(launch_path) != str(value.get("sha256", "")):
			return {"ok": false, "reason": "backup_launch_checksum_failed"}
	var artifacts_value: Variant = snapshot.get("phase_b", {}).get("artifacts", {})
	if not artifacts_value is Dictionary:
		return {"ok": false, "reason": "invalid_backup_artifacts"}
	for record in artifacts_value.values():
		if not record is Dictionary:
			return {"ok": false, "reason": "invalid_backup_artifacts"}
		var name := str(record.get("media_file", ""))
		if not name.is_empty() and not ArtifactServiceScript.is_managed_filename(name):
			return {"ok": false, "reason": "unsafe_media_filename"}
		if not name.is_empty() and not bool(record.get("media_deleted", false)) and not seen.has(name) and not manifest.get("missing_media", []).has(name):
			return {"ok": false, "reason": "backup_media_missing_from_manifest"}
	if not _checkpoint(progress, "import_validate", 1, 1):
		return {"ok": false, "reason": "cancelled"}
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ArtifactServiceScript.ARTIFACT_DIR)) != OK:
		return {"ok": false, "reason": "artifact_directory_failed"}
	var created: Array[String] = []
	var renamed: Dictionary = {}
	var launch_restore := _restore_launch_files(source_directory, launch_seen, progress)
	if not launch_restore.ok:
		return launch_restore
	var restored_count := 0
	for name in seen:
		if not _checkpoint(progress, "import_restore_media", restored_count, seen.size()):
			_rollback_restore(created, launch_restore.created_roots)
			return {"ok": false, "reason": "cancelled"}
		restored_count += 1
		var target_name: String = name
		var target := ArtifactServiceScript.ARTIFACT_DIR.path_join(target_name)
		if FileAccess.file_exists(target):
			if FileAccess.get_sha256(target) == seen[name].sha256:
				continue
			target_name = "restored_%s_%s" % [str(Time.get_ticks_usec()), name]
			target = ArtifactServiceScript.ARTIFACT_DIR.path_join(target_name)
			renamed[name] = target_name
		var temporary := target + ".tmp"
		var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(source_directory.path_join("media").path_join(name)), ProjectSettings.globalize_path(temporary))
		if copied != OK or FileAccess.get_sha256(temporary) != seen[name].sha256 or DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(target)) != OK:
			ArtifactServiceScript._remove_file(temporary)
			_rollback_restore(created, launch_restore.created_roots)
			return {"ok": false, "reason": "backup_restore_copy_failed"}
		created.append(target)
	if not _checkpoint(progress, "import_restore_media", restored_count, seen.size()):
		_rollback_restore(created, launch_restore.created_roots)
		return {"ok": false, "reason": "cancelled"}
	for record in artifacts_value.values():
		if renamed.has(record.get("media_file", "")):
			record.media_file = renamed[record.media_file]
	snapshot = _restore_launch_references(snapshot, launch_restore.remapped)
	if not _checkpoint(progress, "import_ready", 1, 1):
		_rollback_restore(created, launch_restore.created_roots)
		return {"ok": false, "reason": "cancelled"}
	return {"ok": true, "state": SaveServiceScript._merge_with_defaults(snapshot), "media_count": seen.size(),
		"launch_file_count": launch_seen.size(), "missing_media": manifest.get("missing_media", []).duplicate(), "launch_registration_required": true}

static func _safe_launch_relative(path: String) -> bool:
	if not (path.begins_with("versions/") or path.begins_with("working/")) or path.contains("\\") or path.contains(":"):
		return false
	var parts := path.split("/")
	if parts.size() < 3:
		return false
	for part in parts:
		if part in ["", ".", ".."] or part.ends_with(".tmp"):
			return false
	return true

static func _collect_launch_files(progress: Callable = Callable()) -> Dictionary:
	var files: Array[String] = []
	var status := {"cancelled": false}
	for folder in ["versions", "working"]:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(LAUNCH_DIR.path_join(folder))):
			if not _walk_launch(folder, files, progress, status):
				return {"ok": false, "reason": "cancelled" if status.cancelled else "backup_unsafe_launch_file"}
	return {"ok": true, "files": files}

static func _walk_launch(relative: String, files: Array[String], progress: Callable, status: Dictionary) -> bool:
	if not _checkpoint(progress, "export_scan", files.size(), 0):
		status.cancelled = true
		return false
	var directory := DirAccess.open(LAUNCH_DIR.path_join(relative))
	if directory == null or files.size() > MAX_MEDIA_FILES:
		return false
	for name in directory.get_files():
		if not _checkpoint(progress, "export_scan", files.size(), 0):
			status.cancelled = true
			return false
		if name.ends_with(".tmp"):
			continue
		var path := relative.path_join(name)
		if directory.is_link(name) or not _safe_launch_relative(path):
			return false
		files.append(path)
	for name in directory.get_directories():
		# Editor caches can be regenerated and are never a project's only copy.
		if name == ".godot":
			continue
		if directory.is_link(name) or not _walk_launch(relative.path_join(name), files, progress, status):
			return false
	return true

static func _restore_launch_files(source_directory: String, files: Dictionary, progress: Callable = Callable()) -> Dictionary:
	var roots: Dictionary = {}
	var created_roots: Array[String] = []
	var remapped: Dictionary = {}
	var restored_count := 0
	for name in files:
		if not _checkpoint(progress, "import_restore_launch", restored_count, files.size()):
			_rollback_restore([], created_roots)
			return {"ok": false, "reason": "cancelled"}
		var parts: PackedStringArray = str(name).split("/")
		var original_root := parts[0] + "/" + parts[1]
		if not roots.has(original_root):
			var new_root := original_root
			if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(LAUNCH_DIR.path_join(new_root))):
				new_root = parts[0] + "/restored_" + str(Time.get_ticks_usec()) + "_" + parts[1]
			roots[original_root] = new_root
			created_roots.append(LAUNCH_DIR.path_join(new_root))
			remapped["launch_registry/" + original_root + "/"] = "launch_registry/" + new_root + "/"
		var destination: String = LAUNCH_DIR.path_join(roots[original_root]).path_join(str(name).trim_prefix(original_root + "/"))
		var source: String = source_directory.path_join("launch_media").path_join(name)
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir())) != OK or DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination)) != OK or FileAccess.get_sha256(destination) != str(files[name].sha256):
			_rollback_restore([], created_roots)
			return {"ok": false, "reason": "backup_restore_launch_failed"}
		var permissions: Variant = files[name].get("unix_permissions", 0)
		if typeof(permissions) in [TYPE_INT, TYPE_FLOAT] and int(permissions) > 0:
			FileAccess.set_unix_permissions(destination, int(permissions) & 511)
		restored_count += 1
	if not _checkpoint(progress, "import_restore_launch", restored_count, files.size()):
		_rollback_restore([], created_roots)
		return {"ok": false, "reason": "cancelled"}
	return {"ok": true, "created_roots": created_roots, "remapped": remapped}

static func _checkpoint(progress: Callable, phase: String, done: int, total: int) -> bool:
	return not progress.is_valid() or bool(progress.call(phase, done, total))

static func _cancel_export(staging: String) -> Dictionary:
	_remove_tree(staging)
	return {"ok": false, "reason": "cancelled"}

static func _rollback_restore(created_files: Array, created_roots: Array) -> void:
	for path in created_files:
		ArtifactServiceScript._remove_file(str(path))
	for path in created_roots:
		_remove_tree(str(path))

static func _restore_launch_references(value: Variant, remapped: Dictionary) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			# Reimported work never inherits a local launch authorization, even if
			# that computer already has a registry entry with the same public ID.
			if str(key) == "launch_entry_id":
				result[key] = ""
			else:
				result[key] = _restore_launch_references(value[key], remapped)
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_restore_launch_references(item, remapped))
		return result
	if value is String:
		for prefix in remapped:
			if value.begins_with(prefix):
				return remapped[prefix] + value.trim_prefix(prefix)
	return value

static func _portable(value: Variant) -> Variant:
	if value is Dictionary:
		var clean: Dictionary = {}
		for key in value:
			if str(key).to_lower() in PRIVATE_KEYS:
				continue
			if str(key) == "source_archive_file" and (not value[key] is String or not str(value[key]).begins_with("launch_registry/") or not _safe_launch_relative(str(value[key]).trim_prefix("launch_registry/"))):
				clean[key] = ""
				continue
			clean[key] = _portable(value[key])
		return clean
	if value is Array:
		var clean: Array = []
		for item in value:
			clean.append(_portable(item))
		return clean
	if value is String:
		if value.begins_with("/") or value.begins_with("\\") or value.contains("user://") or value.contains("file://") or value.contains("res://") or (value.length() > 2 and value.substr(1, 2) in [":/", ":\\"]):
			return ""
	return value

static func _snapshot_shape_valid(snapshot: Dictionary) -> bool:
	for key in ["phase_b", "phase_c", "adventures", "collections"]:
		if snapshot.has(key) and not snapshot[key] is Dictionary:
			return false
	var artifacts: Variant = snapshot.get("phase_b", {}).get("artifacts", {})
	if not artifacts is Dictionary:
		return false
	for artifact in artifacts.values():
		if not artifact is Dictionary:
			return false
	return true

static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size

static func _write_json(path: String, data: Dictionary) -> bool:
	var serialized := JSON.stringify(data, "  ")
	if serialized.to_utf8_buffer().size() > MAX_METADATA_BYTES:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(serialized)
	file.flush()
	var err := file.get_error()
	file.close()
	return err == OK and FileAccess.get_file_as_string(path) == serialized

static func _read_json(path: String) -> Dictionary:
	var size := _file_size(path)
	if size < 0 or size > MAX_METADATA_BYTES:
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {}
	return parser.data

static func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for name in directory.get_files():
		directory.remove(name)
	for name in directory.get_directories():
		_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
