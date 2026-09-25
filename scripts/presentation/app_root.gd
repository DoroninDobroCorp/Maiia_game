class_name AppRoot
extends Node

## Корневой контроллер игры SUR (Phase A / Vertical Slice)
## Управляет 3D-комнатой станции, сохранениями, звуком и модальными окнами.

const SaveServiceScript = preload("res://scripts/services/save_service.gd")
const AudioServiceScript = preload("res://scripts/services/audio_service.gd")
const QuestRulesScript = preload("res://scripts/domain/quest_rules.gd")
const ProgressionRulesScript = preload("res://scripts/domain/progression_rules.gd")

const StationRoomScene = preload("res://scenes/world/station_room.tscn")
const SymbolDialsScene = preload("res://scenes/minigames/symbol_dials.tscn")
const AuthorTerminalScene = preload("res://scenes/ui/author_terminal.tscn")
const JournalScene = preload("res://scenes/ui/journal.tscn")
const SettingsScene = preload("res://scenes/ui/settings_dialog.tscn")

var game_state: Dictionary = {}
var audio_service: Node
var station_room: Node3D

# UI слои
var ui_layer: CanvasLayer
var hud_root: Control
var modal_container: Control

var header_station_lbl: Label
var header_quest_lbl: Label
var hover_tooltip_panel: PanelContainer
var hover_tooltip_lbl: Label
var toast_panel: PanelContainer
var toast_lbl: Label
var toast_timer: Timer

func _ready() -> void:
	# 1. Инициализация звука
	audio_service = AudioServiceScript.new()
	add_child(audio_service)
	
	# 2. Загрузка сохранения
	game_state = SaveServiceScript.load_game()
	
	# 3. Создание 3D сцены комнаты станции
	station_room = StationRoomScene.instantiate()
	add_child(station_room)
	station_room.prop_clicked.connect(_on_prop_clicked)
	station_room.prop_hovered.connect(_on_prop_hovered)
	station_room.prop_unhovered.connect(_on_prop_unhovered)
	
	# 4. Создание интерфейса HUD и контейнера модальных окон
	_setup_hud()
	
	# 5. Применение загруженного состояния к миру и настройкам
	_apply_state_to_world(false)
	_apply_settings(game_state.get("settings", {}))
	audio_service.start_ambient()
	
	# Приветственное сообщение при первом входе
	var s00: Dictionary = game_state.get("s00_progress", {})
	if not bool(s00.get("station_awakened", false)):
		show_toast("Добро пожаловать на станцию! Осмотри предметы на верстаке, измени вывеску или открой шкатулку с дисками.")
	else:
		show_toast("С возвращением на станцию «" + str(game_state.get("station_name", "Лесная станция")) + "»!")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.keycode == KEY_ESCAPE:
				if modal_container.get_child_count() > 0:
					_close_modals()
				else:
					open_settings()
			elif k.keycode == KEY_J:
				if modal_container.get_child_count() > 0:
					_close_modals()
				else:
					open_journal()
			elif k.keycode == KEY_F12:
				take_screenshot("screenshots/manual_capture.png")

# ==================== ПОСТРОЕНИЕ HUD ====================

func _setup_hud() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_PASS
	ui_layer.add_child(hud_root)
	
	# Верхняя информационная панель
	var top_bar := PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.custom_minimum_size = Vector2(0, 48)
	var tb_style := StyleBoxFlat.new()
	tb_style.bg_color = Color(0.08, 0.08, 0.12, 0.86)
	tb_style.border_color = Color(0.88, 0.72, 0.32, 0.5)
	tb_style.border_width_bottom = 1
	tb_style.content_margin_left = 20
	tb_style.content_margin_right = 20
	tb_style.content_margin_top = 8
	tb_style.content_margin_bottom = 8
	top_bar.add_theme_stylebox_override("panel", tb_style)
	hud_root.add_child(top_bar)
	
	var top_hbox := HBoxContainer.new()
	top_bar.add_child(top_hbox)
	
	header_station_lbl = Label.new()
	header_station_lbl.add_theme_font_size_override("font_size", 16)
	header_station_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.60))
	header_station_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(header_station_lbl)
	
	header_quest_lbl = Label.new()
	header_quest_lbl.add_theme_font_size_override("font_size", 13)
	header_quest_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	top_hbox.add_child(header_quest_lbl)
	
	# Всплывающее уведомление (Toast)
	toast_panel = PanelContainer.new()
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.position = Vector2(-320, 62)
	toast_panel.custom_minimum_size = Vector2(640, 44)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.14, 0.13, 0.18, 0.94)
	t_style.border_color = Color(0.88, 0.72, 0.32, 0.85)
	t_style.set_border_width_all(1)
	t_style.set_corner_radius_all(8)
	t_style.set_content_margin_all(12)
	toast_panel.add_theme_stylebox_override("panel", t_style)
	toast_panel.visible = false
	hud_root.add_child(toast_panel)
	
	toast_lbl = Label.new()
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_lbl.add_theme_font_size_override("font_size", 14)
	toast_lbl.add_theme_color_override("font_color", Color(0.98, 0.94, 0.82))
	toast_panel.add_child(toast_lbl)
	
	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.wait_time = 5.0
	toast_timer.timeout.connect(func(): toast_panel.visible = false)
	add_child(toast_timer)
	
	# Подсказка при наведении на 3D-предмет
	hover_tooltip_panel = PanelContainer.new()
	hover_tooltip_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hover_tooltip_panel.position = Vector2(-200, -115)
	hover_tooltip_panel.custom_minimum_size = Vector2(400, 36)
	hover_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h_style := StyleBoxFlat.new()
	h_style.bg_color = Color(0.10, 0.10, 0.14, 0.92)
	h_style.border_color = Color(1.0, 0.85, 0.45, 0.9)
	h_style.set_border_width_all(1)
	h_style.set_corner_radius_all(6)
	h_style.set_content_margin_all(8)
	hover_tooltip_panel.add_theme_stylebox_override("panel", h_style)
	hover_tooltip_panel.visible = false
	hud_root.add_child(hover_tooltip_panel)
	
	hover_tooltip_lbl = Label.new()
	hover_tooltip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_tooltip_lbl.add_theme_font_size_override("font_size", 14)
	hover_tooltip_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.68))
	hover_tooltip_panel.add_child(hover_tooltip_lbl)
	
	# Нижняя панель быстрых действий
	var bottom_bar := PanelContainer.new()
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.custom_minimum_size = Vector2(0, 58)
	bottom_bar.offset_top = -58
	var bb_style := StyleBoxFlat.new()
	bb_style.bg_color = Color(0.08, 0.08, 0.12, 0.90)
	bb_style.border_color = Color(0.88, 0.72, 0.32, 0.5)
	bb_style.border_width_top = 1
	bb_style.set_content_margin_all(10)
	bottom_bar.add_theme_stylebox_override("panel", bb_style)
	hud_root.add_child(bottom_bar)
	
	var nav_hbox := HBoxContainer.new()
	nav_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_hbox.add_theme_constant_override("separation", 12)
	bottom_bar.add_child(nav_hbox)
	
	_add_nav_btn(nav_hbox, "📖 Журнал [J]", func(): open_journal())
	_add_nav_btn(nav_hbox, "🛠 Оформить станцию", func(): open_author_terminal())
	_add_nav_btn(nav_hbox, "🔐 Шкатулка с дисками", func(): open_puzzle_box())
	_add_nav_btn(nav_hbox, "📻 Радио «Южный Маяк»", func(): _interact_radio())
	_add_nav_btn(nav_hbox, "🗺 Карта долины", func(): _interact_map())
	_add_nav_btn(nav_hbox, "⚙ Настройки [Esc]", func(): open_settings())
	
	# Контейнер модальных окон поверх HUD
	modal_container = Control.new()
	modal_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(modal_container)

func _add_nav_btn(parent: Control, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(150, 36)
	btn.pressed.connect(callback)
	parent.add_child(btn)

# ==================== СОСТОЯНИЕ И ДЕЙСТВИЯ В МИРЕ ====================

func _apply_state_to_world(animate_transition: bool = false) -> void:
	var s_name: String = str(game_state.get("station_name", "Лесная станция"))
	var s_emblem: String = str(game_state.get("station_emblem", "star"))
	var prop_id: String = str(game_state.get("desk_prop_id", "compass"))
	var solved: bool = bool(game_state.get("puzzle_solved", false))
	var dials: Array = game_state.get("puzzle_state", [1, 2, 1])
	
	station_room.update_station_sign(s_name, s_emblem)
	station_room.update_desk_prop(prop_id)
	station_room.update_dials_visual(dials)
	station_room.set_world_stage(solved, animate_transition)
	
	_update_hud_labels()

func _update_hud_labels() -> void:
	var emblem_icons := {"feather": "🪶", "star": "✦", "sprout": "🌱", "gear": "⚙"}
	var s_emblem: String = str(game_state.get("station_emblem", "star"))
	var icon: String = emblem_icons.get(s_emblem, "✦")
	var s_name: String = str(game_state.get("station_name", "Лесная станция"))
	
	header_station_lbl.text = icon + " " + s_name + " (Эль-Больсон)"
	
	var s00: Dictionary = game_state.get("s00_progress", {})
	var done_count: int = 0
	if bool(s00.get("sign_named", false)):
		done_count += 1
	if bool(s00.get("prop_arranged", false)):
		done_count += 1
	if bool(s00.get("puzzle_solved", false)):
		done_count += 1
	if bool(s00.get("station_awakened", false)):
		done_count += 1
	
	if done_count >= 4:
		header_quest_lbl.text = "✓ Пролог S00 завершён (4/4) • Станция пробуждена"
		header_quest_lbl.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
	else:
		header_quest_lbl.text = "Задача S00 «Это моя станция»: шагов выполнено " + str(done_count) + "/4"
		header_quest_lbl.add_theme_color_override("font_color", Color(0.92, 0.86, 0.72))

func _on_prop_hovered(_prop_id: String, prop_title: String) -> void:
	if modal_container.get_child_count() > 0:
		return
	hover_tooltip_lbl.text = "✦ " + prop_title
	hover_tooltip_panel.visible = true

func _on_prop_unhovered(_prop_id: String) -> void:
	hover_tooltip_panel.visible = false

func _on_prop_clicked(prop_id: String) -> void:
	if modal_container.get_child_count() > 0:
		return
	hover_tooltip_panel.visible = false
	
	match prop_id:
		"station_sign":
			open_author_terminal()
		"puzzle_box":
			open_puzzle_box()
		"desk_prop":
			_interact_desk_prop()
		"radio":
			_interact_radio()
		"map_table":
			_interact_map()
		"journal":
			open_journal()
		"door_observatory":
			audio_service.play_sfx("wood_thump")
			show_toast("Дверь в башню обсерватории пока заперта. Ключ от неё откроется в следующих главах.")

func _interact_desk_prop() -> void:
	audio_service.play_sfx("click_dial")
	var cur_id: String = str(game_state.get("desk_prop_id", "compass"))
	for item: Dictionary in QuestRulesScript.DESK_PROPS:
		if str(item.get("id", "")) == cur_id:
			show_toast(str(item.get("title", "")) + ": " + str(item.get("desc", "")) + " (Можно сменить в «Оформить станцию»)")
			return

func _interact_radio() -> void:
	var solved: bool = bool(game_state.get("puzzle_solved", false))
	if not solved:
		audio_service.play_sfx("wood_thump")
		show_toast("Радиоприёмник тихо гудит: частота заблокирована кодом шкатулки на верстаке.")
	else:
		audio_service.play_radio_broadcast()
		show_toast("📻 Эфир «Южный Маяк»: «¡Hola, El Bolsón! Приветствуем новую хранительницу станции! Ветер с Пилтрикитрона приносит ясную погоду...»")

func _interact_map() -> void:
	audio_service.play_sfx("paper_flip")
	show_toast("🗺 Настенная карта долины Эль-Больсон: отмечены река Рио Асуль, пик Серро Пилтрикитрон и неизведанный горный сектор.")

# ==================== МОДАЛЬНЫЕ ОКНА ====================

func _close_modals() -> void:
	for child in modal_container.get_children():
		child.queue_free()
	modal_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

func open_author_terminal() -> void:
	_close_modals()
	modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	audio_service.play_sfx("paper_flip")
	
	var term: Control = AuthorTerminalScene.instantiate()
	modal_container.add_child(term)
	term.setup(
		str(game_state.get("station_name", "Лесная станция")),
		str(game_state.get("station_emblem", "star")),
		str(game_state.get("desk_prop_id", "compass")),
		audio_service
	)
	
	term.settings_applied.connect(func(new_name: String, new_emblem: String, new_prop_id: String):
		apply_author_customization(new_name, new_emblem, new_prop_id)
		_close_modals()
	)
	term.reset_to_default.connect(func():
		apply_author_customization("Лесная станция", "star", "compass")
	)
	term.closed.connect(_close_modals)

func apply_author_customization(new_name: String, new_emblem: String, new_prop_id: String) -> void:
	game_state["station_name"] = new_name
	game_state["station_emblem"] = new_emblem
	game_state["desk_prop_id"] = new_prop_id
	
	var s00: Dictionary = game_state.get("s00_progress", {})
	s00["sign_named"] = true
	s00["prop_arranged"] = true
	game_state["s00_progress"] = s00
	
	ProgressionRulesScript.unlock_achievement(game_state, "station_keeper")
	ProgressionRulesScript.unlock_achievement(game_state, "master_curator")
	
	SaveServiceScript.save_game(game_state)
	_apply_state_to_world(false)
	show_toast("✓ Оформление сохранено! Вывеска «" + new_name + "» и экспонат обновлены в комнате.")

func open_puzzle_box() -> void:
	_close_modals()
	modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	audio_service.play_sfx("wood_thump")
	
	var puzzle: Control = SymbolDialsScene.instantiate()
	modal_container.add_child(puzzle)
	puzzle.setup(
		game_state.get("puzzle_state", [1, 2, 1]),
		bool(game_state.get("puzzle_solved", false)),
		audio_service
	)
	
	puzzle.dial_changed.connect(func(dial_idx: int, new_val: int):
		var dials: Array = game_state.get("puzzle_state", [1, 2, 1])
		if dial_idx >= 0 and dial_idx < dials.size():
			dials[dial_idx] = new_val
			game_state["puzzle_state"] = dials
			station_room.update_dials_visual(dials)
			SaveServiceScript.save_game(game_state)
	)
	
	puzzle.puzzle_solved.connect(func():
		complete_puzzle()
	)
	puzzle.closed.connect(_close_modals)

func complete_puzzle() -> void:
	game_state["puzzle_state"] = [0, 0, 0]
	game_state["puzzle_solved"] = true
	game_state["radio_powered"] = true
	
	var s00: Dictionary = game_state.get("s00_progress", {})
	s00["puzzle_solved"] = true
	s00["station_awakened"] = true
	game_state["s00_progress"] = s00
	
	var newly_unlocked: bool = ProgressionRulesScript.unlock_achievement(game_state, "first_world_change")
	SaveServiceScript.save_game(game_state)
	
	_apply_state_to_world(true)
	audio_service.play_radio_broadcast()
	
	if newly_unlocked:
		show_toast("✨ Достижение «Первое изменение мира»! Лампа зажглась, радиоканал «Южный Маяк» восстановлен!")
	else:
		show_toast("✨ Механизм шкатулки открыт, станция озарена тёплым светом!")

func open_journal() -> void:
	_close_modals()
	modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	audio_service.play_sfx("paper_flip")
	
	var j: Control = JournalScene.instantiate()
	modal_container.add_child(j)
	j.setup(game_state, audio_service)
	j.closed.connect(_close_modals)

func open_settings() -> void:
	_close_modals()
	modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	audio_service.play_sfx("click_dial")
	
	var s: Control = SettingsScene.instantiate()
	modal_container.add_child(s)
	s.setup(game_state.get("settings", {}), audio_service)
	
	s.settings_changed.connect(func(new_settings: Dictionary):
		game_state["settings"] = new_settings
		_apply_settings(new_settings)
		SaveServiceScript.save_game(game_state)
	)
	s.reset_save_requested.connect(func():
		game_state = SaveServiceScript.reset_save()
		_apply_state_to_world(false)
		_apply_settings(game_state.get("settings", {}))
		_close_modals()
		show_toast("Прогресс сброшен к начальному состоянию пролога.")
	)
	s.take_screenshot_requested.connect(func():
		_close_modals()
		get_tree().create_timer(0.15).timeout.connect(func():
			take_screenshot("screenshots/user_capture.png")
		)
	)
	s.closed.connect(_close_modals)

func _apply_settings(settings: Dictionary) -> void:
	var master_v: float = float(settings.get("master_volume", 0.8))
	var music_v: float = float(settings.get("music_volume", 0.7))
	var sfx_v: float = float(settings.get("sfx_volume", 0.8))
	var muted: bool = bool(settings.get("muted", false))
	var red_motion: bool = bool(settings.get("reduce_motion", false))
	var ui_scale: float = clampf(float(settings.get("ui_scale", 1.0)), 0.8, 1.75)
	
	audio_service.update_volumes(master_v, music_v, sfx_v, muted)
	station_room.reduce_motion = red_motion
	get_window().content_scale_factor = ui_scale

func show_toast(msg: String) -> void:
	toast_lbl.text = msg
	toast_panel.visible = true
	toast_timer.start(5.5)

func take_screenshot(path: String) -> bool:
	DirAccess.make_dir_absolute("screenshots")
	var img: Image = get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		var err: Error = img.save_png(path)
		if err == OK:
			show_toast("📷 Снимок экрана сохранён: " + path)
			return true
	return false
