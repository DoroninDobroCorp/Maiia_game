class_name WorldExplorerUI
extends Control

signal closed()
signal quest_open_requested(quest: Dictionary)
signal secret_requested(secret_id: String)

const AtlasMapScript = preload("res://scripts/presentation/atlas_map.gd")
const ContentLibraryServiceScript = preload("res://scripts/services/content_library_service.gd")
const QuestServiceScript = preload("res://scripts/services/quest_service.gd")

var audio_service: Node
var detail_label: Label

func setup(state: Dictionary, audio_svc: Node) -> void:
	audio_service = audio_svc
	# Legacy catalog getters initialise missing fields. Keep that compatibility
	# work inside the view, especially when a future save is read-only.
	_build_ui(state.duplicate(true))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_play_paper()
		closed.emit()

func _build_ui(state: Dictionary) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.018, 0.028, 0.042, 0.95)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_play_paper()
			closed.emit()
	)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1020, 650)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.065, 0.065, 0.075, 0.99)
	style.border_color = Color(0.72, 0.58, 0.30, 0.84)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "АТЛАС ПАТАГОНИИ • ТУМАН ВОЙНЫ"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color(0.97, 0.85, 0.57))
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Закрыть"
	close_btn.pressed.connect(func(): closed.emit())
	header.add_child(close_btn)
	var margin_note := Button.new()
	margin_note.text = "Заметка на полях"
	margin_note.pressed.connect(func(): secret_requested.emit("atlas_margin"))
	header.add_child(margin_note)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	var atlas_tab := _build_atlas_tab(state)
	atlas_tab.name = "Атлас"
	tabs.add_child(atlas_tab)

	var expeditions_tab := _build_expeditions_tab(state)
	expeditions_tab.name = "Экспедиции"
	tabs.add_child(expeditions_tab)

func _build_atlas_tab(state: Dictionary) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 7)
	var station_name := str(state.get("station_name", "Лесная станция")).strip_edges()
	if station_name.is_empty():
		station_name = "Лесная станция"

	var intro := Label.new()
	intro.text = "Открыта только станция «%s». Всё остальное уже видно на карте сквозь туман войны: близкая речка и ближайший водопад (Cascada Escondida), вершина и скейт-парк, дальше Лаго-Пуэло и Барилоче, а по краям — будущие далёкие главы." % station_name
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 12)
	intro.add_theme_color_override("font_color", Color(0.76, 0.78, 0.74))
	root.add_child(intro)

	var atlas: Control = AtlasMapScript.new()
	atlas.custom_minimum_size = Vector2(970, 445)
	atlas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	atlas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(atlas)
	atlas.setup(state)
	atlas.location_selected.connect(_on_location_selected)

	detail_label = Label.new()
	detail_label.text = "◎ %s открыта. Выбери любую метку: туман покажет, что ждёт дальше, но не откроет место раньше времени." % station_name
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", 12)
	detail_label.add_theme_color_override("font_color", Color(0.88, 0.84, 0.73))
	root.add_child(detail_label)
	return root

func _build_expeditions_tab(state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	var intro := Label.new()
	intro.text = "Доступные экспедиции сохранены отдельно от тумана войны. Здесь можно открыть их карточки и исследовать задачи."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 12)
	intro.add_theme_color_override("font_color", Color(0.76, 0.78, 0.74))
	list.add_child(intro)

	var published: Array = QuestServiceScript.list_player_quests(state)
	for location in ContentLibraryServiceScript.list_locations(state):
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.11, 0.12, 0.14, 0.94)
		style.border_color = Color(0.38, 0.34, 0.24, 0.78)
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(10)
		card.add_theme_stylebox_override("panel", style)
		list.add_child(card)

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 5)
		card.add_child(box)

		var title := Label.new()
		title.text = "%s  %s" % [str(location.get("symbol", "•")), str(location.get("title", "Место"))]
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", Color(0.96, 0.84, 0.58))
		box.add_child(title)

		var desc := Label.new()
		desc.text = str(location.get("description", ""))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 11)
		desc.add_theme_color_override("font_color", Color(0.76, 0.75, 0.70))
		box.add_child(desc)

		var count := 0
		for quest_value in published:
			if typeof(quest_value) != TYPE_DICTIONARY:
				continue
			var quest: Dictionary = quest_value
			if str(quest.get("location_id", "")) != str(location.get("location_id", "")):
				continue
			count += 1
			var exact := quest.duplicate(true)
			var quest_btn := Button.new()
			quest_btn.text = "Открыть экспедицию • " + str(quest.get("title", quest.get("quest_id", "Карточка")))
			quest_btn.pressed.connect(func(): quest_open_requested.emit(exact))
			box.add_child(quest_btn)

		if count == 0:
			var empty := Label.new()
			empty.text = "Пока нет опубликованных карточек для этого места."
			empty.add_theme_font_size_override("font_size", 11)
			empty.add_theme_color_override("font_color", Color(0.58, 0.59, 0.58))
			box.add_child(empty)
	return scroll

func _on_location_selected(location: Dictionary) -> void:
	_play_paper()
	if bool(location.get("unlocked", false)):
		detail_label.text = "◎ %s — %s\n%s" % [str(location.get("title", "")), str(location.get("subtitle", "")), str(location.get("description", ""))]
	else:
		detail_label.text = "☁ %s — %s\nТуман войны. %s" % [str(location.get("title", "")), str(location.get("subtitle", "")), str(location.get("description", ""))]

func _play_paper() -> void:
	if audio_service != null and audio_service.has_method("play_sfx"):
		audio_service.play_sfx("paper_flip")
