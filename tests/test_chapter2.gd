extends SceneTree

## Chapter 2: missions of Teo, Bruno and Nora. Isolated storage only:
## run through `python3 tools/run_checks.py test_chapter2`.
const Save = preload("res://scripts/services/save_service.gd")
const Guide = preload("res://scripts/presentation/mission_guide.gd")
const C2G = preload("res://scripts/presentation/chapter2_guide.gd")
const C2 = preload("res://scripts/services/chapter2_service.gd")
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
	print("CH2 %02d %s" % [checks, name])
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

func run() -> void:
	Save.use_test_storage("user://test_chapter2_%d_" % OS.get_process_id())
	Save.cleanup_test_storage()
	if Save.SAVE_PATH == Save.DEFAULT_SAVE_PATH:
		push_error("test storage not isolated")
		quit(1)
		return
	_test_content()
	_test_rules()
	await _test_app()
	Ritual.school_end = Ritual.SCHOOL_END_DATE
	Save.cleanup_test_storage()
	print("CHAPTER 2: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		print("  FAILED: ", failure)
	quit(0 if failures.is_empty() else 1)

# ---------------------------------------------------------------- content

func _test_content() -> void:
	for mid in C2G.IDS:
		var def := C2G.mission(mid)
		check(not Guide.character(str(def.hero)).is_empty(), "%s has a known hero" % mid)
		var ids := {}
		var ok := true
		for step in def.steps:
			if ids.has(step.id) or str(step.get("say", "")).length() < 30 or str(step.get("task", "")).length() < 30 or str(step.get("done", "")).length() < 10:
				ok = false
			ids[step.id] = true
			if str(step.kind) not in ["check", "names", "number", "text", "story"]:
				ok = false
		check(ok, "%s: steps have unique ids, speech, task and reaction" % mid)
		for key in [def.pitch_key, def.finale_key]:
			var data := Guide.finale(str(key))
			check(data.get("beats", []).size() >= 3 and data.get("changes", []).size() >= 2 and not str(data.get("last", "")).is_empty(), "%s scene %s is complete" % [mid, key])
	check(Guide.finale("ch2_chapter").beats.size() >= 4, "the chapter finale has all heroes speaking")
	var spoken := {}
	for beat in Guide.finale("ch2_chapter").beats:
		spoken[str(beat.who)] = true
	check(spoken.has("nora") and spoken.has("teo") and spoken.has("clara") and spoken.has("bruno"), "all four heroes speak in the chapter finale")
	# Nora's grammar
	var story_ok := true
	var message: Array[String] = []
	var keys := 0
	for step in C2G.mission("nora2").steps:
		if str(step.kind) != "story":
			continue
		keys += 1
		message.append(str(step.reveal.es))
		if step.choice.options.size() < 3 or not bool(step.get("confirm", false)):
			story_ok = false
		for option in step.choice.options:
			if str(option.reaction).length() < 15 or str(option.text).is_empty():
				story_ok = false
		if step.has("quiz"):
			story_ok = false
	check(keys == 6 and story_ok, "Nora has six story intercepts with three flavored choices each, confirmed by the adult, and no quizzes")
	check(" ".join(PackedStringArray(message)) == "Hola, ¿estás ahí? Sigo aquí, en el faro. Hay una luz para ti.", "the six fragments assemble the lighthouse message")
	check(C2G.mission("bruno2").steps.size() == 7 and C2G.mission("teo2").steps.size() == 6 and C2G.mission("nora2").steps.size() == 7, "step counts match the design")

# ---------------------------------------------------------------- rules

func _state_with(quests: Array, challenge: bool = false) -> Dictionary:
	var state := Save.get_default_state()
	var instances := {}
	for qid in quests:
		instances[qid + ":x"] = {"quest_id": qid, "profile_id": "player_01", "instance_id": qid + ":x", "status": "COMPLETED"}
	state.phase_b.quest_instances = instances
	if challenge:
		state.phase_c.rituals = {Ritual.CHALLENGE_ID: {"unlocked": true}}
	return state

func _story_data(step: Dictionary) -> Dictionary:
	return {"fields": {"catch": ""}, "choice": str(step.choice.options[0].id)}

func _test_rules() -> void:
	var fresh := Save.get_default_state()
	check(not C2.any_unlocked(fresh), "nothing of chapter 2 is open on a fresh save")
	check(C2.unlocked(_state_with(["FG11"]), "teo2") and not C2.unlocked(_state_with(["FG11"]), "nora2"), "Teo opens after the first game, Nora does not")
	check(C2.unlocked(_state_with(["FG01"]), "nora2") and C2.unlocked(_state_with([], true), "bruno2"), "Nora opens after the radio, Bruno after the 30 days")
	check(not bool(C2.complete_step(fresh, "teo2", "t_names", {}, true).ok), "a locked mission refuses steps")

	var state := _state_with(["FG11"])
	check(C2.current_step_id(state, "teo2") == "t_names", "the first step is current")
	check(str(C2.complete_step(state, "teo2", "t_sketch", {}, false).get("reason", "")) == "not_current", "steps go in order")
	check(str(C2.complete_step(state, "teo2", "t_names", {"fields": {"tool_1": "Гоша"}}, false).get("reason", "")) == "adult_required", "a knife step needs an adult")
	check(str(C2.complete_step(state, "teo2", "t_names", {"fields": {"tool_1": ""}}, true).get("reason", "")) == "field_required", "the first tool needs a name")
	var named := C2.complete_step(state, "teo2", "t_names", {"fields": {"tool_1": " Гоша ", "tool_2": "Кеша"}}, true)
	check(bool(named.ok) and bool(named.applied) and C2.mission_state(state, "teo2").steps[0].record.fields.tool_1 == "Гоша", "names are saved trimmed")
	check(not bool(C2.complete_step(state, "teo2", "t_names", {"fields": {"tool_1": "Другой"}}, true).get("applied", true)), "a finished step cannot be redone")
	check(bool(C2.complete_step(state, "teo2", "t_sketch", {}, false).ok), "an optional photo is not required")
	check(str(C2.complete_step(state, "teo2", "t_blank", {}, true).get("reason", "")) == "photo_required", "the blank needs a photo")
	C2.set_draft(state, "teo2", "t_blank", {"artifact_id": "artifact:test"})
	check(bool(C2.complete_step(state, "teo2", "t_blank", {}, true).ok) and C2.mission_state(state, "teo2").steps[2].record.artifact_id == "artifact:test", "with a photo the blank step completes and keeps it")
	check(not bool(C2.station_view(state).teo_model), "the model waits for the carved piece")

	var run_state := _state_with([], true)
	check(str(C2.complete_step(run_state, "bruno2", "b_measure", {"fields": {"minutes": ""}}, false).get("reason", "")) == "field_required", "the first measure needs minutes")
	check(str(C2.complete_step(run_state, "bruno2", "b_measure", {"fields": {"minutes": "abc"}}, false).get("reason", "")) == "bad_number", "minutes must be a number")
	check(str(C2.complete_step(run_state, "bruno2", "b_measure", {"fields": {"minutes": "-3"}}, false).get("reason", "")) == "bad_number", "minutes must be positive")
	check(bool(C2.complete_step(run_state, "bruno2", "b_measure", {"fields": {"minutes": "4,5", "meters": ""}}, false).ok) and C2.mission_state(run_state, "bruno2").steps[0].record.fields.minutes == "4.5", "a comma decimal is accepted")
	for sid in ["b_pace", "b_1km", "b_2km"]:
		C2.complete_step(run_state, "bruno2", sid, {"fields": {}}, false)
	check(str(C2.complete_step(run_state, "bruno2", "b_hill", {}, false).get("reason", "")) == "adult_required", "the hill needs a companion")
	check(int(C2.station_view(run_state).bruno_done) == 4, "the wall map counts the finished rungs")

	var nora_state := _state_with(["FG01"])
	var steps: Array = C2G.mission("nora2").steps
	var first: Dictionary = steps[0]
	check(str(C2.complete_step(nora_state, "nora2", "n_gender", {"fields": {"catch": ""}, "choice": ""}, false).get("reason", "")) == "choice_required", "a choice is required, nothing else is checked")
	check(str(C2.complete_step(nora_state, "nora2", "n_gender", {"fields": {"catch": ""}, "choice": "nope"}, false).get("reason", "")) == "choice_required", "an unknown choice is refused")
	var heard := C2.complete_step(nora_state, "nora2", "n_gender", _story_data(first), false)
	check(bool(heard.ok) and str(heard.reaction).contains(str(first.choice.options[0].reaction).left(12)), "the intercept answers with the hero's reaction to the choice")
	check(not bool(C2.mission_state(nora_state, "nora2").confirmed.get("n_gender", false)), "hearing a topic does not confirm it")
	for step in steps:
		if str(step.kind) == "story" and str(step.id) != "n_gender":
			check(bool(C2.complete_step(nora_state, "nora2", str(step.id), _story_data(step), false).ok), "intercept %s plays without any exercise" % str(step.id))
	check(int(C2.station_view(nora_state).nora_lamps) == 6, "six intercepts light six lamps")
	check(str(C2.complete_step(nora_state, "nora2", "n_reply", {"fields": {"reply": "Hola"}}, false).get("reason", "")) == "too_short", "a one-word reply is too short")
	var done := C2.complete_step(nora_state, "nora2", "n_reply", {"fields": {"reply": "Hola, estoy aquí"}}, false)
	var waiting := C2.mission_state(nora_state, "nora2")
	check(bool(done.ok) and not bool(done.completed) and not bool(waiting.completed) and bool(waiting.awaiting_adult), "everything heard: the mission waits for the adult, not for more exercises")
	check(C2.confirm_items(nora_state).size() == 6, "the adult confirms six topics")
	check(not bool(C2.confirm_step(nora_state, "nora2", "n_reply").ok), "only topics can be confirmed")
	check(bool(C2.confirm_step(nora_state, "nora2", "n_gender").ok) and not bool(C2.mission_state(nora_state, "nora2").completed), "one confirmed topic does not finish the mission")
	check(not bool(C2.confirm_step(nora_state, "nora2", "n_gender").get("applied", true)), "confirming twice changes nothing")
	var all_confirmed := C2.confirm_all(nora_state, "nora2")
	check(bool(all_confirmed.ok) and int(all_confirmed.confirmed_count) == 5 and bool(all_confirmed.completed) and bool(C2.mission_state(nora_state, "nora2").completed), "«all at once» confirms the rest and completes the mission")
	# The adult may confirm ahead of the story: the mission finishes when the story is heard.
	var ahead := _state_with(["FG01"])
	check(bool(C2.confirm_all(ahead, "nora2").ok) and not bool(C2.mission_state(ahead, "nora2").completed), "topics confirmed ahead do not finish the mission without the story")
	for step in steps:
		if str(step.kind) == "story":
			C2.complete_step(ahead, "nora2", str(step.id), _story_data(step), false)
	check(not bool(C2.mission_state(ahead, "nora2").completed), "the reply is still hers to write")
	check(bool(C2.complete_step(ahead, "nora2", "n_reply", {"fields": {"reply": "Hola, estoy aquí"}}, false).completed), "after the reply the mission completes at once")

	# Scenes
	var scenes := _state_with(["FG11", "FG01"], true)
	var order: Array[String] = []
	for _i in range(4):
		var scene := C2.next_scene(scenes)
		if scene.is_empty():
			break
		order.append(str(scene.key))
		C2.mark_scene(scenes, scene)
	check(order == ["ch2_teo_start", "ch2_bruno_start", "ch2_nora_start"], "the pitches come one by one and only once")
	check(not C2.chapter_done(scenes), "the chapter is not done without the missions and the school")

# ---------------------------------------------------------------- through the application

func _make_png(name: String) -> String:
	var path := OS.get_temp_dir().path_join("sur_ch2_%d_%s.png" % [OS.get_process_id(), name])
	var image := Image.create(96, 64, false, Image.FORMAT_RGB8)
	image.fill(Color(0.7, 0.5, 0.3))
	image.save_png(path)
	return path

func _complete_quest(qid: String) -> void:
	controller.open_quest(qid)
	app._close_modals()
	var inst := UI.instance_for(app.game_state, qid)
	var iid := str(inst.get("instance_id", ""))
	for stage in inst.quest_snapshot.adventure.stages:
		app.game_state.adventures.progress[iid].stages[str(stage.stage_id)]["status"] = "COMPLETED"
		# mark as seen so the older finales do not stand in the way
	inst["status"] = "COMPLETED"
	app.game_state.adventures.progress[iid]["finale_seen"] = true

func _button(node: Node, button_name: String) -> Button:
	return node.find_child(button_name, true, false) as Button

func _send(op: String, payload: Dictionary) -> void:
	controller._on_command(op, payload)

func _close_scenes() -> void:
	for _i in range(8):
		if controller.route != "finale":
			return
		controller._close_screen()

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
	controller.launch_service = load("res://scripts/services/launch_service.gd").new("user://test_chapter2_launch_registry")
	controller.open_quest("FG11")
	app._close_modals()
	controller.open_hub()
	await settle()
	check(controller.screen.find_child("C2Card_teo2", true, false) == null, "no chapter 2 cards before the heroes' first missions")

	# Teo: the first game is done, the carving mission opens with its pitch.
	_complete_quest("FG11")
	controller.open_hub()
	await settle()
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "ch2_teo_start", "Teo's pitch appears once the game is finished")
	await capture("ch2_teo_pitch")
	_close_scenes()
	controller.open_hub()
	await settle()
	check(controller.screen.find_child("C2Card_teo2", true, false) != null, "Teo's card is in the journal")
	await capture("ch2_hub_cards")
	_button(controller.screen, "C2Open_teo2").pressed.emit()
	await settle()
	check(controller.route == "step_mission", "the card opens the mission")
	await capture("ch2_teo_step1")
	var screen: Control = controller.screen
	# Names step: needs a name and an adult.
	(screen.find_child("StepField_tool_1", true, false) as LineEdit).text = "Гоша"
	screen.inputs["t_names:tool_1"] = "Гоша"
	_button(screen, "StepSubmit").pressed.emit()
	await settle()
	check(C2.mission_state(app.game_state, "teo2").done == 0, "without the adult tick the step stays open")
	(screen.find_child("StepAdult", true, false) as CheckBox).button_pressed = true
	screen.adult_checked["t_names"] = true
	_button(screen, "StepSubmit").pressed.emit()
	await settle(4)
	check(C2.mission_state(Save.load_game(), "teo2").done == 1, "the first step is saved to disk")
	check(controller.screen.find_child("StepReaction", true, false) != null, "Teo reacts to the finished step")
	# Sketch (optional photo), then the blank needs a photo.
	_send("c2_step_done", {"mid": "teo2", "sid": "t_sketch", "adult": false, "data": {}})
	await settle(2)
	check(controller.screen.find_child("StepPhoto", true, false) != null and _button(controller.screen, "StepPhotoPick") != null, "the blank step shows the photo window")
	await capture("ch2_teo_photo_step")
	_send("c2_step_done", {"mid": "teo2", "sid": "t_blank", "adult": true, "data": {}})
	await settle(2)
	check(C2.mission_state(app.game_state, "teo2").done == 2, "no photo, no blank step")
	controller._c2_store_photo({"mid": "teo2", "sid": "t_blank"}, _make_png("blank"))
	await settle(3)
	check(controller.screen.find_child("StepPhotoPreview", true, false) != null, "the photo preview appears after choosing a file")
	_send("c2_step_done", {"mid": "teo2", "sid": "t_blank", "adult": true, "data": {}})
	_send("c2_step_done", {"mid": "teo2", "sid": "t_practice", "adult": true, "data": {}})
	controller._c2_store_photo({"mid": "teo2", "sid": "t_carve"}, _make_png("lighthouse"))
	await settle(3)
	_send("c2_step_done", {"mid": "teo2", "sid": "t_carve", "adult": true, "data": {}})
	await settle(3)
	check(app.station_room.lighthouse_model.visible and app.station_room.lighthouse_photo.visible, "the carved lighthouse and its photo stand on the shelf")
	_send("c2_step_done", {"mid": "teo2", "sid": "t_light", "adult": true, "data": {}})
	await settle(4)
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "ch2_teo", "the last step opens Teo's finale")
	check(app.station_room.lighthouse_light.has_meta("lit") and bool(app.station_room.lighthouse_light.get_meta("lit")), "the lighthouse lamp is lit")
	for _i in range(5):
		controller.screen.finish_reveal()
		controller.screen._next()
	await settle()
	await capture("ch2_teo_final")
	check(controller.screen.find_child("FinalePhotos", true, false) != null, "the final page shows the photo of the carving")
	check(Collections.list_works(Save.load_game()).any(func(w): return str(w.get("title", "")).contains("Первая стружка")), "the lighthouse is saved among her works")
	_close_scenes()
	app._close_modals()
	app.station_room.player_position = Vector3(0.0, 1.50, 2.42)
	app.station_room.player_yaw = 0.0
	await capture("ch2_station_lighthouse")

	# Nora: the radio is finished, the cipher mission opens.
	_complete_quest("FG01")
	controller.open_hub()
	await settle()
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "ch2_nora_start", "Nora's pitch appears once the radio is finished")
	_close_scenes()
	Ritual.mark_school_day(app.game_state, Time.get_date_string_from_system(), true, "", "tarea")
	controller.open_step_mission("nora2")
	await settle()
	screen = controller.screen
	check(screen.find_child("SchoolWordsHint", true, false) != null and screen.find_child("SchoolWordsHint", true, false).text.contains("tarea"), "Nora's school catch shows the words from the school glossary")
	var key_one: Dictionary = C2G.mission("nora2").steps[0]
	check(screen.find_child("StoryChoices", true, false) != null and screen.find_child("QuizOption_0_x", true, false) == null, "the intercept offers a story choice, not a test")
	_button(screen, "StepSubmit").pressed.emit()
	await settle(2)
	check(C2.mission_state(app.game_state, "nora2").done == 0, "without a choice the intercept stays shut")
	var option_id := str(key_one.choice.options[1].id)
	_button(controller.screen, "StoryOption_" + option_id).pressed.emit()
	await settle()
	check(controller.screen.find_child("StoryChoiceReaction", true, false) != null, "the hero's reaction to the choice is visible at once")
	screen = controller.screen
	(screen.find_child("StepField_catch", true, false) as TextEdit).text = "La casa es pequeña"
	screen.inputs["n_gender:catch"] = "La casa es pequeña"
	await capture("ch2_nora_wrong")
	_button(controller.screen, "StepSubmit").pressed.emit()
	await settle(4)
	check(C2.mission_state(app.game_state, "nora2").done == 1, "the first intercept opens")
	check(app.station_room.cipher_strip.visible and int(C2.station_view(app.game_state).nora_lamps) == 1, "the first lamp lights on the radio")
	await capture("ch2_nora_after_key1")

	# Bruno: the 30 days are won.
	Ritual.school_end = Ritual.SCHOOL_END_DATE
	for n in range(1, 31):
		Ritual.set_past_day(app.game_state, Ritual.shift_date(Time.get_date_string_from_system(), -n), true)
	controller.refresh_world()
	controller.open_hub()
	await settle()
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "ch2_bruno_start", "Bruno's pitch appears once the 30 days are won")
	_close_scenes()
	controller.open_step_mission("bruno2")
	await settle()
	await capture("ch2_bruno_step1")
	_send("c2_step_done", {"mid": "bruno2", "sid": "b_measure", "adult": false, "data": {"fields": {"minutes": "3", "meters": ""}}})
	await settle(3)
	check(C2.mission_state(app.game_state, "bruno2").done == 1 and "1 из 7" in app.station_room.valley_map_notes.text, "the first rung is written on the wall map")
	app._close_modals()
	app.open_world_explorer()
	await settle(3)
	check(app.modal_container.get_child(0).find_children("*", "Control", true, false).any(func(n): return n.get_script() != null and str(n.get_script().resource_path).ends_with("atlas_map.gd")), "the atlas draws Bruno's trail")
	await capture("ch2_atlas_trail")
	app._close_modals()
	for sid in ["b_pace", "b_1km", "b_2km", "b_hill", "b_recon", "b_run"]:
		_send("c2_step_done", {"mid": "bruno2", "sid": sid, "adult": true, "data": {"fields": {"minutes": ""}}})
		await settle(2)
	check(C2.mission_state(app.game_state, "bruno2").completed, "Bruno's ladder completes")
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "ch2_bruno", "the last rung opens Bruno's finale")
	check(Collections.list_works(Save.load_game()).any(func(w): return str(w.get("title", "")).contains("Тропа Бруно")), "the ladder is saved as a page in the archive")
	_close_scenes()

	# The rest of Nora and the school bring the chapter finale and the beacon.
	for step in steps_after_first():
		var sid_n := str(step.id)
		if str(step.kind) == "story":
			_send("c2_step_done", {"mid": "nora2", "sid": sid_n, "adult": false, "data": _story_data(step)})
		else:
			_send("c2_step_done", {"mid": "nora2", "sid": sid_n, "adult": false, "data": {"fields": {"reply": "Hola, estoy aquí"}}})
		await settle(2)
	check(not C2.mission_state(app.game_state, "nora2").completed and C2.mission_state(app.game_state, "nora2").awaiting_adult, "Nora's story is heard, the adult's confirmation is still needed")
	_send("c2_confirm_all", {"mid": "nora2"})
	await settle(3)
	check(C2.mission_state(app.game_state, "nora2").completed, "Nora's mission completes")
	_close_scenes()
	check(not bool(C2.station_view(app.game_state).chapter_done) and not app.station_room.window_beacon.visible, "the beacon waits for the school report")
	Ritual.mark_school_day(app.game_state, Time.get_date_string_from_system(), true, "hola", "hola")
	Ritual.school_end = Time.get_date_string_from_system()
	Ritual.complete_school(app.game_state)
	controller.refresh_world()
	controller._present_due_finale()
	await settle(3)
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "ch2_chapter", "all four missions done: the chapter finale opens")
	await capture("ch2_chapter_final")
	check(app.station_room.window_beacon.visible, "the old lighthouse light shows in the station window")
	_close_scenes()
	app._close_modals()
	await capture("ch2_window_beacon")
	check(C2.next_scene(app.game_state).is_empty(), "no scene is left to show")
	Ritual.school_end = Ritual.SCHOOL_END_DATE
	app.queue_free()
	await settle()

func steps_after_first() -> Array:
	return C2G.mission("nora2").steps.slice(1)
