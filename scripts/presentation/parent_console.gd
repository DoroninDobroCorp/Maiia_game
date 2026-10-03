class_name ParentConsoleUI
extends Control

signal closed()
signal publish_requested(quest: Dictionary)
signal confirm_requested(activity_id: String)
signal revision_requested(activity_id: String, note: String)
signal revoke_requested(quest_id: String, revision: int)
signal draft_save_requested(quest: Dictionary)
signal package_import_requested(path: String)
signal package_export_requested()
signal adventure_editor_requested()
signal adventure_setup_requested()

const ContentRepositoryScript = preload("res://scripts/services/content_repository.gd")
const ContentLibraryServiceScript = preload("res://scripts/services/content_library_service.gd")
const QuestServiceScript = preload("res://scripts/services/quest_service.gd")

var audio_service: Node
var editor_id: LineEdit
var editor_revision: SpinBox
var editor_title: LineEdit
var editor_summary: TextEdit
var editor_criteria: TextEdit
var editor_skill: OptionButton
var editor_kind: OptionButton
var editor_chapter: OptionButton
var editor_location: OptionButton
var editor_budget: SpinBox
var editor_main: CheckBox
var editor_repeat: SpinBox
var editor_status: Label
var editor_quests: Array[Dictionary] = []

func setup(state: Dictionary, audio_svc: Node) -> void:
	audio_service = audio_svc
	_build_ui(state)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if audio_service != null and audio_service.has_method("play_sfx"):
				audio_service.play_sfx("paper_flip")
			closed.emit()

func _build_ui(state: Dictionary) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.025, 0.035, 0.05, 0.90)
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
	panel.custom_minimum_size = Vector2(960, 650)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.105, 0.11, 0.14, 0.985)
	style.border_color = Color(0.64, 0.72, 0.68, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "РОДИТЕЛЬСКАЯ КОНСОЛЬ • ЛОКАЛЬНО"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.90, 0.88, 0.72))
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Закрыть"
	close_btn.pressed.connect(func(): closed.emit())
	header.add_child(close_btn)

	var note := Label.new()
	note.text = "Здесь взрослый публикует точную версию карточки и подтверждает результат. Черновики до публикации игроку не показываются."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.72, 0.74, 0.70))
	root.add_child(note)
	var adventure_actions := HBoxContainer.new()
	root.add_child(adventure_actions)
	var chapter_button := Button.new()
	chapter_button.text = "Новая глава и семейные инструменты"
	chapter_button.pressed.connect(func(): adventure_setup_requested.emit())
	adventure_actions.add_child(chapter_button)
	var adventure_editor_button := Button.new()
	adventure_editor_button.text = "Конструктор приключений"
	adventure_editor_button.pressed.connect(func(): adventure_editor_requested.emit())
	adventure_actions.add_child(adventure_editor_button)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	var publish_tab := _build_publish_tab(state)
	publish_tab.name = "Публикация квестов"
	tabs.add_child(publish_tab)

	var review_tab := _build_review_tab(state)
	review_tab.name = "Проверка результатов"
	tabs.add_child(review_tab)

	var content_tab := _build_content_editor_tab(state)
	content_tab.name = "Редактор Phase C"
	tabs.add_child(content_tab)

func _build_publish_tab(state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	var phase_b: Dictionary = state.get("phase_b", {})
	var published: Dictionary = phase_b.get("published_versions", {})
	var revoked: Array = phase_b.get("revoked_versions", [])
	for quest in ContentLibraryServiceScript.list_parent_templates(state):
		var qid := str(quest.get("quest_id", ""))
		var revision := int(quest.get("revision", 1))
		var key := QuestServiceScript.version_key(qid, revision)
		var is_published := published.has(key) and not revoked.has(key)

		var card := PanelContainer.new()
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.14, 0.145, 0.17, 0.92)
		card_style.border_color = Color(0.34, 0.50, 0.42, 0.78) if is_published else Color(0.30, 0.31, 0.35, 0.72)
		card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(7)
		card_style.set_content_margin_all(12)
		card.add_theme_stylebox_override("panel", card_style)
		list.add_child(card)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var text_box := VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_box)

		var q_title := Label.new()
		var first_goal_marker := "★ ПЕРВАЯ ЦЕЛЬ • " if str(quest.get("goal_group", "")) == "maya_first_goals" else ""
		q_title.text = "%s%s • v%d • %s" % [first_goal_marker, qid, revision, str(quest.get("title", ""))]
		q_title.add_theme_font_size_override("font_size", 14)
		q_title.add_theme_color_override("font_color", Color(0.96, 0.88, 0.67))
		text_box.add_child(q_title)
		var summary := Label.new()
		summary.text = str(quest.get("summary", ""))
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.add_theme_font_size_override("font_size", 11)
		summary.add_theme_color_override("font_color", Color(0.76, 0.76, 0.72))
		text_box.add_child(summary)

		var reward: Dictionary = quest.get("reward_policy", {})
		var meta := Label.new()
		meta.text = "Награда: %d XP • вариантов: %d • %s" % [int(reward.get("activity_budget", 0)), (quest.get("variants", []) as Array).size(), "ОПУБЛИКОВАН" if is_published else "ЧЕРНОВИК"]
		meta.add_theme_font_size_override("font_size", 10)
		meta.add_theme_color_override("font_color", Color(0.56, 0.80, 0.62) if is_published else Color(0.65, 0.64, 0.60))
		text_box.add_child(meta)

		var actions := VBoxContainer.new()
		actions.custom_minimum_size = Vector2(160, 0)
		row.add_child(actions)
		if is_published:
			var revoke := Button.new()
			revoke.text = "Отозвать по безопасности"
			revoke.pressed.connect(func(): revoke_requested.emit(qid, revision))
			actions.add_child(revoke)
		else:
			var publish := Button.new()
			publish.text = "Одобрить и открыть v%d" % revision
			var exact_quest: Dictionary = quest.duplicate(true)
			publish.pressed.connect(func(): publish_requested.emit(exact_quest))
			actions.add_child(publish)

	return scroll

func _build_review_tab(state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var phase_b: Dictionary = state.get("phase_b", {})
	var activities: Dictionary = phase_b.get("activities", {})
	var found := false
	for activity_value in activities.values():
		var activity: Dictionary = activity_value
		if str(activity.get("status", "")) != "SUBMITTED":
			continue
		var source: Dictionary = phase_b.get("quest_instances", {}).get(str(activity.get("instance_id", "")), {})
		if not str(source.get("superseded_by_instance_id", "")).is_empty():
			continue
		found = true
		var qid := str(activity.get("quest_id", ""))
		var activity_id := str(activity.get("activity_id", ""))
		var quest := ContentLibraryServiceScript.get_template(state, qid, int(activity.get("revision", -1)))

		var card := PanelContainer.new()
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.14, 0.145, 0.17, 0.94)
		card_style.border_color = Color(0.72, 0.58, 0.28, 0.75)
		card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(7)
		card_style.set_content_margin_all(12)
		card.add_theme_stylebox_override("panel", card_style)
		list.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 7)
		card.add_child(box)
		var title := Label.new()
		title.text = "%s • %s" % [qid, str(quest.get("title", "Результат"))]
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", Color(0.96, 0.88, 0.67))
		box.add_child(title)
		var note := Label.new()
		note.text = "Запись игрока: " + str(activity.get("note", "Без заметки"))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(note)
		var review_edit := LineEdit.new()
		review_edit.placeholder_text = "Комментарий при возврате на доработку"
		box.add_child(review_edit)
		var buttons := HBoxContainer.new()
		box.add_child(buttons)
		var confirm := Button.new()
		confirm.text = "✓ Подтвердить результат"
		confirm.pressed.connect(func(): confirm_requested.emit(activity_id))
		buttons.add_child(confirm)
		var revise := Button.new()
		revise.text = "Вернуть к критериям"
		revise.pressed.connect(func(): revision_requested.emit(activity_id, review_edit.text))
		buttons.add_child(revise)

	if not found:
		var empty := Label.new()
		empty.text = "Сейчас нет результатов, ожидающих проверки."
		empty.add_theme_color_override("font_color", Color(0.70, 0.72, 0.68))
		list.add_child(empty)
	return scroll

func _build_content_editor_tab(state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	scroll.add_child(root)

	var intro := Label.new()
	intro.text = "Phase C • 11 выбранных первых целей Майи + 13 универсальных карточек, всего по 3 на каждое из 8 направлений. Встроенные версии не переписываются: редактор создаёт новую ревизию, которую взрослый затем отдельно публикует."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color(0.82, 0.80, 0.72))
	root.add_child(intro)

	editor_quests = ContentLibraryServiceScript.list_parent_templates(state)
	var template_row := HBoxContainer.new()
	template_row.add_theme_constant_override("separation", 8)
	root.add_child(template_row)
	var template_select := OptionButton.new()
	template_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for quest in editor_quests:
		template_select.add_item("%s v%d • %s" % [str(quest.get("quest_id", "")), int(quest.get("revision", 1)), str(quest.get("title", ""))])
	template_row.add_child(template_select)
	var clone_btn := Button.new()
	clone_btn.text = "Открыть как v+1"
	clone_btn.pressed.connect(func():
		if template_select.selected >= 0 and template_select.selected < editor_quests.size():
			_load_editor_quest(editor_quests[template_select.selected], true)
	)
	template_row.add_child(clone_btn)
	var blank_btn := Button.new()
	blank_btn.text = "Новая карточка"
	blank_btn.pressed.connect(_clear_editor_form)
	template_row.add_child(blank_btn)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 7)
	root.add_child(grid)

	_add_form_label(grid, "ID")
	editor_id = LineEdit.new()
	editor_id.placeholder_text = "FAM01"
	grid.add_child(editor_id)
	_add_form_label(grid, "Ревизия")
	editor_revision = SpinBox.new()
	editor_revision.min_value = 1
	editor_revision.max_value = 999
	editor_revision.value = 1
	grid.add_child(editor_revision)

	_add_form_label(grid, "Название")
	editor_title = LineEdit.new()
	editor_title.placeholder_text = "Короткое понятное название"
	editor_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(editor_title)
	_add_form_label(grid, "Тип")
	editor_kind = OptionButton.new()
	for kind in ["project", "practice", "planning", "observation", "family_project", "game_lab"]:
		editor_kind.add_item(kind)
		editor_kind.set_item_metadata(editor_kind.item_count - 1, kind)
	grid.add_child(editor_kind)

	_add_form_label(grid, "Навык")
	editor_skill = OptionButton.new()
	for skill_id in ContentRepositoryScript.SKILLS.keys():
		editor_skill.add_item(str(ContentRepositoryScript.SKILLS[skill_id].get("title", skill_id)))
		editor_skill.set_item_metadata(editor_skill.item_count - 1, str(skill_id))
	grid.add_child(editor_skill)
	_add_form_label(grid, "Глава")
	editor_chapter = OptionButton.new()
	for chapter_num in range(2, 7):
		editor_chapter.add_item("Глава %d" % chapter_num)
		editor_chapter.set_item_metadata(editor_chapter.item_count - 1, "chapter_%02d" % chapter_num)
	grid.add_child(editor_chapter)

	_add_form_label(grid, "Место")
	editor_location = OptionButton.new()
	for location in ContentRepositoryScript.PHASE_C_LOCATIONS:
		editor_location.add_item(str(location.get("title", "Место")))
		editor_location.set_item_metadata(editor_location.item_count - 1, str(location.get("location_id", "")))
	grid.add_child(editor_location)
	_add_form_label(grid, "XP")
	editor_budget = SpinBox.new()
	editor_budget.min_value = 0
	editor_budget.max_value = 100
	editor_budget.step = 5
	editor_budget.value = 20
	grid.add_child(editor_budget)

	_add_form_label(grid, "Повторов")
	editor_repeat = SpinBox.new()
	editor_repeat.min_value = 1
	editor_repeat.max_value = 12
	editor_repeat.value = 1
	grid.add_child(editor_repeat)
	_add_form_label(grid, "Сюжетный ключ")
	editor_main = CheckBox.new()
	editor_main.text = "обязателен для главы"
	grid.add_child(editor_main)

	var summary_lbl := Label.new()
	summary_lbl.text = "Описание"
	root.add_child(summary_lbl)
	editor_summary = TextEdit.new()
	editor_summary.custom_minimum_size = Vector2(0, 74)
	editor_summary.placeholder_text = "Что именно предлагается сделать, без скрытых требований и лишней личной информации."
	root.add_child(editor_summary)

	var criteria_lbl := Label.new()
	criteria_lbl.text = "Критерии готовности • по одному на строку"
	root.add_child(criteria_lbl)
	editor_criteria = TextEdit.new()
	editor_criteria.custom_minimum_size = Vector2(0, 66)
	editor_criteria.placeholder_text = "Есть законченный результат.\nИгрок может объяснить свой выбор."
	root.add_child(editor_criteria)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	root.add_child(save_row)
	var save_btn := Button.new()
	save_btn.text = "Сохранить локальный черновик"
	save_btn.pressed.connect(func(): draft_save_requested.emit(_editor_quest()))
	save_row.add_child(save_btn)
	editor_status = Label.new()
	editor_status.text = "После сохранения карточка появится во вкладке публикации; игрок её ещё не увидит."
	editor_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor_status.add_theme_font_size_override("font_size", 10)
	editor_status.add_theme_color_override("font_color", Color(0.64, 0.70, 0.66))
	save_row.add_child(editor_status)

	var separator := HSeparator.new()
	root.add_child(separator)
	var pack_title := Label.new()
	pack_title.text = "Локальные пакеты JSON"
	pack_title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.62))
	root.add_child(pack_title)
	var pack_note := Label.new()
	pack_note.text = "Импорт принимает только данные квестов, не команды/URL/пути. Поле approved из пакета не является взрослым одобрением."
	pack_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pack_note.add_theme_font_size_override("font_size", 10)
	root.add_child(pack_note)
	var pack_row := HBoxContainer.new()
	pack_row.add_theme_constant_override("separation", 8)
	root.add_child(pack_row)
	var path_edit := LineEdit.new()
	path_edit.placeholder_text = "/Users/.../family_quests.json"
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pack_row.add_child(path_edit)
	var import_btn := Button.new()
	import_btn.text = "Импортировать"
	import_btn.pressed.connect(func(): package_import_requested.emit(path_edit.text.strip_edges()))
	pack_row.add_child(import_btn)
	var export_btn := Button.new()
	export_btn.text = "Экспорт моих черновиков"
	export_btn.pressed.connect(func(): package_export_requested.emit())
	pack_row.add_child(export_btn)

	_clear_editor_form()
	return scroll

func _add_form_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.68))
	parent.add_child(label)

func _clear_editor_form() -> void:
	if editor_id == null:
		return
	editor_id.text = "FAM01"
	editor_revision.value = 1
	editor_title.text = ""
	editor_summary.text = ""
	editor_criteria.text = "Есть законченный результат.\nИгрок может коротко объяснить свой выбор."
	editor_budget.value = 20
	editor_repeat.value = 1
	editor_main.button_pressed = false
	editor_kind.select(0)
	editor_skill.select(0)
	editor_chapter.select(0)
	editor_location.select(0)

func _load_editor_quest(quest: Dictionary, as_next_revision: bool) -> void:
	if editor_id == null:
		return
	editor_id.text = str(quest.get("quest_id", ""))
	editor_revision.value = int(quest.get("revision", 1)) + (1 if as_next_revision else 0)
	editor_title.text = str(quest.get("title", ""))
	editor_summary.text = str(quest.get("summary", ""))
	editor_criteria.text = "\n".join(quest.get("completion_criteria", []))
	editor_budget.value = int((quest.get("reward_policy", {}) as Dictionary).get("activity_budget", 20))
	editor_main.button_pressed = bool(quest.get("is_main_quest", false))
	editor_repeat.value = int((quest.get("repeat_policy", {}) as Dictionary).get("max_completions", 1))
	_select_by_metadata(editor_kind, str(quest.get("kind", "project")))
	var weights: Dictionary = (quest.get("reward_policy", {}) as Dictionary).get("skill_weights_percent", {})
	if not weights.is_empty():
		_select_by_metadata(editor_skill, str(weights.keys()[0]))
	_select_by_metadata(editor_chapter, str(quest.get("chapter_id", "chapter_02")))
	_select_by_metadata(editor_location, str(quest.get("location_id", "radio_cafe")))

func _select_by_metadata(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return

func _editor_quest() -> Dictionary:
	var criteria: Array[String] = []
	for line in editor_criteria.text.split("\n"):
		var clean := str(line).strip_edges()
		if not clean.is_empty():
			criteria.append(clean)
	if criteria.is_empty():
		criteria.append("Есть законченный результат, соответствующий описанию.")
	var skill_id := str(editor_skill.get_item_metadata(editor_skill.selected))
	var repeat_max := int(editor_repeat.value)
	return {
		"schema_version": 1,
		"quest_id": editor_id.text.strip_edges().to_upper(),
		"revision": int(editor_revision.value),
		"content_status": "DRAFT",
		"kind": str(editor_kind.get_item_metadata(editor_kind.selected)),
		"title": editor_title.text.strip_edges(),
		"summary": editor_summary.text.strip_edges(),
		"is_main_quest": editor_main.button_pressed,
		"chapter_id": str(editor_chapter.get_item_metadata(editor_chapter.selected)),
		"location_id": str(editor_location.get_item_metadata(editor_location.selected)),
		"estimated_minutes": {"min": 10, "max": 40},
		"completion_criteria": criteria,
		"variants": [{"id": "home", "title": "Домашний вариант", "home_available": true}],
		"context": {"adult_presence": "for_review", "requires_purchase": false, "requires_network": false, "risk_tags": []},
		"evidence_policy": {"allowed": ["parent_observation", "note", "local_image"], "required_media": false, "reviewer": "parent"},
		"reward_policy": {"activity_budget": int(editor_budget.value), "lane": "project" if int(editor_budget.value) >= 20 else "practice", "skill_weights_percent": {skill_id: 100} if int(editor_budget.value) > 0 else {}, "world_effect_ids": []},
		"repeat_policy": {"mode": "once" if repeat_max == 1 else "limited", "max_completions": repeat_max},
		"provenance": {"origin": "parent_editor"}
	}
