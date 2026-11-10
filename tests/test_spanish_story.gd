extends SceneTree

## Испанская миссия как сюжет: письма Южного Маяка, подтверждение взрослым, без упражнений.
## Только изолированное хранилище: `python3 tools/run_checks.py test_spanish_story`.
const Save = preload("res://scripts/services/save_service.gd")
const Content = preload("res://scripts/services/adventure_content.gd")
const Quests = preload("res://scripts/services/quest_service.gd")
const A = preload("res://scripts/services/adventure_service.gd")
const Progress = preload("res://scripts/services/progress_service.gd")
const Collections = preload("res://scripts/services/collection_service.gd")
const SG = preload("res://scripts/presentation/story_guide.gd")
const Story = preload("res://scripts/services/story_service.gd")
const Guide = preload("res://scripts/presentation/mission_guide.gd")
const UI = preload("res://scripts/presentation/adventure_ui.gd")

var failures: Array[String] = []
var checks := 0
var app: Node
var controller: Node

func _init() -> void:
	call_deferred("run")

func check(value: bool, name: String) -> void:
	checks += 1
	print("STORY %02d %s" % [checks, name])
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
	Save.use_test_storage("user://test_spanish_story_%d_" % OS.get_process_id())
	Save.cleanup_test_storage()
	if Save.SAVE_PATH == Save.DEFAULT_SAVE_PATH:
		push_error("test storage not isolated")
		quit(1)
		return
	_test_content()
	_test_service()
	_test_attestation()
	await _test_app()
	Save.cleanup_test_storage()
	print("SPANISH STORY: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		print("  FAILED: ", failure)
	quit(0 if failures.is_empty() else 1)

# ---------------------------------------------------------------- content

func _test_content() -> void:
	var fg01 := Content.get_quest("FG01")
	var stage_ids: Array = []
	for stage in fg01.adventure.stages:
		stage_ids.append(str(stage.stage_id))
	var chapters: Array = SG.series("fg01").chapters
	var mapped: Array = []
	for chapter in chapters:
		mapped.append(str(chapter.stage_id))
	check(mapped == stage_ids.slice(1), "the five chapters follow the five stages after the first contact")
	var scenes := SG.scenes("fg01")
	check(scenes.size() == 14, "the series has fourteen letters")
	var ids := {}
	var sound := true
	var graded := false
	var tokens_known := true
	var known_tokens: Array = SG.series("fg01").defaults.keys()
	for scene in scenes:
		ids[str(scene.id)] = true
		if Guide.character(str(scene.who)).is_empty() or str(scene.text).length() < 60:
			sound = false
		var choice: Dictionary = scene.get("choice", {})
		if not choice.is_empty():
			known_tokens.append(str(choice.id))
			if choice.options.size() < 3:
				sound = false
			for option in choice.options:
				if str(option.reaction).length() < 15 or option.has("answer") or option.has("correct"):
					graded = true
		for reply in scene.get("replies", []):
			known_tokens.append(str(reply.id))
	for scene in scenes:
		var regex := RegEx.new()
		regex.compile("\\{([a-z_]+)\\}")
		for found in regex.search_all(str(scene.text) + " " + JSON.stringify(scene.get("choice", {}))):
			if not known_tokens.has(found.get_string(1)):
				tokens_known = false
	check(ids.size() == 14 and sound, "scene ids are unique, every letter has a hero and a text, every choice has flavored reactions")
	check(not graded, "nothing in the story is graded as right or wrong")
	check(tokens_known, "every {token} in the letters is a choice, a reply or a default")
	var heroes := {}
	for scene in scenes:
		heroes[str(scene.who)] = true
	check(heroes.has("nora") and heroes.has("clara") and heroes.has("teo") and heroes.has("bruno") and heroes.size() == 4, "all four heroes of the ensemble call the radio, nobody new appears")
	var required := 0
	for scene in scenes:
		for reply in scene.get("replies", []):
			if bool(reply.get("required", false)):
				required += 1
	check(required == 3, "only her own broadcast is required: greeting, news and farewell")

# ---------------------------------------------------------------- service

func _test_service() -> void:
	var state := Save.get_default_state()
	check(str(Story.next_scene(state, "fg01").id) == "c1s1" and not Story.finished(state, "fg01"), "the series starts with the first letter")
	check(Story.text_for(state, "fg01", "кафе «{show}»") == "кафе «наше радиокафе»", "before a choice the default word is used")
	check(str(Story.complete_scene(state, "fg01", "c1s2", "medialunas", {}).get("reason", "")) == "not_current", "letters come in order")
	check(str(Story.complete_scene(state, "fg01", "c1s1", "", {}).get("reason", "")) == "choice_required", "a choice is required")
	check(str(Story.complete_scene(state, "fg01", "c1s1", "nope", {}).get("reason", "")) == "choice_required", "an unknown choice is refused")
	var first := Story.complete_scene(state, "fg01", "c1s1", "moon", {"greet": "  ¡Bienvenidos!  "})
	check(bool(first.ok) and bool(first.applied) and str(first.reaction).contains("Лунный столик"), "the choice answers with the hero's reaction")
	check(Story.text_for(state, "fg01", "кафе «{show}»") == "кафе «Лунный столик»", "the café remembers its name in later letters")
	check(Story.tokens(state, "fg01").greet == "¡Bienvenidos!", "her free reply is kept as she wrote it")
	check(not bool(Story.complete_scene(state, "fg01", "c1s1", "moon", {}).get("applied", true)), "a letter is not played twice")
	Story.complete_scene(state, "fg01", "c1s2", "alfajores", {})
	var third := Story.complete_scene(state, "fg01", "c1s3", "repetir", {})
	check(bool(third.chapter_done) and not bool(third.finished), "the third letter closes the chapter")
	var progress := Story.progress(state, "fg01")
	check(int(progress.done) == 3 and int(progress.total) == 14 and int(progress.chapters[0].done) == 3, "progress counts letters and chapters")
	# Play the rest, in order; the last chapter needs her own broadcast.
	for scene in SG.scenes("fg01"):
		if Story.scene_done(state, "fg01", str(scene.id)):
			continue
		var choice_id := str(scene.choice.options[0].id) if not scene.get("choice", {}).is_empty() else ""
		if str(scene.id) == "c5s1":
			check(str(Story.complete_scene(state, "fg01", "c5s1", "", {"hello": "", "news": "x", "bye": "y"}).get("reason", "")) == "reply_required", "the broadcast needs a greeting")
			Story.complete_scene(state, "fg01", "c5s1", "", {"hello": "¡Hola, valle!", "news": "Hoy hay sol", "bye": "¡Hasta mañana!"})
		else:
			Story.complete_scene(state, "fg01", str(scene.id), choice_id, {})
	check(Story.finished(state, "fg01") and Story.next_scene(state, "fg01").is_empty(), "all letters heard")
	var last_text := Story.text_for(state, "fg01", str(SG.scene("fg01", "c5s2").text))
	check(last_text.contains("¡Hola, valle!") and last_text.contains("Hoy hay sol") and last_text.contains("Лунный столик"), "her own broadcast and her café name sound in the final scene")
	check(Story.journal(state, "fg01").size() >= 10, "the journal of the air keeps her choices and words")

# ---------------------------------------------------------------- adult confirmation

func _fresh_fg01() -> Array:
	var state := Save.get_default_state()
	state.s00_progress.station_awakened = true
	var quest := Content.get_quest("FG01")
	Quests.approve_and_publish(state, quest, "parent_local")
	var accepted := A.accept(state, "FG01", int(quest.revision))
	return [state, str(accepted.instance.instance_id)]

func _total_xp(state: Dictionary) -> int:
	var total := 0
	for value in Progress.get_profile_xp(state, "player_01").values():
		total += int(value)
	return total

func _test_attestation() -> void:
	var pair := _fresh_fg01()
	var state: Dictionary = pair[0]
	var iid: String = pair[1]
	check(str(A.dispatch(state, "attest_stage", {"instance_id": iid, "stage_id": "es_channel_01"}).get("reason", "")) == "stage_locked", "stages are confirmed in order")
	var commit = load("res://scripts/services/activity_commit_service.gd")
	check(str(commit.attest_stage(state, iid, "es_intro", "", "player_self").get("reason", "")) == "parent_required", "only the adult can confirm")
	check(bool(A.dispatch(state, "attest_stage", {"instance_id": iid, "stage_id": "es_intro"}).ok) and A.get_progress(state, iid).stages.es_intro.status == "COMPLETED", "the adult confirms the first stage")
	check(A.get_progress(state, iid).lexemes.size() == 5, "the first five words are recorded as known")
	check(not bool(A.dispatch(state, "attest_stage", {"instance_id": iid, "stage_id": "es_intro"}).get("applied", true)), "confirming twice changes nothing")
	var all := A.dispatch(state, "attest_all", {"instance_id": iid})
	var progress := A.get_progress(state, iid)
	var all_done := true
	for sid in progress.stages:
		if str(progress.stages[sid].status) != "COMPLETED" or str(progress.stages[sid].get("confirmation_mode", "")) != "parent_attest":
			all_done = false
	check(bool(all.ok) and int(all.attested_count) == 5 and all_done, "«all at once» confirms the remaining stages in order")
	check(A.get_instance(state, iid).status == "COMPLETED" and progress.lexemes.size() == 100, "the mission completes with a hundred words recorded")
	check(_total_xp(state) == 40, "the reward is exactly what the mission always paid")
	var recognized := 0
	for record in progress.lexemes.values():
		if bool(record.get("recognized", false)):
			recognized += 1
	check(recognized == 100, "the vocabulary album shows the words as known")
	check(Collections.list_works(state).size() > 0, "the confirmed stages leave works in the archive")
	var other := _fresh_fg01()
	check(bool(A.dispatch(other[0], "attest_all", {"instance_id": other[1]}).ok), "everything can be confirmed from a fresh start")
	var water := Save.get_default_state()
	Quests.approve_and_publish(water, Content.get_quest("FG08"), "parent_local")
	var accepted := A.accept(water, "FG08", int(Content.get_quest("FG08").revision))
	var refused := A.dispatch(water, "attest_stage", {"instance_id": str(accepted.instance.instance_id), "stage_id": "water_intro"})
	check(str(refused.get("reason", "")) == "attestation_not_supported", "confirmation exists only for the Spanish mission, the water and the game still need the real thing")

# ---------------------------------------------------------------- through the application

func _button(node: Node, button_name: String) -> Button:
	return node.find_child(button_name, true, false) as Button

func _fg01_id() -> String:
	return str(UI.instance_for(app.game_state, "FG01").get("instance_id", ""))

func _run(op: String, payload: Dictionary) -> Dictionary:
	return controller._run_command(op, payload)

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
	controller.launch_service = load("res://scripts/services/launch_service.gd").new("user://test_spanish_story_launch_registry")
	controller.open_quest("FG01")
	await settle()
	check(controller.route == "mission", "the radio opens its mission page")
	app._close_modals()
	var iid := _fg01_id()
	# The first contact is a real scene: the callsign. The letters begin after it.
	controller.open_episode(iid, "es_intro")
	await settle()
	check(controller.route == "episode", "the first contact is still a scene of its own")
	check(bool(_run("attest_stage", {"instance_id": iid, "stage_id": "es_intro"}).get("ok", false)), "the first stage is confirmed")
	controller.open_episode(iid, "es_channel_01")
	await settle()
	check(controller.route == "story" and str(controller.route_context.series) == "fg01", "from the first channel on the radio opens the letters, not exercises")
	var reader: Control = controller.screen
	check(reader.find_child("StoryText", true, false) != null and reader.find_child("StoryChoices", true, false) != null, "the first letter has a text and a choice")
	reader.finish_reveal()
	await capture("story_letter")
	_button(reader, "StoryNext").pressed.emit()
	await settle(2)
	check(Story.progress(app.game_state, "fg01").done == 0, "without a choice the letter does not go on")
	_button(reader, "StoryOption_moon").pressed.emit()
	await settle()
	check(controller.screen.find_child("StoryReaction", true, false) != null, "the hero's reaction to the choice is on screen at once")
	controller.screen.finish_reveal()
	await capture("story_choice")
	(controller.screen.find_child("StoryReply_greet", true, false) as TextEdit).text = "¡Bienvenidos!"
	controller.screen.inputs["c1s1:greet"] = "¡Bienvenidos!"
	_button(controller.screen, "StoryNext").pressed.emit()
	await settle(4)
	check(Story.progress(Save.load_game(), "fg01").done == 1, "the first letter is saved")
	check(controller.screen.find_child("StoryEcho", true, false) != null, "the hero answers her reply at the top of the next letter")
	var text_now := (controller.screen.find_child("StoryText", true, false) as Label).text
	check(text_now.contains("Лунный столик"), "the next letter already knows what she called the café")
	controller.screen.finish_reveal()
	await capture("story_next_letter")
	_button(controller.screen, "StoryNext").pressed.emit()
	await settle(2)
	check(Story.progress(app.game_state, "fg01").done == 1, "a reply is optional, a choice is not")
	# Back at the mission page: the status is for the adult to set.
	controller.open_mission("FG01")
	await settle()
	check(controller.route == "mission" and _button(controller.screen, "MissionPrimaryAction").text.begins_with("Продолжить эфир"), "the mission page invites to continue the air")
	check(controller.screen.find_child("StoryProgressNote", true, false) != null, "the page says how many letters are heard")
	await capture("story_mission_page")
	# Play the rest of the letters.
	for scene in SG.scenes("fg01"):
		if Story.scene_done(app.game_state, "fg01", str(scene.id)):
			continue
		var choice_id := str(scene.choice.options[0].id) if not scene.get("choice", {}).is_empty() else ""
		var replies := {"hello": "¡Hola, valle!", "news": "Hoy hay sol", "bye": "¡Hasta mañana!"} if str(scene.id) == "c5s1" else {}
		var told := _run("story_scene_done", {"series": "fg01", "scene": str(scene.id), "choice": choice_id, "replies": replies})
		check(bool(told.get("ok", false)), "letter %s is played" % str(scene.id))
	controller.refresh_world()
	check(Story.finished(app.game_state, "fg01"), "all fourteen letters are heard")
	check(Collections.list_works(app.game_state).any(func(w): return str(w.get("title", "")).contains("Журнал эфира")), "the journal of the air is saved among her works")
	var inst := UI.instance_for(app.game_state, "FG01")
	check(str(inst.status) != "COMPLETED", "hearing the story does not complete the mission: that is the adult's call")
	check(not controller._mission_finished(inst), "no finale yet")
	controller.open_mission("FG01")
	await settle()
	check(controller.screen.find_child("StoryProgressNote", true, false).text.contains("осталось отметить прогресс"), "the page says the air is heard and the adult confirms the rest")
	check(_button(controller.screen, "MissionPrimaryAction").text.begins_with("Журнал эфира"), "the story is always available as a journal")
	# The adult confirms in the family panel: two taps, all at once.
	controller.open_family_tools()
	await settle()
	controller.screen.tab = 4
	controller.screen._build()
	await settle()
	check(_button(controller.screen, "AttestAll") != null, "the family panel has «confirm everything at once» on the Spanish tab")
	await capture("story_adult_tab")
	_button(controller.screen, "AttestAll").pressed.emit()
	await settle()
	check(Story.finished(app.game_state, "fg01") and A.get_instance(app.game_state, iid).status != "COMPLETED", "the first tap only arms the button")
	check(_button(controller.screen, "AttestAll").text.contains("Да, подтверждаю"), "the button asks once more")
	_button(controller.screen, "AttestAll").pressed.emit()
	await settle(5)
	check(A.get_instance(Save.load_game(), iid).status == "COMPLETED", "the second tap confirms the whole mission")
	check(controller.route == "finale" and str(controller.route_context.finale_key) == "FG01", "now that the air is heard and the adult has confirmed, the finale plays")
	await capture("story_finale")
	app.queue_free()
	await settle()
