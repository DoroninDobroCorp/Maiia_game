extends SceneTree

## Автоматизированные приёмочные проверки Phase B (B01-B24).

const SaveServiceScript = preload("res://scripts/services/save_service.gd")
const ContentRepositoryScript = preload("res://scripts/services/content_repository.gd")
const ContentValidationScript = preload("res://scripts/domain/content_validation.gd")
const QuestServiceScript = preload("res://scripts/services/quest_service.gd")
const ProgressServiceScript = preload("res://scripts/services/progress_service.gd")
const ArtifactServiceScript = preload("res://scripts/services/artifact_service.gd")
const AuthorPatchServiceScript = preload("res://scripts/services/author_patch_service.gd")

var failed_count := 0
var passed_count := 0

func _init() -> void:
	SaveServiceScript.use_test_storage("user://test_phase_b_")
	print("\n==================================================")
	print("  SUR — Phase B acceptance B01-B24")
	print("==================================================\n")
	_run_b01_to_b07()
	_run_b08()
	_run_b09()
	_run_b10_b11()
	_run_b12_b13()
	_run_b14_b15()
	_run_b16_b18()
	_run_b19_b20()
	_run_b21_b22()
	_run_b23_b24()
	SaveServiceScript.cleanup_test_storage()
	print("\n==================================================")
	if failed_count == 0:
		print("  PHASE B: ALL PASS (", passed_count, " checks)")
		print("==================================================\n")
		quit(0)
	else:
		print("  PHASE B: FAILURES = ", failed_count, ", passed = ", passed_count)
		print("==================================================\n")
		quit(1)

func _assert_true(condition: bool, name: String, detail: String = "") -> void:
	if condition:
		passed_count += 1
		print("  [PASS] ", name)
	else:
		failed_count += 1
		print("  [FAIL] ", name, " -> ", detail)

func _fresh() -> Dictionary:
	return SaveServiceScript.get_default_state()

func _quest(qid: String) -> Dictionary:
	return ContentRepositoryScript.get_template(qid)

func _publish(state: Dictionary, qid: String) -> Dictionary:
	return QuestServiceScript.approve_and_publish(state, _quest(qid))

func _run_b01_to_b07() -> void:
	print("--- B01-B07: publication, frozen versions, submission, confirmation ---")
	var state := _fresh()
	_assert_true(ContentRepositoryScript.all_templates().size() == 12, "B01.0 Каталог содержит 12 стартовых карточек")
	_assert_true(QuestServiceScript.list_player_quests(state).is_empty(), "B01 Черновики S01-S11 невидимы игроку")

	var q1 := _quest("S01")
	var publish := QuestServiceScript.approve_and_publish(state, q1)
	var visible := QuestServiceScript.list_player_quests(state)
	_assert_true(bool(publish.get("ok", false)) and visible.size() == 1 and str(visible[0].get("title", "")) == str(q1.get("title", "")), "B02 Опубликована точная версия")

	var changed := q1.duplicate(true)
	changed["summary"] = "Изменённый смысл той же ревизии"
	var conflict := QuestServiceScript.approve_and_publish(state, changed)
	_assert_true(not bool(conflict.get("ok", true)) and str(conflict.get("reason", "")) == "revision_conflict", "B03 Изменение одобренной ревизии требует revision + 1")

	var created := QuestServiceScript.create_instance(state, "S01", 1, "window")
	var instance: Dictionary = created.get("instance", {})
	var q2 := q1.duplicate(true)
	q2["revision"] = 2
	q2["summary"] = "Новая версия после принятия старой"
	var published_v2 := QuestServiceScript.approve_and_publish(state, q2)
	var live_instance: Dictionary = state.get("phase_b", {}).get("quest_instances", {}).get(str(instance.get("instance_id", "")), {})
	_assert_true(bool(published_v2.get("ok", false)) and int(live_instance.get("revision", 0)) == 1 and str(live_instance.get("quest_snapshot", {}).get("summary", "")) == str(q1.get("summary", "")), "B04 Принятый QuestInstance сохраняет старую версию")

	var xp_before: Dictionary = ProgressServiceScript.get_profile_xp(state, "player_01")
	var submit := QuestServiceScript.submit_result(state, str(instance.get("instance_id", "")), "activity:b05", "Три наблюдения готовы")
	var xp_after_submit: Dictionary = ProgressServiceScript.get_profile_xp(state, "player_01")
	_assert_true(bool(submit.get("ok", false)) and xp_before == xp_after_submit, "B05 Кнопка «готово» создаёт submission без XP")

	var confirm_1 := QuestServiceScript.confirm_result(state, "activity:b05")
	var xp_after_confirm: Dictionary = ProgressServiceScript.get_profile_xp(state, "player_01")
	var confirm_2 := QuestServiceScript.confirm_result(state, "activity:b05")
	var xp_after_second: Dictionary = ProgressServiceScript.get_profile_xp(state, "player_01")
	_assert_true(bool(confirm_1.get("ok", false)) and int(xp_after_confirm.get("drawing", 0)) == 20 and bool(confirm_2.get("ok", false)) and not bool(confirm_2.get("applied", true)) and xp_after_confirm == xp_after_second, "B06 Повторное подтверждение не платит второй раз")

	_publish(state, "S04")
	var second := QuestServiceScript.create_instance(state, "S04", 1, "paper")
	var duplicate_activity := QuestServiceScript.submit_result(state, str(second.get("instance", {}).get("instance_id", "")), "activity:b05", "Другая карточка")
	_assert_true(not bool(duplicate_activity.get("ok", true)) and str(duplicate_activity.get("reason", "")) == "activity_already_used", "B07 Один activity_id нельзя оплатить через второй квест")

func _run_b08() -> void:
	print("\n--- B08: deterministic XP allocation ---")
	var state := _fresh()
	var first := ProgressServiceScript.apply_award(state, "player_01", "award:b08", "activity:b08", 20, {"drawing": 60, "spanish": 40}, [])
	var xp := ProgressServiceScript.get_profile_xp(state, "player_01")
	var second := ProgressServiceScript.apply_award(state, "player_01", "award:b08", "activity:b08", 20, {"drawing": 60, "spanish": 40}, [])
	_assert_true(bool(first.get("applied", false)) and int(xp.get("drawing", 0)) == 12 and int(xp.get("spanish", 0)) == 8 and not bool(second.get("applied", true)), "B08 20 XP с 60/40 = 12/8 и идемпотентно")

func _run_b09() -> void:
	print("\n--- B09: milestones never exceed project budget ---")
	var state := _fresh()
	_publish(state, "S06")
	var created := QuestServiceScript.create_instance(state, "S06", 1, "cardboard_story")
	var iid := str(created.get("instance", {}).get("instance_id", ""))
	QuestServiceScript.record_milestone(state, iid, 0)
	QuestServiceScript.record_milestone(state, iid, 1)
	QuestServiceScript.record_milestone(state, iid, 2)
	QuestServiceScript.submit_result(state, iid, "activity:b09", "Проект завершён")
	QuestServiceScript.confirm_result(state, "activity:b09")
	var instance: Dictionary = state.get("phase_b", {}).get("quest_instances", {}).get(iid, {})
	var xp := ProgressServiceScript.get_profile_xp(state, "player_01")
	var total_xp := int(xp.get("wood", 0)) + int(xp.get("drawing", 0))
	_assert_true(int(instance.get("awarded_budget", 0)) == 40 and total_xp == 40, "B09 Вехи + финал не превышают бюджет 40 XP")

func _run_b10_b11() -> void:
	print("\n--- B10-B11: pause and agreed alternatives ---")
	var state := _fresh()
	_publish(state, "S07")
	_publish(state, "S05")
	var q7 := QuestServiceScript.create_instance(state, "S07", 1, "home_example")
	var iid := str(q7.get("instance", {}).get("instance_id", ""))
	var paused := QuestServiceScript.pause_instance(state, iid)
	var q5 := QuestServiceScript.create_instance(state, "S05", 1, "clap_rhythm")
	_assert_true(paused and bool(q5.get("ok", false)) and QuestServiceScript.list_player_quests(state).size() == 2, "B10 Отложенный квест не блокирует остальную базу")

	var s05 := _quest("S05")
	var s07 := _quest("S07")
	var has_no_piano := false
	for variant in s05.get("variants", []):
		if str((variant as Dictionary).get("id", "")) == "clap_rhythm":
			has_no_piano = true
	var has_home_walk_alt := false
	for variant in s07.get("variants", []):
		if str((variant as Dictionary).get("id", "")) == "home_example" and bool((variant as Dictionary).get("home_available", false)):
			has_home_walk_alt = true
	_assert_true(has_no_piano and has_home_walk_alt, "B11 Есть согласованные альтернативы без пианино и прогулки")

func _run_b12_b13() -> void:
	print("\n--- B12-B13: managed local image archive ---")
	var state := _fresh()
	var source := "user://phase_b_source.png"
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.7, 0.3, 0.2, 1.0))
	image.save_png(source)
	var imported := ArtifactServiceScript.import_local_image(state, source, "Тестовый рисунок")
	var artifact_id := str(imported.get("artifact", {}).get("artifact_id", ""))
	var source_dir := DirAccess.open("user://")
	if source_dir != null and source_dir.file_exists(source.get_file()):
		source_dir.remove(source.get_file())
	var managed_exists := not ArtifactServiceScript.media_path_for(state, artifact_id).is_empty()
	_assert_true(bool(imported.get("ok", false)) and managed_exists, "B12 Управляемая копия живёт после удаления внешнего исходника")

	var deleted := ArtifactServiceScript.delete_media(state, artifact_id)
	var artifacts: Dictionary = state.get("phase_b", {}).get("artifacts", {})
	_assert_true(bool(deleted.get("ok", false)) and artifacts.has(artifact_id) and bool((artifacts[artifact_id] as Dictionary).get("media_deleted", false)), "B13 Удаление медиа сохраняет ArtifactRecord")

func _run_b14_b15() -> void:
	print("\n--- B14-B15: backups and interrupted-write resilience ---")
	var state := SaveServiceScript.reset_save()
	state["test_marker"] = "v1"
	SaveServiceScript.save_game(state)
	state["test_marker"] = "v2"
	SaveServiceScript.save_game(state)
	var main := FileAccess.open(SaveServiceScript.SAVE_PATH, FileAccess.WRITE)
	if main != null:
		main.store_string("{broken")
		main.close()
	var recovered := SaveServiceScript.load_game()
	_assert_true(str(recovered.get("test_marker", "")) == "v1" and str(recovered.get("recovery_notice", {}).get("kind", "")) == "backup_loaded", "B14 Повреждённый main восстанавливается из проверенного backup")

	state = SaveServiceScript.reset_save()
	_publish(state, "S02")
	var created := QuestServiceScript.create_instance(state, "S02", 1, "parent_roleplay")
	var iid := str(created.get("instance", {}).get("instance_id", ""))
	QuestServiceScript.submit_result(state, iid, "activity:b15", "Готово")
	QuestServiceScript.confirm_result(state, "activity:b15")
	SaveServiceScript.save_game(state)
	var tmp := FileAccess.open(SaveServiceScript.TMP_PATH, FileAccess.WRITE)
	if tmp != null:
		tmp.store_string("partial-write")
		tmp.close()
	var reloaded := SaveServiceScript.load_game()
	var events_before := (reloaded.get("phase_b", {}).get("award_events", {}) as Dictionary).size()
	var xp_before := ProgressServiceScript.get_profile_xp(reloaded, "player_01")
	QuestServiceScript.confirm_result(reloaded, "activity:b15")
	var events_after := (reloaded.get("phase_b", {}).get("award_events", {}) as Dictionary).size()
	var xp_after := ProgressServiceScript.get_profile_xp(reloaded, "player_01")
	_assert_true(events_before == 1 and events_after == 1 and xp_before == xp_after, "B15 Остаточный tmp не создаёт повторной награды и не портит последний snapshot")

func _run_b16_b18() -> void:
	print("\n--- B16-B18: package validation and approval boundary ---")
	var state := _fresh()
	var before := JSON.stringify(state)
	var unknown := ContentValidationScript.validate_package({"schema_version": 99, "quest": _quest("S09")})
	_assert_true(not bool(unknown.get("valid", true)) and JSON.stringify(state) == before, "B16 Неизвестная schema_version отклоняется без перезаписи")

	var unsafe := _quest("S09")
	unsafe["action"] = "res://evil.gd"
	var unsafe_result := ContentValidationScript.validate_package({"schema_version": 1, "quest": unsafe})
	_assert_true(not bool(unsafe_result.get("valid", true)), "B17 Произвольное действие/путь отклоняется до исполнения")

	var fake_approval := _quest("S09")
	fake_approval["approved"] = true
	var fake_result := ContentValidationScript.validate_package({"schema_version": 1, "quest": fake_approval})
	var approvals: Array = state.get("phase_b", {}).get("approval_records", [])
	_assert_true(not bool(fake_result.get("valid", true)) and approvals.is_empty(), "B18 approved:true не создаёт взрослое одобрение")

func _run_b19_b20() -> void:
	print("\n--- B19-B20: author dialogue preview, publish and rollback ---")
	var state := _fresh()
	var package := {
		"schema_version": 1,
		"patch_id": "test_patch_b19",
		"dialogue": {"radio_greeting": "Hola desde la estación", "archive_note": "Новая архивная строка"}
	}
	var before_preview := JSON.stringify(state)
	var preview := AuthorPatchServiceScript.preview(package)
	_assert_true(bool(preview.get("ok", false)) and JSON.stringify(state) == before_preview, "B20 Предпросмотр авторского пакета не мутирует основной прогресс")
	var published := AuthorPatchServiceScript.publish(state, package)
	var changed := AuthorPatchServiceScript.get_dialogue(state, "radio_greeting") == "Hola desde la estación"
	var rolled := AuthorPatchServiceScript.rollback(state, "test_patch_b19")
	var restored := AuthorPatchServiceScript.get_dialogue(state, "radio_greeting") == str(AuthorPatchServiceScript.DEFAULT_DIALOGUE.get("radio_greeting", ""))
	_assert_true(bool(published.get("ok", false)) and changed and bool(rolled.get("ok", false)) and restored, "B19 Реплика имеет preview, publish и rollback")

func _run_b21_b22() -> void:
	print("\n--- B21-B22: safety revoke and offline cycle ---")
	var state := _fresh()
	_publish(state, "S07")
	var created := QuestServiceScript.create_instance(state, "S07", 1, "home_example")
	var iid := str(created.get("instance", {}).get("instance_id", ""))
	var revoked := QuestServiceScript.revoke_version(state, "S07", 1)
	var instance: Dictionary = state.get("phase_b", {}).get("quest_instances", {}).get(iid, {})
	_assert_true(revoked and bool(instance.get("safety_hold", false)) and str(instance.get("status", "")) == "PAUSED" and QuestServiceScript.list_player_quests(state).is_empty(), "B21 Отзыв скрывает выдачу и ставит активную инструкцию на safety hold")

	state = _fresh()
	var no_network_required := true
	for quest in ContentRepositoryScript.real_quest_templates():
		if bool((quest.get("context", {}) as Dictionary).get("requires_network", false)):
			no_network_required = false
	_publish(state, "S02")
	created = QuestServiceScript.create_instance(state, "S02", 1, "approved_dialogue")
	iid = str(created.get("instance", {}).get("instance_id", ""))
	var submitted := QuestServiceScript.submit_result(state, iid, "activity:b22", "Офлайн результат")
	var confirmed := QuestServiceScript.confirm_result(state, "activity:b22")
	_assert_true(no_network_required and bool(submitted.get("ok", false)) and bool(confirmed.get("ok", false)), "B22 Утверждённый цикл работает без сети/AI-ключа")

func _run_b23_b24() -> void:
	print("\n--- B23-B24: profile separation and clean export ---")
	var state := _fresh()
	ProgressServiceScript.apply_award(state, "player_01", "award:player", "activity:player", 10, {"math": 100}, ["atlas_first_page"])
	ProgressServiceScript.apply_award(state, "demo_profile", "award:demo", "activity:demo", 20, {"math": 100}, ["observatory_view_01"])
	var player := ProgressServiceScript.get_profile_xp(state, "player_01")
	var demo := ProgressServiceScript.get_profile_xp(state, "demo_profile")
	var player_effects := ProgressServiceScript.get_profile_world_effects(state, "player_01")
	var demo_effects := ProgressServiceScript.get_profile_world_effects(state, "demo_profile")
	_assert_true(int(player.get("math", 0)) == 10 and int(demo.get("math", 0)) == 20 and player_effects.has("atlas_first_page") and not player_effects.has("observatory_view_01") and demo_effects.has("observatory_view_01"), "B23 Demo-награды и изменения мира не смешиваются с player_01")

	var phase_b: Dictionary = state.get("phase_b", {})
	var artifacts: Dictionary = phase_b.get("artifacts", {})
	artifacts["artifact_export"] = {
		"artifact_id": "artifact_export",
		"profile_id": "player_01",
		"title": "Экспортируемая работа",
		"kind": "local_image",
		"media_file": "secret_local_copy.png",
		"media_deleted": false,
		"source_path": "/Users/example/private/original.png"
	}
	phase_b["artifacts"] = artifacts
	state["phase_b"] = phase_b
	var export := ArtifactServiceScript.build_progress_export(state, "player_01")
	var export_text := JSON.stringify(export)
	var exported_effects: Array = export.get("world_effects", [])
	_assert_true(not export_text.contains("secret_local_copy.png") and not export_text.contains("/Users/") and not export_text.contains("user://") and not export_text.contains("res://") and str(export.get("export_kind", "")) == "sur_progress_without_media" and exported_effects.has("atlas_first_page") and not exported_effects.has("observatory_view_01"), "B24 Экспорт без медиа не содержит системных путей, файлов и demo-эффектов")
