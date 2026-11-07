extends SceneTree

## Clara's school report: rules, journal card, station press card and finale.
## Isolated storage only: run through `python3 tools/run_checks.py test_school_report`.
const Save = preload("res://scripts/services/save_service.gd")
const Guide = preload("res://scripts/presentation/mission_guide.gd")
const Ritual = preload("res://scripts/services/ritual_service.gd")
const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Collections = preload("res://scripts/services/collection_service.gd")

var failures: Array[String] = []
var checks := 0
var app: Node
var controller: Node

func _init() -> void:
	call_deferred("run")

func check(value: bool, name: String) -> void:
	checks += 1
	print("SCHOOL %02d %s" % [checks, name])
	if not value:
		failures.append(name)
		push_error(name)

func settle(frames: int = 3) -> void:
	for _i in range(frames):
		await process_frame

func capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--render") or DisplayServer.get_name() == "headless":
		return
	await settle(6)
	DirAccess.make_dir_recursive_absolute("/tmp/sur-finale-qa")
	root.get_texture().get_image().save_png("/tmp/sur-finale-qa/" + name + ".png")

func _day(offset: int) -> String:
	return Ritual.shift_date(Time.get_date_string_from_system(), offset)

func run() -> void:
	Save.use_test_storage("user://test_school_report_%d_" % OS.get_process_id())
	Save.cleanup_test_storage()
	if Save.SAVE_PATH == Save.DEFAULT_SAVE_PATH:
		push_error("test storage not isolated")
		quit(1)
		return
	_test_wording()
	_test_rules()
	await _test_app()
	Ritual.school_end = Ritual.SCHOOL_END_DATE
	Save.cleanup_test_storage()
	print("SCHOOL REPORT: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		print("  FAILED: ", failure)
	quit(0 if failures.is_empty() else 1)

func _test_wording() -> void:
	for key in ["school_start", "school"]:
		var data := Guide.finale(key)
		check(data.get("beats", []).size() >= 3 and data.get("changes", []).size() >= 3 and not str(data.get("last", "")).is_empty(), "%s scene is complete" % key)
		var ok := true
		for beat in data.get("beats", []):
			if str(beat.get("who", "")) != "clara" or Guide.portrait_path("clara", "happy").is_empty():
				ok = false
		check(ok, "%s is spoken by Clara" % key)
	var start_text := "\n".join(PackedStringArray(Guide.finale("school_start").beats.map(func(b): return str(b.text))))
	check(start_text.contains("10 декабря"), "pitch names the date")
	check(start_text.contains("Страх") and start_text.contains("Первые дни прошли отлично"), "the pitch acknowledges the fear and the good first days")
	check(not start_text.contains("два дня"), "the pitch does not depend on how many days have passed")

func _fake_water(done: bool) -> Dictionary:
	var state := Save.get_default_state()
	state.phase_b.quest_instances = {"FG08:x": {"quest_id": "FG08", "profile_id": "player_01", "instance_id": "FG08:x", "status": "COMPLETED" if done else "ACTIVE"}}
	return state

func _test_rules() -> void:
	check(not Ritual.school_visible(_fake_water(false)) and Ritual.school_visible(_fake_water(true)), "the report appears only after Clara's water mission is completed")
	check(not Ritual.school_visible(Save.get_default_state()), "it is hidden on a fresh save")
	var state := _fake_water(true)
	var info := Ritual.school_state(state)
	check(int(info.days) == 0 and not bool(info.completed) and not bool(info.pitched) and not bool(info.today_done), "starts empty")
	check(not state.phase_c.rituals.has(Ritual.SCHOOL_ID), "reading the state does not write it")
	check(bool(Ritual.mark_school_day(state, _day(0), true, "  Поняла слово «recreo»  ", "recreo").ok), "today can be marked")
	var entry: Dictionary = Ritual.school_state(state).history[_day(0)]
	check(str(entry.note) == "Поняла слово «recreo»" and str(entry.word) == "recreo" and not entry.has("backfilled"), "dispatch and word are saved trimmed, today is not marked as remembered")
	Ritual.mark_school_day(state, _day(0), true)
	check(str(Ritual.school_state(state).history[_day(0)].note) != "", "marking again keeps the dispatch")
	check(bool(Ritual.mark_school_day(state, _day(-3), true).ok) and bool(Ritual.school_state(state).history[_day(-3)].get("backfilled", false)), "past days can be remembered")
	check(int(Ritual.school_state(state).days) == 2 and bool(Ritual.school_state(state).today_done), "days are counted")
	check(not bool(Ritual.mark_school_day(state, _day(1), true).ok), "the future cannot be marked")
	check(not bool(Ritual.mark_school_day(state, _day(-Ritual.SCHOOL_WINDOW_DAYS), true).ok) and bool(Ritual.mark_school_day(state, _day(-(Ritual.SCHOOL_WINDOW_DAYS - 1)), true).ok), "the window is exactly the offered days")
	check(not bool(Ritual.mark_school_day(state, "nonsense", true).ok), "garbage dates are refused")
	Ritual.mark_school_day(state, _day(-3), false)
	check(int(Ritual.school_state(state).days) == 2 and not Ritual.school_state(state).history.has(_day(-3)), "a mark can be taken back")
	# Mood, milestones and glossary.
	var fresh := _fake_water(true)
	var first := Ritual.mark_school_day(fresh, _day(0), true, "", "tarea", "rain")
	check(int(first.get("milestone", 0)) == 1 and str(first.message).contains("Клара"), "the first day brings Clara's first-day line")
	check(str(Ritual.school_state(fresh).history[_day(0)].mood) == "rain", "the mood of the day is saved")
	check(not Ritual.mark_school_day(fresh, _day(0), true).has("milestone"), "re-marking the same day repeats no milestone")
	var mood_only := Ritual.mark_school_day(fresh, _day(-1), true, "", "", "sun")
	check(not mood_only.has("milestone") and str(mood_only.message).contains("Солнечный"), "a plain day gets Clara's line for its mood")
	check(not Ritual.mark_school_day(fresh, _day(-2), true, "", "", "tornado").has("message") and str(Ritual.school_state(fresh).history[_day(-2)].mood) == "", "an unknown mood is ignored")
	var milestone_days: Array[int] = []
	for n in range(3, 12):
		var step_result := Ritual.mark_school_day(fresh, _day(-n), true)
		if step_result.has("milestone"):
			milestone_days.append(int(step_result.milestone))
	check(milestone_days == [5, 10], "milestones come exactly at 5 and 10 days")
	var gloss := Ritual.school_glossary(fresh)
	check(gloss.size() == 1 and str(gloss[0].word) == "tarea", "the glossary lists only days with a word")
	# No streak to lose: a gap changes nothing.
	check(int(Ritual.school_state(state).days) == 2, "gaps never reset the count")
	# Finishing
	check(not bool(Ritual.complete_school(state).ok) and not bool(Ritual.school_state(state).can_finish), "the issue cannot be handed in before the date")
	Ritual.school_end = _day(0)
	check(bool(Ritual.school_state(state).can_finish), "from the end date the issue can be handed in")
	var done := Ritual.complete_school(state)
	check(bool(done.ok) and bool(done.applied) and bool(Ritual.school_state(state).completed), "handing in completes the report")
	check(not bool(Ritual.complete_school(state).get("applied", true)), "handing in twice is a no-op")
	check(not bool(Ritual.mark_school_day(state, _day(-1), true).ok), "a handed-in report is frozen")
	var empty := _fake_water(true)
	check(not bool(Ritual.complete_school(empty).ok), "an empty press card cannot be handed in")
	Ritual.school_end = Ritual.SCHOOL_END_DATE

func _find_button(node: Node, button_name: String) -> Button:
	return node.find_child(button_name, true, false) as Button

func _complete(qid: String) -> void:
	var inst := UI.instance_for(app.game_state, qid)
	var iid := str(inst.get("instance_id", ""))
	for stage in inst.quest_snapshot.adventure.stages:
		app.game_state.adventures.progress[iid].stages[str(stage.stage_id)]["status"] = "COMPLETED"
	inst["status"] = "COMPLETED"

func _test_app() -> void:
	root.size = Vector2i(1280, 720)
	var start := Save.get_default_state()
	start.settings.muted = true
	Save.save_game(start)
	app = load("res://scenes/app/app_root.tscn").instantiate()
	root.add_child(app)
	await settle()
	app.complete_puzzle()
	await settle()
	controller = app.adventure_controller
	controller.launch_service = load("res://scripts/services/launch_service.gd").new("user://test_school_report_launch_registry")

	controller.open_hub()
	await settle()
	check(controller.screen.find_child("SchoolCard", true, false) == null, "no school card before the water mission is done")
	check(not app.station_room.school_card_marker.visible, "no press card on the wall yet")

	controller.open_quest("FG08")
	app._close_modals()
	_complete("FG08")
	controller.open_quest("FG08")
	await settle()
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "FG08", "Clara's first mission ends with its finale")
	controller._close_screen()
	await settle()
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "school_start", "then Clara pitches the school report")
	check(bool(Ritual.school_state(Save.load_game()).pitched), "the pitch is remembered")
	await capture("school_pitch_page1")
	var scene: Control = controller.screen
	for _i in range(6):
		scene.finish_reveal()
		scene._next()
	await capture("school_pitch_summary")
	controller._close_screen()
	await settle()
	check(controller.route == "hub", "after the pitch the journal opens")
	controller.open_quest("FG08")
	await settle()
	check(controller.route == "mission", "the pitch is shown once")
	app._close_modals()

	controller.open_hub()
	await settle()
	check(controller.screen.find_child("SchoolCard", true, false) != null, "the school card appears in the journal")
	for scroller in controller.screen.find_children("*", "ScrollContainer", true, false):
		scroller.scroll_vertical = 100000
	await capture("school_card")
	var note: LineEdit = controller.screen.find_child("SchoolNote", true, false)
	var word: LineEdit = controller.screen.find_child("SchoolWord", true, false)
	note.text = "Поняла, что учитель сказал «tarea»"
	note.text_changed.emit(note.text)
	word.text = "tarea"
	word.text_changed.emit(word.text)
	check(controller.screen.find_child("SchoolMood_rain", true, false) != null, "the mood buttons are on today's card")
	_find_button(controller.screen, "SchoolMood_rain").pressed.emit()
	await settle()
	note = controller.screen.find_child("SchoolNote", true, false)
	word = controller.screen.find_child("SchoolWord", true, false)
	check(not controller.screen.find_child("SchoolFinish", true, false) != null, "no hand-in button before the date")
	_find_button(controller.screen, "SchoolToday").pressed.emit()
	await settle(4)
	var info := Ritual.school_state(Save.load_game())
	check(int(info.days) == 1 and str(info.history[_day(0)].note).contains("tarea") and str(info.history[_day(0)].word) == "tarea", "the first school day is saved with dispatch and word")
	check(str(info.history[_day(0)].mood) == "rain", "the chosen mood reaches the save")
	_find_button(controller.screen, "SchoolGlossaryToggle").pressed.emit()
	await settle()
	check(controller.screen.find_child("SchoolGlossary", true, false) != null and "tarea" in controller.screen.find_child("SchoolGlossary", true, false).find_children("*", "Label", true, false).map(func(l): return l.text).reduce(func(a, b): return a + " " + b, ""), "the glossary shows the word")
	check(_find_button(controller.screen, "SchoolToday") == null, "today's button gives way to the confirmation")
	check(app.station_room.school_card_marker.visible and app.station_room.school_card_label.text.contains("1"), "the press card appears on the wall")
	_find_button(controller.screen, "SchoolCalendarToggle").pressed.emit()
	await settle()
	var days: Array = controller.screen.find_children("SchoolDay_*", "Button", true, false)
	check(days.size() == Ritual.SCHOOL_WINDOW_DAYS, "the calendar offers the whole window")
	await capture("school_calendar")
	_find_button(controller.screen, "SchoolDay_" + _day(-1)).pressed.emit()
	await settle(4)
	check(int(Ritual.school_state(Save.load_game()).days) == 2, "a remembered day is saved from the calendar")
	app.station_room.player_position = Vector3(0.0, 1.50, 2.42)
	app.station_room.player_yaw = 0.0
	app._close_modals()
	await capture("school_press_card")
	# Both cards on the wall: win the 30 days too.
	for n in range(1, 31):
		Ritual.set_past_day(app.game_state, _day(-n), true)
	controller.refresh_world()
	app.station_room.player_position = Vector3(0.6, 1.5, 1.5)
	app.station_room.player_yaw = 42.0
	await capture("school_wall_both")
	app.station_room.player_position = Vector3(0.0, 1.50, 2.42)
	app.station_room.player_yaw = 0.0

	# Handing in the issue, with the date moved to today.
	Ritual.school_end = Ritual.shift_date(Time.get_date_string_from_system(), 0)
	controller.open_hub()
	await settle()
	if controller.route == "finale":
		# Winning the 30 days earlier opened Bruno's pitch first.
		controller._close_screen()
		await settle()
		controller.open_hub()
		await settle()
	var finish := _find_button(controller.screen, "SchoolFinish")
	check(finish != null, "the hand-in button appears on the end date")
	finish.pressed.emit()
	await settle(4)
	check(bool(Ritual.school_state(Save.load_game()).completed), "the report is saved as handed in")
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "school", "handing in opens the final scene")
	check(app.station_room.school_card_label.text.contains("ПЕРВАЯ ПОЛОСА"), "the press card becomes the front page")
	var scene_text := ""
	for label in controller.screen.find_children("*", "Label", true, false):
		scene_text += label.text + "\n"
	for _i in range(6):
		controller.screen.finish_reveal()
		controller.screen._next()
	await settle()
	scene_text = ""
	for label in controller.screen.find_children("*", "Label", true, false):
		scene_text += label.text + "\n"
	check(scene_text.contains("Школьных дней в репортаже: 2") and scene_text.contains("tarea"), "the final page lists the days and the dispatches")
	await capture("school_final")
	var works := Collections.list_works(Save.load_game())
	check(works.any(func(w): return str(w.get("title", "")).contains("Корреспондент Майя")), "the issue is saved among Maya's works")
	controller._close_screen()
	await settle()
	check(controller.route == "hub" or app.modal_container.get_child_count() == 0, "the final scene closes")
	controller.open_hub()
	await settle()
	check(_find_button(controller.screen, "SchoolFinaleReplay") != null and _find_button(controller.screen, "SchoolToday") == null, "afterwards the card offers the final scene instead of the buttons")
	Ritual.school_end = Ritual.SCHOOL_END_DATE
	app._close_modals()
	app.queue_free()
	await settle()
