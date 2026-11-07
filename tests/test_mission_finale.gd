extends SceneTree

## Closing scenes of the missions and of the 30-day challenge. Isolated storage only:
## run it through `python3 tools/run_checks.py test_mission_finale`, never on a family profile.
const Save = preload("res://scripts/services/save_service.gd")
const Guide = preload("res://scripts/presentation/mission_guide.gd")
const Ritual = preload("res://scripts/services/ritual_service.gd")
const Progress = preload("res://scripts/services/progress_service.gd")
const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Finale = preload("res://scripts/presentation/mission_finale.gd")

var failures: Array[String] = []
var checks := 0
var app: Node
var controller: Node

func _init() -> void:
	call_deferred("run")

func check(value: bool, name: String) -> void:
	checks += 1
	print("FINALE %02d %s" % [checks, name])
	if not value:
		failures.append(name)
		push_error(name)

func settle(frames: int = 3) -> void:
	for _i in range(frames):
		await process_frame

## With `-- --render` (native window, not headless) saves a frame to /tmp/sur-finale-qa.
func capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--render") or DisplayServer.get_name() == "headless":
		return
	await settle(6)
	DirAccess.make_dir_recursive_absolute("/tmp/sur-finale-qa")
	root.get_texture().get_image().save_png("/tmp/sur-finale-qa/" + name + ".png")

func run() -> void:
	Save.use_test_storage("user://test_mission_finale_%d_" % OS.get_process_id())
	Save.cleanup_test_storage()
	if Save.SAVE_PATH == Save.DEFAULT_SAVE_PATH:
		push_error("test storage not isolated")
		quit(1)
		return
	_test_guide()
	_test_calendar_rules()
	await _test_screen()
	await _test_app_flow()
	Save.cleanup_test_storage()
	print("MISSION FINALE: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		print("  FAILED: ", failure)
	quit(0 if failures.is_empty() else 1)

# ---------------------------------------------------------------- wording

func _test_guide() -> void:
	for key in ["FG01", "FG11", "FG08", "challenge", "chapter"]:
		var data := Guide.finale(key)
		check(not data.is_empty() and not str(data.get("title", "")).is_empty(), "%s has a closing scene with a title" % key)
		var beats: Array = data.get("beats", [])
		check(beats.size() >= 3, "%s speaks in at least three pages" % key)
		var heroes_ok := true
		for beat in beats:
			if Guide.character(str(beat.get("who", ""))).is_empty() or Guide.portrait_path(str(beat.who), "happy").is_empty() or str(beat.get("text", "")).length() < 40:
				heroes_ok = false
		check(heroes_ok, "%s: every speech has a real hero with a happy portrait" % key)
		check(data.get("changes", []).size() >= 3 and not str(data.get("last", "")).is_empty(), "%s lists what changed and ends with a closing line" % key)
	for qid in ["FG01", "FG11", "FG08"]:
		check(str(Guide.finale(qid).get("last", "")) == str(Guide.mission(qid).get("postscript", "x")), "%s closing line equals the mission postscript" % qid)
	check(Guide.finale("nope").is_empty(), "unknown finale key is empty")

# ---------------------------------------------------------------- calendar of forgotten days

func _day(offset: int) -> String:
	return Ritual.shift_date(Time.get_date_string_from_system(), offset)

func _test_calendar_rules() -> void:
	var today := Time.get_date_string_from_system()
	check(Ritual.shift_date("2026-10-31", 1) == "2026-11-01" and Ritual.shift_date("2026-03-01", -1) == "2026-02-28", "date shift crosses month borders")
	check(Ritual.shift_date("nonsense", 1) == "", "date shift rejects garbage")
	var window := Ritual.backfill_dates()
	check(window.size() == Ritual.BACKFILL_WINDOW_DAYS and window.back() == _day(-1) and not window.has(today), "calendar ends yesterday and never offers today")

	var state := Save.get_default_state()
	check(not bool(Ritual.set_past_day(state, today, true).ok), "today is ticked by the checklist, not the calendar")
	check(not bool(Ritual.set_past_day(state, _day(-Ritual.BACKFILL_WINDOW_DAYS - 1), true).ok), "days outside the window are refused")
	check(not bool(Ritual.set_past_day(state, "garbage", true).ok), "garbage dates are refused")

	# A gap splits the run: the record is the longest run, the live streak is the one ending yesterday.
	for offset in [-1, -2, -3, -4, -5, -7, -8, -9]:
		Ritual.set_past_day(state, _day(offset), true)
	var c := Ritual.get_challenge_state(state)
	check(int(c.current_streak) == 5 and int(c.max_streak) == 5, "gap keeps the streak honest: 5 live, record 5")
	Ritual.set_past_day(state, _day(-6), true)
	c = Ritual.get_challenge_state(state)
	check(int(c.current_streak) == 9 and int(c.max_streak) == 9, "filling the gap joins the runs into 9")
	check(bool(c.history[_day(-6)].get("backfilled", false)), "remembered days are marked as added afterwards")
	check(bool(Ritual.set_past_day(state, _day(-6), false).ok) and int(Ritual.get_challenge_state(state).current_streak) == 5, "a remembered day can be taken back")
	c = Ritual.get_challenge_state(state)
	c.history[_day(-2)].erase("backfilled")
	state.phase_c.rituals.maya_30_streak.history[_day(-2)].erase("backfilled")
	var locked := Ritual.set_past_day(state, _day(-2), false)
	check(not bool(locked.ok) and str(locked.get("reason", "")) == "logged_on_the_day", "a day ticked live in the game cannot be erased by accident")

	# An old run that ended long ago does not count as a live streak but still counts as an achievement.
	var old := Save.get_default_state()
	for offset in [-12, -11, -10]:
		Ritual.set_past_day(old, _day(offset), true)
	c = Ritual.get_challenge_state(old)
	check(int(c.current_streak) == 0 and int(c.max_streak) == 3, "a run that ended earlier is the record, not the live streak")

	# Thirty remembered days unlock the board exactly once.
	var full := Save.get_default_state()
	var unlocked_on := 0
	for n in range(1, 31):
		var result := Ritual.set_past_day(full, _day(-n), true)
		if bool(result.get("newly_unlocked", false)):
			unlocked_on += 1
	c = Ritual.get_challenge_state(full)
	check(unlocked_on == 1 and bool(c.unlocked) and int(c.current_streak) == 30, "30 remembered days unlock the challenge exactly once")
	check(Progress.get_profile_world_effects(full, "player_01").has("challenge_30_board"), "the board and the flame land in the world effects")
	Ritual.set_past_day(full, _day(-3), false)
	check(bool(Ritual.get_challenge_state(full).unlocked) and not bool(Ritual.set_past_day(full, _day(-3), true).get("newly_unlocked", false)), "taking a day back never revokes or repeats the award")

	# Remembered days and today's checklist continue each other.
	var live := Save.get_default_state()
	for n in range(1, 30):
		Ritual.set_past_day(live, _day(-n), true)
	check(not bool(Ritual.get_challenge_state(live).unlocked), "29 days are not enough")
	var last: Dictionary = {}
	for item in Ritual.CHALLENGE_ITEMS:
		last = Ritual.toggle_challenge_item(live, item)
	check(bool(last.get("newly_unlocked", false)) and int(last.current_streak) == 30, "today's six ticks complete day 30 after 29 remembered days")

# ---------------------------------------------------------------- the scene itself

func _make_png(name: String, color: Color) -> String:
	var path := OS.get_temp_dir().path_join("sur_finale_%d_%s.png" % [OS.get_process_id(), name])
	var image := Image.create(96, 64, false, Image.FORMAT_RGB8)
	image.fill(color)
	image.save_png(path)
	return path

func _scene(key: String, extra: Dictionary = {}, base: Dictionary = {}) -> Control:
	var state := Save.get_default_state() if base.is_empty() else base.duplicate(true)
	var context := {"finale_key": key}
	context.merge(extra, true)
	state["_adventure_ui"] = context
	var scene: Control = Finale.new()
	root.add_child(scene)
	scene.setup(state, null)
	return scene

func _button(scene: Node, node_name: String) -> Button:
	return scene.find_child(node_name, true, false) as Button

func _texts(scene: Node) -> String:
	var parts: Array[String] = []
	for label in scene.find_children("*", "Label", true, false):
		parts.append(label.text)
	return "\n".join(PackedStringArray(parts))

func _test_screen() -> void:
	root.size = Vector2i(1280, 720)
	var river := _make_png("river", Color(0.2, 0.5, 0.7))
	var fall := _make_png("fall", Color(0.6, 0.8, 0.9))
	var scene := _scene("FG08", {"images": {"river": river, "fall": fall}})
	await settle()
	var beats: Array = Guide.finale("FG08").beats
	var closed := [0]
	var collection := [0]
	var hub := [0]
	scene.closed.connect(func(): closed[0] += 1)
	scene.collection_requested.connect(func(): collection[0] += 1)
	scene.hub_requested.connect(func(): hub[0] += 1)
	check(scene.page == 0 and scene.find_child("FinaleSpeech", true, false) != null, "the scene opens on the first speech")
	check(_texts(scene).contains("Клара") and not _button(scene, "FinaleNext").disabled, "the speaker is named and the way forward is open")
	check(scene.revealing(), "the first speech is typed out")
	scene._next()
	check(scene.page == 0 and not scene.revealing() and (scene.find_child("FinaleSpeech", true, false) as Label).visible_ratio == 1.0, "first press finishes the text, it does not skip the page")
	await capture("finale_fg08_page1")
	scene._next()
	check(scene.page == 1, "second press turns the page")
	scene._back()
	check(scene.page == 0 and not _button(scene, "FinaleNext").is_queued_for_deletion(), "back returns to the first page")
	for _i in range(beats.size()):
		scene.finish_reveal()
		scene._next()
	await settle()
	await capture("finale_fg08_summary")
	check(scene.page == beats.size(), "the last page is the summary")
	var changes := scene.find_child("FinaleChanges", true, false)
	check(changes != null and changes.get_child_count() == Guide.finale("FG08").changes.size(), "summary lists every real change")
	check(scene.find_child("FinalePhotos", true, false) != null and scene.find_child("FinalePhotos", true, false).get_child_count() == 2, "the water finale shows both of Maya's photos")
	check(_texts(scene).contains(str(Guide.finale("FG08").last).left(30)), "summary ends with the closing line")
	check(not _button(scene, "FinaleNext").visible and _button(scene, "FinaleDone") != null, "forward button gives way to «Готово»")
	_button(scene, "FinaleCollection").pressed.emit()
	_button(scene, "FinaleHub").pressed.emit()
	_button(scene, "FinaleDone").pressed.emit()
	check(collection[0] == 1 and hub[0] == 1 and closed[0] == 1, "the three exits emit their signals")
	scene._back()
	await settle()
	check(scene.summary_buttons.is_empty() and _button(scene, "FinaleDone") == null, "leaving the summary removes its buttons")
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	scene._unhandled_key_input(key)
	check(closed[0] == 2, "Escape closes the scene")
	scene.queue_free()

	var no_photos := _scene("FG11")
	await settle()
	no_photos.finish_reveal()
	await capture("finale_fg11_page1")
	for _i in range(5):
		no_photos.finish_reveal()
		no_photos._next()
	await capture("finale_fg11_summary")
	check(no_photos.page == Guide.finale("FG11").beats.size() and no_photos.find_child("FinalePhotos", true, false) == null, "only the water finale shows photos")
	no_photos.queue_free()

	var radio := _scene("FG01")
	await settle()
	radio.finish_reveal()
	await capture("finale_fg01_page1")
	for _i in range(5):
		radio.finish_reveal()
		radio._next()
	await capture("finale_fg01_summary")
	radio.queue_free()
	var champion := _scene("challenge")
	await settle()
	champion.finish_reveal()
	await capture("finale_challenge_page1")
	for _i in range(5):
		champion.finish_reveal()
		champion._next()
	await capture("finale_challenge_summary")
	champion.queue_free()

	var plain := Save.get_default_state()
	var without_bruno := _scene("chapter", {}, plain)
	check(without_bruno._beats().size() == Guide.finale("chapter").beats.size(), "chapter finale without the challenge has no Bruno line")
	without_bruno.queue_free()
	var won := Save.get_default_state()
	won.phase_c.rituals = {"maya_30_streak": {"unlocked": true}}
	var with_bruno := _scene("chapter", {}, won)
	await settle()
	with_bruno.finish_reveal()
	await capture("finale_chapter_page1")
	var speakers: Array[String] = []
	for beat in with_bruno._beats():
		speakers.append(str(beat.who))
	check(with_bruno._beats().size() == Guide.finale("chapter").beats.size() + 1 and speakers.has("bruno") and speakers.back() == "nora", "Bruno joins the chapter finale when the challenge is won, Nora still has the last word")
	with_bruno.queue_free()
	await settle()

# ---------------------------------------------------------------- through the real application

func _complete(qid: String) -> String:
	var inst := UI.instance_for(app.game_state, qid)
	var iid := str(inst.get("instance_id", ""))
	for stage in inst.quest_snapshot.adventure.stages:
		app.game_state.adventures.progress[iid].stages[str(stage.stage_id)]["status"] = "COMPLETED"
	inst["status"] = "COMPLETED"
	return iid

func _test_app_flow() -> void:
	var start := Save.get_default_state()
	start.settings.muted = true
	Save.save_game(start)
	app = load("res://scenes/app/app_root.tscn").instantiate()
	root.add_child(app)
	await settle()
	app.complete_puzzle()
	await settle()
	controller = app.adventure_controller
	controller.launch_service = load("res://scripts/services/launch_service.gd").new("user://test_mission_finale_launch_registry")

	# 1. Opening a finished mission for the first time ends with its closing scene.
	controller.open_quest("FG08")
	app._close_modals()
	var water_id := _complete("FG08")
	controller.open_quest("FG08")
	await settle()
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "FG08", "a finished mission opens its closing scene first")
	check(bool(Save.load_game().adventures.progress[water_id].get("finale_seen", false)), "the scene is remembered across restarts")
	controller._close_screen()
	await settle()
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "school_start", "Clara's first mission is followed by her school-report pitch")
	controller._close_screen()
	await settle()
	check(controller.route == "hub", "closing the scenes returns to the journal")

	# 2. Afterwards the ordinary mission page is shown, with a way to watch the scene again.
	controller.open_quest("FG08")
	await settle()
	check(controller.route == "mission" and controller.screen.find_child("MissionFinaleReplay", true, false) != null, "later visits show the mission page with a replay button")
	controller.screen.find_child("MissionFinaleReplay", true, false).pressed.emit()
	await settle()
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "FG08", "the replay button shows the scene again")
	controller._close_screen()
	await settle()

	# 3. Finishing the last step and closing it leads to the scene, also when the object stood in the room.
	controller.open_quest("FG11")
	app._close_modals()
	var game_id := str(UI.instance_for(app.game_state, "FG11").instance_id)
	controller.open_episode(game_id, "game_concept")
	await settle()
	check(controller.route == "episode", "the last step is open")
	_complete("FG11")
	controller._opened_from_room = true
	controller._close_screen()
	await settle()
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "FG11", "closing the last step opens the closing scene")
	controller._close_screen()
	await settle()
	check(app.modal_container.get_child_count() == 0 and controller.route == "finale", "after the scene a mission started from the room returns to the room")

	# 4. The chapter card in the journal.
	controller.open_quest("FG01")
	app._close_modals()
	_complete("FG01")
	var picks := {}
	for qid in ["FG01", "FG11", "FG08"]:
		var made: Dictionary = controller._run_command("create_work", {"title": "Работа " + qid, "kind": "image", "content": {"note": qid}, "quest_ids": [qid]})
		picks[qid] = str(made.get("work_id", ""))
	check(not picks.values().has(""), "one work per story exists for the chapter evening")
	controller.open_collection()
	await settle()
	controller._on_command("chapter_finale", {"title": "Тихий вечер", "work_ids": picks.values(), "selections": picks, "quiet": true})
	await settle(4)
	check(bool(app.game_state.adventures.chapters_by_profile.player_01.get("completed", false)), "the chapter evening is saved as completed")
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "chapter", "opening the chapter evening ends with its closing scene")
	controller._close_screen()
	await settle()
	controller._close_screen()
	await settle()
	controller.open_hub()
	await settle()
	var chapter_button := false
	for button in controller.screen.find_children("*", "Button", true, false):
		if button.text == "Посмотреть финал главы":
			chapter_button = true
			button.pressed.emit()
	await settle()
	check(chapter_button and controller.route == "finale" and str(controller.route_context.finale_key) == "chapter", "a finished chapter shows «Посмотреть финал главы» in the journal")
	controller._close_screen()
	await settle()
	check(controller.route == "hub", "the journal opens after the last pending scene")

	# 5. Thirty days: remembering the last forgotten day opens Bruno's ceremony and the wall changes.
	for n in range(1, 30):
		Ritual.set_past_day(app.game_state, _day(-n), true)
	Save.save_game(app.game_state)
	controller.open_hub()
	await settle()
	var toggle: Button = controller.screen.find_child("ChallengeCalendarToggle", true, false)
	check(toggle != null and controller.screen.find_child("ChallengeCalendar", true, false) == null, "the calendar is closed by default")
	toggle.pressed.emit()
	await settle()
	check(controller.screen.find_child("ChallengeCalendar", true, false) != null, "the calendar opens on demand")
	await capture("hub_calendar")
	var grid_days: Array = controller.screen.find_children("Day_*", "Button", true, false)
	check(grid_days.size() == Ritual.BACKFILL_WINDOW_DAYS, "the calendar offers exactly the remembered window")
	var done_days: Array = grid_days.filter(func(b): return b.disabled)
	check(done_days.is_empty(), "days remembered in this session stay clickable so a mistake can be undone")
	check(not app.station_room.challenge_board_marker.visible, "the board is not on the wall yet")
	var last_day: Button = controller.screen.find_child("Day_" + _day(-30), true, false)
	check(last_day != null, "day thirty is in the calendar")
	last_day.pressed.emit()
	await settle(4)
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "challenge", "the thirtieth day opens Bruno's ceremony")
	check(app.station_room.challenge_board_marker.visible and app.station_room.challenge_board_light.light_energy > 0.0, "the Champion board and the flame appear on the station wall")
	check(Ritual.get_challenge_state(Save.load_game()).unlocked, "the unlock is saved")
	controller._close_screen()
	await create_timer(1.8).timeout
	check(app.modal_container.get_child_count() == 0, "closing the ceremony returns to the room")
	var room = app.station_room
	var to_board: Vector3 = room.CHALLENGE_BOARD_POSITION - room.player_position
	var expected_yaw := rad_to_deg(atan2(-to_board.x, -to_board.z))
	check(absf(wrapf(room.player_yaw - expected_yaw, -180.0, 180.0)) < 1.0, "the view turns to the new board")
	await capture("station_after_win")
	for view in [[Vector3(0.5, 1.5, 1.4), 40.0], [Vector3(-1.0, 1.45, 0.4), 80.0]]:
		app.station_room.player_position = view[0]
		app.station_room.player_yaw = view[1]
		await capture("station_board_yaw%d" % int(view[1]))
	app.station_room.player_position = Vector3(0.0, 1.50, 2.42)
	app.station_room.player_yaw = 0.0
	controller.open_hub()
	await settle()
	var ceremony: Button = controller.screen.find_child("ChallengeCeremony", true, false)
	check(ceremony != null and controller.screen.find_child("ChallengeCalendarToggle", true, false) == null, "after the win the card offers the ceremony instead of the calendar")
	ceremony.pressed.emit()
	await settle()
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "challenge", "the ceremony can be watched again")
	app._close_modals()
	app.queue_free()
	await settle()
