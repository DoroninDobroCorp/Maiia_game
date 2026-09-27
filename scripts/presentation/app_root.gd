class_name AppRoot
extends Node

## Корневой контроллер игры SUR (Phase A / Vertical Slice)
## Управляет 3D-комнатой станции, сохранениями, звуком и модальными окнами.

const SaveServiceScript = preload("res://scripts/services/save_service.gd")
const AudioServiceScript = preload("res://scripts/services/audio_service.gd")
const QuestRulesScript = preload("res://scripts/domain/quest_rules.gd")
const ProgressionRulesScript = preload("res://scripts/domain/progression_rules.gd")
const ContentRepositoryScript = preload("res://scripts/services/content_repository.gd")
const ContentLibraryServiceScript = preload("res://scripts/services/content_library_service.gd")
const QuestServiceScript = preload("res://scripts/services/quest_service.gd")
const ArtifactServiceScript = preload("res://scripts/services/artifact_service.gd")
const AuthorPatchServiceScript = preload("res://scripts/services/author_patch_service.gd")
const ProgressServiceScript = preload("res://scripts/services/progress_service.gd")
const RadioWeatherServiceScript = preload("res://scripts/services/radio_weather_service.gd")

const StationRoomScene = preload("res://scenes/world/station_room.tscn")
const SymbolDialsScene = preload("res://scenes/minigames/symbol_dials.tscn")
const AuthorTerminalScene = preload("res://scenes/ui/author_terminal.tscn")
const AuthorDialogueEditorScene = preload("res://scenes/ui/author_dialogue_editor.tscn")
const JournalScene = preload("res://scenes/ui/journal.tscn")
const ParentConsoleScene = preload("res://scenes/ui/parent_console.tscn")
const QuestDetailScene = preload("res://scenes/ui/quest_detail.tscn")
const WorldExplorerScene = preload("res://scenes/ui/world_explorer.tscn")
const SettingsScene = preload("res://scenes/ui/settings_dialog.tscn")

var game_state: Dictionary = {}
var audio_service: Node
var radio_weather_service: Node
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
	radio_weather_service = RadioWeatherServiceScript.new()
	add_child(radio_weather_service)
	radio_weather_service.bulletin_ready.connect(_on_radio_bulletin_ready)
	
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
		show_toast("Добро пожаловать на станцию! Осмотри комнату, оформи вывеску и разгадай первую тайну в шкатулке на верстаке.")
	else:
		show_toast("С возвращением на станцию «" + str(game_state.get("station_name", "Лесная станция")) + "»!")

func _unhandled_key_input(event: InputEvent) -> void:
	_unhandled_input(event)

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
			elif k.keycode == KEY_P:
				if modal_container.get_child_count() > 0:
					_close_modals()
				else:
					open_parent_console()
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
	
	# Небольшая табличка вместо полосы на всю ширину: интерфейс оставляет миру воздух.
	var top_bar := PanelContainer.new()
	top_bar.position = Vector2(18, 16)
	top_bar.custom_minimum_size = Vector2(310, 38)
	var tb_style := StyleBoxFlat.new()
	tb_style.bg_color = Color(0.055, 0.05, 0.065, 0.76)
	tb_style.border_color = Color(0.82, 0.64, 0.28, 0.72)
	tb_style.set_border_width_all(1)
	tb_style.set_corner_radius_all(7)
	tb_style.content_margin_left = 14
	tb_style.content_margin_right = 14
	tb_style.content_margin_top = 7
	tb_style.content_margin_bottom = 7
	top_bar.add_theme_stylebox_override("panel", tb_style)
	hud_root.add_child(top_bar)
	
	var top_hbox := HBoxContainer.new()
	top_bar.add_child(top_hbox)
	
	header_station_lbl = Label.new()
	header_station_lbl.add_theme_font_size_override("font_size", 15)
	header_station_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.60))
	top_hbox.add_child(header_station_lbl)

	# Состояние пролога — отдельный компактный индикатор в правом углу.
	var quest_card := PanelContainer.new()
	quest_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	quest_card.position = Vector2(-382, 16)
	quest_card.custom_minimum_size = Vector2(364, 38)
	var q_style := StyleBoxFlat.new()
	q_style.bg_color = Color(0.055, 0.05, 0.065, 0.70)
	q_style.border_color = Color(0.42, 0.48, 0.56, 0.48)
	q_style.set_border_width_all(1)
	q_style.set_corner_radius_all(7)
	q_style.content_margin_left = 12
	q_style.content_margin_right = 12
	q_style.content_margin_top = 7
	q_style.content_margin_bottom = 7
	quest_card.add_theme_stylebox_override("panel", q_style)
	hud_root.add_child(quest_card)

	header_quest_lbl = Label.new()
	header_quest_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_quest_lbl.add_theme_font_size_override("font_size", 12)
	header_quest_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	quest_card.add_child(header_quest_lbl)
	
	# Всплывающее уведомление (Toast)
	toast_panel = PanelContainer.new()
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.position = Vector2(-290, 68)
	toast_panel.custom_minimum_size = Vector2(580, 42)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.08, 0.075, 0.095, 0.90)
	t_style.border_color = Color(0.88, 0.72, 0.32, 0.70)
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
	hover_tooltip_panel.position = Vector2(-210, -62)
	hover_tooltip_panel.custom_minimum_size = Vector2(420, 36)
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
	
	# Лаконичная подсказка: основные действия совершаются прямо с предметами в комнате.
	var hint_card := PanelContainer.new()
	hint_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_card.position = Vector2(18, -48)
	hint_card.custom_minimum_size = Vector2(330, 30)
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color(0.04, 0.04, 0.055, 0.66)
	hint_style.set_corner_radius_all(6)
	hint_style.set_content_margin_all(7)
	hint_card.add_theme_stylebox_override("panel", hint_style)
	hud_root.add_child(hint_card)
	var hint_lbl := Label.new()
	hint_lbl.text = "Осматривай предметы • клик — действие   |   J — журнал   Esc — настройки"
	hint_lbl.add_theme_font_size_override("font_size", 11)
	hint_lbl.add_theme_color_override("font_color", Color(0.78, 0.76, 0.70, 0.90))
	hint_card.add_child(hint_lbl)
	
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
	station_room.apply_phase_b_world_effects(ProgressServiceScript.get_profile_world_effects(game_state, "player_01"))
	
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
			var effects: Array = ProgressServiceScript.get_profile_world_effects(game_state, "player_01")
			if effects.has("observatory_view_01"):
				show_toast("Обсерватория открыта. За стеклом снова видны огни долины — станция получила твой ответ и оставляет следующую главу своему автору.")
			else:
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
		show_toast("Радио молчит, а лампа не горит: станция спит. Разгадай первую тайну шкатулки на верстаке — возможно, она знает, как разбудить станцию.")
	else:
		audio_service.play_radio_broadcast()
		if radio_weather_service.request_bulletin():
			show_toast("📻 Южный Маяк ловит погодную волну Эль-Больсона…")
		else:
			show_toast("📻 Плохая связь. Приёмник пока не может обновить прогноз.")

func _on_radio_bulletin_ready(text: String) -> void:
	show_toast(text)

func _interact_map() -> void:
	audio_service.play_sfx("paper_flip")
	open_world_explorer()

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
	term.dialogue_editor_requested.connect(open_author_dialogue_editor)
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
		show_toast("✨ Первая тайна разгадана! Лампа зажглась, радио ожило — станция пробуждается ото сна!")
	else:
		show_toast("✨ Механизм шкатулки открыт, станция озарена тёплым светом!")

func open_journal() -> void:
	_close_modals()
	modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	audio_service.play_sfx("paper_flip")
	
	var j: Control = JournalScene.instantiate()
	modal_container.add_child(j)
	j.setup(game_state, audio_service)
	j.quest_open_requested.connect(func(quest: Dictionary, instance: Dictionary):
		open_quest_detail(quest, instance)
	)
	j.artifact_delete_requested.connect(func(artifact_id: String):
		var result := ArtifactServiceScript.delete_media(game_state, artifact_id)
		if bool(result.get("ok", false)):
			SaveServiceScript.save_game(game_state)
			open_journal()
			show_toast("Вложение удалено; запись результата и сюжетный прогресс сохранены.")
	)
	j.closed.connect(_close_modals)

func open_parent_console() -> void:
	_close_modals()
	modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	audio_service.play_sfx("paper_flip")
	var console: Control = ParentConsoleScene.instantiate()
	modal_container.add_child(console)
	console.setup(game_state, audio_service)
	console.publish_requested.connect(func(quest: Dictionary):
		var result := QuestServiceScript.approve_and_publish(game_state, quest)
		if bool(result.get("ok", false)):
			SaveServiceScript.save_game(game_state)
			open_parent_console()
			show_toast("Точная версия %s v%d опубликована для игрока." % [str(quest.get("quest_id", "")), int(quest.get("revision", 1))])
		else:
			show_toast("Не удалось опубликовать карточку: " + str(result.get("reason", "ошибка проверки")))
	)
	console.confirm_requested.connect(func(activity_id: String):
		_confirm_activity_transaction(activity_id)
	)
	console.revision_requested.connect(func(activity_id: String, note: String):
		var result := QuestServiceScript.request_revision(game_state, activity_id, note)
		if bool(result.get("ok", false)):
			SaveServiceScript.save_game(game_state)
			open_parent_console()
			show_toast("Результат возвращён к заранее опубликованным критериям.")
	)
	console.revoke_requested.connect(func(quest_id: String, revision: int):
		if QuestServiceScript.revoke_version(game_state, quest_id, revision):
			SaveServiceScript.save_game(game_state)
			open_parent_console()
			show_toast("Версия отозвана. Активные инструкции поставлены на безопасную паузу.")
	)
	console.draft_save_requested.connect(func(quest: Dictionary):
		var result := ContentLibraryServiceScript.save_draft(game_state, quest)
		if bool(result.get("ok", false)):
			SaveServiceScript.save_game(game_state)
			open_parent_console()
			show_toast("Черновик %s v%d сохранён локально. Для игрока он появится только после отдельной публикации." % [str(quest.get("quest_id", "")), int(quest.get("revision", 1))])
		else:
			var details := "; ".join(result.get("errors", [])) if result.has("errors") else str(result.get("message", result.get("reason", "ошибка")))
			show_toast("Черновик не сохранён: " + details)
	)
	console.package_import_requested.connect(func(path: String):
		_import_content_package(path)
	)
	console.package_export_requested.connect(func():
		_export_content_package()
	)
	console.closed.connect(_close_modals)

func open_world_explorer() -> void:
	_close_modals()
	modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	var explorer: Control = WorldExplorerScene.instantiate()
	modal_container.add_child(explorer)
	explorer.setup(game_state, audio_service)
	explorer.quest_open_requested.connect(func(quest: Dictionary):
		open_quest_detail(quest, {})
	)
	explorer.closed.connect(_close_modals)

func open_quest_detail(quest: Dictionary, instance: Dictionary = {}) -> void:
	_close_modals()
	modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	var detail: Control = QuestDetailScene.instantiate()
	modal_container.add_child(detail)
	detail.setup(quest, instance, audio_service)
	detail.accept_requested.connect(func(quest_id: String, revision: int, variant_id: String):
		var result := QuestServiceScript.create_instance(game_state, quest_id, revision, variant_id, "player_01")
		if bool(result.get("ok", false)):
			SaveServiceScript.save_game(game_state)
			var fresh_quest := _published_quest(quest_id, revision)
			open_quest_detail(fresh_quest, result.get("instance", {}))
			show_toast("Экспедиция принята: её точная версия теперь зафиксирована.")
		else:
			show_toast("Не удалось принять экспедицию: " + str(result.get("reason", "ошибка")))
	)
	detail.submit_requested.connect(func(instance_id: String, note: String):
		var phase_b: Dictionary = game_state.get("phase_b", {})
		var instances: Dictionary = phase_b.get("quest_instances", {})
		var current: Dictionary = instances.get(instance_id, {})
		var artifact_id := str(current.get("draft_artifact_id", ""))
		var activity_id := "activity:%s:%d" % [instance_id, Time.get_ticks_usec()]
		var result := QuestServiceScript.submit_result(game_state, instance_id, activity_id, note, artifact_id)
		if bool(result.get("ok", false)):
			SaveServiceScript.save_game(game_state)
			open_journal()
			show_toast("Результат отправлен на проверку. XP пока не начислен.")
		else:
			show_toast("Не удалось отправить результат: " + str(result.get("reason", "ошибка")))
	)
	detail.pause_requested.connect(func(instance_id: String):
		if QuestServiceScript.pause_instance(game_state, instance_id):
			SaveServiceScript.save_game(game_state)
			open_journal()
			show_toast("Экспедиция отложена без штрафа.")
	)
	detail.resume_requested.connect(func(instance_id: String):
		if QuestServiceScript.resume_instance(game_state, instance_id):
			SaveServiceScript.save_game(game_state)
			var current := _instance_by_id(instance_id)
			open_quest_detail(current.get("quest_snapshot", {}), current)
	)
	detail.artifact_import_requested.connect(func(source_path: String, instance_id: String):
		_import_artifact_for_instance(source_path, instance_id)
	)
	detail.closed.connect(open_journal)

func open_author_dialogue_editor() -> void:
	_close_modals()
	modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	var editor: Control = AuthorDialogueEditorScene.instantiate()
	modal_container.add_child(editor)
	editor.setup(game_state, audio_service)
	editor.publish_requested.connect(func(package: Dictionary):
		var result := AuthorPatchServiceScript.publish(game_state, package)
		if bool(result.get("ok", false)):
			SaveServiceScript.save_game(game_state)
			_apply_state_to_world(false)
			open_author_dialogue_editor()
			show_toast("Авторская реплика опубликована локально; версия сохранена для отката.")
		else:
			show_toast("Пакет не опубликован: " + str(result.get("reason", result.get("errors", ["ошибка"])) ))
	)
	editor.rollback_requested.connect(func(patch_id: String):
		var result := AuthorPatchServiceScript.rollback(game_state, patch_id)
		if bool(result.get("ok", false)):
			SaveServiceScript.save_game(game_state)
			open_author_dialogue_editor()
			show_toast("Реплика откатилась к предыдущей сохранённой версии.")
	)
	editor.closed.connect(open_author_terminal)

func _confirm_activity_transaction(activity_id: String) -> void:
	var before := game_state.duplicate(true)
	var result := QuestServiceScript.confirm_result(game_state, activity_id)
	if not bool(result.get("ok", false)):
		show_toast("Не удалось подтвердить результат: " + str(result.get("reason", "ошибка")))
		return
	if not SaveServiceScript.save_game(game_state):
		game_state = before
		show_toast("Сохранение не завершилось; подтверждение не применено в текущем сеансе.")
		return
	_apply_state_to_world(true)
	open_parent_console()
	show_toast("✓ Результат подтверждён: XP и изменение мира сохранены одним снимком.")

func _import_artifact_for_instance(source_path: String, instance_id: String) -> void:
	var instance := _instance_by_id(instance_id)
	if instance.is_empty():
		show_toast("Не найдено прохождение для вложения.")
		return
	var quest: Dictionary = instance.get("quest_snapshot", {})
	var result := ArtifactServiceScript.import_local_image(game_state, source_path, str(quest.get("title", "Работа")), str(instance.get("profile_id", "player_01")))
	if not bool(result.get("ok", false)):
		show_toast("Не удалось импортировать изображение: " + str(result.get("reason", "ошибка")))
		return
	var phase_b: Dictionary = game_state.get("phase_b", {})
	var instances: Dictionary = phase_b.get("quest_instances", {})
	var live: Dictionary = instances[instance_id]
	live["draft_artifact_id"] = str((result.get("artifact", {}) as Dictionary).get("artifact_id", ""))
	instances[instance_id] = live
	phase_b["quest_instances"] = instances
	game_state["phase_b"] = phase_b
	SaveServiceScript.save_game(game_state)
	open_quest_detail(quest, live)
	show_toast("Изображение скопировано в управляемый локальный архив.")

func _instance_by_id(instance_id: String) -> Dictionary:
	return (game_state.get("phase_b", {}).get("quest_instances", {}) as Dictionary).get(instance_id, {}).duplicate(true)

func _published_quest(quest_id: String, revision: int) -> Dictionary:
	var key := QuestServiceScript.version_key(quest_id, revision)
	var published: Dictionary = game_state.get("phase_b", {}).get("published_versions", {})
	if published.has(key):
		return ((published[key] as Dictionary).get("quest", {}) as Dictionary).duplicate(true)
	return ContentLibraryServiceScript.get_template(game_state, quest_id, revision)

func _import_content_package(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		show_toast("Не найден локальный JSON-пакет по указанному пути.")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		show_toast("Не удалось открыть локальный JSON-пакет.")
		return
	var text := file.get_as_text()
	file.close()
	var result := ContentLibraryServiceScript.import_package_json(game_state, text)
	if not bool(result.get("ok", false)):
		var details := "; ".join(result.get("errors", [])) if result.has("errors") else str(result.get("reason", "ошибка"))
		show_toast("Пакет отклонён целиком: " + details)
		return
	SaveServiceScript.save_game(game_state)
	open_parent_console()
	show_toast("Импортировано черновиков: %d. Ни один не опубликован автоматически." % int(result.get("imported", 0)))

func _export_content_package() -> void:
	var package := ContentLibraryServiceScript.build_export_package(game_state)
	var path := "user://phase_c_quest_pack.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		show_toast("Не удалось создать локальный экспорт пакета.")
		return
	file.store_string(JSON.stringify(package, "  "))
	file.close()
	show_toast("Пакет черновиков сохранён: " + ProjectSettings.globalize_path(path))

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
