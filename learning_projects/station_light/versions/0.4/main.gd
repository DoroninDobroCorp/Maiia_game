extends Node2D
## Экран и управление. Правила находятся в game_state.gd; выбор автора — в lesson.json.

const GameState = preload("game_state.gd")
const INK: Color = Color("283e38")
const MUTED: Color = Color("58675c")
const CREAM: Color = Color("f6f2e9")

var game: GameState
var pointer_direction: Vector2 = Vector2.ZERO
var counter_label: Label
var goal_label: Label
var status_label: Label
var restart_button: Button
var direction_buttons: Array[Button] = []
var victory_panel: Panel
var accent: Color = Color("c66a43")
var glow: Color = Color("f4ba52")

func _ready() -> void:
	var settings: Dictionary = {}
	# Относительно скрипта: сцену можно загрузить и из теста в другом проекте.
	var settings_path: String = get_script().resource_path.get_base_dir().path_join("lesson.json")
	if FileAccess.file_exists(settings_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
		if parsed is Dictionary:
			settings = parsed
	game = GameState.new(settings)
	if game.theme_name == "moss":
		accent = Color("39776e")
		glow = Color("d6b45b")
	_install_input()
	_build_interface()
	game.changed.connect(_refresh)
	_refresh()

func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("light_left", "light_right", "light_up", "light_down")
	game.move_hero((direction + pointer_direction).limit_length(1.0), minf(delta, 0.1))

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("light_restart") and not event.is_echo():
		restart_game()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# Отпускание мыши вне кнопки тоже останавливает движение.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		pointer_direction = Vector2.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		pointer_direction = Vector2.ZERO
		for action: String in ["light_left", "light_right", "light_up", "light_down"]:
			if InputMap.has_action(action):
				Input.action_release(action)

func restart_game() -> bool:
	pointer_direction = Vector2.ZERO
	return game.restart()

func _install_input() -> void:
	var bindings: Dictionary = {
		"light_left": [KEY_LEFT, KEY_A], "light_right": [KEY_RIGHT, KEY_D],
		"light_up": [KEY_UP, KEY_W], "light_down": [KEY_DOWN, KEY_S],
		"light_restart": [KEY_R],
	}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)

func _build_interface() -> void:
	_label("МАСТЕРСКАЯ SUR  /  МАЛЕНЬКАЯ ИГРА", Rect2(44, 25, 690, 28), 15, MUTED)
	_label("Собери свет для станции", Rect2(42, 62, 990, 58), 38, INK)
	goal_label = _label("", Rect2(44, 122, 830, 42), 21, MUTED)
	var badge := _label("ВЕРСИЯ " + game.version, Rect2(874, 27, 180, 26), 15, MUTED)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel(Rect2(42, 184, 1016, 384), Color("e5e6d6"), 26)
	_label("САД У СТАНЦИИ", Rect2(66, 199, 330, 25), 13, MUTED)
	counter_label = _label("", Rect2(879, 119, 178, 43), 28, INK)
	counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Поле рисуется ниже интерфейса, панели пропускают мышь.
	var instructions := _panel(Rect2(42, 586, 1016, 122), Color("fffcf5"), 22)
	instructions.z_index = -1
	_label("Твой ход", Rect2(65, 604, 140, 30), 22, INK)
	_label("Стрелки / WASD", Rect2(65, 643, 220, 27), 17, MUTED)
	var directions: Array[Vector2] = [Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2.RIGHT]
	var symbols: Array[String] = ["←", "↑", "↓", "→"]
	var descriptions: Array[String] = ["Влево", "Вверх", "Вниз", "Вправо"]
	for index in range(4):
		var button := _button(symbols[index], Rect2(285 + index * 61, 616, 53, 57), false)
		button.tooltip_text = descriptions[index] + ": удерживай мышь или нажми Enter"
		button.button_down.connect(func() -> void: pointer_direction = directions[index])
		button.button_up.connect(func() -> void: pointer_direction = Vector2.ZERO)
		direction_buttons.append(button)
	_label("Можно идти\nв своём темпе.", Rect2(553, 619, 229, 57), 17, MUTED)
	restart_button = _button("Начать снова · R", Rect2(800, 618, 231, 55), true)
	restart_button.pressed.connect(restart_game)
	restart_button.visible = game.can_restart()
	if not game.can_restart():
		_label("Повтор: закрой окно\nи запусти эту версию.", Rect2(804, 620, 231, 65), 16, MUTED)
	status_label = _label("", Rect2(50, 531, 995, 31), 17, INK)
	_label("Учебная основа • свои решения и изменения отметь в карточке авторства", Rect2(45, 723, 1015, 23), 13, MUTED)
	victory_panel = _panel(Rect2(292, 275, 516, 229), Color("fffcf5"), 25)
	victory_panel.z_index = 10
	var victory_title := _label("Свет собран!", Rect2(318, 293, 464, 44), 32, INK)
	var message := _label(game.win_message, Rect2(318, 344, 464, 82), 23, INK)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var next_hint := _label("Ещё одна прогулка? Нажми R или «Начать снова».", Rect2(318, 434, 464, 54), 17, MUTED)
	if not game.can_restart():
		next_hint.text = "Победа работает! Перезапуск появится в версии 0.4."
	next_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for label: Label in [victory_title, message, next_hint]:
		label.reparent(victory_panel, true)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _refresh() -> void:
	counter_label.text = "%d / 3 огонька" % game.count
	goal_label.text = "Собери три огонька — подойди к каждому."
	if game.stage == 1:
		goal_label.text = "Исследуй сад: научи героя двигаться."
		counter_label.text = "ДВИЖЕНИЕ"
		status_label.text = "Проверь: по диагонали герой идёт с той же скоростью?"
	elif game.stage == 2:
		status_label.text = "Счётчик работает. Победу добавим в версии 0.3."
	elif game.has_won:
		status_label.text = "Все три огонька дома. Спасибо за свет!"
	else:
		status_label.text = "Огонёк считается один раз. Здесь нет спешки."
	victory_panel.visible = game.has_won
	queue_redraw()

func _draw() -> void:
	if game == null:
		return
	# Тёплая дорожка, клумбы и маленький дом станции; внешних ресурсов нет.
	_draw_round(Rect2(109, 289, 860, 205), Color("eee8d8"), 85)
	draw_line(Vector2(177, 403), Vector2(915, 403), Color("dcd7c7"), 2.0)
	for x in range(192, 929, 92):
		draw_line(Vector2(x, 327), Vector2(x, 479), Color("e1dccd"), 1.0)
	for place: Vector2 in [Vector2(94, 279), Vector2(244, 496), Vector2(632, 266), Vector2(976, 493)]:
		_draw_plant(place)
	_draw_station(Vector2(944, 285))
	# Все предметы отмечены и номером, и формой, а не одним цветом.
	if game.can_collect():
		for index in range(GameState.LIGHT_COUNT):
			if not game.collected[index]:
				_draw_light(game.light_positions[index], index)
	_draw_hero(game.hero_position)

func _draw_hero(point: Vector2) -> void:
	draw_ellipse_shadow(point + Vector2(0, 23), Vector2(24, 7))
	_draw_round(Rect2(point + Vector2(-18, -12), Vector2(36, 36)), accent, 13)
	draw_circle(point + Vector2(0, -17), 16, Color("f2d1a8"))
	draw_arc(point + Vector2(0, -21), 16, PI, TAU, 20, INK, 8, true)
	draw_circle(point + Vector2(-5, -18), 1.8, INK)
	draw_circle(point + Vector2(5, -18), 1.8, INK)
	draw_line(point + Vector2(-15, 2), point + Vector2(16, 2), Color("f9dda0"), 5, true)
	draw_line(point + Vector2(-8, 22), point + Vector2(-8, 29), INK, 6, true)
	draw_line(point + Vector2(8, 22), point + Vector2(8, 29), INK, 6, true)

func _draw_light(point: Vector2, index: int) -> void:
	draw_circle(point, 30, Color(glow, 0.15))
	draw_circle(point, 22, Color(glow, 0.26))
	var diamond := PackedVector2Array([point + Vector2(0, -17), point + Vector2(12, 0), point + Vector2(0, 17), point + Vector2(-12, 0)])
	draw_colored_polygon(diamond, glow)
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("a76c24"), 2, true)
	draw_circle(point + Vector2(-3, -5), 3, Color("fff7d3"))
	draw_string(ThemeDB.fallback_font, point + Vector2(-5, 44), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MUTED)

func _draw_station(point: Vector2) -> void:
	_draw_round(Rect2(point + Vector2(-38, 1), Vector2(76, 67)), Color("bf8c61"), 8)
	draw_colored_polygon(PackedVector2Array([point + Vector2(-49, 6), point + Vector2(0, -27), point + Vector2(49, 6)]), INK)
	for index in range(3):
		var window_color: Color = glow if game.count > index else Color("e8dbc1")
		_draw_round(Rect2(point + Vector2(-28 + index * 21, 22), Vector2(15, 24)), window_color, 3)
	if game.has_won:
		draw_arc(point, 84, PI * 1.08, PI * 1.91, 30, Color(glow, 0.7), 5, true)

func _draw_plant(point: Vector2) -> void:
	draw_circle(point, 16, Color("c3cbb2"))
	draw_line(point + Vector2(0, 8), point + Vector2(0, -20), Color("678368"), 3, true)
	draw_circle(point + Vector2(-7, -12), 8, Color("839b78"))
	draw_circle(point + Vector2(8, -21), 9, Color("839b78"))

func draw_ellipse_shadow(point: Vector2, ellipse_size: Vector2) -> void:
	draw_set_transform(point, 0, ellipse_size)
	draw_circle(Vector2.ZERO, 1.0, Color(0.20, 0.28, 0.21, 0.13))
	draw_set_transform(Vector2.ZERO)

func _draw_round(rect: Rect2, color: Color, radius: int) -> void:
	_style(color, radius).draw(get_canvas_item(), rect)

func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style

func _panel(rect: Rect2, color: Color, radius: int) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(color, radius))
	# Panels behind Node2D drawing, except the explicit victory overlay.
	panel.z_index = -1
	add_child(panel)
	return panel

func _label(text: String, rect: Rect2, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _button(text: String, rect: Rect2, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 19 if primary else 29)
	button.add_theme_color_override("font_color", Color("fffcf5") if primary else INK)
	button.add_theme_color_override("font_hover_color", Color("fffcf5") if primary else INK)
	button.add_theme_color_override("font_pressed_color", Color("fffcf5") if primary else INK)
	var base: Color = INK if primary else Color("edece0")
	button.add_theme_stylebox_override("normal", _style(base, 13))
	button.add_theme_stylebox_override("hover", _style(base.lightened(0.08), 13))
	button.add_theme_stylebox_override("pressed", _style(base.darkened(0.08), 13))
	var focus := _style(Color(0, 0, 0, 0), 13)
	focus.border_color = accent
	focus.set_border_width_all(3)
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	button.add_theme_stylebox_override("focus", focus)
	add_child(button)
	return button
