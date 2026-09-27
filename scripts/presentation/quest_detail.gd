class_name QuestDetailUI
extends Control

signal closed()
signal accept_requested(quest_id: String, revision: int, variant_id: String)
signal submit_requested(instance_id: String, note: String)
signal pause_requested(instance_id: String)
signal resume_requested(instance_id: String)
signal artifact_import_requested(source_path: String, instance_id: String)

var audio_service: Node
var selected_variant_id := ""

func setup(quest: Dictionary, instance: Dictionary, audio_svc: Node) -> void:
	audio_service = audio_svc
	_build_ui(quest, instance)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if audio_service != null and audio_service.has_method("play_sfx"):
				audio_service.play_sfx("paper_flip")
			closed.emit()

func _build_ui(quest: Dictionary, instance: Dictionary) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.045, 0.075, 0.88)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if audio_service != null and audio_service.has_method("play_sfx"):
				audio_service.play_sfx("paper_flip")
			closed.emit()
	)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 590)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.145, 0.125, 0.16, 0.985)
	style.border_color = Color(0.84, 0.69, 0.32, 0.86)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "%s • %s" % [str(quest.get("quest_id", "")), str(quest.get("title", "Экспедиция"))]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.56))
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Закрыть"
	close_btn.pressed.connect(func(): closed.emit())
	header.add_child(close_btn)

	var summary := Label.new()
	summary.text = str(quest.get("summary", ""))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 13)
	summary.add_theme_color_override("font_color", Color(0.84, 0.82, 0.76))
	root.add_child(summary)

	var criteria_title := Label.new()
	criteria_title.text = "Что считается завершением"
	criteria_title.add_theme_font_size_override("font_size", 14)
	criteria_title.add_theme_color_override("font_color", Color(0.94, 0.84, 0.64))
	root.add_child(criteria_title)
	for criterion in quest.get("completion_criteria", []):
		var line := Label.new()
		line.text = "• " + str(criterion)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", 12)
		root.add_child(line)

	var reward: Dictionary = quest.get("reward_policy", {})
	var reward_label := Label.new()
	reward_label.text = "Награда после подтверждения взрослым: %d XP" % int(reward.get("activity_budget", 0))
	reward_label.add_theme_color_override("font_color", Color(0.58, 0.88, 0.63))
	root.add_child(reward_label)

	if instance.is_empty():
		_build_accept_controls(root, quest)
	else:
		_build_instance_controls(root, quest, instance)

func _build_accept_controls(root: VBoxContainer, quest: Dictionary) -> void:
	var variants: Array = quest.get("variants", [])
	var variant_label := Label.new()
	variant_label.text = "Выбери один из уже разрешённых вариантов:"
	root.add_child(variant_label)
	var option := OptionButton.new()
	for variant in variants:
		option.add_item(str((variant as Dictionary).get("title", "Вариант")))
		option.set_item_metadata(option.item_count - 1, str((variant as Dictionary).get("id", "")))
	root.add_child(option)
	if option.item_count > 0:
		selected_variant_id = str(option.get_item_metadata(0))
	option.item_selected.connect(func(index: int): selected_variant_id = str(option.get_item_metadata(index)))
	var accept := Button.new()
	accept.text = "Принять экспедицию"
	accept.custom_minimum_size = Vector2(0, 42)
	accept.pressed.connect(func(): accept_requested.emit(str(quest.get("quest_id", "")), int(quest.get("revision", 1)), selected_variant_id))
	root.add_child(accept)

func _build_instance_controls(root: VBoxContainer, quest: Dictionary, instance: Dictionary) -> void:
	var status := str(instance.get("status", "ACTIVE"))
	var status_label := Label.new()
	status_label.text = "Состояние: " + _status_title(status)
	status_label.add_theme_font_size_override("font_size", 14)
	root.add_child(status_label)
	var variant_title := _variant_title(quest.get("variants", []), str(instance.get("variant_id", "")))
	if not variant_title.is_empty():
		var variant := Label.new()
		variant.text = "Вариант: " + variant_title
		variant.add_theme_color_override("font_color", Color(0.74, 0.78, 0.82))
		root.add_child(variant)

	var instance_id := str(instance.get("instance_id", ""))
	if status == "ACTIVE":
		var note := TextEdit.new()
		note.placeholder_text = "Коротко: что получилось, где понадобилась помощь, что хочешь сохранить в архиве"
		note.custom_minimum_size = Vector2(0, 90)
		root.add_child(note)
		var artifact_id := str(instance.get("draft_artifact_id", ""))
		var attachment := Label.new()
		attachment.text = "Вложение: управляемая локальная копия добавлена ✓" if not artifact_id.is_empty() else "Вложение: необязательно"
		attachment.add_theme_color_override("font_color", Color(0.62, 0.82, 0.70) if not artifact_id.is_empty() else Color(0.62, 0.62, 0.60))
		root.add_child(attachment)
		var actions := HBoxContainer.new()
		root.add_child(actions)
		var add_image := Button.new()
		add_image.text = "Добавить рисунок / фото"
		actions.add_child(add_image)
		var file_dialog := FileDialog.new()
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
		add_child(file_dialog)
		add_image.pressed.connect(func(): file_dialog.popup_centered_ratio(0.72))
		file_dialog.file_selected.connect(func(path: String): artifact_import_requested.emit(path, instance_id))
		var submit := Button.new()
		submit.text = "Готово — отправить на проверку"
		submit.pressed.connect(func(): submit_requested.emit(instance_id, note.text))
		actions.add_child(submit)
		var pause := Button.new()
		pause.text = "Отложить"
		pause.pressed.connect(func(): pause_requested.emit(instance_id))
		actions.add_child(pause)
	elif status == "PAUSED":
		var paused := Label.new()
		paused.text = "Экспедиция отложена без штрафа. Архив и остальные задания остаются доступны."
		paused.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(paused)
		if bool(instance.get("safety_hold", false)):
			paused.text = "Этот план нужно уточнить со взрослым. Уже сделанная работа и прогресс сохранены."
		else:
			var resume := Button.new()
			resume.text = "Продолжить"
			resume.pressed.connect(func(): resume_requested.emit(instance_id))
			root.add_child(resume)
	elif status == "SUBMITTED":
		var waiting := Label.new()
		waiting.text = "Результат отправлен взрослому. XP и изменение мира появятся только после подтверждения."
		waiting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		waiting.add_theme_color_override("font_color", Color(0.86, 0.78, 0.58))
		root.add_child(waiting)
	elif status == "COMPLETED":
		var done := Label.new()
		done.text = "✓ Результат подтверждён. Работа записана в архив, награда и открытия уже применены."
		done.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		done.add_theme_color_override("font_color", Color(0.52, 0.90, 0.60))
		root.add_child(done)

func _variant_title(variants: Array, variant_id: String) -> String:
	for variant in variants:
		if str((variant as Dictionary).get("id", "")) == variant_id:
			return str((variant as Dictionary).get("title", ""))
	return ""

func _status_title(status: String) -> String:
	return {
		"ACTIVE": "в работе",
		"PAUSED": "отложено",
		"SUBMITTED": "на проверке",
		"COMPLETED": "завершено"
	}.get(status, status)
