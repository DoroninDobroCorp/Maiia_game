extends SceneTree

## Isolated metadata and headless lifecycle tests. Never opens the real save.
const A = preload("res://scripts/services/adventure_service.gd")
const C = preload("res://scripts/services/collection_service.gd")
const Commit = preload("res://scripts/services/activity_commit_service.gd")
const Rules = preload("res://scripts/domain/adventure_rules.gd")
const Content = preload("res://scripts/services/adventure_content.gd")
const Quests = preload("res://scripts/services/quest_service.gd")
const Save = preload("res://scripts/services/save_service.gd")
const Repository = preload("res://scripts/services/content_repository.gd")
const Progress = preload("res://scripts/services/progress_service.gd")

var passed := 0
var failed := 0
var writes := 0

func _init() -> void:
	Save.use_test_storage("user://adventures_core_%d_" % OS.get_process_id())
	_test_rules()
	_test_transactions()
	_test_evidence_boundaries()
	_test_choice_context()
	_test_authored_chapter()
	_test_migration()
	_test_superseded_submission()
	_test_collections()
	_test_room_lifecycle()
	_test_archive_search()
	_test_profiles()
	Save.cleanup_test_storage()
	Save.restore_default_storage()
	print("ADVENTURES CORE: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func check(value: bool, label: String, detail: Variant = "") -> void:
	if value:
		passed += 1
		print("[PASS] " + label)
	else:
		failed += 1
		print("[FAIL] " + label + " " + str(detail))

func memory_save(_candidate: Dictionary) -> bool:
	writes += 1
	return true

func failed_save(candidate: Dictionary) -> Dictionary:
	candidate["callback_touched"] = true
	return {"ok": false, "reason": "disk_full", "message": "Injected isolated failure"}

func registered_fixture(entry_id: String, profile_id: String) -> Dictionary:
	# Trusted platform-adapter test double; no user registry is opened by core tests.
	if entry_id != "isolated_test_game":
		return {"ok": false, "reason": "unknown_entry"}
	return {"ok": true, "entry": {"launch_entry_id": entry_id, "profile_id": profile_id,
		"source_archive_file": "launch_registry/versions/isolated_test_game/source.zip", "source_archive_kind": "project_source", "demonstration_only": false}}

func application_fixture(entry_id: String, profile_id: String) -> Dictionary:
	var result := registered_fixture(entry_id, profile_id)
	if bool(result.get("ok", false)):
		result.entry.source_archive_kind = "application_bundle"
	return result

func demo_fixture(entry_id: String, profile_id: String) -> Dictionary:
	var result := registered_fixture(entry_id, profile_id)
	if bool(result.get("ok", false)):
		result.entry.demonstration_only = true
	return result

func fresh() -> Dictionary:
	var state := Save.get_default_state()
	state.s00_progress.station_awakened = true
	A.ensure_adventures(state)
	C.ensure_collections(state)
	return state

func begin(state: Dictionary, qid: String, profile: String = "player_01", definition: Dictionary = {}) -> String:
	var quest := Content.get_quest(qid) if definition.is_empty() else definition
	var published := Quests.approve_and_publish(state, quest)
	check(bool(published.get("ok", false)), "publish " + qid, published)
	if not bool(published.get("ok", false)):
		return ""
	var accepted := A.accept(state, qid, int(quest.revision), profile)
	check(bool(accepted.get("ok", false)), "accept " + qid + " " + profile, accepted)
	return str(accepted.get("instance", {}).get("instance_id", ""))

func response_for(interaction: Dictionary) -> Dictionary:
	var config: Dictionary = interaction.get("config", {})
	var response: Dictionary = {"fields": {}, "note": "Собственное наблюдение для проверки"}
	for field in config.get("fields", []):
		response.fields[str(field.id)] = "Выбрала и проверила: " + str(field.id)
	match str(interaction.type):
		"match_cards":
			response.pairs = config.accepted_pairs.duplicate(true)
			if config.has("lexeme_ids"):
				response.unassisted_lexeme_ids = config.lexeme_ids.slice(0, int(config.get("minimum_unassisted_correct", config.lexeme_ids.size())))
		"order_fragments":
			response.order = config.accepted_orders[0].duplicate(true)
		"inspect_reveal":
			response.revealed_ids = config.required_detail_ids.duplicate(true)
		"assemble_selection", "exhibit_composition":
			response.selected_ids = config.get("required_ids", []).duplicate(true)
			for item in config.get("items", config.get("choices", [])):
				if response.selected_ids.size() < int(config.get("min_selected", 1)) and not response.selected_ids.has(str(item.id)):
					response.selected_ids.append(str(item.id))
		"scripted_dialogue":
			var nodes: Dictionary = {}
			for node in config.nodes:
				nodes[str(node.node_id)] = node
			var node_id := str(config.start_node_id)
			response.choice_ids = []
			for _step in range(20):
				var node: Dictionary = nodes[node_id]
				if bool(node.get("terminal", false)):
					break
				for choice in node.get("choices", []):
					if bool(choice.get("correct", true)):
						response.choice_ids.append(str(choice.id))
						node_id = str(choice.next_node_id)
						break
			response.node_id = node_id
		"compare_observations":
			response.category_id = str(config.categories[0].id)
			response.comparison = "У реки движение вдоль берега, у водопада вниз"
	return response

func prepare_stage(state: Dictionary, iid: String, sid: String) -> Dictionary:
	var quest: Dictionary = A.get_instance(state, iid).quest_snapshot
	var stage := Rules.stage_by_id(quest, sid)
	for interaction_id in stage.interaction_ids:
		var definition: Dictionary = quest.adventure.interactions[str(interaction_id)]
		var attempt := A.record_attempt(state, iid, sid, str(interaction_id), response_for(definition))
		check(bool(attempt.get("success", false)), sid + " interaction " + str(interaction_id), attempt)
	var evidence := {"note": "Моя запись", "attested": true, "own_contribution": "Выбрала правило", "own_change": "Добавила правило", "causal_explanation": "Изменение скорости ускорило героя", "visited": true,
		"launch_entry_id": "isolated_test_game",
		"checks": {"launches": true, "movement": true, "collection": true, "win": true, "clean_restart": true, "own_improvement": true}}
	if not stage.get("atlas_unlock_ids", []).is_empty():
		evidence.atlas_location_id = stage.atlas_unlock_ids[0]
	if sid == "es_final":
		var config: Dictionary = quest.adventure.interactions.es_mixed_check.config
		evidence.sample_lexeme_ids = config.lexeme_ids.duplicate(true)
		evidence.unassisted_lexeme_ids = config.lexeme_ids.slice(0, int(config.minimum_unassisted_correct))
	return evidence

func finish_stage(state: Dictionary, iid: String, sid: String, evidence: Dictionary = {}) -> Dictionary:
	var report := prepare_stage(state, iid, sid) if evidence.is_empty() else evidence
	var result := Commit.commit_stage(state, iid, sid, report, "player_self", memory_save, registered_fixture)
	if bool(result.get("awaiting_review", false)):
		result = Commit.review_stage(state, iid, sid, true, "Проверили вместе", "parent_local", memory_save, {}, registered_fixture)
	check(bool(result.get("ok", false)), "finish " + sid, result)
	return result

func total_xp(state: Dictionary, profile: String = "player_01") -> int:
	var total := 0
	for value in Progress.get_profile_xp(state, profile).values():
		total += int(value)
	return total

func _test_rules() -> void:
	for quest in Content.quests():
		check(bool(Rules.validate_adventure(quest).valid), "authored graph and exact budget " + str(quest.quest_id))
	var cycle := Content.get_quest("FG08")
	cycle.adventure.stages[0].prerequisite_stage_ids = ["water_exhibit"]
	check(not bool(Rules.validate_adventure(cycle).valid), "cycle rejected")
	var missing := Content.get_quest("FG08")
	missing.adventure.stages[0].prerequisite_stage_ids = ["missing"]
	check(not bool(Rules.validate_adventure(missing).valid), "missing dependency rejected")
	var budget := Content.get_quest("FG11")
	budget.adventure.stages[1].budget_share = 13
	check(not bool(Rules.validate_adventure(budget).valid), "budget inflation rejected")
	check(Rules.normalise_word("  SÍ   hola ") == "sí hola" and Rules.normalise_word("sí") != Rules.normalise_word("si"), "word normalization preserves accents")
	check(Rules.grant_key("a:b", "c", "d") != Rules.grant_key("a", "b:c", "d"), "grant tuple is unambiguous")
	var dialogue: Dictionary = Content.get_quest("FG01").adventure.interactions.es_01_hello
	check(not bool(Rules.check_interaction(dialogue, {"node_id": "end", "terminal": true}).ok), "terminal flag cannot bypass dialogue path")

func _test_transactions() -> void:
	var state := fresh()
	var iid := begin(state, "FG11")
	if iid.is_empty(): return
	check(not bool(Commit.commit_stage(state, iid, "game_move", {}, "parent_local", memory_save).ok), "locked stage rejected")
	check(not bool(Commit.commit_stage(state, iid, "game_concept", {"attested": true}, "player_self", memory_save).ok), "forged completion without attempts rejected")
	var evidence := prepare_stage(state, iid, "game_concept")
	var before := state.duplicate(true)
	var failed_result := Commit.commit_stage(state, iid, "game_concept", evidence, "player_self", failed_save)
	check(not bool(failed_result.ok) and state == before, "save failure rolls back ALL live state including callback changes", failed_result)
	var saved := Commit.commit_stage(state, iid, "game_concept", evidence)
	check(bool(saved.ok), "real isolated SaveService commit", saved)
	var loaded := Save.load_game()
	check(A.get_progress(loaded, iid).stages.game_concept.status == "COMPLETED", "restart restores committed stage before presentation")
	var event_count: int = loaded.phase_b.award_events.size()
	var replay := Commit.commit_stage(loaded, iid, "game_concept", evidence, "player_self", memory_save)
	check(bool(replay.ok) and not bool(replay.applied) and loaded.phase_b.award_events.size() == event_count, "double click/restart grants once")
	check(Commit.pending_presentations(loaded).size() == 1, "unshown presentation recovers after restart")
	var move_evidence := prepare_stage(loaded, iid, "game_move")
	var submitted := Commit.commit_stage(loaded, iid, "game_move", move_evidence, "player_self", memory_save)
	check(bool(submitted.get("awaiting_review", false)) and total_xp(loaded) == 0, "joint submission has no premature reward")
	check(not bool(Commit.review_stage(loaded, iid, "game_move", true, "", "player_self", memory_save).ok), "player cannot masquerade as joint review")
	var revision := Commit.review_stage(loaded, iid, "game_move", false, "Ещё одна проверка", "parent_local", memory_save)
	check(bool(revision.ok) and A.get_progress(loaded, iid).stages.game_move.attempts.size() == 2, "revision preserves attempts and draft")
	var help := A.request_help(loaded, iid, "game_move", "game_speed_prediction", 3)
	check(bool(help.ok), "third assistance level recorded")
	var draft_before := A.get_progress(loaded, iid)
	check(bool(A.pause(loaded, iid).ok) and not bool(A.start_stage(loaded, iid, "game_move").ok), "pause blocks new work")
	check(bool(A.resume(loaded, iid).ok) and A.get_progress(loaded, iid) == draft_before, "resume preserves exact stage state")
	finish_stage(loaded, iid, "game_move", move_evidence)
	check(total_xp(loaded) == 12, "help/revision never reduces reward")
	var frozen: Dictionary = A.get_instance(loaded, iid).quest_snapshot.duplicate(true)
	loaded.phase_b.published_versions["FG11@2"].quest.title = "Edited outside accepted snapshot"
	check(A.get_instance(loaded, iid).quest_snapshot == frozen, "published edits cannot change frozen instance")
	Quests.revoke_version(loaded, "FG11", 2)
	check(not bool(Commit.commit_stage(loaded, iid, "game_goal", {}, "player_self", memory_save).ok), "revocation blocks new completion")
	check(not C.list_works(loaded).is_empty(), "revocation retains earlier works")

func _test_authored_chapter() -> void:
	var state := fresh()
	var selected: Dictionary = {}
	for qid in ["FG01", "FG11", "FG08"]:
		var iid := begin(state, qid)
		if iid.is_empty(): continue
		var quest: Dictionary = A.get_instance(state, iid).quest_snapshot
		if qid == "FG01":
			check(A.get_progress(state, iid).lexemes.is_empty(), "accepted Spanish mission starts with no invented known words")
		var order: Array[String] = []
		for stage in Rules.stages(quest): order.append(str(stage.stage_id))
		if qid == "FG08": order = ["water_intro", "water_plan", "water_fall", "water_river", "water_compare", "water_exhibit"]
		for sid in order:
			if qid == "FG08" and sid == "water_fall":
				var evidence := prepare_stage(state, iid, sid)
				evidence.home_materials = true
				check(not bool(Commit.commit_stage(state, iid, sid, evidence, "player_self", memory_save).ok), "home material cannot claim real visit")
			var result := finish_stage(state, iid, sid)
			if not bool(result.get("ok", false)): break
			selected[qid] = result.get("work_id", "")
			if qid == "FG01":
				var expected: Dictionary = {"es_intro": 5, "es_channel_01": 25, "es_channel_02": 50, "es_channel_03": 75, "es_channel_04": 100, "es_final": 100}
				check(A.get_progress(state, iid).lexemes.size() == int(expected[sid]), "actual scene success derives unique words " + sid, A.get_progress(state, iid).lexemes.size())
			if qid == "FG01" and sid == "es_channel_04":
				check(total_xp(state) == 32, "four Spanish channels total 32")
			if qid == "FG08" and sid == "water_fall":
				check(state.phase_c.atlas_unlocked.has("waterfalls") and not state.phase_c.atlas_unlocked.has("rio_azul"), "waterfall-first unlocks only agreed point")
		check(A.get_instance(state, iid).status == "COMPLETED", "lifecycle finalized " + qid)
		check(int(A.get_instance(state, iid).awarded_budget) == int(Rules.BUDGETS[qid]), "exact complete budget " + qid)
	check(total_xp(state) == 140, "chapter total exactly 140", total_xp(state))
	check(bool(A.chapter_status(state).available), "chapter finale unlocked by three completed quests")
	var finale := A.complete_chapter(state, selected)
	check(bool(finale.ok) and bool(finale.get("snapshot_offer", false)), "chapter grants cosmetics and snapshot offer", finale)
	check(C.available_themes(state).has("evening") and not C.available_themes(state, "demo").has("evening"), "chapter lighting unlock is profile scoped")
	check(not C.get_exhibit(state, str(finale.get("exhibit_id", ""))).is_empty(), "chapter album has a placeable exhibit")
	A.complete_chapter(state, selected)
	check(total_xp(state) == 140, "replaying finale never adds XP")
	for secret in Content.secrets():
		var secret_id := str(secret.get("secret_id", secret.get("id", "")))
		check(bool(A.discover_secret(state, secret_id).ok), "discover " + secret_id)
		check(not bool(A.discover_secret(state, secret_id).get("applied", true)), "secret replay idempotent")
	check(A.get_secrets(state).size() == 6 and total_xp(state) == 140, "six secrets no XP")
	check(C.available_themes(state).has("constellation"), "three secrets unlock usable constellation theme")
	var themed := C.create_room(state, "Звёзды", "constellation")
	check(bool(themed.ok), "unlocked constellation can actually decorate new room")

func _test_choice_context() -> void:
	var state := fresh()
	var iid := begin(state, "FG08")
	if iid.is_empty(): return
	var question: Dictionary = Content.get_quest("FG08").adventure.interactions.water_question
	var answer := response_for(question)
	answer.selected_ids = ["sound"]
	A.record_attempt(state, iid, "water_intro", "water_question", answer)
	var sound := A.choice_context(state, iid)
	check(sound.suggested_category_id == "sound" and str(sound.question).contains("голоса") and not sound.hints.is_empty(), "chosen water question selects next comparison category and authored hint")
	answer.selected_ids = ["movement"]
	A.record_attempt(state, iid, "water_intro", "water_question", answer)
	var movement := A.choice_context(state, iid)
	check(movement.suggested_category_id == "movement" and movement.hints != sound.hints, "different question changes following scene guidance")
	state.adventures.progress[iid].choices.water_question = ["movement"]
	check(A.choice_context(state, iid) == movement, "legacy choice array recovers fields without runtime error")
	answer.selected_ids = ["unknown"]
	A.record_attempt(state, iid, "water_intro", "water_question", answer)
	check(A.choice_context(state, iid) == movement, "failed choice cannot alter saved scene context")
	var spanish := fresh()
	var es_id := begin(spanish, "FG01")
	if es_id.is_empty(): return
	A.start_stage(spanish, es_id, "es_intro")
	check(A.get_progress(spanish, es_id).lexemes.is_empty(), "opening scene does not mark words known")
	var hello: Dictionary = Content.get_quest("FG01").adventure.interactions.es_01_hello
	A.record_attempt(spanish, es_id, "es_intro", "es_01_hello", {"choice_ids": ["choice_3"], "node_id": "node_1"})
	check(A.get_progress(spanish, es_id).lexemes.is_empty(), "incorrect language response does not credit vocabulary")
	var answered := A.record_attempt(spanish, es_id, "es_intro", "es_01_hello", response_for(hello))
	check(int(answered.lexeme_update.used_count) == 5 and int(answered.lexeme_update.recognized_count) == 5, "meaningful first dialogue credits five words without a manual extra click")
	A.record_attempt(spanish, es_id, "es_intro", "es_01_hello", response_for(hello))
	check(A.get_progress(spanish, es_id).lexemes.size() == 5, "repeat lesson reuses stable lexeme IDs")
	check(not bool(A.record_attempt(spanish, es_id, "es_intro", "es_15_dispatch", response_for(Content.get_quest("FG01").adventure.interactions.es_15_dispatch)).ok), "future envelope cannot be used in wrong stage")

func _test_evidence_boundaries() -> void:
	var state := fresh()
	var iid := begin(state, "FG11")
	if iid.is_empty(): return
	var report := prepare_stage(state, iid, "game_concept")
	var before := state.duplicate(true)
	var malformed := report.duplicate(true)
	malformed.choices = []
	check(not bool(Commit.commit_stage(state, iid, "game_concept", malformed, "player_self", memory_save).ok) and state == before, "malformed choices rejected without mutation")
	check(not bool(A.save_draft(state, iid, "game_concept", {"fields": []}).ok) and state == before, "malformed draft rejected without starting stage")
	check(not bool(A.record_attempt(state, iid, "game_concept", "game_choose_concept", {"selected_ids": "lights"}).ok) and state == before, "malformed interaction does not crash or mutate")
	var old_tmp := Save.TMP_PATH
	Save.TMP_PATH = "user://adventures_core_missing_%d/subdir/save.tmp" % OS.get_process_id()
	var actual_failure := Commit.commit_stage(state, iid, "game_concept", report)
	Save.TMP_PATH = old_tmp
	check(not bool(actual_failure.ok) and state == before and not actual_failure.get("detail", {}).is_empty(), "actual SaveService IO error preserves state and propagates detail")
	finish_stage(state, iid, "game_concept", report)
	for sid in ["game_move", "game_goal", "game_win", "game_restart"]:
		finish_stage(state, iid, sid)
	var premiere := prepare_stage(state, iid, "game_premiere")
	var prior_xp := total_xp(state)
	var missing := premiere.duplicate(true)
	missing.erase("launch_entry_id")
	check(not bool(Commit.commit_stage(state, iid, "game_premiere", missing, "player_self", memory_save, registered_fixture).ok), "premiere requires registered playable copy")
	var forged := premiere.duplicate(true)
	forged.launch_entry_id = "forged"
	check(not bool(Commit.commit_stage(state, iid, "game_premiere", forged, "player_self", memory_save, registered_fixture).ok), "forged launch ID rejected")
	check(not bool(Commit.commit_stage(state, iid, "game_premiere", premiere, "player_self", memory_save, demo_fixture).ok), "registered builtin demonstration cannot finish FG11")
	check(total_xp(state) == prior_xp, "rejected launch evidence adds no XP")
	Commit.commit_stage(state, iid, "game_premiere", premiere, "player_self", memory_save, registered_fixture)
	var awaiting := state.duplicate(true)
	check(not bool(Commit.review_stage(state, iid, "game_premiere", true, "", "parent_local", memory_save, {}, demo_fixture).ok) and state == awaiting, "registration is rechecked at review; changed trust cannot commit")
	var finished := Commit.review_stage(state, iid, "game_premiere", true, "", "parent_local", memory_save, {}, registered_fixture)
	check(bool(finished.ok), "verified original game finishes")
	var version := C.get_version(state, str(finished.get("work_id", "")))
	check(version.get("content", {}).get("source_archive_file", "") == "launch_registry/versions/isolated_test_game/source.zip" and version.content.launch_entry_id == "isolated_test_game", "work stores verified relative archive and launch ID")
	check(version.get("content", {}).get("source_archive_kind", "") == "project_source", "premiere retains verified source archive kind")
	var app_state := awaiting.duplicate(true)
	var app_finished := Commit.review_stage(app_state, iid, "game_premiere", true, "", "parent_local", memory_save, {}, application_fixture)
	var app_version := C.get_version(app_state, str(app_finished.get("work_id", "")))
	check(bool(app_finished.ok) and app_version.get("content", {}).get("source_archive_kind", "") == "application_bundle", "premiere does not mislabel application bundle as project source")
	check(bool(Commit.commit_stage(state, iid, "game_premiere", {}, "player_self", memory_save, demo_fixture).ok) and total_xp(state) == 60, "later unavailable build never revokes completed mission")
	var mixed: Dictionary = Content.get_quest("FG01").adventure.interactions.es_mixed_check
	var answer := response_for(mixed)
	answer.erase("unassisted_lexeme_ids")
	answer.assisted_ids = ["card_15", "card_16", "card_17", "card_18", "card_19", "card_20"]
	check(bool(Rules.check_interaction(mixed, answer).ok) and Rules.unassisted_lexemes(mixed, answer).size() == 14, "mixed check accepts 14 genuine unassisted answers")
	answer.pairs.card_1 = "wrong"
	check(not bool(Rules.check_interaction(mixed, answer).ok), "mixed check rejects 13 unassisted correct answers")
	var future := {"schema_version": "9.0.0", "read_only": true, "untouched": {"data": [1, 2]}}
	var raw := future.duplicate(true)
	A.ensure_adventures(future)
	A.migrate_legacy(future)
	check(future == raw, "future-schema raw state preserved by core initialization")

func _test_migration() -> void:
	var state := fresh()
	var legacy := Repository.get_template("FG01")
	legacy.reward_policy.milestones_percent = [25]
	var iid := begin(state, "FG01", "player_01", legacy)
	if iid.is_empty(): return
	check(bool(Quests.record_milestone(state, iid, 0).ok), "legacy intermediate reward")
	# The award ledger, including legacy awards made after overlay initialization,
	# remains authoritative; no test rewriting of progress or budget is needed.
	A.migrate_legacy(state)
	var old_snapshot: Dictionary = A.get_instance(state, iid).quest_snapshot.duplicate(true)
	Quests.approve_and_publish(state, Content.get_quest("FG01"))
	var migrated := A.migrate_instance(state, iid, 2)
	check(bool(migrated.ok), "explicit active legacy transfer", migrated)
	if not bool(migrated.ok): return
	var new_id := str(migrated.instance.instance_id)
	check(A.get_instance(state, iid).quest_snapshot == old_snapshot, "migration preserves original frozen snapshot")
	var plan_total := 0
	for amount in migrated.remaining_budget_plan.values(): plan_total += int(amount)
	check(plan_total == 30 and total_xp(state) == 10, "legacy milestone leaves only original remaining 30 XP", migrated)
	check(not bool(A.resume(state, iid).ok), "superseded lineage source cannot resume for double awards")
	check(A.get_progress(state, iid).reward_lineage_id == A.get_progress(state, new_id).reward_lineage_id, "migration retains stable lineage")
	var before := state.duplicate(true)
	A.migrate_legacy(state)
	check(state == before, "legacy migration rerun idempotent")
	var complete_state := fresh()
	var old_id := begin(complete_state, "FG11", "player_01", Repository.get_template("FG11"))
	if old_id.is_empty(): return
	Quests.submit_result(complete_state, old_id, "legacy-completed", "Прежнее подтверждение")
	Quests.confirm_result(complete_state, "legacy-completed", "player_direct")
	A.migrate_legacy(complete_state)
	var works := C.list_works(complete_state)
	check(works.size() == 1 and works[0].authorship.confirmation_source == "player_direct" and total_xp(complete_state) == 60, "completed legacy becomes honest no-XP archive work")
	A.migrate_legacy(complete_state)
	check(C.list_works(complete_state).size() == 1, "completed legacy archive not duplicated")
	check(not bool(A.migrate_instance(complete_state, old_id, 2).ok), "completed legacy remains an archive result rather than a fictitious new active mission")
	# Transfer a paid stage to another revision, with an explicit canonical mapping.
	var modern := fresh()
	var active_id := begin(modern, "FG11")
	if active_id.is_empty(): return
	finish_stage(modern, active_id, "game_concept")
	finish_stage(modern, active_id, "game_move")
	var revision := Content.get_quest("FG11")
	revision.revision = 3
	Quests.approve_and_publish(modern, revision)
	var transfer := A.migrate_instance(modern, active_id, 3, {"game_concept": "game_concept", "game_move": "game_move"})
	check(bool(transfer.ok), "paid stages transfer explicitly", transfer)
	if not bool(transfer.ok): return
	var target_id := str(transfer.instance.instance_id)
	var count: int = modern.phase_b.award_events.size()
	Commit.commit_stage(modern, target_id, "game_move", {}, "player_self", memory_save)
	check(total_xp(modern) == 12 and modern.phase_b.award_events.size() == count, "new instance ID cannot replay transferred reward")
	for sid in ["game_goal", "game_win", "game_restart", "game_premiere"]:
		finish_stage(modern, target_id, sid)
	check(total_xp(modern) == 60, "migrated modern lineage finishes at original 60")

func _test_superseded_submission() -> void:
	var state := fresh()
	var legacy := Repository.get_template("FG11")
	legacy.reward_policy.milestones_percent = [20]
	var old_id := begin(state, "FG11", "player_01", legacy)
	if old_id.is_empty(): return
	check(bool(Quests.submit_result(state, old_id, "legacy-pending-review", "Ожидает семейного просмотра").ok), "legacy submission exists before migration")
	check(bool(Quests.approve_and_publish(state, Content.get_quest("FG11")).ok), "publish target for submitted legacy instance")
	var transferred := A.migrate_instance(state, old_id, 2)
	check(bool(transferred.ok), "submitted legacy instance transfers with history intact", transferred)
	if not bool(transferred.ok): return
	var new_id := str(transferred.instance.instance_id)
	finish_stage(state, new_id, "game_concept")
	finish_stage(state, new_id, "game_move")
	check(total_xp(state) == 12, "transferred instance earns its first 12 XP")
	var before := state.duplicate(true)
	var rejected := Quests.confirm_result(state, "legacy-pending-review", "parent_local")
	check(not bool(rejected.ok) and state == before and total_xp(state) == 12, "superseded legacy submission cannot add original budget again", rejected)
	check(not bool(Quests.submit_result(state, old_id, "another-old-submission").ok), "superseded source cannot submit a fresh result")
	check(not bool(Quests.record_milestone(state, old_id, 0).ok), "superseded source cannot award old milestones")
	check(not Quests.resume_instance(state, old_id) and total_xp(state) == 12, "superseded source cannot resume and retains exact total")

func _test_collections() -> void:
	var state := fresh()
	var room := C.ensure_gallery(state)
	check(bool(room.ok) and C.list_slots().size() == 12, "gallery available after prologue with 12 stable slots")
	var favorites_id := "station_favorites:player_01"
	check(C.list_rooms(state).size() == 2 and state.collections.rooms[favorites_id].profile_id == "player_01" and C.list_slots(str(state.collections.rooms[favorites_id].template_id)).size() == 3, "station favorites has a profile-owned room and three valid slots")
	C.ensure_gallery(state)
	check(C.list_rooms(state).size() == 2 and int(state.collections.rooms[favorites_id].order) == 9999, "gallery initialization keeps favorites stable and ordered last")
	check(C.available_themes(state) == ["warm", "dusk", "daylight"] and not bool(C.update_room(state, str(room.room_id), {"theme": "constellation"}).ok), "cosmetic themes remain gated before actual grants")
	check(not bool(C.create_room(state, "Второй").ok), "additional room locked before first finale/eight works")
	var work := C.create_work(state, {"title": "Мой рисунок", "kind": "image", "content": {"note": "Первая линия"}})
	var exhibit := C.create_exhibit(state, str(work.work_id), "frame")
	var first := C.place_exhibit(state, str(room.room_id), "frame_01", str(exhibit.exhibit_id))
	check(bool(C.place_exhibit(state, favorites_id, "favorite_01", str(exhibit.exhibit_id)).ok), "station favorite can reference an archive work")
	C.place_exhibit(state, str(room.room_id), "frame_02", str(exhibit.exhibit_id))
	check(C.list_works(state).size() == 1 and C.list_placements(state, str(room.room_id)).size() == 2, "two placements reference one work")
	C.add_version(state, str(work.work_id), {"note": "Вторая линия"}, "Добавила линию")
	check(C.list_placements(state, str(room.room_id))[0].version_id == first.placement.version_id, "new work version leaves old placements pinned")
	check(C.get_work(state, str(work.work_id)).versions.size() == 2, "old version preserved")
	var snapshot := C.save_exhibition(state, str(room.room_id), "Первая выставка")
	var before_incompatible := state.duplicate(true)
	var incompatible := C.restore_exhibition(state, str(snapshot.snapshot_id), favorites_id)
	check(not bool(incompatible.ok) and state == before_incompatible, "gallery snapshot cannot erase station favorites through incompatible restore")
	var favorite_snapshot := C.save_exhibition(state, favorites_id, "Избранное")
	before_incompatible = state.duplicate(true)
	incompatible = C.restore_exhibition(state, str(favorite_snapshot.snapshot_id), str(room.room_id))
	check(not bool(incompatible.ok) and state == before_incompatible, "favorites snapshot cannot erase physical gallery through incompatible restore")
	C.remove_placement(state, str(room.room_id), "frame_01")
	C.restore_exhibition(state, str(snapshot.snapshot_id))
	check(C.list_placements(state, str(room.room_id)).size() == 2, "snapshot restores pinned occupancy")
	C.delete_room(state, str(room.room_id), true)
	check(C.list_works(state).size() == 1 and C.list_rooms(state).size() == 1 and C.list_rooms(state)[0].room_id == favorites_id and C.list_placements(state, favorites_id).size() == 1, "gallery deletion keeps archive and independent station favorites")
	C.restore_exhibition(state, str(snapshot.snapshot_id))
	check(C.list_rooms(state).size() == 2 and C.list_placements(state, str(room.room_id)).size() == 2, "snapshot restores deleted gallery alongside station favorites")
	state.phase_b.artifacts["missing_media"] = {"artifact_id": "missing_media", "profile_id": "player_01", "media_file": "missing.png", "media_deleted": true}
	var version := C.add_version(state, str(work.work_id), {"artifact_id": "missing_media"})
	var placed := C.place_exhibit(state, str(room.room_id), "frame_03", str(exhibit.exhibit_id), str(version.version_id))
	check(bool(C.inspect_placement(state, placed.placement).placeholder), "missing/deleted media shows placeholder")
	for index in range(7): C.create_work(state, {"title": "Работа " + str(index)})
	check(bool(C.create_room(state, "Новая выставка").ok), "eight unique personal works unlock additional rooms")
	check(C.list_works(state, "player_01", {"search": "рисунок", "kind": "image"}).size() == 1, "archive metadata filters")
	var game := C.create_work(state, {"title": "Моя игра", "kind": "game"})
	var terminal := C.create_exhibit(state, str(game.work_id), "game_premiere")
	var game_frame := C.place_exhibit(state, str(room.room_id), "frame_04", str(terminal.exhibit_id))
	var game_terminal := C.place_exhibit(state, str(room.room_id), "terminal_01", str(terminal.exhibit_id))
	check(not bool(game_frame.placement.launch_allowed) and bool(game_terminal.placement.launch_allowed), "game launches only from terminal slot")
	check(not bool(C.place_exhibit(state, str(room.room_id), "audio_01", str(terminal.exhibit_id)).ok), "incompatible slot rejected")
	var started := Time.get_ticks_usec()
	for index in range(1000): C.create_work(state, {"title": "Load " + str(index), "kind": "note"})
	var filter_started := Time.get_ticks_usec()
	var page := C.list_works(state, "player_01", {"search": "Load", "offset": 50, "limit": 20})
	var filter_ms := (Time.get_ticks_usec() - filter_started) / 1000.0
	check(page.size() == 20 and filter_ms < 200, "1000-work metadata pagination under 200ms", filter_ms)
	print("Synthetic collection create+filter ms: ", (Time.get_ticks_usec() - started) / 1000.0, "; filter ms: ", filter_ms)

func _test_room_lifecycle() -> void:
	var state := fresh()
	var first := C.ensure_gallery(state)
	for i in range(8): C.create_work(state, {"title": "Room fixture %d" % i})
	var old := C.create_room(state, "Старая выставка")
	var removed := C.delete_room(state, str(old.room_id))
	var newer := C.create_room(state, "Новая выставка")
	check(old.room_id != newer.room_id, "new gallery cannot reuse a deleted room identity")
	C.restore_exhibition(state, str(removed.snapshot_id))
	check(str(state.collections.rooms[newer.room_id].title) == "Новая выставка", "restoring deleted gallery never overwrites a newer gallery")
	C.delete_room(state, str(first.room_id))
	C.ensure_gallery(state)
	check(not state.collections.rooms.has(first.room_id), "refresh does not resurrect deleted first gallery")
	check(Save.save_game(state), "deleted gallery lifecycle saves")
	var loaded := Save.load_game()
	C.ensure_gallery(loaded)
	check(not loaded.collections.rooms.has(first.room_id), "deleted gallery remains deleted after restart")
	for room in C.list_rooms(loaded):
		if str(room.template_id) == "gallery_v1": C.delete_room(loaded, str(room.room_id))
	C.ensure_gallery(loaded)
	check(C.list_rooms(loaded).all(func(r): return str(r.template_id) == "station_favorites"), "removing all physical galleries retains only station favorites")
	var before := loaded.duplicate(true)
	var fixed := C.delete_room(loaded, "station_favorites:player_01")
	check(not bool(fixed.ok) and loaded == before, "station favorite slots are permanent and cannot be deleted as a room")
	var temporary := C.create_room(loaded, "Без снимка")
	C.delete_room(loaded, str(temporary.room_id), false)
	var next := C.create_room(loaded, "Следующая")
	check(str(temporary.room_id) != str(next.room_id), "room identity stays reserved even without an exhibition snapshot")
	loaded.collections.erase("retired_room_ids")
	C.ensure_gallery(loaded)
	check(not loaded.collections.rooms.has(first.room_id), "older save with a deletion snapshot does not resurrect first gallery")

func _test_archive_search() -> void:
	var state := fresh()
	var work := C.create_work(state, {"title": "Мой лист", "quest_ids": ["FG08"], "content": {"note": "Тихая заводь"}, "source": {"quest_snapshot": {"title": "Исследование течения", "story_title": "Секреты горной воды"}}})
	C.add_version(state, str(work.work_id), {"note": "Солнечные блики"})
	for query in ["Тихая заводь", "СОЛНЕЧНЫЕ", "FG08", "горной воды", "Исследование течения"]:
		check(C.list_works(state, "player_01", {"search": query}).size() == 1, "archive finds saved note or frozen adventure title: " + query)
	check(C.list_works(state, "demo", {"search": "горной воды"}).is_empty(), "metadata search never exposes other profile works")

func _test_profiles() -> void:
	var state := fresh()
	var iid := begin(state, "FG08", "demo")
	if iid.is_empty(): return
	finish_stage(state, iid, "water_intro")
	finish_stage(state, iid, "water_plan")
	finish_stage(state, iid, "water_river")
	check(total_xp(state) == 0 and total_xp(state, "demo") == 10, "demo XP isolated")
	check(C.list_works(state).is_empty() and not C.list_works(state, "demo").is_empty(), "demo archive isolated")
	check(not state.phase_c.atlas_unlocked.has("rio_azul") and state.phase_c.atlas_unlocked_by_profile.demo.has("rio_azul"), "demo atlas never leaks into primary map")
	check(not bool(A.dispatch(state, "stage_hint", {"instance_id": iid, "stage_id": "water_fall", "level": 1}).ok), "controller rejects other-profile instance")
	var demo_work := C.list_works(state, "demo")[0]
	check(C.get_work(state, str(demo_work.work_id)).is_empty(), "work getter enforces profile")
	var room := C.ensure_gallery(state)
	C.ensure_gallery(state, "demo")
	check(C.list_rooms(state).size() == 2 and C.list_rooms(state, "demo").size() == 2 and state.collections.rooms.has("station_favorites:demo"), "favorites room is independently initialized per profile")
	var demo_exhibit := C.list_exhibits(state, "demo")[0]
	check(not bool(C.place_exhibit(state, str(room.room_id), "frame_01", str(demo_exhibit.exhibit_id)).ok), "cross-profile placement rejected")
