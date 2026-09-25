class_name QuestRules
extends RefCounted

## Правила и валидация пролога S00 «Это моя станция»

const S00_ID := "S00_my_station"

const DIAL_DATA: Array[Array] = [
	[
		{"id": "mountain", "title": "Гора", "desc": "Вершина Серро Пилтрикитрон"},
		{"id": "river", "title": "Река", "desc": "Быстрые воды Рио Асуль"},
		{"id": "forest", "title": "Лес", "desc": "Патагонский кедровый лес"}
	],
	[
		{"id": "wind", "title": "Ветер", "desc": "Свежий южный ветер с гор"},
		{"id": "fire", "title": "Огонь", "desc": "Тёплый очаг мастерской"},
		{"id": "rain", "title": "Дождь", "desc": "Шорох капель по крыше"}
	],
	[
		{"id": "star", "title": "Звезда", "desc": "Путеводная звезда ночного неба"},
		{"id": "moon", "title": "Луна", "desc": "Серебристый свет над хребтом"},
		{"id": "sun", "title": "Солнце", "desc": "Золотой рассвет долины"}
	]
]

const SOLUTION: Array[int] = [0, 0, 0] # Гора, Ветер, Звезда

const EMBLEM_PRESETS: Array[Dictionary] = [
	{"id": "feather", "title": "Перо", "desc": "Вдохновение, дневник и наблюдения"},
	{"id": "star", "title": "Звезда", "desc": "Путешествия, ориентиры и обсерватория"},
	{"id": "sprout", "title": "Росток", "desc": "Природа, сад и бережное развитие"},
	{"id": "gear", "title": "Шестерёнка", "desc": "Мастерская, механизмы и конструирование"}
]

const DESK_PROPS: Array[Dictionary] = [
	{
		"id": "compass",
		"title": "Латунный компас",
		"desc": "Надёжный морской компас в полированном латунном корпусе."
	},
	{
		"id": "crystal",
		"title": "Светящийся кристалл",
		"desc": "Минерал из местных пещер с мягким люминесцентным сиянием."
	},
	{
		"id": "owl",
		"title": "Резная сова",
		"desc": "Фигурка совы, вручную выточенная из ароматного патагонского кедра."
	},
	{
		"id": "astrolabe",
		"title": "Походная астролябия",
		"desc": "Старинный навигационный прибор для наблюдения за созвездиями."
	}
]

static func check_solution(current_dials: Array) -> bool:
	if current_dials.size() != SOLUTION.size():
		return false
	for i in range(SOLUTION.size()):
		if int(current_dials[i]) != SOLUTION[i]:
			return false
	return true

static func get_clue_text() -> String:
	return "«Сначала поднимись на вершину высокой горы.\nЗатем почувствуй, куда дует свежий южный ветер.\nИ тогда в ночном небе вспыхнет путеводная звезда.»"

static func get_hint_text() -> String:
	return "Подсказка из журнала: правильный порядок символов на дисках — Гора (1), Ветер (2), Звезда (3)."

static func is_s00_complete(progress: Dictionary) -> bool:
	return (
		bool(progress.get("sign_named", false)) and
		bool(progress.get("prop_arranged", false)) and
		bool(progress.get("puzzle_solved", false)) and
		bool(progress.get("station_awakened", false))
	)

static func create_default_progress() -> Dictionary:
	return {
		"sign_named": false,
		"prop_arranged": false,
		"puzzle_solved": false,
		"station_awakened": false
	}
