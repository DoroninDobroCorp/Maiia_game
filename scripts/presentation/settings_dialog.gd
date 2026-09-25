class_name SettingsDialogUI
extends Control

## Настройки игры и доступности (Звук, Масштаб UI, Уменьшение движения, Сброс)

signal settings_changed(settings: Dictionary)
signal reset_save_requested()
signal take_screenshot_requested()
signal closed()

var audio_service: Node
var master_slider: HSlider
var music_slider: HSlider
var sfx_slider: HSlider
var mute_check: CheckBox
var motion_check: CheckBox
var scale_option: OptionButton

var current_settings: Dictionary = {}

func setup(settings: Dictionary, audio_svc: Node) -> void:
	audio_service = audio_svc
	current_settings = settings.duplicate(true)
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 0.85)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 520)
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.14, 0.13, 0.18, 0.98)
	p_style.border_color = Color(0.88, 0.72, 0.32, 0.85)
	p_style.set_border_width_all(2)
	p_style.set_corner_radius_all(10)
	p_style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", p_style)
	center.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	
	var title_lbl := Label.new()
	title_lbl.text = "✦ НАСТРОЙКИ И ДОСТУПНОСТЬ ✦"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	vbox.add_child(title_lbl)
	
	# Раздел: Звук
	var sound_sec := VBoxContainer.new()
	sound_sec.add_theme_constant_override("separation", 8)
	vbox.add_child(sound_sec)
	
	var s_title := Label.new()
	s_title.text = "Звук и музыка:"
	s_title.add_theme_font_size_override("font_size", 15)
	s_title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	sound_sec.add_child(s_title)
	
	mute_check = CheckBox.new()
	mute_check.text = "Полностью выключить звук (Mute)"
	mute_check.button_pressed = bool(current_settings.get("muted", false))
	mute_check.toggled.connect(func(_val: bool): _apply_changes())
	sound_sec.add_child(mute_check)
	
	master_slider = _add_slider(sound_sec, "Общая громкость:", float(current_settings.get("master_volume", 0.8)))
	music_slider = _add_slider(sound_sec, "Фоновый ветер и атмосфера:", float(current_settings.get("music_volume", 0.7)))
	sfx_slider = _add_slider(sound_sec, "Эффекты механизмов и радио:", float(current_settings.get("sfx_volume", 0.8)))
	
	# Раздел: Доступность
	var acc_sec := VBoxContainer.new()
	acc_sec.add_theme_constant_override("separation", 8)
	vbox.add_child(acc_sec)
	
	var a_title := Label.new()
	a_title.text = "Доступность и интерфейс:"
	a_title.add_theme_font_size_override("font_size", 15)
	a_title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	acc_sec.add_child(a_title)
	
	motion_check = CheckBox.new()
	motion_check.text = "Уменьшение движения (отключить покачивание камеры)"
	motion_check.button_pressed = bool(current_settings.get("reduce_motion", false))
	motion_check.toggled.connect(func(_val: bool): _apply_changes())
	acc_sec.add_child(motion_check)
	
	var scale_hbox := HBoxContainer.new()
	scale_hbox.add_theme_constant_override("separation", 12)
	acc_sec.add_child(scale_hbox)
	
	var sc_lbl := Label.new()
	sc_lbl.text = "Масштаб интерфейса:"
	scale_hbox.add_child(sc_lbl)
	
	scale_option = OptionButton.new()
	scale_option.add_item("100% (Стандартный)", 0)
	scale_option.add_item("125% (Увеличенный)", 1)
	scale_option.add_item("150% (Крупный текст)", 2)
	var cur_scale: float = float(current_settings.get("ui_scale", 1.0))
	if cur_scale >= 1.4:
		scale_option.selected = 2
	elif cur_scale >= 1.2:
		scale_option.selected = 1
	else:
		scale_option.selected = 0
	scale_option.item_selected.connect(func(_idx: int): _apply_changes())
	scale_hbox.add_child(scale_option)
	
	# Раздел: Управление профилем и скриншоты
	var act_hbox := HBoxContainer.new()
	act_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	act_hbox.add_theme_constant_override("separation", 14)
	vbox.add_child(act_hbox)
	
	var btn_screen := Button.new()
	btn_screen.text = "📷 Снимок экрана (F12)"
	btn_screen.pressed.connect(func(): take_screenshot_requested.emit())
	act_hbox.add_child(btn_screen)
	
	var btn_reset := Button.new()
	btn_reset.text = "↺ Сброс прогресса к началу"
	btn_reset.pressed.connect(func(): reset_save_requested.emit())
	act_hbox.add_child(btn_reset)
	
	var btn_close := Button.new()
	btn_close.text = "Закрыть [Esc]"
	btn_close.custom_minimum_size = Vector2(120, 36)
	btn_close.pressed.connect(func(): closed.emit())
	act_hbox.add_child(btn_close)

func _add_slider(parent: Control, label_text: String, init_val: float) -> HSlider:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	parent.add_child(h)
	
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(230, 0)
	l.add_theme_font_size_override("font_size", 12)
	h.add_child(l)
	
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = init_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(_val: float): _apply_changes())
	h.add_child(slider)
	
	return slider

func _apply_changes() -> void:
	current_settings["muted"] = mute_check.button_pressed
	current_settings["master_volume"] = master_slider.value
	current_settings["music_volume"] = music_slider.value
	current_settings["sfx_volume"] = sfx_slider.value
	current_settings["reduce_motion"] = motion_check.button_pressed
	
	match scale_option.selected:
		0:
			current_settings["ui_scale"] = 1.0
		1:
			current_settings["ui_scale"] = 1.25
		2:
			current_settings["ui_scale"] = 1.50
	
	settings_changed.emit(current_settings)
