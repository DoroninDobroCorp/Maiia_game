class_name AuthorDialogueEditorUI
extends Control

signal closed()
signal publish_requested(package: Dictionary)
signal rollback_requested(patch_id: String)

const AuthorPatchServiceScript = preload("res://scripts/services/author_patch_service.gd")

var state_ref: Dictionary
var radio_edit: TextEdit
var archive_edit: TextEdit
var patch_id_edit: LineEdit
var preview_label: Label

func setup(state: Dictionary, _audio_service: Node) -> void:
	state_ref = state
	_build_ui()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			closed.emit()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.045, 0.075, 0.90)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			closed.emit()
	)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 610)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.135, 0.12, 0.17, 0.985)
	style.border_color = Color(0.72, 0.62, 0.36, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "ТЕРМИНАЛ АВТОРА • РЕПЛИКИ"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.56))
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Закрыть"
	close_btn.pressed.connect(func(): closed.emit())
	header.add_child(close_btn)

	var desc := Label.new()
	desc.text = "Редактируются только две разрешённые реплики. Предпросмотр ничего не меняет; публикацию можно откатить."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.78, 0.77, 0.72))
	root.add_child(desc)

	patch_id_edit = LineEdit.new()
	patch_id_edit.text = "family_patch_%d" % int(Time.get_unix_time_from_system())
	patch_id_edit.placeholder_text = "ID версии"
	root.add_child(patch_id_edit)

	var radio_label := Label.new()
	radio_label.text = "Приветствие радио"
	root.add_child(radio_label)
	radio_edit = TextEdit.new()
	radio_edit.custom_minimum_size = Vector2(0, 95)
	radio_edit.text = AuthorPatchServiceScript.get_dialogue(state_ref, "radio_greeting")
	root.add_child(radio_edit)

	var archive_label := Label.new()
	archive_label.text = "Заметка архива"
	root.add_child(archive_label)
	archive_edit = TextEdit.new()
	archive_edit.custom_minimum_size = Vector2(0, 95)
	archive_edit.text = AuthorPatchServiceScript.get_dialogue(state_ref, "archive_note")
	root.add_child(archive_edit)

	preview_label = Label.new()
	preview_label.text = "Предпросмотр ещё не запускался."
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_label.add_theme_font_size_override("font_size", 11)
	preview_label.add_theme_color_override("font_color", Color(0.68, 0.70, 0.72))
	root.add_child(preview_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	root.add_child(actions)
	var preview_btn := Button.new()
	preview_btn.text = "Предпросмотр"
	preview_btn.pressed.connect(_on_preview)
	actions.add_child(preview_btn)
	var publish_btn := Button.new()
	publish_btn.text = "Опубликовать локально"
	publish_btn.pressed.connect(func(): publish_requested.emit(_package()))
	actions.add_child(publish_btn)

	var last_patch := _last_published_patch_id()
	if not last_patch.is_empty():
		var rollback_btn := Button.new()
		rollback_btn.text = "Откатить «%s»" % last_patch
		rollback_btn.pressed.connect(func(): rollback_requested.emit(last_patch))
		actions.add_child(rollback_btn)

func _package() -> Dictionary:
	return {
		"schema_version": 1,
		"patch_id": patch_id_edit.text.strip_edges(),
		"dialogue": {
			"radio_greeting": radio_edit.text.strip_edges(),
			"archive_note": archive_edit.text.strip_edges()
		}
	}

func _on_preview() -> void:
	var before := state_ref.duplicate(true)
	var result := AuthorPatchServiceScript.preview(_package())
	if bool(result.get("ok", false)):
		var preview: Dictionary = result.get("preview", {})
		preview_label.text = "✓ Предпросмотр: «%s» / «%s»" % [str(preview.get("dialogue", {}).get("radio_greeting", "")), str(preview.get("dialogue", {}).get("archive_note", ""))]
		preview_label.add_theme_color_override("font_color", Color(0.56, 0.88, 0.64))
	else:
		preview_label.text = "Ошибка: " + "; ".join(result.get("errors", []))
		preview_label.add_theme_color_override("font_color", Color(0.95, 0.58, 0.52))
	# Явный инвариант предпросмотра: состояние остаётся побитно эквивалентным по данным.
	assert(JSON.stringify(before) == JSON.stringify(state_ref))

func _last_published_patch_id() -> String:
	var patches: Dictionary = state_ref.get("phase_b", {}).get("author_patches", {})
	var last_id := ""
	var last_time := ""
	for patch_id in patches.keys():
		var record: Dictionary = patches[patch_id]
		if str(record.get("status", "")) != "PUBLISHED":
			continue
		var published_at := str(record.get("published_at", ""))
		if published_at >= last_time:
			last_time = published_at
			last_id = str(patch_id)
	return last_id
