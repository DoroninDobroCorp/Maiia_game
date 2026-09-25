extends SceneTree

## Автоматизированные приёмочные тесты Фазы A (A01 - A06)
## SUR: Vertical Slice Verification

var failed_count: int = 0
var passed_count: int = 0

func _init() -> void:
	print("\n==================================================")
	print("  SUR — Запуск приёмочных проверок Фазы A (A01-A06)")
	print("==================================================\n")
	
	_run_test_a01()
	_run_test_a02_a03()
	_run_test_a04()
	_run_test_a05()
	_run_test_a06()
	
	print("\n==================================================")
	if failed_count == 0:
		print("  ИТОГ: ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО! (", passed_count, " проверок)")
		print("==================================================\n")
		quit(0)
	else:
		print("  ИТОГ: ОБНАРУЖЕНЫ ОШИБКИ (Провалено: ", failed_count, ", Пройдено: ", passed_count, ")")
		print("==================================================\n")
		quit(1)

func _assert_true(condition: bool, test_name: String, details: String = "") -> void:
	if condition:
		passed_count += 1
		print("  [PASS] ", test_name)
	else:
		failed_count += 1
		print("  [FAIL] ", test_name, " -> ", details)

func _run_test_a01() -> void:
	print("--- Тест A01: Первый запуск без сети и внешних зависимостей ---")
	var save_svc = preload("res://scripts/services/save_service.gd")
	var fresh_state: Dictionary = save_svc.get_default_state()
	
	_assert_true(fresh_state.has("schema_version"), "A01.1 Наличие схемы сохранения")
	_assert_true(fresh_state.get("station_name") == "Лесная станция", "A01.2 Начальное имя станции")
	_assert_true(fresh_state.get("puzzle_solved") == false, "A01.3 Загадка изначально не решена")
	_assert_true(fresh_state.get("radio_powered") == false, "A01.4 Радио изначально выключено")
	_assert_true(fresh_state.get("achievements").size() == 0, "A01.5 Начальный список достижений пуст")

func _run_test_a02_a03() -> void:
	print("\n--- Тесты A02 и A03: Изменение оформления и сохранение после перезапуска ---")
	var save_svc = preload("res://scripts/services/save_service.gd")
	var prog_rules = preload("res://scripts/domain/progression_rules.gd")
	
	var test_state: Dictionary = save_svc.get_default_state()
	test_state["station_name"] = "Маяк Рио Асуль"
	test_state["station_emblem"] = "feather"
	test_state["desk_prop_id"] = "crystal"
	
	var s00: Dictionary = test_state.get("s00_progress", {})
	s00["sign_named"] = true
	s00["prop_arranged"] = true
	test_state["s00_progress"] = s00
	
	prog_rules.unlock_achievement(test_state, "station_keeper")
	prog_rules.unlock_achievement(test_state, "master_curator")
	
	# Сохраняем
	var save_ok: bool = save_svc.save_game(test_state)
	_assert_true(save_ok, "A02.1 Атомарное сохранение выполнено")
	
	# Имитируем перезапуск приложения: читаем заново с диска
	var loaded_state: Dictionary = save_svc.load_game()
	_assert_true(loaded_state.get("station_name") == "Маяк Рио Асуль", "A03.1 Имя станции восстановлено после перезапуска")
	_assert_true(loaded_state.get("station_emblem") == "feather", "A03.2 Символ восстановлен")
	_assert_true(loaded_state.get("desk_prop_id") == "crystal", "A03.3 Экспонат 'crystal' восстановлен")
	_assert_true(prog_rules.has_achievement(loaded_state, "station_keeper"), "A03.4 Достижение 'station_keeper' сохранено")
	_assert_true(prog_rules.has_achievement(loaded_state, "master_curator"), "A03.5 Достижение 'master_curator' сохранено")

func _run_test_a04() -> void:
	print("\n--- Тест A04: Головоломка с ошибкой, подсказкой и решением ---")
	var quest_rules = preload("res://scripts/domain/quest_rules.gd")
	var prog_rules = preload("res://scripts/domain/progression_rules.gd")
	var save_svc = preload("res://scripts/services/save_service.gd")
	
	# Ошибочная комбинация
	var wrong_dials: Array[int] = [1, 2, 0]
	var is_wrong_solved: bool = quest_rules.check_solution(wrong_dials)
	_assert_true(not is_wrong_solved, "A04.1 Ошибочная комбинация не открывает замок")
	
	# Проверка подсказки (доступна без штрафа)
	var hint: String = quest_rules.get_hint_text()
	_assert_true(hint.contains("Гора (1)"), "A04.2 Подсказка содержит ясный намёк на диск 1")
	_assert_true(hint.contains("Ветер (2)"), "A04.3 Подсказка содержит намёк на диск 2")
	_assert_true(hint.contains("Звезда (3)"), "A04.4 Подсказка содержит намёк на диск 3")
	
	# Правильная комбинация
	var correct_dials: Array[int] = [0, 0, 0]
	var is_correct_solved: bool = quest_rules.check_solution(correct_dials)
	_assert_true(is_correct_solved, "A04.5 Правильная комбинация [0, 0, 0] открывает замок")
	
	# Проверка применения решения и защита от повторного начисления (идемпотентность)
	var state: Dictionary = save_svc.load_game()
	var unlock_1: bool = prog_rules.unlock_achievement(state, "first_world_change")
	var unlock_2: bool = prog_rules.unlock_achievement(state, "first_world_change")
	_assert_true(unlock_1 == true, "A04.6 Первое начисление достижения успешно")
	_assert_true(unlock_2 == false, "A04.7 Повторное начисление отклонено (защита от дублирования)")

func _run_test_a05() -> void:
	print("\n--- Тест A05: Целостность журналов и прогресса пролога S00 ---")
	var quest_rules = preload("res://scripts/domain/quest_rules.gd")
	var prog_rules = preload("res://scripts/domain/progression_rules.gd")
	
	var full_progress: Dictionary = {
		"sign_named": true,
		"prop_arranged": true,
		"puzzle_solved": true,
		"station_awakened": true
	}
	_assert_true(quest_rules.is_s00_complete(full_progress), "A05.1 Все 4 условия пролога S00 выполнены")
	
	var partial_progress: Dictionary = {
		"sign_named": true,
		"prop_arranged": false,
		"puzzle_solved": false,
		"station_awakened": false
	}
	_assert_true(not quest_rules.is_s00_complete(partial_progress), "A05.2 Частичный прогресс не завершает пролог")
	_assert_true(prog_rules.ACHIEVEMENTS.size() >= 3, "A05.3 В каталоге достижений зарегистрировано минимум 3 значка")

func _run_test_a06() -> void:
	print("\n--- Тест A06: Настройки доступности (Масштаб UI, Mute, Reduce Motion) ---")
	var save_svc = preload("res://scripts/services/save_service.gd")
	
	var state: Dictionary = save_svc.load_game()
	var settings: Dictionary = state.get("settings", {})
	settings["muted"] = true
	settings["reduce_motion"] = true
	settings["ui_scale"] = 1.25
	settings["master_volume"] = 0.5
	state["settings"] = settings
	
	save_svc.save_game(state)
	
	var reloaded: Dictionary = save_svc.load_game()
	var reloaded_settings: Dictionary = reloaded.get("settings", {})
	_assert_true(reloaded_settings.get("muted") == true, "A06.1 Режим 'muted' сохранён")
	_assert_true(reloaded_settings.get("reduce_motion") == true, "A06.2 Режим 'reduce_motion' сохранён")
	_assert_true(float(reloaded_settings.get("ui_scale")) == 1.25, "A06.3 Масштаб интерфейса 125% сохранён")
	_assert_true(float(reloaded_settings.get("master_volume")) == 0.5, "A06.4 Уровень громкости сохранён")
