class_name ArtifactService
extends RefCounted

## Управляемый локальный архив работ. В состояние сохраняется только имя файла
## внутри user://artifacts, исходный системный путь никогда не сохраняется.

const DEFAULT_ARTIFACT_DIR := "user://artifacts"
static var ARTIFACT_DIR: String = DEFAULT_ARTIFACT_DIR
const MAX_IMAGE_BYTES := 20 * 1024 * 1024
const MAX_PROJECT_BYTES := 200 * 1024 * 1024
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const ARCHIVE_EXTENSIONS := ["zip", "pck", "tar", "gz", "tgz", "7z"]
const MAX_IMAGE_SIDE := 8192
const ProgressServiceScript = preload("res://scripts/services/progress_service.gd")

static func ensure_phase_b(state: Dictionary) -> Dictionary:
	var phase_b: Dictionary = state.get("phase_b", {})
	if not phase_b.has("artifacts"):
		phase_b["artifacts"] = {}
	state["phase_b"] = phase_b
	return phase_b

static func import_local_image(
	state: Dictionary,
	source_path: String,
	title: String,
	profile_id: String = "player_01"
) -> Dictionary:
	if source_path.strip_edges().is_empty() or not FileAccess.file_exists(source_path):
		return {"ok": false, "reason": "source_missing"}

	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return {"ok": false, "reason": "source_unreadable"}
	var byte_size := source.get_length()
	source.close()
	if byte_size > MAX_IMAGE_BYTES:
		return {"ok": false, "reason": "image_file_too_large", "limit_bytes": MAX_IMAGE_BYTES}
	if not IMAGE_EXTENSIONS.has(source_path.get_extension().to_lower()):
		return {"ok": false, "reason": "unsupported_image_type"}
	var image := Image.new()
	var load_error := image.load(source_path)
	if load_error != OK or image.is_empty():
		return {"ok": false, "reason": "invalid_image"}
	if image.get_width() > MAX_IMAGE_SIDE or image.get_height() > MAX_IMAGE_SIDE:
		return {"ok": false, "reason": "image_too_large"}

	var absolute_dir := ProjectSettings.globalize_path(ARTIFACT_DIR)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "reason": "artifact_directory_failed"}

	var artifact_id := "artifact_%s_%s" % [str(Time.get_ticks_usec()), str(title.hash()).replace("-", "n")]
	var file_name := artifact_id + ".png"
	var managed_path := ARTIFACT_DIR.path_join(file_name)
	var temporary_path := managed_path + ".tmp"
	var save_error := image.save_png(ProjectSettings.globalize_path(temporary_path))
	if save_error != OK:
		_remove_file(temporary_path)
		return {"ok": false, "reason": "managed_copy_failed"}
	var verification := Image.new()
	if verification.load_png_from_buffer(FileAccess.get_file_as_bytes(temporary_path)) != OK or verification.get_size() != image.get_size():
		_remove_file(temporary_path)
		return {"ok": false, "reason": "managed_copy_verification_failed"}
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(managed_path)) != OK:
		_remove_file(temporary_path)
		return {"ok": false, "reason": "managed_copy_failed"}

	var record := {
		"artifact_id": artifact_id,
		"profile_id": profile_id,
		"title": title.strip_edges().substr(0, 120),
		"kind": "local_image",
		"media_file": file_name,
		"media_deleted": false,
		"byte_size": FileAccess.get_file_as_bytes(managed_path).size(),
		"sha256": FileAccess.get_sha256(managed_path),
		"created_at": Time.get_datetime_string_from_system()
	}
	var phase_b := ensure_phase_b(state)
	var artifacts: Dictionary = phase_b.get("artifacts", {})
	artifacts[artifact_id] = record
	phase_b["artifacts"] = artifacts
	state["phase_b"] = phase_b
	return {"ok": true, "artifact": record.duplicate(true), "artifact_id": artifact_id, "managed_path": managed_path}

static func media_path_for(state: Dictionary, artifact_id: String) -> String:
	var artifacts: Dictionary = ensure_phase_b(state).get("artifacts", {})
	if not artifacts.has(artifact_id):
		return ""
	var record: Dictionary = artifacts[artifact_id]
	if bool(record.get("media_deleted", false)):
		return ""
	var file_name := str(record.get("media_file", ""))
	if not is_managed_filename(file_name):
		return ""
	var path := ARTIFACT_DIR.path_join(file_name)
	return path if FileAccess.file_exists(path) else ""

static func delete_media(state: Dictionary, artifact_id: String) -> Dictionary:
	var phase_b := ensure_phase_b(state)
	var artifacts: Dictionary = phase_b.get("artifacts", {})
	if not artifacts.has(artifact_id):
		return {"ok": false, "reason": "unknown_artifact"}
	var record: Dictionary = artifacts[artifact_id]
	var file_name := str(record.get("media_file", ""))
	if is_managed_filename(file_name):
		var dir := DirAccess.open(ARTIFACT_DIR)
		if dir != null and dir.file_exists(file_name):
			dir.remove(file_name)
	record["media_deleted"] = true
	record["media_file"] = ""
	record["media_deleted_at"] = Time.get_datetime_string_from_system()
	artifacts[artifact_id] = record
	phase_b["artifacts"] = artifacts
	state["phase_b"] = phase_b
	return {"ok": true, "artifact": record.duplicate(true)}

static func build_progress_export(state: Dictionary, profile_id: String = "player_01") -> Dictionary:
	var phase_b := ensure_phase_b(state)
	var instances_out: Array[Dictionary] = []
	for instance_value in (phase_b.get("quest_instances", {}) as Dictionary).values():
		var instance: Dictionary = instance_value
		if str(instance.get("profile_id", "")) != profile_id:
			continue
		instances_out.append({
			"instance_id": str(instance.get("instance_id", "")),
			"quest_id": str(instance.get("quest_id", "")),
			"revision": int(instance.get("revision", 0)),
			"status": str(instance.get("status", "")),
			"variant_id": str(instance.get("variant_id", ""))
		})

	var activities_out: Array[Dictionary] = []
	for activity_value in (phase_b.get("activities", {}) as Dictionary).values():
		var activity: Dictionary = activity_value
		if str(activity.get("profile_id", "")) != profile_id:
			continue
		activities_out.append({
			"activity_id": str(activity.get("activity_id", "")),
			"quest_id": str(activity.get("quest_id", "")),
			"revision": int(activity.get("revision", 0)),
			"status": str(activity.get("status", "")),
			"artifact_id": str(activity.get("artifact_id", ""))
		})

	var artifacts_out: Array[Dictionary] = []
	for artifact_value in (phase_b.get("artifacts", {}) as Dictionary).values():
		var artifact: Dictionary = artifact_value
		if str(artifact.get("profile_id", "")) != profile_id:
			continue
		artifacts_out.append({
			"artifact_id": str(artifact.get("artifact_id", "")),
			"title": str(artifact.get("title", "")),
			"kind": str(artifact.get("kind", "")),
			"media_deleted": bool(artifact.get("media_deleted", false)),
			"created_at": str(artifact.get("created_at", ""))
		})

	return {
		"schema_version": 1,
		"export_kind": "sur_progress_without_media",
		"profile_id": profile_id,
		"exported_at": Time.get_datetime_string_from_system(),
		"skill_xp": (phase_b.get("skill_xp_by_profile", {}) as Dictionary).get(profile_id, {}).duplicate(true),
		"world_effects": ProgressServiceScript.get_profile_world_effects(state, profile_id),
		"quest_instances": instances_out,
		"activities": activities_out,
		"artifacts": artifacts_out
	}

static func use_test_storage(directory: String) -> void:
	ARTIFACT_DIR = directory

static func restore_default_storage() -> void:
	ARTIFACT_DIR = DEFAULT_ARTIFACT_DIR

static func is_managed_filename(value: String) -> bool:
	return not value.is_empty() and value == value.get_file() and not value.contains("..") and not value.contains("/") and not value.contains("\\") and not value.contains(":")

static func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## Each import is a new immutable managed file. WorkVersion stores artifact_id;
## neither the source path nor launch permission enters portable work metadata.
static func import_managed_file(state: Dictionary, source_path: String, title: String, kind: String = "project_archive", profile_id: String = "player_01", previous_artifact_id: String = "") -> Dictionary:
	if not previous_artifact_id.is_empty():
		var previous: Dictionary = state.get("phase_b", {}).get("artifacts", {}).get(previous_artifact_id, {})
		if previous.is_empty() or str(previous.get("profile_id", "")) != profile_id:
			return {"ok": false, "reason": "unknown_previous_artifact"}
	if kind == "local_image":
		var imported := import_local_image(state, source_path, title, profile_id)
		if bool(imported.get("ok", false)) and not previous_artifact_id.is_empty():
			state.phase_b.artifacts[imported.artifact_id]["previous_artifact_id"] = previous_artifact_id
			imported.artifact["previous_artifact_id"] = previous_artifact_id
		return imported
	if kind not in ["project_archive", "game_build"]:
		return {"ok": false, "reason": "unsupported_media_kind"}
	if not ARCHIVE_EXTENSIONS.has(source_path.get_extension().to_lower()):
		return {"ok": false, "reason": "unsupported_archive_type"}
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return {"ok": false, "reason": "source_missing"}
	var byte_size := source.get_length()
	source.close()
	if byte_size > MAX_PROJECT_BYTES:
		return {"ok": false, "reason": "project_file_too_large", "limit_bytes": MAX_PROJECT_BYTES}
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIR)) != OK:
		return {"ok": false, "reason": "artifact_directory_failed"}
	var artifact_id := "artifact_%s_%s" % [str(Time.get_ticks_usec()), str(title.hash()).replace("-", "n")]
	var file_name := artifact_id + "." + source_path.get_extension().to_lower()
	var managed_path := ARTIFACT_DIR.path_join(file_name)
	var temporary := managed_path + ".tmp"
	var checksum := FileAccess.get_sha256(source_path)
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(source_path), ProjectSettings.globalize_path(temporary)) != OK:
		_remove_file(temporary)
		return {"ok": false, "reason": "managed_copy_failed"}
	if checksum.is_empty() or FileAccess.get_sha256(temporary) != checksum:
		_remove_file(temporary)
		return {"ok": false, "reason": "managed_copy_verification_failed"}
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(managed_path)) != OK:
		_remove_file(temporary)
		return {"ok": false, "reason": "managed_copy_failed"}
	var record := {"artifact_id": artifact_id, "profile_id": profile_id, "title": title.strip_edges().substr(0, 120),
		"kind": kind, "media_file": file_name, "media_deleted": false, "byte_size": byte_size,
		"sha256": checksum, "created_at": Time.get_datetime_string_from_system(), "previous_artifact_id": previous_artifact_id}
	ensure_phase_b(state).artifacts[artifact_id] = record
	return {"ok": true, "artifact_id": artifact_id, "artifact": record.duplicate(true), "managed_path": managed_path}
