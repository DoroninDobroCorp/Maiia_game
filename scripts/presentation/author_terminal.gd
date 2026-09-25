class_name AuthorTerminalUI
extends Control

## Терминал автора (Phase A: Название станции, символ, памятный экспонат)

signal settings_applied(new_name: String, new_emblem: String, new_prop_id: String)
signal reset_to_default()
signal closed()

const QuestRulesScript = preload("res://scripts/domain/quest_rules.gd")

var name_edit: LineEdit
var emblem_buttons: Array[Button] = []
var prop_buttons: Array[Button] = []

var selected_emblem: String = "star"
var selected_prop: String = "compass"
var audio_service: Node

func setup(current_name: String, current_emblem: String, current_prop: String, audio_svc: Node) -> void:
	audio_service = audio_svc
	selected_emblem = current_emblem
	selected_prop = current_prop
	
	_build_ui(current_name)
	_update_selections()

func _build_ui(current_name: String) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09, 0.82)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 560)
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.13, 0.12, 0.17, 0.98)
	p_style.border_color = Color(0.88, 0.72, 0.32, 0.85)
	p_style.set_border_width_all(2)
	p_style.set_corner_radius_all(10)
	p_style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", p_style)
	center.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	
	# Заголовок
	var title_lbl := Label.new()
	title_lbl.text = "✦ ТЕРМИНАЛ АВТОРА: ОФОРМЛЕНИЕ СТАНЦИИ ✦"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	vbox.add_child(title_lbl)
	
	var desc_lbl := Label.new()
	desc_lbl.text = "Каждое изменение немедленно преображает твой мир и сохраняется."
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.78, 0.72))
	vbox.add_child(desc_lbl)
	
	# Раздел 1: Название станции
	var name_sec := VBoxContainer.new()
	name_sec.add_theme_constant_override("separation", 6)
	vbox.add_child(name_sec)
	
	var name_lbl := Label.new()
	name_lbl.text = "1. Название станции:"
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	name_sec.add_child(name_lbl)
	
	name_edit = LineEdit.new()
	name_edit.text = current_name
	name_edit.max_length = 28
	name_edit.custom_minimum_size = Vector2(0, 36)
	name_sec.add_child(name_edit)
	
	# Быстрые пресеты названий
	var presets_hbox := HBoxContainer.new()
	presets_hbox.add_theme_constant_override("separation", 8)
	name_sec.add_child(presets_hbox)
	
	var name_presets := ["Лесная станция", "Мастерская Пилтри", "Маяк Рио Асуль", "База Сур"]
	for p_name in name_presets:
		var chip := Button.new()
		chip.text = p_name
		chip.add_theme_font_size_override("font_size", 11)
		chip.pressed.connect(func():
			name_edit.text = p_name
			if audio_service != null and audio_service.has_method("play_sfx"):
				audio_service.play_sfx("paper_flip")
		)
		presets_hbox.add_child(chip)
	
	# Раздел 2: Символ станции
	var emblem_sec := VBoxContainer.new()
	emblem_sec.add_theme_constant_override("separation", 6)
	vbox.add_child(emblem_sec)
	
	var emb_lbl := Label.new()
	emb_lbl.text = "2. Символ на деревянной вывеске:"
	emb_lbl.add_theme_font_size_override("font_size", 15)
	emb_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	emblem_sec.add_child(emb_lbl)
	
	var emb_grid := HBoxContainer.new()
	emb_grid.add_theme_constant_override("separation", 10)
	emblem_sec.add_child(emb_grid)
	
	emblem_buttons.clear()
	var emblem_icons := {"feather": "🪶", "star": "✦", "sprout": "🌱", "gear": "⚙"}
	for item: Dictionary in QuestRulesScript.EMBLEM_PRESETS:
		var e_id: String = str(item.get("id", ""))
		var e_btn := Button.new()
		e_btn.custom_minimum_size = Vector2(170, 42)
		e_btn.text = emblem_icons.get(e_id, "✦") + " " + str(item.get("title", ""))
		e_btn.pressed.connect(func():
			selected_emblem = e_id
			_update_selections()
			if audio_service != null and audio_service.has_method("play_sfx"):
				audio_service.play_sfx("click_dial")
		)
		emb_grid.add_child(e_btn)
		emblem_buttons.append(e_btn)
	
	# Раздел 3: Памятный экспонат верстака
	var prop_sec := VBoxContainer.new()
	prop_sec.add_theme_constant_override("separation", 6)
	vbox.add_child(prop_sec)
	
	var prop_lbl := Label.new()
	prop_lbl.text = "3. Памятный предмет на подставке:"
	prop_lbl.add_theme_font_size_override("font_size", 15)
	prop_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	prop_sec.add_child(prop_lbl)
	
	var prop_grid := HBoxContainer.new()
	prop_grid.add_theme_constant_override("separation", 10)
	prop_sec.add_child(prop_grid)
	
	prop_buttons.clear()
	var prop_icons := {"compass": "🧭", "crystal": "💎", "owl": "🦉", "astrolabe": "🔭"}
	for item: Dictionary in QuestRulesScript.DESK_PROPS:
		var p_id: String = str(item.get("id", ""))
		var p_btn := Button.new()
		p_btn.custom_minimum_size = Vector2(170, 42)
		p_btn.text = prop_icons.get(p_id, "✦") + " " + str(item.get("title", ""))
		p_btn.pressed.connect(func():
			selected_prop = p_id
			_update_selections()
			if audio_service != null and audio_service.has_method("play_sfx"):
				audio_service.play_sfx("click_dial")
		)
		prop_grid.add_child(p_btn)
		prop_buttons.append(p_btn)
	
	# Нижние кнопки
	var actions_hbox := HBoxContainer.new()
	actions_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	actions_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(actions_hbox)
	
	var btn_apply := Button.new()
	btn_apply.text = "✓ Применить в мире"
	btn_apply.custom_minimum_size = Vector2(180, 40)
	btn_apply.pressed.connect(_on_apply_pressed)
	actions_hbox.add_child(btn_apply)
	
	var btn_reset := Button.new()
	btn_reset.text = "↺ Исходный вид"
	btn_reset.custom_minimum_size = Vector2(140, 40)
	btn_reset.pressed.connect(_on_reset_pressed)
	actions_hbox.add_child(btn_reset)
	
	var btn_cancel := Button.new()
	btn_cancel.text = "Закрыть [Esc]"
	btn_cancel.custom_minimum_size = Vector2(120, 40)
	btn_cancel.pressed.connect(func(): closed.emit())
	actions_hbox.add_child(btn_cancel)

func _update_selections() -> void:
	for i in range(QuestRulesScript.EMBLEM_PRESETS.size()):
		var item: Dictionary = QuestRulesScript.EMBLEM_PRESETS[i]
		var e_id: String = str(item.get("id", ""))
		var btn: Button = emblem_buttons[i]
		if e_id == selected_emblem:
			btn.modulate = Color(1.2, 1.1, 0.7)
		else:
			btn.modulate = Color(0.85, 0.85, 0.85)
	
	for i in range(QuestRulesScript.DESK_PROPS.size()):
		var item: Dictionary = QuestRulesScript.DESK_PROPS[i]
		var p_id: String = str(item.get("id", ""))
		var btn: Button = prop_buttons[i]
		if p_id == selected_prop:
			btn.modulate = Color(1.2, 1.1, 0.7)
		else:
			btn.modulate = Color(0.85, 0.85, 0.85)

func _on_apply_pressed() -> void:
	var final_name := name_edit.text.strip_edges()
	if final_name.is_empty():
		final_name = "Лесная станция"
	
	if audio_service != null and audio_service.has_method("play_sfx"):
		audio_service.play_sfx("wood_thump")
	
	settings_applied.emit(final_name, selected_emblem, selected_prop)

func _on_reset_pressed() -> void:
	name_edit.text = "Лесная станция"
	selected_emblem = "star"
	selected_prop = "compass"
	_update_selections()
	if audio_service != null and audio_service.has_method("play_sfx"):
		audio_service.play_sfx("paper_flip")
	reset_to_default.emit()
