extends SceneTree

const Save = preload("res://scripts/services/save_service.gd")
const Validation = preload("res://scripts/domain/content_validation.gd")
const Library = preload("res://scripts/services/content_library_service.gd")
const Repository = preload("res://scripts/services/content_repository.gd")
const Content = preload("res://scripts/services/adventure_content.gd")
const Artifact = preload("res://scripts/services/artifact_service.gd")
const Backup = preload("res://scripts/services/backup_service.gd")
var passed := 0
var failed := 0
var test_root := OS.get_environment("TMPDIR").path_join("sur_infrastructure_" + str(Time.get_ticks_usec()))

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_root))
	Save.use_test_storage(test_root.path_join("profile_"))
	Artifact.use_test_storage(test_root.path_join("artifacts"))
	Backup.LAUNCH_DIR = test_root.path_join("launch_registry")
	_test_saves()
	_test_content()
	_test_media_backup()
	Save.cleanup_test_storage()
	Artifact.restore_default_storage()
	Backup._remove_tree(test_root)
	print("ADVENTURE INFRASTRUCTURE: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(condition: bool, label: String, details: Variant = "") -> void:
	if condition:
		passed += 1
		print("[PASS] ", label)
	else:
		failed += 1
		print("[FAIL] ", label, ": ", details)

func _write(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(contents)
		file.close()

func _test_saves() -> void:
	var defaults := Save.get_default_state()
	_check(defaults.schema_version == "1.3.0" and defaults.adventures is Dictionary and defaults.collections is Dictionary, "I01 schema1.3 defaults")
	for schema in ["1.0.0", "1.1.0", "1.2.0", "1.3.0"]:
		Save.use_test_storage(test_root.path_join(schema + "_"))
		var legacy := Save.get_default_state()
		legacy.schema_version = schema
		legacy.station_name = "Original station " + schema
		legacy.erase("adventures")
		legacy.erase("collections")
		legacy.phase_b.skill_xp_by_profile = {"player_01": {"spanish": 17}}
		var original := JSON.stringify(legacy, "\t")
		_write(Save.SAVE_PATH, original)
		var migrated := Save.load_game()
		_check(migrated.schema_version == "1.3.0" and migrated.station_name == legacy.station_name and int(migrated.phase_b.skill_xp_by_profile.player_01.spanish) == 17 and migrated.has("adventures"), "I02 migration " + schema)
		if schema != "1.3.0":
			_check(FileAccess.get_file_as_string(Save.premigration_snapshot_path()) == original, "I03 exact premigration bytes " + schema)
			migrated.station_name = "Updated"
			Save.save_game(migrated)
			Save.save_game(migrated)
			_check(FileAccess.get_file_as_string(Save.premigration_snapshot_path()) == original, "I04 immutable original " + schema)
		Save.cleanup_test_storage()
	Save.use_test_storage(test_root.path_join("future_"))
	var future := {"schema_version": "9.0.0", "station_name": "Future family", "unknown_payload": {"keep": true}}
	var original := JSON.stringify(future)
	_write(Save.SAVE_PATH, original)
	_write(Save.BACKUP_PATH, JSON.stringify(defaults))
	var loaded := Save.load_game()
	_check(loaded.get("read_only", false) and loaded.get("unknown_payload") == future.unknown_payload and loaded.schema_version == "9.0.0", "I05 future schema preserved, no fallback")
	_check(not Save.save_game(loaded) and not Save.save_game(defaults) and Save.get_last_error().reason == "unsupported_schema" and FileAccess.get_file_as_string(Save.SAVE_PATH) == original, "I06 future disk and memory write protection")
	_check(Save.list_recovery_snapshots().size() == 1 and Save.list_recovery_snapshots()[0].supported, "I06a recovery snapshots listed without loading over future save")
	var restored := Save.restore_from_backup(Save.BACKUP_PATH)
	_check(restored.ok and FileAccess.get_file_as_string(restored.preserved_file) == original and not Save.is_write_blocked() and Save.load_game().schema_version == "1.3.0", "I06b explicit restore preserves unsupported original and unlocks valid snapshot")
	Save.cleanup_test_storage()
	Save.use_test_storage(test_root.path_join("failure_"))
	var state := Save.get_default_state()
	state.station_name = "Committed"
	_check(Save.save_game(state), "I07 initial atomic write")
	original = FileAccess.get_file_as_string(Save.SAVE_PATH)
	var candidate := state.duplicate(true)
	candidate.station_name = "Should not commit"
	var before := JSON.stringify(candidate)
	var old_tmp := Save.TMP_PATH
	Save.TMP_PATH = test_root.path_join("missing/subfolder/save.tmp")
	_check(not Save.save_game(candidate) and JSON.stringify(candidate) == before and FileAccess.get_file_as_string(Save.SAVE_PATH) == original, "I08 write failure preserves caller and old disk")
	Save.TMP_PATH = old_tmp
	var old_backup := Save.BACKUP_PATHS[0]
	Save.BACKUP_PATHS[0] = test_root.path_join("missing/subfolder/backup.json")
	_check(not Save.save_game(candidate) and JSON.stringify(candidate) == before and FileAccess.get_file_as_string(Save.SAVE_PATH) == original, "I09 backup failure preserves caller and old disk")
	Save.BACKUP_PATHS[0] = old_backup
	_check(Save.save_game(candidate) and Save.load_game().station_name == "Should not commit", "I10 retry commits after IO recovery")
	Save.cleanup_test_storage()
	Save.use_test_storage(test_root.path_join("no_real_profile_"))
	_check(Save.load_game().station_name == Save.get_default_state().station_name, "I11 isolated storage does not read real legacy backup")

func _quest(id: String = "INFRA01") -> Dictionary:
	var quest := Repository.get_template("ES01")
	quest.quest_id = id
	quest.schema_version = 2
	quest.revision = 1
	quest.reward_policy = {"activity_budget": 20, "skill_weights_percent": {"drawing": 100}, "world_effect_ids": []}
	quest.required_capabilities = ["adventure_v1"]
	quest.adventure = {
		"stages": [
			{"stage_id": "start", "title": "Start", "completion_policy": "automatic", "budget_share": 2, "prerequisite_stage_ids": [], "interaction_ids": ["look"], "grant_ids": [], "work_recipe_id": "radio_contact_card"},
			{"stage_id": "finish", "title": "Finish", "completion_policy": "joint_review", "budget_share": 18, "prerequisite_stage_ids": ["start"], "interaction_ids": [], "grant_ids": []}
		],
		"interactions": {"look": {"interaction_id": "look", "type": "inspect_reveal", "config": {"details": [{"id": "clue", "text": "clue"}], "required_detail_ids": ["clue"]}}},
		"work_recipes": {"radio_contact_card": {"recipe_id": "radio_contact_card", "kind": "note"}},
		"grant_definitions": {}, "lexicon": [], "dialogues": {}, "final_stage_id": "finish"
	}
	return quest

func _package(quests: Array, schema: int = 2) -> Dictionary:
	return {"schema_version": schema, "package_type": "sur_quest_pack", "package_id": "infrastructure", "quests": quests}

func _test_content() -> void:
	var quest := _quest()
	var checked := Validation.validate_quest(quest)
	_check(checked.valid, "I12 valid schema2 fixture", checked.errors)
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(quest))
	_check(Validation.content_hash(quest) == Validation.content_hash(roundtrip), "I12a frozen hash survives JSON numeric roundtrip")
	for builtin in Content.quests():
		checked = Validation.validate_quest(builtin)
		_check(checked.valid, "I13 builtin validation " + str(builtin.quest_id), checked.errors)
	var example_check := Validation.validate_package(Content.example_package())
	_check(example_check.valid, "I13a schema2 extension example validation", example_check.errors)
	_check(Repository.phase_c_templates().size() == 24, "I14 old24 bank unchanged")
	var bad := quest.duplicate(true)
	bad.adventure.stages[0].prerequisite_stage_ids = ["finish"]
	_check(not Validation.validate_quest(bad).valid, "I15 cyclic graph rejected")
	bad = quest.duplicate(true)
	bad.adventure.stages[1].prerequisite_stage_ids = ["missing"]
	_check(not Validation.validate_quest(bad).valid, "I16 missing stage rejected")
	bad = quest.duplicate(true)
	bad.adventure.stages[1].budget_share = 17
	_check(not Validation.validate_quest(bad).valid, "I17 budget mismatch rejected")
	for field in ["grant_ids", "interaction_ids", "atlas_unlock_ids"]:
		bad = quest.duplicate(true)
		bad.adventure.stages[0][field] = ["unknown"]
		_check(not Validation.validate_quest(bad).valid, "I18 unknown reference " + field)
	bad = quest.duplicate(true)
	bad.required_capabilities = ["run_any_script"]
	_check(not Validation.validate_quest(bad).valid, "I19 unknown required capability")
	var incompatible := _package([quest])
	incompatible["manifest"] = {"required_capabilities": ["unknown_runtime"]}
	_check(not Validation.validate_package(incompatible).valid, "I19a manifest compatibility enforced")
	for value in [null, "bad", [], 1, false]:
		bad = quest.duplicate(true)
		bad.adventure.stages[0] = value
		_check(not Validation.validate_quest(bad).valid, "I20 malformed nested stage " + str(value))
	bad = quest.duplicate(true)
	bad.reward_policy.skill_weights_percent = {"drawing": {"nested": 100}}
	_check(not Validation.validate_quest(bad).valid, "I21 nested reward type rejected")
	bad = quest.duplicate(true)
	bad.adventure.interactions.look.config = ["wrong"]
	_check(not Validation.validate_quest(bad).valid, "I22 malformed interaction config")
	bad = quest.duplicate(true)
	for index in range(65):
		bad.adventure.stages.append({"stage_id": "extra" + str(index)})
	_check(not Validation.validate_quest(bad).valid, "I23 stage cap64")
	bad = quest.duplicate(true)
	for index in range(257):
		bad.adventure.dialogues[str(index)] = {"node_id": str(index), "text": "text"}
	_check(not Validation.validate_quest(bad).valid, "I24 dialogue cap256")
	bad = quest.duplicate(true)
	for index in range(1001):
		bad.adventure.lexicon.append({"lexeme_id": "word" + str(index)})
	_check(not Validation.validate_package(_package([bad])).valid, "I25 lexicon cap1000")
	var too_many: Array = []
	for index in range(51):
		too_many.append(_quest("COUNT" + str(index)))
	_check(not Validation.validate_package(_package(too_many)).valid, "I26 package cap50")
	var state := Save.get_default_state()
	var before := JSON.stringify(state)
	bad = _quest("BAD")
	bad.adventure.interactions.look.config["script"] = "evil"
	var imported := Library.import_package(state, _package([quest, bad]))
	_check(not imported.ok and JSON.stringify(state) == before, "I27 all-or-nothing package import")
	imported = Library.import_package(state, _package([quest]))
	_check(imported.ok and state.phase_c.custom_quests["INFRA01@1"].content_status == "DRAFT" and state.phase_b.approval_records.is_empty(), "I28 schema2 imports only DRAFT", imported)
	var old := Repository.get_template("ES01")
	old.quest_id = "INFRA_OLD"
	_check(Library.import_package(state, _package([old], 1)).ok, "I29 schema1 import remains supported")
	var legacy_numeric := Repository.get_template("FG01")
	legacy_numeric["goal_steps"] = [25, 50, 75, 100]
	_check(Validation.validate_quest(legacy_numeric).valid, "I29a original schema1 numeric goal_steps remains supported")
	var strict_steps := quest.duplicate(true)
	strict_steps["goal_steps"] = [25, 50, 75, 100]
	_check(not Validation.validate_quest(strict_steps).valid, "I29b schema2 goal_steps keeps strict array form")
	for revision in [1, 2]:
		var builtin := Library.get_builtin_template("FG01", revision)
		_check(not builtin.is_empty() and not Library.save_draft(state, builtin).ok, "I30 every builtin revision frozen " + str(revision))
	state.phase_c.custom_quests["INFRA01@1"].approved_by = "should be excluded"
	state.phase_c.custom_quests["INFRA01@1"].approved = true
	var exported := Library.build_export_package(state)
	_check(not JSON.stringify(exported).contains("approved") and exported.schema_version == 2, "I31 exports carry no approval")
	var fresh := Save.get_default_state()
	_check(Library.import_package(fresh, exported).ok, "I32 export round trip", Validation.validate_package(exported))
	bad = quest.duplicate(true)
	bad.adventure.interactions.look.config["note"] = "/Users/person/private.txt"
	_check(not Validation.validate_quest(bad).valid, "I33 absolute path blocked")

func _test_media_backup() -> void:
	var state := Save.get_default_state()
	var source := test_root.path_join("picture.png")
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	image.save_png(ProjectSettings.globalize_path(source))
	var first := Artifact.import_local_image(state, source, "Original")
	_check(first.ok, "I34 managed image import", first)
	var sparse := FileAccess.open(test_root.path_join("oversize.png"), FileAccess.WRITE)
	sparse.seek(Artifact.MAX_IMAGE_BYTES)
	sparse.store_8(0)
	sparse.close()
	var oversized := Artifact.import_local_image(state, test_root.path_join("oversize.png"), "oversize")
	_check(not oversized.ok and oversized.reason == "image_file_too_large", "I35 size checked before decoding")
	image.fill(Color.TOMATO)
	image.save_png(ProjectSettings.globalize_path(source))
	var second := Artifact.import_managed_file(state, source, "Second version", "local_image", "player_01", str(first.get("artifact_id", "")))
	_check(second.ok and first.artifact_id != second.artifact_id and FileAccess.get_sha256(first.managed_path) == first.artifact.sha256, "I36 media versions preserve previous bytes")
	var project_file := test_root.path_join("sources.zip")
	_write(project_file, "Opaque source archive; deliberately not decoded")
	var archive := Artifact.import_managed_file(state, project_file, "My source")
	_check(archive.ok and FileAccess.get_file_as_string(archive.managed_path) == FileAccess.get_file_as_string(project_file), "I37 source archive opaque managed copy")
	DirAccess.make_dir_recursive_absolute(Backup.LAUNCH_DIR.path_join("versions/launch_fixture/project"))
	DirAccess.make_dir_recursive_absolute(Backup.LAUNCH_DIR.path_join("working/station_light"))
	_write(Backup.LAUNCH_DIR.path_join("versions/launch_fixture/project/main.gd"), "Archived Godot project")
	_write(Backup.LAUNCH_DIR.path_join("versions/launch_fixture/source.zip"), "Opaque launch source archive")
	_write(Backup.LAUNCH_DIR.path_join("working/station_light/main.gd"), "Editable project")
	_write(Backup.LAUNCH_DIR.path_join("registry.json"), "{\"engine_path\":\"/private/local/engine\"}")
	_write(Backup.LAUNCH_DIR.path_join("registry.json.tmp"), "local temporary registration")
	_write(Backup.LAUNCH_DIR.path_join("working/station_light/temp.tmp"), "unfinished temporary file")
	state["launch_registry"] = {"entry": {"path": "/Users/private/app"}}
	state["old_external_path"] = "/Users/private/old.png"
	state.collections["works"] = {"w": {"work_id": "w", "profile_id": "player_01", "versions": [{"version_id": "v1", "content": {"artifact_id": first.artifact_id}}, {"version_id": "v2", "content": {"artifact_id": second.artifact_id, "launch_entry_id": "launch_fixture", "source_archive_file": "launch_registry/versions/launch_fixture/source.zip"}}]}}
	var backup_path := test_root.path_join("family-backup")
	var exported := Backup.export_family_backup(state, backup_path)
	_check(exported.ok and exported.media_count == 3, "I38 full family backup includes all media versions", exported)
	var portable := FileAccess.get_file_as_string(backup_path.path_join("snapshot.json"))
	_check(not portable.contains("/Users/") and not portable.contains("\"launch_registry\":") and portable.contains(first.artifact_id), "I39 portable snapshot excludes paths and launch registry")
	var manifest_text := FileAccess.get_file_as_string(backup_path.path_join("manifest.json"))
	_check(exported.get("launch_file_count", 0) == 3 and not manifest_text.contains("registry.json") and not manifest_text.contains(".tmp"), "I39a backup contains build/source/working data, excludes launch trust and temp files")
	var old_media_dir := Artifact.ARTIFACT_DIR
	Artifact.use_test_storage(test_root.path_join("restored_artifacts"))
	var restored := Backup.import_family_backup(backup_path)
	_check(restored.ok and restored.state.collections.works.w.versions.size() == 2 and not Artifact.media_path_for(restored.state, first.artifact_id).is_empty(), "I40 full backup restores metadata and media", restored.get("reason", ""))
	var restored_content: Dictionary = restored.state.collections.works.w.versions[1].content
	_check(restored_content.launch_entry_id == "" and restored_content.source_archive_file.contains("restored_") and FileAccess.file_exists(Backup.LAUNCH_DIR.path_join(str(restored_content.source_archive_file).trim_prefix("launch_registry/"))) and FileAccess.get_file_as_string(Backup.LAUNCH_DIR.path_join("registry.json")).contains("/private/local/engine"), "I40a launch backup remaps collisions and requires fresh approval without changing local registry")
	Artifact.use_test_storage(old_media_dir)
	_test_backup_cancellation(state, backup_path)
	var media_name: String = first.artifact.media_file
	_write(backup_path.path_join("media").path_join(media_name), "corrupt")
	var corrupted := Backup.import_family_backup(backup_path)
	_check(not corrupted.ok and FileAccess.get_sha256(first.managed_path) == first.artifact.sha256, "I41 corruption rejected before managed files change")
	_check(not Backup.export_family_backup(state, backup_path).ok, "I42 existing family backup is never overwritten")

func _tree_checksums(path: String) -> Dictionary:
	var result: Dictionary = {}
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	for name in directory.get_files():
		result[name] = FileAccess.get_sha256(path.path_join(name))
	for name in directory.get_directories():
		result[name + "/"] = _tree_checksums(path.path_join(name))
	return result

func _test_backup_cancellation(state: Dictionary, backup_path: String) -> void:
	var state_before := JSON.stringify(state)
	var save_before := FileAccess.get_file_as_string(Save.SAVE_PATH) if FileAccess.file_exists(Save.SAVE_PATH) else ""
	var launch_before := _tree_checksums(Backup.LAUNCH_DIR)
	var backup_before := _tree_checksums(backup_path)
	var media_before := _tree_checksums(Artifact.ARTIFACT_DIR)
	for stop in [["export_prepare", 0], ["export_media", 1], ["export_scan", 0], ["export_launch", 1], ["export_metadata", 1], ["export_commit", 0]]:
		var destination := test_root.path_join("cancel-" + str(stop[0]))
		var cancelled := Backup.export_family_backup(state, destination, func(phase: String, done: int, _total: int) -> bool:
			return phase != stop[0] or done < int(stop[1]))
		var clean := not DirAccess.dir_exists_absolute(destination)
		for name in DirAccess.open(test_root).get_directories():
			if name.begins_with(destination.get_file() + ".pending-"):
				clean = false
		_check(cancelled.get("reason") == "cancelled" and clean and _tree_checksums(Artifact.ARTIFACT_DIR) == media_before and _tree_checksums(Backup.LAUNCH_DIR) == launch_before, "I43 cancellation removes only export staging: " + str(stop[0]), cancelled)
	var old_media_dir := Artifact.ARTIFACT_DIR
	Artifact.use_test_storage(test_root.path_join("cancelled-import-artifacts"))
	DirAccess.make_dir_recursive_absolute(Artifact.ARTIFACT_DIR)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(backup_path.path_join("manifest.json")))
	_write(Artifact.ARTIFACT_DIR.path_join(str(manifest.media[0].file)), "Existing different media must survive cancellation")
	_write(Artifact.ARTIFACT_DIR.path_join("keep.txt"), "Existing independent file")
	var destination_before := _tree_checksums(Artifact.ARTIFACT_DIR)
	for stop in [["import_validate", 0], ["import_media_validate", 1], ["import_launch_validate", 1], ["import_restore_launch", 1], ["import_restore_media", 1], ["import_ready", 1]]:
		var cancelled := Backup.import_family_backup(backup_path, func(phase: String, done: int, _total: int) -> bool:
			return phase != stop[0] or done < int(stop[1]))
		_check(cancelled.get("reason") == "cancelled" and _tree_checksums(Artifact.ARTIFACT_DIR) == destination_before and _tree_checksums(Backup.LAUNCH_DIR) == launch_before and _tree_checksums(backup_path) == backup_before, "I44 cancellation rolls back new copies and keeps collisions: " + str(stop[0]), cancelled)
	Artifact.use_test_storage(old_media_dir)
	var save_after := FileAccess.get_file_as_string(Save.SAVE_PATH) if FileAccess.file_exists(Save.SAVE_PATH) else ""
	_check(JSON.stringify(state) == state_before and save_after == save_before, "I45 cancellation never mutates caller state or current profile")
	var worker := Thread.new()
	var worker_progress: Array[String] = []
	var destination := test_root.path_join("worker-backup")
	var thread_error := worker.start(func() -> Dictionary:
		return Backup.export_family_backup(state.duplicate(true), destination, func(phase: String, done: int, total: int) -> bool:
			worker_progress.append(phase)
			return done >= 0 and total >= 0))
	var result: Dictionary = worker.wait_to_finish() if thread_error == OK else {}
	_check(result.get("ok", false) and worker_progress.has("export_commit") and _tree_checksums(Backup.LAUNCH_DIR) == launch_before, "I46 backup callback works on a worker without scene access", result)
