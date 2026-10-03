extends SceneTree

## Child-facing entry, feedback and continuation. Isolated state, no player files.
const Content = preload("res://scripts/services/adventure_content.gd")
const Save = preload("res://scripts/services/save_service.gd")
const Quests = preload("res://scripts/services/quest_service.gd")
const Adventures = preload("res://scripts/services/adventure_service.gd")
const Episode = preload("res://scripts/presentation/adventure_episode.gd")
var failures: Array[String] = []
var checks := 0
var state: Dictionary
var episode: Control
var last_result: Dictionary
var emitted: Array = []
var fail_next := false
var closes := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
	print("EXPERIENCE %d %s" % [checks,label])
func settle() -> void:
	for _i in range(4): await process_frame
func visible_control(control: Control) -> bool:
	if not control.is_visible_in_tree(): return false
	var rect := control.get_global_rect()
	var clip := root.get_visible_rect()
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents:
			clip = clip.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return clip.encloses(rect)
func button(label: String) -> Button:
	for control in episode.find_children("*", "Button", true, false):
		if control.text == label: return control
	return null
func dispatch(operation: String, payload: Dictionary) -> void:
	emitted.append({"op":operation,"payload":payload.duplicate(true)})
	if fail_next:
		fail_next = false
		last_result = {"ok":false,"reason":"save_failed"}
		episode.show_result(last_result)
		return
	var candidate := state.duplicate(true)
	last_result = Adventures.dispatch(candidate, operation, payload)
	if bool(last_result.get("ok", false)): state = candidate
	episode.show_result(last_result)
	if bool(last_result.get("ok", false)) and operation in ["stage_submit","stage_review"]:
		var view := state.duplicate(true)
		view["_adventure_ui"] = {"instance_id":episode.instance_id,"stage_id":episode.stage_id,"quest":episode.quest}
		episode.setup(view)
func open_story(qid: String) -> void:
	state = Save.get_default_state()
	state.s00_progress.station_awakened = true
	var quest := Content.get_quest(qid)
	Quests.approve_and_publish(state,quest)
	var accepted := Adventures.accept(state,qid,int(quest.revision))
	var view := state.duplicate(true)
	view["_adventure_ui"] = {"quest":quest,"instance_id":accepted.instance.instance_id,"stage_id":quest.adventure.stages[0].stage_id}
	episode = Episode.new()
	root.add_child(episode)
	episode.setup(view)
	episode.command_requested.connect(dispatch)
func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--render"): return
	DirAccess.make_dir_recursive_absolute("/tmp/sur-experience-qa")
	await settle()
	root.get_texture().get_image().save_png("/tmp/sur-experience-qa/" + label + ".png")
func run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	for scale in [1.0,1.25]:
		root.content_scale_factor = scale
		for qid in ["FG01","FG11","FG08"]:
			open_story(qid)
			await settle()
			var action: Button
			match qid:
				"FG01": action = button("Hola. Sí, gracias.")
				"FG11":
					var options: Array = episode.area.find_children("*", "CheckBox", true, false)
					if not options.is_empty(): action = options[0]
				"FG08":
					for candidate in episode.area.find_children("*", "Button", true, false):
						if candidate.text.begins_with("Открыть · "): action = candidate; break
			check(action != null and visible_control(action), "%s first real action visible without scrolling at %.0f%%" % [qid,scale*100])
			if qid == "FG01":
				check(visible_control(button("Hola. No, gracias.")) and visible_control(button("Gracias. Nombre.")), "All radio replies remain visible, including declining the callsign at %.0f%%" % [scale*100])
			if qid == "FG11":
				var choices: Array = episode.area.find_children("*", "CheckBox", true, false)
				choices[0].button_pressed = true
				choices[1].button_pressed = true
				check(not choices[0].button_pressed and episode.response.selected_ids.size() == 1,"Single-choice theme switches cleanly without a false too-many-choices error")
			await capture("%s-%d-start" % [qid,int(scale*100)])
			episode.free()
			await settle()
	await radio_journey()
	print("ADVENTURE EXPERIENCE: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func primary() -> Button:
	return episode.find_child("EpisodePrimaryAction",true,false) as Button

func radio_journey() -> void:
	root.content_scale_factor = 1.25
	open_story("FG01")
	await settle()
	var before := state.duplicate(true)
	button("Gracias. Nombre.").pressed.emit()
	check(state == before and episode.feedback.visible and episode.feedback.text.contains("hola"), "Wrong reply explains the word without penalty or progress")
	await capture("radio-helpful-mistake")
	episode._hint()
	check(episode.help_button.text.contains("1/3") and episode.hint_label.visible and episode.hint_label.text == episode._interaction().hints[0], "Hint counter and authored clue agree on screen")
	emitted.clear()
	var before_attempt := state.duplicate(true)
	fail_next = true
	button("Hola. Sí, gracias.").pressed.emit()
	check(state == before_attempt and not primary().disabled and primary().text == "Повторить проверку", "Failed automatic dialogue save retains the answer and a reachable retry")
	emitted.clear()
	primary().grab_focus()
	primary().pressed.emit()
	await settle()
	check(root.gui_get_focus_owner() == primary(), "Keyboard focus follows continuation rather than jumping to Close after success")
	check(bool(last_result.get("success",false)) and emitted.size() == 1, "Answering Nora validates the real dialogue without an extra check click")
	var iid := str(episode.instance_id)
	check(state.adventures.progress[iid].lexemes.size() == 5, "First reply actually adds five words without manual self-credit")
	check(primary().text == "Продолжить →" and visible_control(primary()), "Success offers a visible next scene instead of premature stage submission")
	check(episode.area.find_children("*","Label",true,false).any(func(label): return label.text.contains("Ты поздоровалась")), "Success uses Nora's concrete authored response")
	await capture("radio-first-answer-saved")
	primary().pressed.emit()
	await settle()
	check(str(episode._interaction().interaction_id) == "es_callsign", "Primary continuation reaches the child's callsign choice")
	var choices: Array = episode.area.find_children("*","CheckBox",true,false)
	if not choices.is_empty(): choices[0].button_pressed = true
	for field in episode.response_fields.values(): field.text = "Маяк вечерних искр"
	var selected_field := str(episode.response_fields.keys()[0]) if not episode.response_fields.is_empty() else ""
	episode.closed.connect(func(): closes += 1)
	fail_next = true
	button("Продолжить позже").pressed.emit()
	check(closes == 0 and not selected_field.is_empty() and episode.response_fields[selected_field].text == "Маяк вечерних искр", "Stop-for-today retains the child's choice and text if saving fails")
	button("Продолжить позже").pressed.emit()
	check(closes == 1 and str(last_result.get("reason", "")) != "save_failed", "Stop-for-today closes only after a successful draft save")
	var quest: Dictionary = episode.quest
	episode.free()
	episode = Episode.new()
	root.add_child(episode)
	var view := state.duplicate(true)
	view["_adventure_ui"] = {"quest":quest,"instance_id":iid,"stage_id":"es_intro"}
	episode.setup(view)
	episode.command_requested.connect(dispatch)
	await settle()
	check(str(episode._interaction().interaction_id) == "es_callsign" and episode.response_fields[selected_field].text == "Маяк вечерних искр", "Returning opens the saved scene and exact personal text")
	primary().pressed.emit()
	check(bool(last_result.get("success",false)), "Personal callsign is validated through the actual primary button")
	primary().pressed.emit()
	await settle()
	check(str(state.adventures.progress[iid].stages.es_intro.status) == "COMPLETED", "The first episode finishes through visible child controls")
	var work_button := button("Посмотреть мою работу →")
	check(work_button != null and visible_control(work_button), "Completed episode puts the child's real saved work within reach")
	var opened: Array = []
	episode.work_requested.connect(func(id): opened.append(id))
	if work_button != null: work_button.pressed.emit()
	check(opened.size() == 1 and state.collections.works.has(opened[0]), "Reward opens a real owned archive work, not an empty collection")
	await capture("radio-my-first-work")
	var committed := state.duplicate(true)
	var command_count := emitted.size()
	button("Открыть сцену ещё раз").pressed.emit()
	episode._check_current()
	check(state == committed and emitted.size() == command_count, "Replay remains local and never repeats rewards")
	episode.free()
