extends SceneTree

const Save = preload("res://scripts/services/save_service.gd")
const Dev = preload("res://scripts/presentation/developer_session.gd")
var failures := 0
var checks := 0
var app: Node

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("[PASS] " if ok else "[FAIL] ", label)

func _init() -> void: call_deferred("run")

func settle() -> void:
	for _i in range(5): await process_frame

func run() -> void:
	if not Dev.enabled() or not Dev.isolated():
		printerr("Developer session test requires tools/isolated_session.py developer=True")
		quit(2)
		return
	Save.use_test_storage("user://developer_check_")
	root.size = Vector2i(1280, 720)
	app = load("res://scenes/app/app_root.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await settle()
	check(not app.game_state.puzzle_solved, "fresh developer session starts with original prologue")
	check(app.game_state.station_name == "Тестовая станция", "session has its own station name")
	var dev: Node
	for child in app.get_children():
		if child.get_script() == Dev: dev = child
	check(dev != null and dev.menu.visible, "developer start menu is visible")
	dev.menu.hide()
	app.apply_author_customization("Только в этом тесте", "feather", "owl")
	check(Save.load_game().station_name == "Только в этом тесте", "real gameplay can save within temporary session")
	check(app.header_station_lbl.text.contains("Только в этом тесте") and app.station_room.sign_label.text.contains("Только в этом тесте"), "saved name reaches actual header and 3D sign")
	dev.selected_mode = "adventures"
	dev._restart()
	await settle()
	app = current_scene
	check(app.game_state.puzzle_solved and app.game_state.s00_progress.station_awakened, "developer can skip prologue to three missions")
	check(app.game_state.phase_b.published_versions.size() == 3, "all three production stories published in sandbox")
	check(app.game_state.phase_b.award_events.is_empty(), "skip does not fabricate mission rewards")
	app.adventure_controller.open_quest("FG01")
	await settle()
	check(app.adventure_controller.route == "episode", "real episode can be played in developer session")
	var route: Dictionary = app.adventure_controller.route_context
	var result: Dictionary = app.adventure_controller._run_command("stage_draft", {"instance_id":route.instance_id,"stage_id":route.stage_id,"draft":{"note":"temporary developer note"}})
	check(result.get("ok", false), "real controller persists temporary stage draft")
	for child in app.get_children():
		if child.get_script() == Dev: dev = child
	dev.menu.hide()
	app.adventure_controller._close_screen()
	dev.selected_mode = "prologue"
	dev._restart()
	await settle()
	app = current_scene
	check(not app.game_state.puzzle_solved and app.game_state.phase_b.quest_instances.is_empty(), "restart clears temporary missions and returns to prologue")
	check(Save.load_game().station_name == "Тестовая станция", "restart does not reuse previous session name")
	for child in app.get_children():
		if child.get_script() == Dev: dev = child
	dev.menu.hide()
	if OS.get_cmdline_user_args().has("--render"):
		await settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/sur-developer-session.png")
	app.queue_free()
	await settle()
	Save.cleanup_test_storage()
	print("DEVELOPER SESSION: %d passed, %d failed" % [checks-failures, failures])
	quit(0 if failures == 0 else 1)
