extends RefCounted
## Правила игры без экрана, файлов и сохранений. Их можно проверить отдельно.

signal changed
signal light_collected(index: int, count: int)
signal won

const LIGHT_COUNT: int = 3
const HERO_RADIUS: float = 18.0
const PICKUP_RADIUS: float = 34.0
const PLAY_AREA: Rect2 = Rect2(72, 234, 956, 300)
const DEFAULT_LIGHTS: Array[Vector2] = [Vector2(340, 310), Vector2(565, 475), Vector2(800, 310)]

var version: String = "1.0"
var stage: int = 5
var speed: float = 220.0
var theme_name: String = "sunset"
var win_message: String = "Станция снова светится!"
var hero_start: Vector2 = Vector2(154, 422)
var hero_position: Vector2
var light_positions: Array[Vector2] = []
var collected: Array[bool] = [false, false, false]
var count: int = 0
var has_won: bool = false

func _init(settings: Dictionary = {}) -> void:
	version = str(settings.get("version", "1.0"))
	stage = clampi(int(settings.get("stage", 5)), 1, 5)
	speed = clampf(float(settings.get("speed", 220.0)), 40.0, 600.0)
	theme_name = str(settings.get("theme", "sunset"))
	win_message = str(settings.get("win_message", win_message)).strip_edges().left(90)
	if win_message.is_empty():
		win_message = "Станция снова светится!"
	hero_start = _read_point(settings.get("hero_start"), hero_start)
	var supplied: Variant = settings.get("lights", [])
	for index in range(LIGHT_COUNT):
		var point: Vector2 = DEFAULT_LIGHTS[index]
		if supplied is Array and index < supplied.size():
			point = _read_point(supplied[index], point)
		light_positions.append(point)
	_reset_attempt()

func can_collect() -> bool:
	return stage >= 2

func can_win() -> bool:
	return stage >= 3

func can_restart() -> bool:
	return stage >= 4

func move_hero(direction: Vector2, delta: float) -> void:
	if has_won or delta <= 0.0 or not is_finite(delta) or not direction.is_finite():
		return
	var previous: Vector2 = hero_position
	# normalized/limit_length: диагональ не должна быть быстрее прямого пути.
	hero_position = _inside(hero_position + direction.limit_length(1.0) * speed * delta)
	if can_collect():
		for index in range(LIGHT_COUNT):
			# Проверяем весь путь кадра: быстрый герой не перескакивает огонёк.
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(light_positions[index], previous, hero_position)
			if nearest.distance_to(light_positions[index]) <= PICKUP_RADIUS:
				_collect(index)
	if hero_position != previous:
		changed.emit()

func try_collect_light(index: int) -> bool:
	if index < 0 or index >= LIGHT_COUNT:
		return false
	if hero_position.distance_to(light_positions[index]) > PICKUP_RADIUS:
		return false
	return _collect(index)

func restart() -> bool:
	if not can_restart():
		return false
	_reset_attempt()
	changed.emit()
	return true

func snapshot() -> Dictionary:
	# Копии массивов не позволяют проверке случайно изменить саму игру.
	return {
		"version": version, "stage": stage, "hero_position": hero_position,
		"hero_start": hero_start, "light_positions": light_positions.duplicate(),
		"collected": collected.duplicate(), "count": count, "has_won": has_won,
	}

func _collect(index: int) -> bool:
	if not can_collect() or has_won or collected[index]:
		return false
	# Сначала помечаем огонёк: повторное касание не увеличит счётчик.
	collected[index] = true
	count += 1
	var became_won: bool = can_win() and count == LIGHT_COUNT
	if became_won:
		has_won = true
	light_collected.emit(index, count)
	if became_won:
		won.emit()
	changed.emit()
	return true

func _reset_attempt() -> void:
	hero_position = hero_start
	collected = [false, false, false]
	count = 0
	has_won = false

func _inside(point: Vector2) -> Vector2:
	return Vector2(
		clampf(point.x, PLAY_AREA.position.x + HERO_RADIUS, PLAY_AREA.end.x - HERO_RADIUS),
		clampf(point.y, PLAY_AREA.position.y + HERO_RADIUS, PLAY_AREA.end.y - HERO_RADIUS)
	)

func _read_point(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() == 2:
		if (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
			var point := Vector2(float(value[0]), float(value[1]))
			if point.is_finite():
				return _inside(point)
	return _inside(fallback)
