extends SceneTree

const Save = preload("res://scripts/services/save_service.gd")
const Dev = preload("res://scripts/presentation/developer_session.gd")
const Content = preload("res://scripts/services/adventure_content.gd")
const Quest = preload("res://scripts/services/quest_service.gd")
const Adventure = preload("res://scripts/services/adventure_service.gd")
const Collections = preload("res://scripts/services/collection_service.gd")
const Artifacts = preload("res://scripts/services/artifact_service.gd")
const Launcher = preload("res://scripts/services/launch_service.gd")
var passed := 0
var failed := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[PASS] " if ok else "[FAIL] ", label)
func write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "fixture file opens: " + path)
		return
	file.store_string(value)
	file.close()
func settle() -> void:
	for _i in range(5): await process_frame
func developer(app: Node) -> Node:
	for child in app.get_children():
		if child.get_script() == Dev: return child
	return null

func run() -> void:
	if not Dev.enabled() or not Dev.isolated():
		printerr("Use python3 tools/run_checks.py test_developer_family --developer")
		quit(2)
		return
	Save.use_test_storage("user://family_copy_check_")
	var seed := Dev.FAMILY_SNAPSHOT
	DirAccess.make_dir_recursive_absolute(seed)
	var state := Save.get_default_state()
	state.station_name = "Сохранение Майи"
	state.station_emblem = "feather"
	state.desk_prop_id = "owl"
	state.puzzle_solved = true
	state.radio_powered = true
	state.s00_progress = {"sign_named":true,"prop_arranged":true,"puzzle_solved":true,"station_awakened":true}
	state.settings.muted = true
	var quest := Content.get_quest("FG01")
	Quest.approve_and_publish(state, quest)
	var accepted := Adventure.accept(state, "FG01", 2)
	var iid := str(accepted.instance.instance_id)
	Adventure.dispatch(state, "stage_draft", {"instance_id":iid,"stage_id":"es_intro","draft":{"note":"Семейный черновик"}})
	var picture := Image.create(16, 16, false, Image.FORMAT_RGB8)
	picture.fill(Color.CORNFLOWER_BLUE)
	picture.save_png("user://family_fixture.png")
	Artifacts.use_test_storage(seed.path_join("artifacts"))
	var media := Artifacts.import_local_image(state, "user://family_fixture.png", "Семейный рисунок")
	Artifacts.restore_default_storage()
	var work := Collections.create_work(state, {"title":"Работа Майи","kind":"drawing","content":{"artifact_id":media.artifact.artifact_id,"note":"Оригинал"}})
	var launcher := Launcher.new(seed.path_join("launch_registry"))
	var prepared := launcher.prepare_starter_project()
	var entry := launcher.register_starter()
	check(prepared.ok and entry.ok and media.ok and work.ok, "seed contains a real work, image, working copy and registered project")
	write(seed.path_join("savegame.json"), JSON.stringify(state))
	write("user://.developer-family-info.json", JSON.stringify({"available":true,"station_name":state.station_name}))
	var original_save := FileAccess.get_sha256(seed.path_join("savegame.json"))
	var image_name := str(media.artifact.media_file)
	var original_image := FileAccess.get_sha256(seed.path_join("artifacts").path_join(image_name))
	var source_relative := "launch_registry/working/station_light/main.gd"
	var original_project := FileAccess.get_sha256(seed.path_join(source_relative))
	check(original_project.length() == 64 and original_image.length() == 64, "original fixture files have actual SHA256 hashes")
	ProjectSettings.set_setting("sur/developer_start", "family")
	root.size = Vector2i(1280, 720)
	var app: Node = load("res://scenes/app/app_root.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	check(app.game_state.station_name == state.station_name and app.game_state.station_emblem == "feather" and app.game_state.desk_prop_id == "owl", "family customization restored in actual app")
	check(app.header_station_lbl.text.contains(state.station_name), "family station name visible")
	check(Adventure.get_progress(app.game_state, iid).stages.es_intro.draft.note == "Семейный черновик", "actual mission draft copied")
	check(not Collections.get_work(app.game_state, str(work.work_id)).is_empty(), "family archive work copied")
	check(FileAccess.get_sha256("user://artifacts".path_join(image_name)) == original_image, "work image copied into temporary user directory")
	check(app.adventure_controller._launcher().inspect_entry(str(entry.launch_entry_id)).ok, "copied registered game passes unchanged resource checksums")
	var dev := developer(app)
	var button := dev.find_child("StartFromFamilySave", true, false) as Button
	check(button != null and not button.disabled, "family save option is available in menu")
	check(dev.menu.size.y < root.size.y and dev.menu.get_ok_button().get_global_rect().end.y <= dev.menu.size.y, "developer menu and continue button fit the window")
	if OS.get_cmdline_user_args().has("--render"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/sur-family-copy-menu.png")
	dev.menu.hide()
	app.apply_author_customization("Изменено только в тесте", "star", "compass")
	app.adventure_controller.open_quest("FG01", iid)
	var result: Dictionary = app.adventure_controller._run_command("stage_draft", {"instance_id":iid,"stage_id":"es_intro","draft":{"note":"Тестовый черновик"}})
	check(result.ok and Adventure.get_progress(Save.load_game(), iid).stages.es_intro.draft.note == "Тестовый черновик", "real controller can advance the copied save")
	write("user://artifacts".path_join(image_name), "temporary edited media")
	write("user://".path_join(source_relative), "temporary edited working project")
	check(FileAccess.get_sha256("user://artifacts".path_join(image_name)) != original_image and FileAccess.get_sha256("user://".path_join(source_relative)) != original_project, "test really changes working media and project before reset")
	check(FileAccess.get_sha256(seed.path_join("savegame.json")) == original_save and FileAccess.get_sha256(seed.path_join("artifacts").path_join(image_name)) == original_image and FileAccess.get_sha256(seed.path_join(source_relative)) == original_project, "changes cannot mutate the seed save, media or project")
	button.pressed.emit()
	check(dev.confirm.visible and dev.selected_mode == "family", "real family menu button selects snapshot restart")
	dev.confirm.confirmed.emit()
	await settle()
	app = current_scene
	check(app.game_state.station_name == state.station_name and Adventure.get_progress(app.game_state, iid).stages.es_intro.draft.note == "Семейный черновик", "restart discards test changes and restores initial family progress")
	check(FileAccess.get_sha256("user://artifacts".path_join(image_name)) == original_image and FileAccess.get_sha256("user://".path_join(source_relative)) == original_project, "restart restores original copied image and editable project")
	check(app.adventure_controller._launcher().inspect_entry(str(entry.launch_entry_id)).ok, "registry remains valid after reset")
	check(FileAccess.get_sha256(seed.path_join("savegame.json")) == original_save, "initial snapshot stays byte-identical after restart")
	app.queue_free()
	await settle()
	Save.cleanup_test_storage()
	print("DEVELOPER FAMILY COPY: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
