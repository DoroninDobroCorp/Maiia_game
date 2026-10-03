extends SceneTree

const Save = preload("res://scripts/services/save_service.gd")
var failed := 0
var passed := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	# This test deliberately puts a sentinel at default paths. Never run it in
	# the real project/user directory, even when a caller forgets the runner.
	var expected := str(ProjectSettings.get_setting("sur/isolated_user_dir", ""))
	if expected.is_empty() or expected != OS.get_user_data_dir() or not FileAccess.file_exists("user://.sur-temporary-session.json"):
		printerr("Use python3 tools/run_checks.py test_save_isolation")
		quit(2)
		return
	var originals: Dictionary = {}
	var sentinel := Save.get_default_state()
	sentinel.station_name = "Family sentinel — must survive"
	sentinel.station_emblem = "feather"
	sentinel.desk_prop_id = "owl"
	var paths: Array = [Save.DEFAULT_SAVE_PATH, Save.LEGACY_BACKUP_PATH] + Save.DEFAULT_BACKUP_PATHS
	for path in paths:
		originals[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(sentinel))
		file.close()
	var hashes: Dictionary = {}
	for path in paths:
		hashes[path] = FileAccess.get_sha256(path)
	Save.use_test_storage("user://isolation_fixture_")
	var selected := Save.SAVE_PATH
	var state := Save.get_default_state()
	state.station_name = "Test only"
	check(Save.save_game(state), "test writes selected storage")
	Save.cleanup_test_storage()
	check(Save.SAVE_PATH == selected, "cleanup retains selected storage — original regression")
	check(not FileAccess.file_exists(selected), "cleanup removes only the fixture")
	check(Save.save_game(state) and Save.load_game().station_name == "Test only", "save after cleanup stays in fixture")
	Save.cleanup_test_storage()
	Save.restore_default_storage()
	check(not Save.save_game(state) and Save.get_last_error().get("reason") == "unsafe_test_storage", "explicit reset cannot re-enable family writes in test process")
	check(Save.load_game().get("read_only", false), "script cannot read family profile through default storage")
	check(Save.reset_save().get("read_only", false), "script cannot reset family profile")
	check(not Save.restore_snapshot(state).get("ok", false), "restore cannot bypass isolation")
	check(Save.list_recovery_snapshots().is_empty(), "script cannot fall through to family backups")
	Save.cleanup_test_storage()
	Save.use_test_storage("user://nested/../")
	check(not Save.save_game(state), "canonical aliases cannot bypass default path protection")
	Save.use_test_storage("user://isolation_fixture_")
	Save.TMP_PATH = Save.DEFAULT_SAVE_PATH
	check(not Save.save_game(state), "temporary path cannot target family profile")
	Save.use_test_storage("user://isolation_fixture_")
	Save.BACKUP_PATHS[0] = Save.DEFAULT_BACKUP_PATHS[0]
	check(not Save.save_game(state), "backup rotation cannot target family backups")
	Save.cleanup_test_storage()
	for path in paths:
		check(FileAccess.get_sha256(path) == hashes[path], "family sentinel byte-identical: " + path)
		if originals[path] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(originals[path])
			file.close()
	# Load a legacy family-shaped snapshot through the real app, not just a getter.
	Save.use_test_storage("user://station_reload_")
	var legacy := Save.get_default_state()
	legacy.schema_version = "1.2.0"
	legacy.station_name = "Станция Майи"
	legacy.station_emblem = "feather"
	legacy.desk_prop_id = "owl"
	legacy.puzzle_solved = true
	legacy.radio_powered = true
	legacy.s00_progress = {"sign_named":true,"prop_arranged":true,"puzzle_solved":true,"station_awakened":true}
	legacy.settings.muted = true
	var original_text := JSON.stringify(legacy)
	var original_file := FileAccess.open(Save.SAVE_PATH, FileAccess.WRITE)
	original_file.store_string(original_text)
	original_file.close()
	root.size = Vector2i(1280, 720)
	var app: Node = load("res://scenes/app/app_root.tscn").instantiate()
	root.add_child(app)
	for _i in range(3): await process_frame
	check(app.game_state.station_name == "Станция Майи" and app.game_state.desk_prop_id == "owl" and app.game_state.station_emblem == "feather", "legacy profile retains name, owl and feather")
	check(app.header_station_lbl.text.contains("Станция Майи") and app.station_room.sign_label.text.contains("Станция Майи"), "saved family name visible in HUD and station sign")
	var atlas := load("res://scripts/services/atlas_service.gd")
	check(atlas.list_locations(app.game_state)[0].title == "Станция Майи", "atlas uses the saved station name")
	check(FileAccess.get_file_as_string(Save.premigration_snapshot_path()) == original_text, "migration preserves exact original bytes")
	if OS.get_cmdline_user_args().has("--render"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/sur-restored-station-check.png")
	app.queue_free()
	for _i in range(3): await process_frame
	Save.cleanup_test_storage()
	print("SAVE ISOLATION: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
