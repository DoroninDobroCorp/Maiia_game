extends SceneTree

## Real AppRoot integration, isolated storage. Optional --render captures /tmp.
const Save = preload("res://scripts/services/save_service.gd")
const Collections = preload("res://scripts/services/collection_service.gd")
const Adventures = preload("res://scripts/services/adventure_service.gd")
const Artifacts = preload("res://scripts/services/artifact_service.gd")
var failures: Array[String] = []
var checks := 0
var app: Node
var render_metrics: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func check(value: bool, name: String) -> void:
	checks += 1
	print("APP %02d %s" % [checks, name])
	if not value:
		failures.append(name)
		push_error(name)

func settle() -> void:
	await process_frame
	await process_frame

func press_key(key: Key, unicode_value: int = 0) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.unicode = unicode_value
	event.pressed = true
	root.push_input(event)
	await settle()
	event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = false
	root.push_input(event)
	await settle()

func capture(name: String) -> void:
	await settle()
	if OS.get_cmdline_user_args().has("--render") and DisplayServer.get_name() != "headless":
		await create_timer(0.12).timeout
		DirAccess.make_dir_recursive_absolute("/tmp/sur-adventure-qa")
		root.get_texture().get_image().save_png("/tmp/sur-adventure-qa/" + name + ".png")

func measure_frames(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--render") or DisplayServer.get_name() == "headless":
		return
	for index in range(30):
		await process_frame
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for index in range(180):
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	samples.sort()
	var total := 0.0
	for sample in samples: total += sample
	render_metrics[label] = {"frames": samples.size(), "mean_ms": total / samples.size(), "p95_ms": samples[170], "max_ms": samples.back()}
	print("RENDER ", label, " ", JSON.stringify(render_metrics[label]))

func run() -> void:
	Save.use_test_storage("user://test_adventure_app_")
	Save.cleanup_test_storage()
	var start := Save.get_default_state()
	start.settings.muted = true
	check(Save.save_game(start), "isolated initial save")
	root.size = Vector2i(1280, 720)
	app = load("res://scenes/app/app_root.tscn").instantiate()
	root.add_child(app)
	await settle()
	check(not app.game_state.puzzle_solved, "prologue still first")
	check(not app.adventure_controller.navigation_bar.visible, "adventures hidden before prologue")
	await measure_frames("prologue_station")
	await press_key(KEY_J)
	check(app.modal_container.get_child_count() == 1, "J opens original journal before prologue completion")
	await press_key(KEY_ESCAPE)
	check(app.modal_container.get_child_count() == 0, "Escape closes original journal once")
	app.complete_puzzle()
	await settle()
	check(app.game_state.puzzle_solved, "original prologue completion")
	var controller: Node = app.adventure_controller
	controller.launch_service = load("res://scripts/services/launch_service.gd").new("user://test_adventure_app_launch_registry")
	check(controller.navigation_bar.visible, "adventure navigation after prologue")
	check(controller._run_command("publish_chapter", {}).get("ok", false), "parent publishes chapter atomically")
	controller.refresh_world()
	await capture("01-station")
	await measure_frames("awakened_station")
	controller.open_hub()
	await capture("02-hub")
	check(controller.screen.get_script().get_global_name() == "AdventureHub", "hub mounted through app")
	check(not app.station_room.navigation_enabled, "modal locks station")
	controller.open_quest("FG01")
	await capture("03-radio-intro")
	check(controller.route == "episode", "story navigation starts exact instance")
	var iid := str(controller.route_context.instance_id)
	var sid := str(controller.route_context.stage_id)
	check(sid == "es_intro", "radio intro selected")
	var drafted: Dictionary = controller._run_command("stage_draft", {"instance_id": iid, "stage_id": sid, "draft": {"note":"Мой позывной — Заря"}})
	check(drafted.get("ok",false), "draft committed")
	check(str(Adventures.get_progress(Save.load_game(),iid).get("stages",{}).get(sid,{}).get("draft",{}).get("note","")) == "Мой позывной — Заря", "draft survives reload")
	var old_path := Save.SAVE_PATH
	Save.SAVE_PATH = "user://absent_test_adventure_app_directory/save.json"
	var before := JSON.stringify(app.game_state)
	var failed: Dictionary = controller._run_command("stage_draft", {"instance_id":iid,"stage_id":sid,"draft":{"note":"must not replace"}})
	check(not failed.get("ok",false) and JSON.stringify(app.game_state)==before, "failed save keeps live state and prior draft")
	Save.SAVE_PATH = old_path
	check(controller._run_command("pause_adventure", {"instance_id":iid}).get("ok",false), "pause through controller")
	check(not controller._run_command("stage_submit", {"instance_id":iid,"stage_id":sid}).get("ok",false), "paused stage cannot complete")
	check(controller._run_command("resume_adventure", {"instance_id":iid}).get("ok",false), "resume through controller")
	var created: Dictionary = controller._run_command("create_work", {"title":"Мой рисунок","kind":"image","content":{"note":"Вечерние огни у воды"}})
	check(created.get("ok",false), "create personal work")
	controller.open_episode(iid,sid)
	controller.screen.work_requested.emit(str(created.work_id))
	check(controller.route == "collection" and controller.screen.work_id == str(created.work_id), "episode reward navigation opens the exact owned work through AppRoot")
	var exhibit: Dictionary = controller._run_command("create_exhibit", {"work_id":created.work_id,"recipe_id":"frame","caption":"Первая выставка"})
	check(exhibit.get("ok",false), "create exhibit command")
	var favourite: Dictionary = controller._run_command("place_exhibit", {"room_id":"station_favorites:player_01","slot_id":"favorite_01","exhibit_id":exhibit.exhibit_id,"version_id":created.version_id})
	check(favourite.get("ok",false), "station favorites exist and accept owned work")
	controller.handle_prop("station_favourite_1")
	check(controller.route == "collection" and controller.route_context.slot_id == "favorite_01", "station favorite opens exact placement")
	var first_gallery_start := Time.get_ticks_usec()
	controller.open_gallery("")
	await settle()
	render_metrics["first_gallery_transition_ms"] = float(Time.get_ticks_usec() - first_gallery_start) / 1000.0
	await capture("04-gallery")
	await measure_frames("gallery")
	check(controller.is_in_gallery() and app.station_room.get_parent()==null, "one physical room loaded")
	var rid: String = controller.gallery.room_id
	var placed: Dictionary = controller._run_command("place_exhibit", {"room_id":rid,"slot_id":"frame_01","exhibit_id":exhibit.exhibit_id,"version_id":created.version_id})
	check(placed.get("ok",false), "gallery placement")
	controller.open_collection({"room_id":rid,"slot_id":"frame_01"})
	await capture("05-collection")
	check(not controller.gallery.navigation_enabled, "collection locks gallery")
	controller._close_screen()
	await settle()
	check(controller.gallery.navigation_enabled and Collections.list_placements(controller.gallery.state,rid).size()==1, "gallery refreshed on modal close")
	controller.leave_gallery()
	await settle()
	check(app.station_room.get_parent()==app and not controller.is_in_gallery(), "gallery returns to station")
	controller.open_family_tools()
	controller.screen.tab = 3
	controller.screen._build()
	await capture("06-family-backups")
	controller.open_editor()
	await capture("07-editor")
	controller._preview_quest(load("res://scripts/services/adventure_content.gd").get_quest("FG08"))
	check(controller.preview_active and controller.route=="episode", "isolated author preview")
	var actual := JSON.stringify(app.game_state)
	controller._run_command("stage_draft", {"instance_id":controller.route_context.instance_id,"stage_id":controller.route_context.stage_id,"draft":{"note":"preview"}})
	check(JSON.stringify(app.game_state)==actual, "preview cannot mutate player state")
	controller._close_screen()
	check(not controller.preview_active, "preview closes back to editor")
	app.game_state.settings.ui_scale = 1.25
	app._apply_settings(app.game_state.settings)
	controller.open_hub()
	await capture("08-hub-125")
	controller.open_quest("FG01")
	await capture("09-episode-125")
	var warm_gallery_start := Time.get_ticks_usec()
	controller.open_gallery("")
	await settle()
	render_metrics["warm_gallery_transition_ms"] = float(Time.get_ticks_usec() - warm_gallery_start) / 1000.0
	await capture("10-gallery-125")
	controller.leave_gallery()
	# Exercise the real event pipeline: directly calling open_hub misses duplicate
	# _unhandled_key_input/_unhandled_input dispatch and focused text handling.
	app._close_modals()
	await press_key(KEY_J)
	check(app.modal_container.get_child_count() == 1 and controller.route == "hub", "J opens hub exactly once through keyboard events")
	await press_key(KEY_J)
	check(app.modal_container.get_child_count() == 0, "J closes hub without reopening it")
	await press_key(KEY_P)
	check(app.modal_container.get_child_count() == 1 and controller.route == "family", "P opens family tools exactly once")
	await press_key(KEY_ESCAPE)
	check(app.modal_container.get_child_count() == 0, "Escape closes family tools once")
	await press_key(KEY_ESCAPE)
	check(app.modal_container.get_child_count() == 1, "Escape opens settings on station")
	await press_key(KEY_ESCAPE)
	check(app.modal_container.get_child_count() == 0, "Escape closes settings without reopening")
	controller.open_episode(iid, sid)
	await settle()
	controller.screen.note.text = "keyboard draft "
	controller.screen.note.grab_focus()
	await press_key(KEY_J, 106)
	check(controller.route == "episode" and controller.screen.note.text.contains("j"), "J types inside a focused note without navigating")
	var keyboard_note: String = controller.screen.note.text
	Save.SAVE_PATH = "user://absent_test_adventure_app_directory/save.json"
	await press_key(KEY_ESCAPE)
	check(controller.route == "episode" and controller.screen.note.text == keyboard_note, "Escape retains focused draft on actual save failure")
	Save.SAVE_PATH = old_path
	await press_key(KEY_ESCAPE)
	check(controller.route == "hub" and app.modal_container.get_child_count() == 1, "Escape saves episode and returns to hub once")
	check(str(Adventures.get_progress(Save.load_game(), iid).stages[sid].draft.note) == keyboard_note, "keyboard close persisted typed draft")
	await press_key(KEY_ESCAPE)
	check(app.modal_container.get_child_count() == 0, "Escape leaves hub without opening settings")
	var backup = load("res://scripts/services/backup_service.gd")
	var scratch := "/tmp/sur-app-file-jobs-" + str(OS.get_process_id())
	Artifacts.use_test_storage(scratch.path_join("test_media"))
	DirAccess.make_dir_recursive_absolute(scratch)
	var fixture_path := scratch.path_join("drawing.png")
	var drawing := Image.create(8,8,false,Image.FORMAT_RGB8)
	drawing.fill(Color("749fbd"))
	drawing.save_png(fixture_path)
	controller.open_collection({"work_id":created.work_id})
	var attached_content := {"note":"Заметка рядом с моим рисунком"}
	var version_before := Collections.get_version(app.game_state, str(created.work_id))
	controller._attach_media({"work_id":created.work_id,"version_id":version_before.version_id,"content":attached_content,"note":"Рисунок и описание"})
	var chooser := app.find_children("*","FileDialog",true,false)[0] as FileDialog
	chooser.file_selected.emit(fixture_path)
	await settle()
	var attached_version := Collections.get_version(app.game_state,str(created.work_id))
	check(attached_version.content.note == attached_content.note and attached_version.change_note == "Рисунок и описание" and not str(attached_version.content.get("artifact_id", "")).is_empty(), "image attachment persists edited note with new media version")
	check(Collections.get_version(app.game_state,str(created.work_id),str(version_before.version_id)) == version_before, "image attachment preserves previous immutable version")
	check(controller.route == "collection" and controller.screen.work_id == created.work_id and controller.screen.version_id == attached_version.version_id, "attachment returns to the new version of the selected work")
	var next_content: Dictionary = attached_version.content.duplicate(true)
	next_content.note = "Продолжение после рисунка"
	controller._on_command("add_work_version", {"work_id":created.work_id,"content":next_content,"note":"Ещё одна версия"})
	var shown_note: bool = controller.screen.find_children("*","Label",true,false).any(func(label): return label.text == "Продолжение после рисунка")
	check(shown_note and controller.screen.version_id == Collections.get_version(app.game_state,str(created.work_id)).version_id, "saving after an attachment displays the newest version and its actual note")
	backup.LAUNCH_DIR = scratch.path_join("launch_registry")
	var before_export := JSON.stringify(app.game_state)
	controller._start_file_job("export", scratch.path_join("backup"))
	var deadline := Time.get_ticks_msec() + 5000
	while controller.file_job != null and Time.get_ticks_msec() < deadline:
		await process_frame
	check(controller.file_job == null and FileAccess.file_exists(scratch.path_join("backup/manifest.json")), "background backup completes through responsive controller")
	check(JSON.stringify(app.game_state) == before_export, "background backup cannot mutate live profile")
	app.game_state.station_name = "Изменение после резервной копии"
	Save.save_game(app.game_state)
	var before_cancelled_import: Dictionary = app.game_state.duplicate(true)
	controller._start_file_job("import", scratch.path_join("backup"))
	await press_key(KEY_ESCAPE)
	check(controller.file_job == null or bool(controller.file_job.snapshot().cancelled), "Escape cancels backup worker rather than merely hiding it")
	deadline = Time.get_ticks_msec() + 5000
	while controller.file_job != null and Time.get_ticks_msec() < deadline: await process_frame
	check(app.game_state == before_cancelled_import and str(Save.load_game().station_name) == "Изменение после резервной копии", "Escape during restore cannot later replace current progress")
	var job = load("res://scripts/services/local_file_job.gd").new()
	job.cancel()
	check(job.start_export(app.game_state, scratch.path_join("cancelled")) == OK, "cancelled worker can be joined")
	while not job.poll(): await process_frame
	check(str(job.result.get("reason", "")) == "cancelled" and not DirAccess.dir_exists_absolute(scratch.path_join("cancelled")), "cancellation leaves no committed backup")
	var damaged_backup := scratch.path_join("invalid_backup")
	DirAccess.make_dir_recursive_absolute(damaged_backup)
	var damaged_manifest := FileAccess.open(damaged_backup.path_join("manifest.json"), FileAccess.WRITE)
	damaged_manifest.store_string(JSON.stringify({"format":"sur_family_backup","version":1,"media":"damaged","launch_media":[]}))
	damaged_manifest.close()
	controller.open_family_tools()
	var family_before: Node = controller.screen
	controller._preview_backup(damaged_backup)
	check(controller.screen == family_before and controller.screen.feedback.visible and not controller.screen.feedback.text.is_empty() and controller.file_job == null, "damaged backup manifest produces a readable error without starting restore")
	backup._remove_tree(scratch)
	Artifacts.restore_default_storage()
	backup.LAUNCH_DIR = "user://launch_registry"
	# Delete/restore through the same controller that refreshes the live world.
	controller.open_gallery(rid)
	controller.open_collection({"room_id":rid,"tab":1})
	var before_delete: Dictionary = app.game_state.duplicate(true)
	Save.SAVE_PATH = "user://absent_test_adventure_app_directory/save.json"
	controller._on_command("delete_room", {"room_id":rid,"save_snapshot":true})
	check(app.game_state == before_delete and is_instance_valid(controller.screen), "failed room deletion preserves live room, placements and screen")
	Save.SAVE_PATH = old_path
	controller._on_command("delete_room", {"room_id":rid,"save_snapshot":true})
	check(not app.game_state.collections.rooms.has(rid) and not Save.load_game().collections.rooms.has(rid), "controller refresh and disk both preserve gallery deletion")
	var restore_button: Button
	for button in controller.screen.find_children("*","Button",true,false):
		if button.text == "Вернуть сохранённый зал": restore_button = button
	check(restore_button != null, "deleted last gallery can be restored from station favorites screen")
	controller._close_screen()
	check(not controller.is_in_gallery() and app.station_room.get_parent() == app, "closing last deleted gallery returns to real station")
	controller.open_gallery("")
	check(controller.route == "collection" and controller.screen.tab == 1 and not controller.is_in_gallery(), "gallery door opens restoration controls when all halls were deleted")
	for button in controller.screen.find_children("*","Button",true,false):
		if button.text == "Вернуть сохранённый зал": button.pressed.emit(); break
	check(app.game_state.collections.rooms.has(rid) and controller.screen.room_id == rid, "restore button recreates and selects original gallery")
	check(Collections.list_placements(app.game_state,rid).size() == 1 and Collections.list_works(app.game_state).size() == 1, "restored room preserves pinned placement without duplicating personal work")
	for i in range(7): controller._run_command("create_work", {"title":"Дополнительная работа %d" % i})
	controller.open_collection({"work_id":created.work_id})
	for button in controller.screen.find_children("*","Button",true,false):
		if button.text == "Выставить…": button.pressed.emit(); break
	controller._on_command("create_room", {"name":"Отдельная выставка"})
	var additional_id := str(controller.screen.room_id)
	check(controller.screen.work_id.is_empty() and controller.screen.tab == 1 and additional_id != rid and str(app.game_state.collections.rooms[additional_id].title) == "Отдельная выставка", "creating additional room opens the newly created hall after entering from a work")
	controller._on_command("delete_room", {"room_id":additional_id})
	controller._on_command("create_room", {"name":"Следующая выставка"})
	var latest_id := str(controller.screen.room_id)
	var additional_snapshot := ""
	for snapshot in Collections.list_snapshots(app.game_state):
		if str(snapshot.room_id) == additional_id: additional_snapshot = str(snapshot.snapshot_id)
	controller._on_command("restore_snapshot", {"snapshot_id":additional_snapshot})
	check(latest_id != additional_id and app.game_state.collections.rooms.has(additional_id) and str(app.game_state.collections.rooms[latest_id].title) == "Следующая выставка", "restoring old hall cannot replace newer hall through UI dispatch")
	app.game_state = {"schema_version":"9.0.0","station_name":"Future profile","read_only":true}
	controller._read_only = true
	var future_before := JSON.stringify(app.game_state)
	app._apply_state_to_world()
	app.apply_author_customization("Changed","star","compass")
	app.complete_puzzle()
	controller.open_family_tools()
	check(JSON.stringify(app.game_state) == future_before, "unsupported profile stays unchanged in app and legacy UI")
	app.open_world_explorer()
	check(JSON.stringify(app.game_state) == future_before, "atlas renders unsupported profile without adding legacy defaults")
	var readonly_map: Node = app.modal_container.get_child(0)
	app.open_quest_detail({"quest_id":"S01", "title":"Legacy quest", "revision":1})
	check(app.modal_container.get_child(0) == readonly_map and JSON.stringify(app.game_state) == future_before, "readonly atlas cannot open legacy quest mutation controls")
	app.queue_free()
	await settle()
	Save.cleanup_test_storage()
	Save.restore_default_storage()
	if OS.get_cmdline_user_args().has("--render"):
		var report := FileAccess.open("/tmp/sur-adventure-qa/render_metrics.json", FileAccess.WRITE)
		if report: report.store_string(JSON.stringify(render_metrics, "\t"))
		print("RENDER METRICS ", JSON.stringify(render_metrics))
	print("Adventure App integration: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
