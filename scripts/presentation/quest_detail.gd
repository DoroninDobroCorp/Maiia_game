class_name QuestDetailUI
extends Control

const ContentRepositoryScript = preload("res://scripts/services/content_repository.gd")

signal closed()
signal accept_requested(quest_id: String, revision: int, variant_id: String)
signal submit_requested(instance_id: String, note: String)
signal complete_requested(quest_id: String, revision: int, variant_id: String, instance_id: String, note: String)
signal pause_requested(instance_id: String)
signal resume_requested(instance_id: String)
signal artifact_import_requested(source_path: String, instance_id: String)

var audio_service: Node
var selected_variant_id := ""
var note_edit: TextEdit
var confirm_dialog_panel: PanelContainer

func setup(quest: Dictionary, instance: Dictionary, audio_svc: Node) -> void:
	audio_service = audio_svc
	_build_ui(quest, instance)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if confirm_dialog_panel != null and is_instance_valid(confirm_dialog_panel):
				confirm_dialog_panel.queue_free()
				get_viewport().set_input_as_handled()
				return
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
			if confirm_dialog_panel != null and is_instance_valid(confirm_dialog_panel):
				return
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

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	scroll.add_child(root)

	# Заголовок
	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "%s • %s" % [str(quest.get("quest_id", "")), str(quest.get("title", "Экспедиция"))]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.56))
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "Закрыть [Esc]"
	close_btn.pressed.connect(func(): closed.emit())
	header.add_child(close_btn)

	# Мета-информация: направление, время, опыт
	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 14)
	root.add_child(meta_row)

	var reward: Dictionary = quest.get("reward_policy", {})
	var weights: Dictionary = reward.get("skill_weights_percent", {})
	var skill_id := str(weights.keys()[0]) if not weights.is_empty() else ""
	if not skill_id.is_empty():
		var skill_lbl := Label.new()
		var skill_info: Dictionary = ContentRepositoryScript.SKILLS.get(skill_id, {})
		var icon: String = str(skill_info.get("icon", "✦"))
		var s_title: String = str(skill_info.get("title", skill_id))
		skill_lbl.text = "%s %s" % [icon, s_title]
		skill_lbl.add_theme_font_size_override("font_size", 12)
		skill_lbl.add_theme_color_override("font_color", Color(0.72, 0.88, 0.95))
		meta_row.add_child(skill_lbl)

	var minutes: Variant = quest.get("minutes", {})
	if typeof(minutes) == TYPE_DICTIONARY and not (minutes as Dictionary).is_empty():
		var min_m := int((minutes as Dictionary).get("min", 0))
		var max_m := int((minutes as Dictionary).get("max", 0))
		if min_m > 0 and max_m > 0:
			var time_lbl := Label.new()
			time_lbl.text = "⏱ %d–%d мин" % [min_m, max_m]
			time_lbl.add_theme_font_size_override("font_size", 12)
			time_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.70))
			meta_row.add_child(time_lbl)

	var reward_lbl := Label.new()
	reward_lbl.text = "✦ Награда: %d XP" % int(reward.get("activity_budget", 0))
	reward_lbl.add_theme_font_size_override("font_size", 12)
	reward_lbl.add_theme_color_override("font_color", Color(0.55, 0.92, 0.65))
	meta_row.add_child(reward_lbl)

	# Описание / Пояснение задачи
	var summary_box := PanelContainer.new()
	var sum_style := StyleBoxFlat.new()
	sum_style.bg_color = Color(0.20, 0.17, 0.22, 0.70)
	sum_style.set_corner_radius_all(6)
	sum_style.set_content_margin_all(10)
	summary_box.add_theme_stylebox_override("panel", sum_style)
	root.add_child(summary_box)

	var summary := Label.new()
	summary.text = str(quest.get("summary", ""))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 13)
	summary.add_theme_color_override("font_color", Color(0.92, 0.90, 0.84))
	summary_box.add_child(summary)

	# Маршрут шагов (если есть)
	var steps: Array = quest.get("goal_steps", [])
	if not steps.is_empty():
		var steps_box := VBoxContainer.new()
		steps_box.add_theme_constant_override("separation", 4)
		root.add_child(steps_box)

		var steps_title := Label.new()
		steps_title.text = "Маршрут шагов:"
		steps_title.add_theme_font_size_override("font_size", 13)
		steps_title.add_theme_color_override("font_color", Color(0.90, 0.80, 0.55))
		steps_box.add_child(steps_title)

		var step_str_list: Array[String] = []
		var idx := 1
		for s in steps:
			step_str_list.append("%d. %s" % [idx, str(s)])
			idx += 1
		var steps_lbl := Label.new()
		steps_lbl.text = "    →    ".join(step_str_list)
		steps_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		steps_lbl.add_theme_font_size_override("font_size", 12)
		steps_lbl.add_theme_color_override("font_color", Color(0.74, 0.82, 0.88))
		steps_box.add_child(steps_lbl)

	# Что считается завершением
	var criteria_title := Label.new()
	criteria_title.text = "Что нужно сделать для завершения:"
	criteria_title.add_theme_font_size_override("font_size", 14)
	criteria_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	root.add_child(criteria_title)

	var criteria_list := VBoxContainer.new()
	criteria_list.add_theme_constant_override("separation", 6)
	root.add_child(criteria_list)

	for criterion in quest.get("completion_criteria", []):
		var item_hbox := HBoxContainer.new()
		item_hbox.add_theme_constant_override("separation", 8)
		criteria_list.add_child(item_hbox)

		var bullet := Label.new()
		bullet.text = "✓"
		bullet.add_theme_font_size_override("font_size", 12)
		bullet.add_theme_color_override("font_color", Color(0.55, 0.90, 0.60))
		item_hbox.add_child(bullet)

		var line := Label.new()
		line.text = str(criterion)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", 12)
		line.add_theme_color_override("font_color", Color(0.88, 0.86, 0.80))
		item_hbox.add_child(line)

	# Разделитель
	var sep := HSeparator.new()
	sep.modulate = Color(0.6, 0.5, 0.3, 0.5)
	root.add_child(sep)

	# Блок действий
	if instance.is_empty():
		_build_accept_controls(root, quest)
	else:
		_build_instance_controls(root, quest, instance)

func _build_accept_controls(root: VBoxContainer, quest: Dictionary) -> void:
	var variants: Array = quest.get("variants", [])
	if variants.size() > 1:
		var variant_label := Label.new()
		variant_label.text = "Выбери вариант выполнения:"
		variant_label.add_theme_font_size_override("font_size", 12)
		variant_label.add_theme_color_override("font_color", Color(0.8, 0.76, 0.68))
		root.add_child(variant_label)

		var option := OptionButton.new()
		for variant in variants:
			option.add_item(str((variant as Dictionary).get("title", "Вариант")))
			option.set_item_metadata(option.item_count - 1, str((variant as Dictionary).get("id", "")))
		root.add_child(option)
		if option.item_count > 0:
			selected_variant_id = str(option.get_item_metadata(0))
		option.item_selected.connect(func(index: int): selected_variant_id = str(option.get_item_metadata(index)))
	elif variants.size() == 1:
		selected_variant_id = str((variants[0] as Dictionary).get("id", ""))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	root.add_child(actions)

	var complete_btn := Button.new()
	complete_btn.text = "Отметить выполненным ✓"
	complete_btn.custom_minimum_size = Vector2(230, 44)
	complete_btn.pressed.connect(func():
		_show_confirmation_dialog(quest, "", "")
	)
	actions.add_child(complete_btn)

	var accept := Button.new()
	accept.text = "Взять в работу"
	accept.custom_minimum_size = Vector2(170, 44)
	accept.pressed.connect(func():
		accept_requested.emit(str(quest.get("quest_id", "")), int(quest.get("revision", 1)), selected_variant_id)
	)
	actions.add_child(accept)

func _build_instance_controls(root: VBoxContainer, quest: Dictionary, instance: Dictionary) -> void:
	var status := str(instance.get("status", "ACTIVE"))
	var status_label := Label.new()
	status_label.text = "Состояние: " + _status_title(status)
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.85, 0.80, 0.65))
	root.add_child(status_label)

	var variant_title := _variant_title(quest.get("variants", []), str(instance.get("variant_id", "")))
	if not variant_title.is_empty():
		var variant := Label.new()
		variant.text = "Вариант: " + variant_title
		variant.add_theme_color_override("font_color", Color(0.74, 0.78, 0.82))
		root.add_child(variant)

	var instance_id := str(instance.get("instance_id", ""))

	if status == "ACTIVE":
		note_edit = TextEdit.new()
		note_edit.placeholder_text = "Короткая заметка о том, как всё прошло (необязательно)"
		note_edit.custom_minimum_size = Vector2(0, 68)
		root.add_child(note_edit)

		var artifact_id := str(instance.get("draft_artifact_id", ""))
		var attachment := Label.new()
		attachment.text = "Вложение: рисунок или фото добавлено ✓" if not artifact_id.is_empty() else "Вложение: можно прикрепить рисунок или фото"
		attachment.add_theme_color_override("font_color", Color(0.62, 0.85, 0.70) if not artifact_id.is_empty() else Color(0.65, 0.65, 0.62))
		attachment.add_theme_font_size_override("font_size", 11)
		root.add_child(attachment)

		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 12)
		root.add_child(actions)

		var complete_btn := Button.new()
		complete_btn.text = "Отметить выполненным ✓"
		complete_btn.custom_minimum_size = Vector2(230, 42)
		complete_btn.pressed.connect(func():
			var note := note_edit.text if note_edit != null else ""
			_show_confirmation_dialog(quest, instance_id, note)
		)
		actions.add_child(complete_btn)

		var add_image := Button.new()
		add_image.text = "📷 Рисунок / фото"
		actions.add_child(add_image)

		var file_dialog := FileDialog.new()
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
		var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		if not downloads.is_empty() and DirAccess.dir_exists_absolute(downloads):
			file_dialog.current_dir = downloads
		add_child(file_dialog)
		add_image.pressed.connect(func(): file_dialog.popup_centered_ratio(0.72))
		file_dialog.file_selected.connect(func(path: String): artifact_import_requested.emit(path, instance_id))

		var pause := Button.new()
		pause.text = "Отложить"
		pause.pressed.connect(func(): pause_requested.emit(instance_id))
		actions.add_child(pause)

	elif status == "PAUSED":
		var paused := Label.new()
		paused.text = "Экспедиция отложена без штрафа. Всегда можно вернуться к ней в любое время."
		paused.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(paused)

		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 12)
		root.add_child(actions)

		var complete_btn := Button.new()
		complete_btn.text = "Отметить выполненным ✓"
		complete_btn.custom_minimum_size = Vector2(230, 42)
		complete_btn.pressed.connect(func():
			_show_confirmation_dialog(quest, instance_id, "")
		)
		actions.add_child(complete_btn)

		var resume := Button.new()
		resume.text = "Продолжить"
		resume.pressed.connect(func(): resume_requested.emit(instance_id))
		actions.add_child(resume)

	elif status == "SUBMITTED":
		var waiting := Label.new()
		waiting.text = "Результат готов к зачислению:"
		waiting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		waiting.add_theme_color_override("font_color", Color(0.86, 0.78, 0.58))
		root.add_child(waiting)

		var complete_btn := Button.new()
		complete_btn.text = "Отметить выполненным ✓"
		complete_btn.custom_minimum_size = Vector2(230, 42)
		complete_btn.pressed.connect(func():
			_show_confirmation_dialog(quest, instance_id, "")
		)
		root.add_child(complete_btn)

	elif status == "COMPLETED":
		var done_panel := PanelContainer.new()
		var done_style := StyleBoxFlat.new()
		done_style.bg_color = Color(0.12, 0.22, 0.15, 0.90)
		done_style.border_color = Color(0.40, 0.85, 0.50, 0.85)
		done_style.set_border_width_all(1)
		done_style.set_corner_radius_all(6)
		done_style.set_content_margin_all(14)
		done_panel.add_theme_stylebox_override("panel", done_style)
		root.add_child(done_panel)

		var done_box := VBoxContainer.new()
		done_box.add_theme_constant_override("separation", 4)
		done_panel.add_child(done_box)

		var done_lbl := Label.new()
		done_lbl.text = "✓ Цель успешно выполнена! Награда начислена на станции."
		done_lbl.add_theme_font_size_override("font_size", 14)
		done_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
		done_box.add_child(done_lbl)

		var note_text: String = str(instance.get("note", ""))
		if not note_text.is_empty():
			var note_lbl := Label.new()
			note_lbl.text = "Заметка: " + note_text
			note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note_lbl.add_theme_font_size_override("font_size", 11)
			note_lbl.add_theme_color_override("font_color", Color(0.80, 0.85, 0.80))
			done_box.add_child(note_lbl)

func _show_confirmation_dialog(quest: Dictionary, instance_id: String, note: String) -> void:
	if confirm_dialog_panel != null and is_instance_valid(confirm_dialog_panel):
		confirm_dialog_panel.queue_free()

	confirm_dialog_panel = PanelContainer.new()
	confirm_dialog_panel.set_anchors_preset(PRESET_FULL_RECT)
	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.02, 0.02, 0.04, 0.82)
	confirm_dialog_panel.add_theme_stylebox_override("panel", overlay_style)
	add_child(confirm_dialog_panel)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	confirm_dialog_panel.add_child(center)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(480, 200)
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.18, 0.15, 0.22, 0.98)
	box_style.border_color = Color(0.92, 0.78, 0.42, 0.95)
	box_style.set_border_width_all(2)
	box_style.set_corner_radius_all(10)
	box_style.set_content_margin_all(24)
	box.add_theme_stylebox_override("panel", box_style)
	center.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	box.add_child(vbox)

	var q_lbl := Label.new()
	q_lbl.text = "Все точно верно — отмечаю?"
	q_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q_lbl.add_theme_font_size_override("font_size", 18)
	q_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.62))
	vbox.add_child(q_lbl)

	var reward_budget := int((quest.get("reward_policy", {}) as Dictionary).get("activity_budget", 0))
	var desc_lbl := Label.new()
	desc_lbl.text = "Критерии выполнены! Опыт (+%d XP) сразу зачислится на станции, а результат сохранится в журнале." % reward_budget
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.76))
	vbox.add_child(desc_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var btn_confirm := Button.new()
	btn_confirm.text = "Да, всё готово! ✓"
	btn_confirm.custom_minimum_size = Vector2(160, 42)
	btn_confirm.pressed.connect(func():
		confirm_dialog_panel.queue_free()
		complete_requested.emit(str(quest.get("quest_id", "")), int(quest.get("revision", 1)), selected_variant_id, instance_id, note)
	)
	btn_row.add_child(btn_confirm)

	var btn_cancel := Button.new()
	btn_cancel.text = "Ещё проверю"
	btn_cancel.custom_minimum_size = Vector2(140, 42)
	btn_cancel.pressed.connect(func():
		confirm_dialog_panel.queue_free()
	)
	btn_row.add_child(btn_cancel)

func _variant_title(variants: Array, variant_id: String) -> String:
	for variant in variants:
		if str((variant as Dictionary).get("id", "")) == variant_id:
			return str((variant as Dictionary).get("title", ""))
	return ""

func _status_title(status: String) -> String:
	return {
		"ACTIVE": "в работе",
		"PAUSED": "отложено",
		"SUBMITTED": "готово к подтверждению",
		"COMPLETED": "завершено"
	}.get(status, status)
