extends SceneTree

## Automated acceptance checks for Phase C: selected content bank, local editor,
## package import/export, publication boundary, world locations and repeat rules.

const SaveServiceScript = preload("res://scripts/services/save_service.gd")
const ContentRepositoryScript = preload("res://scripts/services/content_repository.gd")
const ContentLibraryServiceScript = preload("res://scripts/services/content_library_service.gd")
const QuestServiceScript = preload("res://scripts/services/quest_service.gd")
const AtlasServiceScript = preload("res://scripts/services/atlas_service.gd")
const RadioWeatherServiceScript = preload("res://scripts/services/radio_weather_service.gd")
const RitualServiceScript = preload("res://scripts/services/ritual_service.gd")
const ProgressServiceScript = preload("res://scripts/services/progress_service.gd")

var failed_count := 0
var passed_count := 0

func _init() -> void:
	print("\n==================================================")
	print("  SUR — Phase C acceptance C01-C20")
	print("==================================================\n")
	_run_c01_c03()
	_run_c04_c05()
	_run_c06_c09()
	_run_c10_c12()
	_run_c13_c16()
	_run_c17_c20()
	print("\n==================================================")
	if failed_count == 0:
		print("  PHASE C: ALL PASS (", passed_count, " checks)")
		print("==================================================\n")
		quit(0)
	else:
		print("  PHASE C: FAILURES = ", failed_count, ", passed = ", passed_count)
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

func _custom_quest(
	quest_id: String,
	revision: int = 1,
	title: String = "Семейная карточка",
	repeat_mode: String = "once",
	max_completions: int = 1
) -> Dictionary:
	var quest := ContentRepositoryScript.get_template("ES01").duplicate(true)
	quest["quest_id"] = quest_id
	quest["revision"] = revision
	quest["title"] = title
	quest["summary"] = "Локальная семейная карточка для проверки Phase C."
	quest["content_status"] = "DRAFT"
	quest["repeat_policy"] = {"mode": repeat_mode, "max_completions": max_completions}
	quest["provenance"] = {"origin": "parent_editor"}
	return quest

func _package(package_id: String, quests: Array) -> Dictionary:
	return {
		"schema_version": 1,
		"package_type": "sur_quest_pack",
		"package_id": package_id,
		"quests": quests
	}

func _contains_quest(quests: Array[Dictionary], quest_id: String, revision: int = -1) -> bool:
	for quest in quests:
		if str(quest.get("quest_id", "")) != quest_id:
			continue
		if revision > 0 and int(quest.get("revision", 0)) != revision:
			continue
		return true
	return false

func _complete_once(state: Dictionary, quest_id: String, revision: int, suffix: String) -> bool:
	var created := QuestServiceScript.create_instance(state, quest_id, revision, "home")
	if not bool(created.get("ok", false)):
		return false
	var instance_id := str((created.get("instance", {}) as Dictionary).get("instance_id", ""))
	var activity_id := "activity:c:" + suffix
	var submitted := QuestServiceScript.submit_result(state, instance_id, activity_id, "Готово")
	if not bool(submitted.get("ok", false)):
		return false
	var confirmed := QuestServiceScript.confirm_result(state, activity_id)
	return bool(confirmed.get("ok", false))

func _run_c01_c03() -> void:
	print("--- C01-C03: bank, locations, draft visibility ---")
	var templates := ContentRepositoryScript.phase_c_templates()
	var counts: Dictionary = {}
	for quest in templates:
		var weights: Dictionary = (quest.get("reward_policy", {}) as Dictionary).get("skill_weights_percent", {})
		if not weights.is_empty():
			var skill_id := str(weights.keys()[0])
			counts[skill_id] = int(counts.get(skill_id, 0)) + 1
	var balanced := templates.size() == 24 and counts.size() == ContentRepositoryScript.SKILLS.size()
	for skill_id in ContentRepositoryScript.SKILLS.keys():
		balanced = balanced and int(counts.get(str(skill_id), 0)) == 3
	_assert_true(balanced, "C01 Выбранный банк содержит 24 карточки — по 3 на каждое из 8 направлений", JSON.stringify(counts))

	var state := _fresh()
	var locations := ContentLibraryServiceScript.list_locations(state)
	var location_ids: Array[String] = []
	for location in locations:
		location_ids.append(str(location.get("location_id", "")))
	_assert_true(locations.size() == 3 and location_ids.has("radio_cafe") and location_ids.has("workshop_annex") and location_ids.has("field_archive"), "C02 Доступны три новых места мира")

	var atlas_locations := AtlasServiceScript.list_locations(state)
	var atlas_ids: Array[String] = []
	var atlas_unlocked: Array[String] = []
	for location in atlas_locations:
		var atlas_id := str(location.get("id", ""))
		atlas_ids.append(atlas_id)
		if bool(location.get("unlocked", false)):
			atlas_unlocked.append(atlas_id)
	var atlas_required := ["station", "rio_azul", "waterfalls", "piltriquitron", "el_bolson_skatepark", "lago_puelo", "bariloche", "bariloche_skatepark", "chile", "whales", "ushuaia"]
	var atlas_ok := atlas_locations.size() == 11 and atlas_unlocked == ["station"]
	for atlas_id in atlas_required:
		atlas_ok = atlas_ok and atlas_ids.has(atlas_id)
	_assert_true(atlas_ok, "C02a Атлас содержит 11 расширяемых точек, а на старте открыта только Лесная станция", JSON.stringify(atlas_unlocked))

	var parent_catalog := ContentLibraryServiceScript.list_parent_templates(state)
	var player_catalog := QuestServiceScript.list_player_quests(state)
	_assert_true(parent_catalog.size() == 38 and _contains_quest(parent_catalog, "ES01") and _contains_quest(parent_catalog, "RL01") and player_catalog.is_empty(), "C03 Phase C виден взрослому как черновики и невидим игроку до публикации")

func _run_c04_c05() -> void:
	print("\n--- C04-C05: local editing and immutable built-ins ---")
	var state := _fresh()
	var draft := _custom_quest("FAM01", 1, "Наш первый семейный квест")
	var saved := ContentLibraryServiceScript.save_draft(state, draft)
	var stored := ContentLibraryServiceScript.get_template(state, "FAM01", 1)
	var published := QuestServiceScript.approve_and_publish(state, stored)
	var visible := QuestServiceScript.list_player_quests(state)
	_assert_true(bool(saved.get("ok", false)) and bool(published.get("ok", false)) and _contains_quest(visible, "FAM01", 1), "C04 Взрослый добавляет новый квест данными и публикует его без правки Godot-сцены")

	state = _fresh()
	var builtin := ContentRepositoryScript.get_template("ES01")
	var overwrite := ContentLibraryServiceScript.save_draft(state, builtin)
	var revision_two := builtin.duplicate(true)
	revision_two["revision"] = 2
	revision_two["title"] = "Меню радиокафе — семейная версия"
	var revision_saved := ContentLibraryServiceScript.save_draft(state, revision_two)
	_assert_true(not bool(overwrite.get("ok", true)) and str(overwrite.get("reason", "")) == "builtin_revision_locked" and bool(revision_saved.get("ok", false)), "C05 Встроенная ревизия неизменяема, а revision + 1 сохраняется")

func _run_c06_c09() -> void:
	print("\n--- C06-C09: package import boundary and safety ---")
	var state := _fresh()
	var imported_quest := _custom_quest("IMP01")
	var imported := ContentLibraryServiceScript.import_package(state, _package("pack-c06", [imported_quest]))
	var custom: Dictionary = state.get("phase_c", {}).get("custom_quests", {})
	var approvals: Array = state.get("phase_b", {}).get("approval_records", [])
	_assert_true(bool(imported.get("ok", false)) and custom.has("IMP01@1") and approvals.is_empty() and QuestServiceScript.list_player_quests(state).is_empty(), "C06 Валидный пакет импортирует только черновики, без публикации")

	state = _fresh()
	var good := _custom_quest("ATOMIC01")
	var bad := _custom_quest("ATOMIC02")
	bad["action"] = "run_something"
	var atomic := ContentLibraryServiceScript.import_package(state, _package("pack-c07", [good, bad]))
	var after_atomic: Dictionary = state.get("phase_c", {}).get("custom_quests", {})
	_assert_true(not bool(atomic.get("ok", true)) and after_atomic.is_empty(), "C07 Ошибка одной карточки отклоняет весь пакет без частичного импорта")

	state = _fresh()
	var duplicate_a := _custom_quest("DUP01", 1, "Первый вариант")
	var duplicate_b := _custom_quest("DUP01", 1, "Второй вариант")
	var duplicate_result := ContentLibraryServiceScript.import_package(state, _package("pack-c07-dup", [duplicate_a, duplicate_b]))
	_assert_true(not bool(duplicate_result.get("ok", true)) and (state.get("phase_c", {}).get("custom_quests", {}) as Dictionary).is_empty(), "C07a Дубликат quest_id@revision отклоняет пакет вместо тихой перезаписи")

	state = _fresh()
	ContentLibraryServiceScript.save_draft(state, _custom_quest("KEEP01", 1, "Локальная версия"))
	var collision := _custom_quest("KEEP01", 1, "Версия из импорта")
	var collision_result := ContentLibraryServiceScript.import_package(state, _package("pack-c07-collision", [collision]))
	var kept := ContentLibraryServiceScript.get_template(state, "KEEP01", 1)
	_assert_true(not bool(collision_result.get("ok", true)) and str(kept.get("title", "")) == "Локальная версия", "C07b Импорт не перезаписывает существующий локальный черновик")

	state = _fresh()
	var legacy_approval := _custom_quest("APPROVAL01")
	legacy_approval["approved"] = true
	legacy_approval["is_approved"] = true
	var approval_import := ContentLibraryServiceScript.import_package(state, _package("pack-c08", [legacy_approval]))
	var sanitized := ContentLibraryServiceScript.get_template(state, "APPROVAL01", 1)
	var no_approval := (state.get("phase_b", {}).get("approval_records", []) as Array).is_empty()
	_assert_true(bool(approval_import.get("ok", false)) and not sanitized.has("approved") and not sanitized.has("is_approved") and no_approval and QuestServiceScript.list_player_quests(state).is_empty(), "C08 imported approved:true удаляется и не создаёт взрослое одобрение")

	state = _fresh()
	var with_action := _custom_quest("UNSAFE01")
	with_action["command"] = "noop"
	var with_path := _custom_quest("UNSAFE02")
	with_path["summary"] = "res://outside.gd"
	var with_url := _custom_quest("UNSAFE03")
	with_url["summary"] = "https://example.invalid/task"
	var action_result := ContentLibraryServiceScript.import_package(state, _package("pack-c09-a", [with_action]))
	var path_result := ContentLibraryServiceScript.import_package(state, _package("pack-c09-b", [with_path]))
	var url_result := ContentLibraryServiceScript.import_package(state, _package("pack-c09-c", [with_url]))
	_assert_true(not bool(action_result.get("ok", true)) and not bool(path_result.get("ok", true)) and not bool(url_result.get("ok", true)), "C09 Команды, пути и URL отклоняются как данные пакета")

	var malformed_reward := _custom_quest("MALFORMED01")
	malformed_reward["reward_policy"] = "twenty xp"
	var malformed_variants := _custom_quest("MALFORMED02")
	malformed_variants["variants"] = {"home": true}
	var malformed_reward_result := ContentLibraryServiceScript.import_package(state, _package("pack-c09-d", [malformed_reward]))
	var malformed_variants_result := ContentLibraryServiceScript.import_package(state, _package("pack-c09-e", [malformed_variants]))
	_assert_true(not bool(malformed_reward_result.get("ok", true)) and not bool(malformed_variants_result.get("ok", true)), "C09a Неверные типы вложенных полей отклоняются без падения валидатора")

func _run_c10_c12() -> void:
	print("\n--- C10-C12: frozen instances and limited repeats ---")
	var state := _fresh()
	var v1 := _custom_quest("FREEZE01", 1, "Первая замороженная версия")
	ContentLibraryServiceScript.save_draft(state, v1)
	QuestServiceScript.approve_and_publish(state, ContentLibraryServiceScript.get_template(state, "FREEZE01", 1))
	var created := QuestServiceScript.create_instance(state, "FREEZE01", 1, "home")
	var v2 := v1.duplicate(true)
	v2["revision"] = 2
	v2["title"] = "Новая версия после принятия"
	var saved_v2 := ContentLibraryServiceScript.save_draft(state, v2)
	var snapshot: Dictionary = (created.get("instance", {}) as Dictionary).get("quest_snapshot", {})
	_assert_true(bool(created.get("ok", false)) and bool(saved_v2.get("ok", false)) and str(snapshot.get("title", "")) == "Первая замороженная версия" and int(snapshot.get("revision", 0)) == 1, "C10 Принятый custom-квест хранит frozen snapshot точной ревизии")

	state = _fresh()
	var limited := _custom_quest("REPEAT02", 1, "Можно дважды", "limited", 2)
	ContentLibraryServiceScript.save_draft(state, limited)
	QuestServiceScript.approve_and_publish(state, ContentLibraryServiceScript.get_template(state, "REPEAT02", 1))
	var first_ok := _complete_once(state, "REPEAT02", 1, "repeat-1")
	var second_ok := _complete_once(state, "REPEAT02", 1, "repeat-2")
	var third := QuestServiceScript.create_instance(state, "REPEAT02", 1, "home")
	_assert_true(first_ok and second_ok and not bool(third.get("ok", true)) and str(third.get("reason", "")) == "repeat_limit_reached", "C11 limited-квест блокируется после разрешённого числа завершений")

	state = _fresh()
	var once := _custom_quest("ONCE01")
	ContentLibraryServiceScript.save_draft(state, once)
	QuestServiceScript.approve_and_publish(state, ContentLibraryServiceScript.get_template(state, "ONCE01", 1))
	var once_complete := _complete_once(state, "ONCE01", 1, "once-1")
	var repeated := QuestServiceScript.create_instance(state, "ONCE01", 1, "home")
	_assert_true(once_complete and not bool(repeated.get("ok", true)) and str(repeated.get("reason", "")) == "repeat_limit_reached", "C12 once-квест нельзя завершить повторно")

func _run_c13_c16() -> void:
	print("\n--- C13-C16: save migration, export, offline and regression ---")
	var legacy := SaveServiceScript.get_default_state()
	legacy["schema_version"] = "1.1.0"
	legacy["station_name"] = "Старая станция"
	legacy.erase("phase_c")
	var migrated := SaveServiceScript._merge_with_defaults(legacy)
	var migrated_c: Dictionary = migrated.get("phase_c", {})
	_assert_true(str(migrated.get("schema_version", "")) == "1.3.0" and str(migrated.get("station_name", "")) == "Старая станция" and migrated_c.has("custom_quests") and (migrated_c.get("locations_unlocked", []) as Array).size() == 3, "C13 Схема 1.1 мигрирует в 1.3 с Phase C без потери старых полей")

	var state := _fresh()
	ContentLibraryServiceScript.save_draft(state, _custom_quest("EXPORT01"))
	QuestServiceScript.approve_and_publish(state, ContentRepositoryScript.get_template("S02"))
	var exported := ContentLibraryServiceScript.build_export_package(state)
	var exported_quests: Array = exported.get("quests", [])
	var export_text := JSON.stringify(exported)
	var export_clean := exported_quests.size() == 1 and str((exported_quests[0] as Dictionary).get("quest_id", "")) == "EXPORT01"
	export_clean = export_clean and not export_text.contains("approval_records") and not export_text.contains("approved") and not export_text.contains("res://") and not export_text.contains("user://")
	_assert_true(export_clean, "C14 Экспорт содержит только семейные карточки и не переносит одобрения/системные пути")

	var all_offline := true
	for quest in ContentRepositoryScript.phase_c_templates():
		if bool((quest.get("context", {}) as Dictionary).get("requires_network", true)):
			all_offline = false
	_assert_true(all_offline, "C15 Все встроенные Phase C карточки работают без сети и AI")

	var weather_text := RadioWeatherServiceScript.format_weather_daily({
		"time": ["2026-09-26", "2026-09-27"],
		"weather_code": [2, 61],
		"temperature_2m_max": [14.0, 11.0],
		"temperature_2m_min": [3.0, 5.0],
		"precipitation_probability_max": [10, 70],
		"wind_speed_10m_max": [12.0, 20.0]
	})
	_assert_true(weather_text.contains("Эль-Больсон") and weather_text.contains("Сегодня") and weather_text.contains("Завтра"), "C15a Радио форматирует прогноз Эль-Больсона на сегодня и завтра без зависимости от AI")

	var weather_light_rain := RadioWeatherServiceScript.format_weather_daily({
		"time": ["2026-09-26", "2026-09-27"],
		"weather_code": [0, 51],
		"temperature_2m_max": [16.0, 13.0],
		"temperature_2m_min": [4.0, 6.0],
		"precipitation_sum": [0.0, 0.8],
		"precipitation_probability_max": [5, 45],
		"wind_speed_10m_max": [10.0, 15.0]
	})
	_assert_true(weather_light_rain.contains("без осадков, 0 мм в день") and weather_light_rain.contains("совсем немного дождя, 0.8 мм в день"), "C15b Радио различает сухую погоду и совсем небольшой дождь словами и мм в день")

	var weather_heavy_rain := RadioWeatherServiceScript.format_weather_daily({
		"time": ["2026-09-26", "2026-09-27"],
		"weather_code": [61, 65],
		"temperature_2m_max": [12.0, 10.0],
		"temperature_2m_min": [5.0, 7.0],
		"precipitation_sum": [8.0, 18.0],
		"precipitation_probability_max": [70, 95],
		"wind_speed_10m_max": [14.0, 22.0]
	})
	_assert_true(weather_heavy_rain.contains("умеренный дождь, 8 мм в день") and weather_heavy_rain.contains("много дождя, 18 мм в день"), "C15c Радио различает умеренный дождь и много дождя")

	var weather_deluge_snow := RadioWeatherServiceScript.format_weather_daily({
		"time": ["2026-09-26", "2026-09-27"],
		"weather_code": [82, 73],
		"temperature_2m_max": [9.0, 1.0],
		"temperature_2m_min": [4.0, -3.0],
		"precipitation_sum": [35.0, 12.0],
		"precipitation_probability_max": [100, 80],
		"wind_speed_10m_max": [25.0, 18.0]
	})
	_assert_true(weather_deluge_snow.contains("очень много дождя, 35 мм в день") and weather_deluge_snow.contains("умеренный снегопад, 12 мм в день"), "C15d Радио различает сильный ливень и снегопад")

	state = _fresh()
	var legacy_catalog_ok := ContentRepositoryScript.all_templates().size() == 12 and ContentRepositoryScript.real_quest_templates().size() == 11
	var parent_catalog_ok := ContentLibraryServiceScript.list_parent_templates(state).size() == 38
	var published := QuestServiceScript.approve_and_publish(state, ContentRepositoryScript.get_template("S02"))
	var created := QuestServiceScript.create_instance(state, "S02", 1, "approved_dialogue")
	var instance_id := str((created.get("instance", {}) as Dictionary).get("instance_id", ""))
	var submitted := QuestServiceScript.submit_result(state, instance_id, "activity:c16", "Обычный Phase B цикл")
	var confirmed := QuestServiceScript.confirm_result(state, "activity:c16")
	_assert_true(legacy_catalog_ok and parent_catalog_ok and bool(published.get("ok", false)) and bool(created.get("ok", false)) and bool(submitted.get("ok", false)) and bool(confirmed.get("ok", false)), "C16 Phase B lifecycle и его исторический каталог не ломаются от Phase C")

func _run_c17_c20() -> void:
	print("\n--- C17-C20: featured adventures and movement ritual ---")
	var featured := ContentRepositoryScript.featured_goal_templates()
	var featured_ids: Array[String] = []
	for goal in featured:
		featured_ids.append(str(goal.get("quest_id", "")))
	_assert_true(featured_ids == ["FG01", "FG11", "FG08"], "C17 В центре старта ровно три приключения: 100 слов, первая игра, река и водопады", JSON.stringify(featured_ids))

	var first_goals := ContentRepositoryScript.first_goal_templates()
	_assert_true(not _contains_quest(first_goals, "FG10") and _contains_quest(first_goals, "FG01") and _contains_quest(first_goals, "FG08") and _contains_quest(first_goals, "FG11"), "C17a Разминка больше не оформлена как основная цель")
	var river_goal := ContentRepositoryScript.get_template("FG08")
	_assert_true((river_goal.get("goal_steps", []) as Array) == ["подготовка", "выход", "запись в полевой журнал"], "C18 У приключения к воде есть три понятных этапа")

	var state := _fresh()
	var day_one := RitualServiceScript.mark_day(state, "2026-09-01")
	var duplicate := RitualServiceScript.mark_day(state, "2026-09-01")
	_assert_true(bool(day_one.get("ok", false)) and bool(duplicate.get("already_marked", false)) and int(duplicate.get("days", 0)) == 1, "C19 Одна дата даёт только одну отметку ритуала")

	RitualServiceScript.mark_day(state, "2026-09-03")
	var gap_result := RitualServiceScript.mark_day(state, "2026-09-10")
	_assert_true(int(gap_result.get("days", 0)) == 3 and not bool(gap_result.get("unlocked", true)), "C19a Пропуски дней не сбрасывают ритуал и не требуют серии подряд")

	RitualServiceScript.mark_day(state, "2026-09-21")
	var unlock := RitualServiceScript.mark_day(state, "2026-09-28")
	var effects := ProgressServiceScript.get_profile_world_effects(state, "player_01")
	_assert_true(bool(unlock.get("newly_unlocked", false)) and bool(unlock.get("unlocked", false)) and int(unlock.get("days", 0)) == 5 and effects.has("movement_ritual_light"), "C20 Пятая отдельная дата навсегда открывает огонь станции", JSON.stringify(effects))
