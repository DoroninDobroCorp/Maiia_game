extends SceneTree

## Full authored journeys using production services and real atomic persistence.
## All filesystem state belongs to one fresh OS temporary directory.
const Content = preload("res://scripts/services/adventure_content.gd")
const A = preload("res://scripts/services/adventure_service.gd")
const C = preload("res://scripts/services/collection_service.gd")
const Commit = preload("res://scripts/services/activity_commit_service.gd")
const Rules = preload("res://scripts/domain/adventure_rules.gd")
const Quests = preload("res://scripts/services/quest_service.gd")
const Progress = preload("res://scripts/services/progress_service.gd")
const Save = preload("res://scripts/services/save_service.gd")
const Library = preload("res://scripts/services/content_library_service.gd")
const Launcher = preload("res://scripts/services/launch_service.gd")
const Game = preload("res://learning_projects/station_light/game_state.gd")

const PROFILE := "journey_test"
var passed := 0
var failed := 0
var root_dir := ""
var state: Dictionary = {}
var instance_ids: Dictionary = {}
var selected_works: Dictionary = {}
var launch_entry_id := ""
var launch_service: RefCounted

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String, detail: Variant = "") -> void:
	if value:
		passed += 1
	else:
		failed += 1
		printerr("FAIL: ", label, " ", detail)

func _run() -> void:
	root_dir = OS.get_temp_dir().path_join("sur_journeys_" + Crypto.new().generate_random_bytes(8).hex_encode())
	DirAccess.make_dir_recursive_absolute(root_dir)
	Save.use_test_storage(root_dir.path_join("journey_"))
	state = Save.get_default_state()
	state.s00_progress.station_awakened = true
	A.ensure_adventures(state)
	C.ensure_collections(state)
	for quest in Content.quests():
		var published := Quests.approve_and_publish(state, quest, "parent_local")
		check(published.ok, "Explicitly publish exact authored revision " + str(quest.quest_id), published)
		if not published.ok: continue
		var accepted := A.accept(state, quest.quest_id, quest.revision, PROFILE, "home")
		check(accepted.ok, "Accept independent storyline " + str(quest.quest_id), accepted)
		if accepted.ok: instance_ids[quest.quest_id] = accepted.instance.instance_id
	if instance_ids.size() != 3:
		_finish()
		return
	check(_xp() == 0, "Accepting all stories awards zero XP")
	check(not A.complete_chapter(state, {}, PROFILE).ok, "Chapter finale cannot precede completed stories")
	_save_reload("Three concurrent accepted snapshots")
	_secrets()
	await _launch_without_completion()
	_play_es()
	check(_xp() == 40, "Full Spanish journey awards exactly40")
	_play_game()
	check(_xp() == 100, "Game journey adds exactly60")
	_play_water()
	check(_xp() == 140, "Water journey adds exactly40; chapter total140")
	_chapter_and_history()
	_imported_family_mission()
	_finish()

func _finish() -> void:
	Save.cleanup_test_storage()
	Save.restore_default_storage()
	Launcher._remove_tree(root_dir)
	print("AUTHORED JOURNEYS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _xp() -> int:
	var total := 0
	for value in Progress.get_profile_xp(state, PROFILE).values(): total += int(value)
	return total

func _save_reload(label: String) -> void:
	check(Save.save_game(state), "Save isolated checkpoint: " + label, Save.get_last_error())
	var before := state.duplicate(true)
	state = Save.load_game()
	var difference := _difference(before.get("adventures", {}), state.get("adventures", {}), "adventures")
	if difference.is_empty(): difference = _difference(before.get("collections", {}), state.get("collections", {}), "collections")
	check(difference.is_empty(), "Reload preserves stage attempts/works: " + label, difference)

func _difference(before: Variant, after: Variant, location: String) -> String:
	if before is Dictionary and after is Dictionary:
		for key in before:
			if not after.has(key): return location + "." + str(key) + " removed"
			var child := _difference(before[key], after[key], location + "." + str(key))
			if not child.is_empty(): return child
		return "" # Default metadata may add fields, but cannot replace old facts.
	if before is Array and after is Array:
		if before.size() != after.size(): return location + " array size changed"
		for index in before.size():
			var child := _difference(before[index], after[index], location + "[%d]" % index)
			if not child.is_empty(): return child
		return ""
	return "" if before == after else location + ": " + str(before) + " -> " + str(after)

func _quest(qid: String) -> Dictionary:
	return A.get_instance(state, str(instance_ids[qid])).quest_snapshot

func _stage(qid: String, sid: String) -> Dictionary:
	return Rules.stage_by_id(_quest(qid), sid)

func _attempt(qid: String, sid: String, iid: String, response: Dictionary) -> Dictionary:
	var result := A.record_attempt(state, str(instance_ids[qid]), sid, iid, response)
	check(result.get("ok", false), "Attempt stored " + sid + "/" + iid, result)
	return result

func _response(definition: Dictionary) -> Dictionary:
	var data: Dictionary = definition.config
	var response := {"fields": {}, "assistance": "test_fixture"}
	for f in data.get("fields", []):
		response.fields[f.id] = _field_text(str(f.id))
	match str(definition.type):
		"match_cards":
			response["pairs"] = data.accepted_pairs.duplicate(true)
			if data.has("lexeme_ids"):
				# This recorded attempt really has six assisted pairs and fourteen
				# unassisted pairs; evidence cannot simply assert a passed test.
				response["assisted_ids"] = ["card_15", "card_16", "card_17", "card_18", "card_19", "card_20"]
		"order_fragments": response["order"] = data.accepted_orders[0].duplicate()
		"inspect_reveal": response["revealed_ids"] = data.required_detail_ids.duplicate()
		"assemble_selection", "exhibit_composition":
			var chosen: Array = data.get("required_ids", []).duplicate()
			for value in data.get("items", data.get("choices", [])):
				if chosen.size() < int(data.min_selected) and not chosen.has(value.id): chosen.append(value.id)
			response["selected_ids"] = chosen
		"scripted_dialogue":
			var nodes: Dictionary = {}
			for node in data.nodes: nodes[node.node_id] = node
			var current: String = data.start_node_id
			var selected: Array = []
			for _step in range(50):
				if nodes[current].get("terminal", false): break
				for choice in nodes[current].choices:
					if choice.correct:
						selected.append(choice.id)
						current = choice.next_node_id
						break
			response["choice_ids"] = selected
			response["node_id"] = current
		"compare_observations":
			response["category_id"] = "movement"
			response["comparison"] = "В тестовой речной записи вода огибала камень, а в водопадной падала с уступа."
		"real_world_step": response["note"] = _field_text("observation")
	return response

func _field_text(id: String) -> String:
	var known := {"hero": "Хранитель огоньков", "goal": "Собрать три огонька для станции", "prediction": "При скорости250 путь за секунду станет длиннее, чем при220", "observation": "В тестовой версии предмет исчез один раз и счётчик вырос на1", "own_contribution": "В тестовой авторской версии выбрана скорость250 и проверено движение", "own_change": "Скорость изменена с220 на250", "causal_explanation": "За одинаковое время герой проходит большее расстояние", "layout": "Огоньки расположены треугольником", "win_message": "Три огонька зажгли станцию", "viewer_observation": "Первый тестовый игрок попросил более заметную кнопку повторения", "shared_work": "Основа подготовлена разработчиком, настройку проверили вместе", "source_version": "Тестовая1.0, самостоятельная копия исходников", "difference": "У реки вода огибала камень, у водопада падала с уступа", "question": "Как движется вода?", "family_plan": "Тестовые записи: Río Azul и водопад ближнего каталога", "recording_method": "Бумажная запись и совместный рассказ после возвращения", "atlas_choice": "rio_azul", "family_visit": "Явная тестовая семейная отметка состоявшегося выхода", "review_note": "Применены14 слов без карточки;6 с помощью", "title": "Тестовая выставка первых открытий", "callsign": "Тестовый маяк"}
	return str(known.get(id, "Собственная тестовая заметка: " + id))

func _attempt_stage(qid: String, sid: String) -> void:
	var quest := _quest(qid)
	for iid in _stage(qid, sid).interaction_ids:
		var result := _attempt(qid, sid, str(iid), _response(quest.adventure.interactions[iid]))
		check(result.get("success", false), "Meaningful authored response succeeds " + str(iid), result)

func _submit_finish(qid: String, sid: String, evidence: Dictionary, reject_once: bool = false) -> Dictionary:
	var iid: String = instance_ids[qid]
	var stage := _stage(qid, sid)
	var before_xp := _xp()
	var report := evidence.duplicate(true)
	report["attested"] = true
	var verifier := Callable(launch_service, "inspect_entry")
	var result := Commit.commit_stage(state, iid, sid, report, "player_self", Callable(), verifier)
	check(result.get("ok", false), "Submit exact current stage " + sid, result)
	if not result.get("ok", false): return result
	if stage.completion_policy == "joint_review":
		check(result.get("awaiting_review", false) and _xp() == before_xp, "Submission waits for explicit family review " + sid)
		check(not Commit.review_stage(state, iid, sid, true, "", "player_self").ok, "Child cannot review own report " + sid)
		_save_reload("Awaiting review " + sid)
		if reject_once:
			var old_attempts: Array = A.get_progress(state, iid).stages[sid].attempts.duplicate(true)
			var returned := Commit.review_stage(state, iid, sid, false, "Проверим ещё раз чистый перезапуск", "parent_local")
			check(returned.ok and A.get_progress(state, iid).stages[sid].status == "IN_PROGRESS" and _xp() == before_xp, "Return for improvement preserves prior awards")
			check(A.get_progress(state, iid).stages[sid].attempts == old_attempts, "Review does not discard material")
			_save_reload("Returned functional check")
			result = Commit.commit_stage(state, iid, sid, report, "player_self", Callable(), verifier)
			check(result.get("awaiting_review", false), "Corrected report resubmitted")
		var criteria: Array = []
		for _criterion in stage.criteria: criteria.append(true)
		result = Commit.review_stage(state, iid, sid, true, "Тестовая семья проверила каждый функциональный критерий", "parent_local", Callable(), {"criteria": criteria, "assistance": "together"}, verifier)
		check(result.get("ok", false), "Review and atomic completion " + sid, result)
	if result.get("ok", false):
		check(A.get_progress(state, iid).stages[sid].status == "COMPLETED", "Stage actually completed " + sid)
		check(_xp() - before_xp == int(stage.budget_share), "Only allocated stage share awarded " + sid)
		var count: int = state.phase_b.award_events.size()
		var replay := Commit.commit_stage(state, iid, sid, report, "player_self", Callable(), verifier)
		check(replay.ok and not replay.applied and count == state.phase_b.award_events.size(), "Repeated completion idempotent " + sid)
		if not str(result.get("work_id", "")).is_empty(): selected_works[qid] = result.work_id
	return result

func _secrets() -> void:
	for secret in Content.secrets():
		var found := A.discover_secret(state, secret.secret_id, PROFILE)
		check(found.ok and found.applied, "Optional secret found before learning " + str(secret.secret_id))
		var work_count := C.list_works(state, PROFILE).size()
		var grants: int = state.adventures.grants.size()
		var replay := A.discover_secret(state, secret.secret_id, PROFILE)
		check(replay.ok and not replay.applied and C.list_works(state, PROFILE).size() == work_count and state.adventures.grants.size() == grants, "Secret repeat creates neither duplicate work nor grant")
	check(A.get_secrets(state, PROFILE).size() == 6 and A.get_secrets(state, "other_profile").is_empty(), "Secret history is profile scoped")
	check(_xp() == 0, "All six optional finds give zero skill XP")
	_save_reload("Six finds and decoration")

func _launch_without_completion() -> void:
	var launcher = Launcher.new(root_dir.path_join("launch_registry"))
	launch_service = launcher
	var prepared: Dictionary = launcher.prepare_starter_project()
	check(prepared.ok, "Prepare actual learner project in isolated storage")
	if not prepared.ok: return
	var lesson_path := str(prepared.project_dir).path_join("lesson.json")
	var lesson: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(lesson_path))
	lesson.speed = 250
	lesson.author_note = "Тестовая причинная правка: скорость220→250"
	var file := FileAccess.open(lesson_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(lesson, "\t"))
	file.close()
	var before := state.duplicate(true)
	var registered: Dictionary = launcher.register_project(prepared.project_dir, "Тестовая1.0", "parent_local", PROFILE)
	check(registered.ok and not registered.entry.demonstration_only, "Register actual changed learner version")
	if not registered.ok: return
	launch_entry_id = registered.launch_entry_id
	var launched: Dictionary = launcher.launch(launch_entry_id, PROFILE)
	check(launched.ok and not launched.completion_evidence, "Separate learner starts without claiming completion")
	if launched.ok:
		await create_timer(1.0).timeout
		if OS.is_process_running(launched.pid): OS.kill(launched.pid)
	check(state == before and _xp() == 0, "Actual registration and launch cannot alter quests, grants or XP")
	check(A.get_progress(state, instance_ids.FG11).stages.game_concept.status == "AVAILABLE", "Launching full game leaves even concept incomplete")

func _play_es() -> void:
	var iid: String = instance_ids.FG01
	var quest := _quest("FG01")
	# Wrong semantic answer is saved; restart, help and correction preserve history.
	var wrong := _attempt("FG01", "es_intro", "es_01_hello", {"choice_ids": ["choice_3"], "node_id": "end"})
	check(not wrong.get("success", true), "Incorrect greeting cannot pass")
	check(not Commit.commit_stage(state, iid, "es_intro", {"note": "Нажатие готово"}).ok, "Fake completion before semantic response rejected")
	_save_reload("Incorrect greeting")
	var hint := A.request_help(state, iid, "es_intro", "es_01_hello", 2)
	check(hint.ok and not str(hint.hint).is_empty(), "Contextual help after failed attempt")
	check(A.pause(state, iid).ok, "Pause Spanish during active scene")
	_save_reload("Paused Spanish")
	check(A.resume(state, iid).ok, "Resume after restart with failed attempt intact")
	for stage in quest.adventure.stages:
		var sid: String = stage.stage_id
		_attempt_stage("FG01", sid)
		for envelope in quest.adventure.envelopes:
			var included: bool = envelope.number == 1 if sid == "es_intro" else envelope.channel_id == sid
			if included:
				var words := A.record_lexemes(state, iid, envelope.lexeme_ids, "used", "contextual_test_scene")
				check(words.ok, "Record introduced lexemes after their scene " + str(envelope.number))
		var evidence := {"note": "Тестовая запись эфира", "choices": {"broadcast_theme": "valley"}}
		if sid == "es_final":
			var config: Dictionary = quest.adventure.interactions.es_mixed_check.config
			evidence["sample_lexeme_ids"] = config.lexeme_ids.duplicate()
			evidence["unassisted_lexeme_ids"] = config.lexeme_ids.slice(0, 14)
			var forged := evidence.duplicate(true)
			forged.unassisted_lexeme_ids = config.lexeme_ids.duplicate()
			check(not Commit.commit_stage(state, iid, sid, forged).ok, "Cannot claim20 unassisted from recorded14 result")
		_submit_finish("FG01", sid, evidence)
		if sid == "es_intro":
			var progress := A.get_progress(state, iid)
			check(_xp() == 0 and progress.lexemes.size() == 5 and C.get_work(state, progress.stages.es_intro.work_id, PROFILE).size() > 0, "First five words produce first personal work without XP")
			check(progress.stages.es_intro.attempts.size() == 3 and progress.stages.es_intro.help_history.size() == 1, "Failure and hint remain after corrected completion")
		if sid == "es_channel_04": check(_xp() == 32, "Four channels grant exactly32 before final")
	check(A.get_progress(state, iid).lexemes.size() == 100, "Finished personal set contains exactly100 lexemes")
	check(A.get_instance(state, iid).status == "COMPLETED" and int(A.get_instance(state, iid).awarded_budget) == 40, "Spanish lifecycle completes at40")
	_save_reload("Completed Spanish with frozen dictionary")

func _play_game() -> void:
	var iid: String = instance_ids.FG11
	var game = Game.new({"speed": 250, "stage": 5})
	var start: Vector2 = game.hero_position
	game.move_hero(Vector2.RIGHT, 0.1)
	var movement_ok: bool = game.hero_position.distance_to(start) > 24.9
	game.restart()
	var collection_ok := true
	var no_early_win := true
	for index in range(3):
		var distance: Vector2 = game.light_positions[index] - game.hero_position
		game.move_hero(distance.normalized(), distance.length() / game.speed)
		collection_ok = collection_ok and game.count == index + 1 and not game.try_collect_light(index)
		if index < 2: no_early_win = no_early_win and not game.has_won
	var victory_ok: bool = game.has_won and no_early_win
	game.restart()
	var restart_ok: bool = game.count == 0 and not game.has_won and game.hero_position == game.hero_start and game.collected == [false, false, false]
	check(movement_ok and collection_ok and victory_ok and restart_ok, "Evidence derived from actual learner model full cycle")
	for stage in _quest("FG11").adventure.stages:
		var sid: String = stage.stage_id
		_attempt_stage("FG11", sid)
		var evidence := {"note": "Тестовая проверка отдельной версии " + str(stage.get("version_label", "замысел")), "own_contribution": "Выбрана скорость250 и проверен путь героя", "own_change": "Изменили скорость220→250", "causal_explanation": "За0.1секунды путь стал25 вместо22", "demo_only": false, "launch_entry_id": launch_entry_id, "checks": {"launches": not launch_entry_id.is_empty(), "movement": movement_ok, "collection": collection_ok, "win": victory_ok, "clean_restart": restart_ok, "own_improvement": movement_ok}}
		if sid == "game_move":
			var demo := evidence.duplicate(true)
			demo.demo_only = true
			check(not Commit.commit_stage(state, iid, sid, demo).ok, "Ready-made demonstration cannot finish movement")
		if sid == "game_goal":
			var before := state.duplicate(true)
			var rejected := Commit.commit_stage(state, iid, sid, evidence, "player_self", func(_candidate): return false)
			check(not rejected.ok and rejected.reason == "save_failed" and state == before, "Write failure leaves submission, XP and works unchanged")
			_save_reload("Successful prior stages after write failure")
		_submit_finish("FG11", sid, evidence, sid == "game_restart")
	check(A.get_instance(state, iid).status == "COMPLETED" and A.get_instance(state, iid).awarded_budget == 60, "All six game stages finish at60")
	var work := C.get_work(state, selected_works.FG11, PROFILE)
	check(work.kind == "game" and work.versions.size() == 5, "Game work keeps five historical project versions")
	check(work.versions[-1].content.launch_entry_id == launch_entry_id, "Premiere work links registered version only by ID")
	_save_reload("Completed game and all five work versions")

func _play_water() -> void:
	var iid: String = instance_ids.FG08
	# Deliberately visit waterfall before river to prove branches are independent.
	for sid in ["water_intro", "water_plan", "water_fall", "water_river", "water_compare", "water_exhibit"]:
		_attempt_stage("FG08", sid)
		var note := "Тестовая заметка о реке: вода огибала камень" if sid == "water_river" else "Тестовая заметка о водопаде: вода падала с уступа"
		var evidence := {"note": note, "visited": true, "home_materials": false, "comparison": "У реки вода огибала камень, у водопада падала сверху", "choices": {"question": "movement"}}
		var stage := _stage("FG08", sid)
		if not stage.atlas_unlock_ids.is_empty(): evidence["atlas_location_id"] = stage.atlas_unlock_ids[0]
		if sid == "water_fall":
			var home := evidence.duplicate(true)
			home.home_materials = true
			check(not Commit.commit_stage(state, iid, sid, home).ok, "Home materials cannot replace actual visit")
			var wrong_location := evidence.duplicate(true)
			wrong_location.atlas_location_id = "rio_azul"
			check(not Commit.commit_stage(state, iid, sid, wrong_location).ok, "Cannot open unrelated atlas point with visit")
		_submit_finish("FG08", sid, evidence)
		if sid == "water_fall":
			check(state.phase_c.atlas_unlocked_by_profile[PROFILE] == ["waterfalls"], "Waterfall opens alone when visited first")
			check(A.get_progress(state, iid).stages.water_river.status == "AVAILABLE", "River remains available independently")
			_save_reload("Waterfall first, river pending")
	check(state.phase_c.atlas_unlocked_by_profile[PROFILE].has("rio_azul") and state.phase_c.atlas_unlocked_by_profile[PROFILE].size() == 2, "Both agreed locations open only after distinct observations")
	var progress := A.get_progress(state, iid)
	check(progress.stages.water_river.work_id != progress.stages.water_fall.work_id, "Two observations preserved as distinct pages")
	check(A.get_instance(state, iid).status == "COMPLETED" and A.get_instance(state, iid).awarded_budget == 40, "Water lifecycle completes at40")
	_save_reload("Water diptych ready")

func _chapter_and_history() -> void:
	check(A.chapter_status(state, PROFILE).available, "Three completed adventures unlock chapter finale")
	var missing := A.complete_chapter(state, {"FG01": selected_works.get("FG01", "")}, PROFILE)
	check(not missing.ok, "Finale needs chosen works from all three storylines")
	var selected := selected_works.duplicate(true)
	selected.title = "Тихий тестовый вечер"
	selected.quiet = true
	var total := _xp()
	var completed := A.complete_chapter(state, selected, PROFILE)
	check(completed.ok and completed.applied and _xp() == total, "Quiet chapter finale grants no additional XP")
	var work_count := C.list_works(state, PROFILE).size()
	var grants: int = state.adventures.grants.size()
	var replay := A.complete_chapter(state, selected, PROFILE)
	check(replay.ok and not replay.applied and _xp() == 140 and C.list_works(state, PROFILE).size() == work_count and state.adventures.grants.size() == grants, "Replaying finale does not duplicate archive or rewards")
	_save_reload("Completed chapter and optional discoveries")
	check(A.chapter_status(state, PROFILE).completed and A.get_secrets(state, PROFILE).size() == 6, "Chapter and secrets survive final restart")
	check(C.list_works(state, "other_profile").is_empty(), "Journey materials do not leak into another profile")
	check(Progress.get_profile_xp(state, "player_01").values().all(func(value): return int(value) == 0), "Real/default profile untouched")
	for qid in instance_ids:
		var quest := _quest(qid)
		check(quest.schema_version == 2 and quest.revision == 2 and not quest.adventure.interactions.is_empty(), "Frozen content still present after archive reload " + str(qid))

func _imported_family_mission() -> void:
	var before := _xp()
	var package := Content.example_package()
	var imported := Library.import_package(state, package)
	check(imported.get("ok", false), "PACK04 import external silhouettes schema2 package atomically", imported)
	if not imported.get("ok", false): return
	var draft := Library.get_template(state, "AR02", 1)
	check(not draft.is_empty() and draft.content_status == "DRAFT", "Imported family quest remains draft")
	check(not A.accept(state, "AR02", 1, PROFILE, "home").ok, "Imported draft cannot be started before explicit publication")
	var publication := Quests.approve_and_publish(state, draft, "parent_local")
	check(publication.ok, "Publish reviewed silhouettes revision through existing lifecycle", publication)
	if not publication.ok: return
	var visible := A.list_adventures(state, PROFILE, {"search": "силуэта"})
	check(visible.size() == 1 and visible[0].quest_id == "AR02" and visible[0].status == "AVAILABLE", "New package appears in catalog search without scene changes")
	var started := A.accept(state, "AR02", 1, PROFILE, "home")
	check(started.ok, "Accept the imported family mission", started)
	if not started.ok: return
	instance_ids["AR02"] = started.instance.instance_id
	var snapshot := _quest("AR02")
	check(snapshot.adventure.stages.size() == 3, "External package supplies all three required stages")
	for stage in snapshot.adventure.stages:
		_attempt_stage("AR02", stage.stage_id)
		var evidence := {"note": "Тестовые силуэты чашки: высокая, широкая, с большой ручкой. Для вывески выбрана широкая: ручка видна издалека.", "fields": {"variants_note": "Высокая чашка; широкая чашка; чашка с большой ручкой", "reason": "Широкую чашку легко узнать по ручке"}, "choices": {"silhouette": "second"}}
		_submit_finish("AR02", stage.stage_id, evidence)
	var instance := A.get_instance(state, instance_ids.AR02)
	check(instance.status == "COMPLETED" and instance.awarded_budget == 20 and _xp() == before + 20, "Imported mission completes with its own20 budget")
	var works := C.list_works(state, PROFILE, {"quest_id": "AR02"})
	check(works.size() == 3, "Imported quest has saved sample, three-variant sheet and chosen exhibit")
	var final_work := C.get_work(state, selected_works.AR02, PROFILE)
	check(final_work.kind == "image" and final_work.source.recipe.recipe_id == "silhouette_frame", "Existing frame recipe presents the new authored result")
	visible = A.list_adventures(state, PROFILE, {"search": "силуэта", "status": "COMPLETED"})
	check(visible.size() == 1 and visible[0].quest_id == "AR02", "Completed external mission remains searchable")
	_save_reload("Published imported silhouettes and final work")
	check(C.get_work(state, selected_works.AR02, PROFILE).versions[0].content.fields.reason == "Широкую чашку легко узнать по ручке", "Reason for chosen silhouette survives restart")
