class_name WaterPhotoUpload
extends Control

## Dedicated screen for Maya's river and waterfall photo upload.
##
## Narrative context:
## Maya has returned from her family outings to both Río Azul and Cascada Escondida.
## Clara (photojournalist from El Bolsón) welcomes Maya, gathers her photos and observations
## for the newspaper reportage, places them on the station's brass diptych, and heads
## to the darkroom to develop the film. Clara does NOT give a next mission yet —
## she will appear again later with the printed paper and new adventures.

const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Guide = preload("res://scripts/presentation/mission_guide.gd")
const Artifacts = preload("res://scripts/services/artifact_service.gd")

signal closed
signal command_requested(operation: String, payload: Dictionary)
signal mission_requested(quest_id: String)
signal collection_requested

var state: Dictionary = {}
var audio_service: Node
var instance_id := ""
var quest: Dictionary = {}
var feedback: Label

var river_artifact_id := ""
var fall_artifact_id := ""
var river_image_path := ""
var fall_image_path := ""
var river_note := ""
var fall_note := ""
var diff_note := ""
var submitted := false

var river_edit: TextEdit
var fall_edit: TextEdit
var diff_edit: TextEdit
var clara_speech_label: Label
var clara_status_label: Label
var clara_portrait_view: TextureRect
var submit_button: Button
var voiced := false

const CLARA_SPEECH_PENDING := "Майя, ты вернулась! Какая радость!\nТы побывала и на реке Río Azul, и на водопаде Cascada Escondida! Я так ждала твоих кадров для нашего фоторепортажа в газете Эль-Больсона. Давай загрузим сюда твои снимки: один с реки и один с водопада. Они сразу займут почётное место в латунном диптихе на стене станции!\n\nА я возьму снимки с собой в редакцию, чтобы проявить плёнку, отобрать лучшие ракурсы и сверстать полосу. Новую миссию я тебе пока не даю: мне нужно время хорошенько поработать в фотолаборатории! Я обязательно загляну к тебе на станцию позже, и мы продолжим наши приключения! До скорой встречи!"

const CLARA_SPEECH_SUBMITTED := "Клара бережно укладывает снимки в альбом:\n«Майя, какие чудесные кадры! Вода на них просто живая! Твой диптих уже красуется на стене у Галереи станции!\n\nА я забираю снимки в редакцию — проявлять плёнку, подбирать цвета и верстать полосу для газеты Эль-Больсона. Новую миссию я тебе пока не даю: мне нужно время на аккуратную работу в тёмной комнате! Я обязательно появлюсь на станции позже — с готовым номером газеты и новыми историями.\n\nА ты пока любуйся своим диптихом на стене станции. До встречи, напарница!»"

func setup(game_state: Dictionary, audio_svc: Node = null) -> void:
	state = game_state.duplicate(true)
	audio_service = audio_svc
	var ctx := UI.context(state)
	instance_id = str(ctx.get("instance_id", ""))
	if instance_id.is_empty():
		instance_id = str(UI.instance_for(state, "FG08").get("instance_id", ""))
	quest = ctx.get("quest", UI.quest_for(UI.instance_for(state, instance_id)))
	if quest.is_empty():
		quest = UI.quest_for(UI.instance_for(state, "FG08"))

	_load_existing_data()
	_build()

func show_result(result: Dictionary) -> void:
	if feedback == null:
		return
	feedback.text = UI.result_text(result)
	feedback.visible = true

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close_and_save()

func _load_existing_data() -> void:
	var progress: Dictionary = state.get("adventures", {}).get("progress", {}).get(instance_id, {})
	var stages: Dictionary = progress.get("stages", {})

	# River stage
	var r_stage: Dictionary = stages.get("water_river", {})
	river_artifact_id = str(r_stage.get("draft", {}).get("artifact_id", ""))
	if river_artifact_id.is_empty():
		for att in r_stage.get("attempts", []):
			var aid := str(att.get("evidence", {}).get("artifact_id", ""))
			if not aid.is_empty():
				river_artifact_id = aid
				break
	if not river_artifact_id.is_empty():
		river_image_path = Artifacts.media_path_for(state, river_artifact_id)
	else:
		river_image_path = str(r_stage.get("draft", {}).get("source_path", ""))

	if river_note.is_empty():
		river_note = str(r_stage.get("draft", {}).get("note", ""))
		if river_note.is_empty():
			river_note = str(r_stage.get("draft", {}).get("responses", {}).get("water_river_return", {}).get("fields", {}).get("observation", ""))

	# Waterfall stage
	var f_stage: Dictionary = stages.get("water_fall", {})
	fall_artifact_id = str(f_stage.get("draft", {}).get("artifact_id", ""))
	if fall_artifact_id.is_empty():
		for att in f_stage.get("attempts", []):
			var aid := str(att.get("evidence", {}).get("artifact_id", ""))
			if not aid.is_empty():
				fall_artifact_id = aid
				break
	if not fall_artifact_id.is_empty():
		fall_image_path = Artifacts.media_path_for(state, fall_artifact_id)
	else:
		fall_image_path = str(f_stage.get("draft", {}).get("source_path", ""))

	if fall_note.is_empty():
		fall_note = str(f_stage.get("draft", {}).get("note", ""))
		if fall_note.is_empty():
			fall_note = str(f_stage.get("draft", {}).get("responses", {}).get("water_fall_return", {}).get("fields", {}).get("observation", ""))

	# Comparison stage
	var comp_stage: Dictionary = stages.get("water_compare", {})
	if diff_note.is_empty():
		diff_note = str(comp_stage.get("draft", {}).get("note", ""))
		if diff_note.is_empty():
			diff_note = str(comp_stage.get("draft", {}).get("responses", {}).get("water_compare_pages", {}).get("fields", {}).get("difference", ""))

	submitted = bool(progress.get("water_photos_submitted", false))

func _build() -> void:
	for child in get_children():
		child.queue_free()

	var s := UI.shell(self, state, "Фоторепортаж Клары · Снимки реки и водопада", "Клара · фотограф из газеты Эль-Больсона", func(): closed.emit(), true)
	feedback = s.feedback
	var content: VBoxContainer = s.content
	var sc := UI.scroll(content)
	var main_col := UI.column(sc)
	main_col.add_theme_constant_override("separation", 16)

	_build_story_card(main_col)
	_build_photos_row(main_col)
	_build_comparison_card(main_col)
	_build_footer(content)

func _build_story_card(parent: Node) -> void:
	var card := UI.card(parent)
	var head := UI.row(card)
	head.add_theme_constant_override("separation", 16)

	var portrait_path := Guide.portrait_path("clara", "happy" if submitted else "neutral")
	if not voiced:
		voiced = true
		UI.voice(audio_service, "clara", "happy" if submitted else "greet")

	clara_portrait_view = TextureRect.new()
	if not portrait_path.is_empty():
		clara_portrait_view.texture = load(portrait_path)
	clara_portrait_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	clara_portrait_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	clara_portrait_view.custom_minimum_size = Vector2(100, 100)
	head.add_child(clara_portrait_view)

	var who := UI.column(head)
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.label("Клара", who, 22, UI.BRASS)
	UI.label("фотограф из газеты Эль-Больсона", who, 14, UI.TEAL)
	UI.label("«Хороший кадр прячется в тишине. Давай его поймаем!»", who, 13, UI.MUTED)

	clara_speech_label = UI.label(CLARA_SPEECH_SUBMITTED if submitted else CLARA_SPEECH_PENDING, card, 15, UI.PAPER)
	clara_speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	clara_status_label = UI.label("✓ Снимки переданы Кларе · Клара вернётся позже с готовым номером газеты!" if submitted else "Клара ждёт снимки реки и водопада", card, 14, UI.TEAL if submitted else UI.MUTED)

func _build_photos_row(parent: Node) -> void:
	var row := UI.row(parent)
	row.add_theme_constant_override("separation", 18)

	_build_river_card(row)
	_build_fall_card(row)

func _build_river_card(parent: Node) -> void:
	var card := UI.card(parent)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(320, 0)

	var title_row := UI.row(card)
	UI.label("🌊 Река · Río Azul", title_row, 18, UI.BRASS)
	UI.label("Эль-Больсон", card, 12, UI.MUTED)

	var photo_box := UI.column(card)
	photo_box.add_theme_constant_override("separation", 8)

	var has_photo := not river_image_path.is_empty() and FileAccess.file_exists(river_image_path)
	if has_photo:
		var tex := UI.texture(river_image_path, 512)
		if tex != null:
			var prev := TextureRect.new()
			prev.texture = tex
			prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			prev.custom_minimum_size = Vector2(260, 160)
			photo_box.add_child(prev)
		UI.label("✓ Снимок реки прикреплён (на диптихе станции)", photo_box, 13, UI.TEAL)
		UI.button("Заменить фото реки 📷", photo_box, func():
			_capture_edits()
			command_requested.emit("attach_water_photo", {
				"target": "river",
				"instance_id": instance_id,
				"river_note": river_note,
				"fall_note": fall_note,
				"diff_note": diff_note
			}))
	else:
		var placeholder := PanelContainer.new()
		placeholder.custom_minimum_size = Vector2(260, 130)
		placeholder.add_theme_stylebox_override("panel", UI.style(Color("16242c"), UI.MUTED, 8))
		photo_box.add_child(placeholder)
		var p_label := Label.new()
		p_label.text = "📷 Здесь появится снимок реки Río Azul\nНажми кнопку ниже, чтобы выбрать файл"
		p_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p_label.add_theme_color_override("font_color", UI.MUTED)
		p_label.add_theme_font_size_override("font_size", 13)
		placeholder.add_child(p_label)

		UI.button("Загрузить фото реки 📷", photo_box, func():
			_capture_edits()
			command_requested.emit("attach_water_photo", {
				"target": "river",
				"instance_id": instance_id,
				"river_note": river_note,
				"fall_note": fall_note,
				"diff_note": diff_note
			}), true)

	UI.label("Что запомнилось на реке? (голос воды, цвет, течение)", card, 13, UI.TEAL)
	river_edit = TextEdit.new()
	river_edit.custom_minimum_size = Vector2(0, 65)
	river_edit.placeholder_text = "Например: вода бирюзовая и чистая, река течёт спокойно среди леса..."
	river_edit.text = river_note
	river_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	card.add_child(river_edit)

func _build_fall_card(parent: Node) -> void:
	var card := UI.card(parent)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(320, 0)

	var title_row := UI.row(card)
	UI.label("💧 Водопад · Cascada Escondida", title_row, 18, UI.BRASS)
	UI.label("Мальин-Аогадо", card, 12, UI.MUTED)

	var photo_box := UI.column(card)
	photo_box.add_theme_constant_override("separation", 8)

	var has_photo := not fall_image_path.is_empty() and FileAccess.file_exists(fall_image_path)
	if has_photo:
		var tex := UI.texture(fall_image_path, 512)
		if tex != null:
			var prev := TextureRect.new()
			prev.texture = tex
			prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			prev.custom_minimum_size = Vector2(260, 160)
			photo_box.add_child(prev)
		UI.label("✓ Снимок водопада прикреплён (на диптихе станции)", photo_box, 13, UI.TEAL)
		UI.button("Заменить фото водопада 📷", photo_box, func():
			_capture_edits()
			command_requested.emit("attach_water_photo", {
				"target": "fall",
				"instance_id": instance_id,
				"river_note": river_note,
				"fall_note": fall_note,
				"diff_note": diff_note
			}))
	else:
		var placeholder := PanelContainer.new()
		placeholder.custom_minimum_size = Vector2(260, 130)
		placeholder.add_theme_stylebox_override("panel", UI.style(Color("16242c"), UI.MUTED, 8))
		photo_box.add_child(placeholder)
		var p_label := Label.new()
		p_label.text = "📷 Здесь появится снимок Cascada Escondida\nНажми кнопку ниже, чтобы выбрать файл"
		p_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p_label.add_theme_color_override("font_color", UI.MUTED)
		p_label.add_theme_font_size_override("font_size", 13)
		placeholder.add_child(p_label)

		UI.button("Загрузить фото водопада 📷", photo_box, func():
			_capture_edits()
			command_requested.emit("attach_water_photo", {
				"target": "fall",
				"instance_id": instance_id,
				"river_note": river_note,
				"fall_note": fall_note,
				"diff_note": diff_note
			}), true)

	UI.label("Что запомнилось у водопада? (грохот, свежесть, брызги)", card, 13, UI.TEAL)
	fall_edit = TextEdit.new()
	fall_edit.custom_minimum_size = Vector2(0, 65)
	fall_edit.placeholder_text = "Например: водопад шумит на всю долину, от падающей воды летит прохладный туман..."
	fall_edit.text = fall_note
	fall_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	card.add_child(fall_edit)

func _build_comparison_card(parent: Node) -> void:
	var card := UI.card(parent)
	UI.label("Сравнение для газетной статьи:", card, 16, UI.BRASS)
	UI.label("Чем отличаются голоса реки и водопада? (авторская цитата Майи для статьи Клары):", card, 13, UI.MUTED)
	diff_edit = TextEdit.new()
	diff_edit.custom_minimum_size = Vector2(0, 50)
	diff_edit.placeholder_text = "Например: река течёт плавно и тихо, а водопад громко гремит и падает с высоты уступа."
	diff_edit.text = diff_note
	diff_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	card.add_child(diff_edit)

func _build_footer(parent: Node) -> void:
	var footer := UI.row(parent)
	UI.button("Вернуться на станцию", footer, func(): _close_and_save())
	UI.button("О миссии Клары", footer, func(): mission_requested.emit("FG08"))

	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(space)

	if submitted:
		UI.label("✓ Снимки у Клары · Клара появится позже", footer, 13, UI.TEAL)
		var view_btn := UI.button("Полюбоваться диптихом на станции →", footer, func(): _close_and_save(), true)
		view_btn.name = "PhotoUploadPrimaryAction"
	else:
		submit_button = UI.button("Передать снимки Кларе ✨", footer, func():
			_capture_edits()
			command_requested.emit("submit_water_photos", {
				"instance_id": instance_id,
				"river_note": river_note,
				"fall_note": fall_note,
				"diff_note": diff_note
			}), true)
		submit_button.name = "PhotoUploadPrimaryAction"

func _capture_edits() -> void:
	if is_instance_valid(river_edit):
		river_note = river_edit.text.strip_edges()
	if is_instance_valid(fall_edit):
		fall_note = fall_edit.text.strip_edges()
	if is_instance_valid(diff_edit):
		diff_note = diff_edit.text.strip_edges()

func _close_and_save() -> void:
	_capture_edits()
	if not river_note.is_empty() or not fall_note.is_empty() or not diff_note.is_empty():
		command_requested.emit("submit_water_photos", {
			"instance_id": instance_id,
			"river_note": river_note,
			"fall_note": fall_note,
			"diff_note": diff_note,
			"silent": true
		})
	closed.emit()

func show_clara_submission_success() -> void:
	submitted = true
	if is_instance_valid(clara_speech_label):
		clara_speech_label.text = CLARA_SPEECH_SUBMITTED
	if is_instance_valid(clara_status_label):
		clara_status_label.text = "✓ Снимки переданы Кларе · Клара вернётся позже с готовым номером газеты!"
		clara_status_label.add_theme_color_override("font_color", UI.TEAL)
	if is_instance_valid(clara_portrait_view):
		var path := Guide.portrait_path("clara", "happy")
		if not path.is_empty():
			clara_portrait_view.texture = load(path)
	UI.voice(audio_service, "clara", "happy")
