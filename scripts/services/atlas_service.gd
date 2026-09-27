class_name AtlasService
extends RefCounted

## Географический атлас SUR. Координаты нормализованы (0..1), поэтому карта
## может расширяться без переделки UI: новая точка добавляется одной записью.

const DEFAULT_UNLOCKED: Array[String] = ["station"]

const LOCATIONS: Array[Dictionary] = [
	{
		"id": "station",
		"title": "Лесная станция",
		"subtitle": "Эль-Больсон • база",
		"description": "Твоя точка старта. Отсюда постепенно будет раскрываться личный атлас Патагонии.",
		"icon": "◎",
		"map_position": Vector2(0.50, 0.56),
		"distance": "base"
	},
	{
		"id": "rio_azul",
		"title": "Речка неподалёку",
		"subtitle": "Río Azul • совсем рядом",
		"description": "Близкая речная точка. Пока видна только подпись сквозь туман войны.",
		"icon": "≈",
		"map_position": Vector2(0.34, 0.63),
		"distance": "near"
	},
	{
		"id": "waterfalls",
		"title": "Водопады неподалёку",
		"subtitle": "ближняя долина",
		"description": "Одна из первых будущих природных экспедиций рядом с Эль-Больсоном.",
		"icon": "≋",
		"map_position": Vector2(0.35, 0.42),
		"distance": "near"
	},
	{
		"id": "piltriquitron",
		"title": "Вершина Эль-Больсона",
		"subtitle": "Cerro Piltriquitrón",
		"description": "Горная вершина над долиной. На карте она близко, но пока остаётся за туманом войны.",
		"icon": "▲",
		"map_position": Vector2(0.66, 0.42),
		"distance": "near"
	},
	{
		"id": "el_bolson_skatepark",
		"title": "Скейт-парк Эль-Больсона",
		"subtitle": "ролики • ближняя точка",
		"description": "Будущая точка для роликов. Реальный выход открывается только семейным решением.",
		"icon": "◉",
		"map_position": Vector2(0.68, 0.61),
		"distance": "near"
	},
	{
		"id": "lago_puelo",
		"title": "Лаго-Пуэло",
		"subtitle": "озеро и посёлок • южнее",
		"description": "Региональная точка южнее Эль-Больсона. Она заметно дальше ближних мест долины.",
		"icon": "◒",
		"map_position": Vector2(0.48, 0.79),
		"distance": "regional"
	},
	{
		"id": "bariloche",
		"title": "Барилоче — Top 10 National Geographic",
		"marker_title": "Барилоче\nTop 10 National Geographic",
		"subtitle": "Cerro Campanario • дальняя глава",
		"description": "Барилоче заметно дальше мест вокруг Эль-Больсона. На карте отдельно отмечен Cerro Campanario с его знаменитой панорамой.",
		"icon": "✦",
		"map_position": Vector2(0.49, 0.25),
		"distance": "regional"
	},
	{
		"id": "bariloche_skatepark",
		"title": "Скейт-парк Барилоче",
		"subtitle": "ролики • дальняя городская точка",
		"description": "Отдельная будущая точка в районе Барилоче для роликовых заданий.",
		"icon": "◉",
		"map_position": Vector2(0.72, 0.27),
		"distance": "regional"
	},
	{
		"id": "chile",
		"title": "Чили",
		"subtitle": "очень далёкий сектор",
		"description": "Чили — одна из далёких будущих глав. Пока на атласе остаётся только силуэт за густым туманом.",
		"icon": "◁",
		"map_position": Vector2(0.90, 0.52),
		"distance": "distant"
	},
	{
		"id": "whales",
		"title": "Киты",
		"subtitle": "Península Valdés • очень далеко",
		"description": "Атлантический берег и китовый горизонт — очень далёкая будущая глава.",
		"icon": "≈",
		"map_position": Vector2(0.09, 0.40),
		"distance": "distant"
	},
	{
		"id": "ushuaia",
		"title": "Ушуайя",
		"subtitle": "Огненная Земля • очень далеко",
		"description": "Ушуайя — одна из самых далёких отметок текущего атласа. Пока это только имя за туманом.",
		"icon": "▽",
		"map_position": Vector2(0.52, 0.07),
		"distance": "distant"
	}
]

static func list_locations(state: Dictionary) -> Array[Dictionary]:
	var unlocked := _unlocked_ids(state)
	var result: Array[Dictionary] = []
	for location in LOCATIONS:
		var copy := location.duplicate(true)
		copy["unlocked"] = unlocked.has(str(copy.get("id", "")))
		result.append(copy)
	return result

static func get_location(state: Dictionary, location_id: String) -> Dictionary:
	for location in list_locations(state):
		if str(location.get("id", "")) == location_id:
			return location
	return {}

static func is_unlocked(state: Dictionary, location_id: String) -> bool:
	return _unlocked_ids(state).has(location_id)

static func unlock(state: Dictionary, location_id: String) -> bool:
	if get_location({}, location_id).is_empty():
		return false
	var phase_c: Dictionary = state.get("phase_c", {})
	var unlocked: Array = phase_c.get("atlas_unlocked", DEFAULT_UNLOCKED.duplicate())
	if unlocked.has(location_id):
		return false
	unlocked.append(location_id)
	phase_c["atlas_unlocked"] = unlocked
	state["phase_c"] = phase_c
	return true

static func _unlocked_ids(state: Dictionary) -> Array:
	var phase_c: Dictionary = state.get("phase_c", {})
	var unlocked_value: Variant = phase_c.get("atlas_unlocked", DEFAULT_UNLOCKED)
	if typeof(unlocked_value) != TYPE_ARRAY:
		return DEFAULT_UNLOCKED.duplicate()
	var unlocked: Array = (unlocked_value as Array).duplicate()
	if not unlocked.has("station"):
		unlocked.append("station")
	return unlocked
