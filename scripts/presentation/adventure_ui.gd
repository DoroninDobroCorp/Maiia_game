class_name AdventureUI
extends RefCounted

## Presentation API (all screens are read-only projections of state).
## setup(state: Dictionary, audio_svc: Node = null); show_result(result: Dictionary).
## Main routes command_requested(operation, payload), commits, then refreshes on success.
## _adventure_ui optional context: quest, instance_id, stage_id, room_id, slot_id,
## work_id, editor_quest, catalog. No context is written back to the save.
## Navigation: closed, quest_requested(qid), episode_requested(instance_id,stage_id),
## collection_requested, gallery_requested(room_id), map_requested, editor_requested,
## legacy_journal_requested, family_requested. Main must disable world movement under a modal.
## Commands:
## stage_draft {instance_id,stage_id,draft}; stage_submit {instance_id,stage_id,evidence};
## stage_attempt {instance_id,stage_id,interaction_id,response};
## stage_lexemes {instance_id,lexeme_ids,status,assistance};
## stage_hint {instance_id,stage_id,interaction_id,level}; stage_review {instance_id,stage_id,approved,
## criteria:Array[bool],note,assistance}; pin_quest {quest_id,pinned};
## pause_adventure / resume_adventure {instance_id};
## create_work {title,kind,authorship,content}; add_work_version {work_id,content,note};
## create_exhibit {work_id,recipe_id,caption}; import_image {work_id,version_id};
## attach_stage_media {instance_id,stage_id,draft}; open_starter_project {starter_project_id};
## place_exhibit {room_id,slot_id,exhibit_id,version_id,caption};
## remove_placement {room_id,slot_id}; create_room {name,theme};
## update_room {room_id,name,theme,frame_style}; delete_room {room_id,save_snapshot};
## snapshot_room {room_id,name}; restore_snapshot {room_id,snapshot_id};
## launch_work {work_id,version_id,launch_entry_id};
## save_adventure_draft / validate_adventure / preview_adventure / publish_adventure
## {quest:Dictionary}; import_adventure_package {package:Dictionary};
## chapter_finale {title,work_ids:Array,quiet:bool}; discover_secret {secret_id}.
## stage_submit evidence.choices maps interaction ID to {selected_ids,fields,interaction_id};
## all puzzle responses are sent to the core for validation. Completed replay stays local.
## No button claims success before main calls show_result. Errors retain form data.

const NIGHT := Color("101b27")
const PANEL := Color("1e2b34")
const PAPER := Color("f0e3c8")
const BRASS := Color("d8b676")
const MUTED := Color("b7bbb2")
const TEAL := Color("88bab0")
const INK := Color("25343b")

static func style(color: Color, border: Color = Color.TRANSPARENT, padding: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(padding)
	return s

static func make_theme(state: Dictionary) -> Theme:
	var t := Theme.new()
	# AppRoot owns content_scale_factor; multiplying here would scale twice.
	t.default_font_size = 16
	for type_name in ["Label", "Button", "CheckButton", "CheckBox", "OptionButton", "LineEdit", "TextEdit"]:
		t.set_color("font_color", type_name, PAPER)
		t.set_color("font_hover_color", type_name, Color.WHITE)
		t.set_color("font_pressed_color", type_name, BRASS)
		t.set_color("font_disabled_color", type_name, MUTED.darkened(0.2))
	for type_name in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type_name, style(Color("263842"), Color("576065"), 10))
		t.set_stylebox("hover", type_name, style(Color("344b50"), BRASS, 10))
		t.set_stylebox("pressed", type_name, style(Color("405b59"), BRASS, 10))
		t.set_stylebox("disabled", type_name, style(Color("1c2933"), Color("37434a"), 10))
		t.set_stylebox("focus", type_name, style(Color.TRANSPARENT, PAPER, 2))
	for type_name in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type_name, style(Color("15232e"), Color("60716f"), 12))
		t.set_stylebox("focus", type_name, style(Color("15232e"), BRASS, 12))
		t.set_color("caret_color", type_name, BRASS)
	t.set_stylebox("panel", "PanelContainer", style(PANEL, Color("4b5457")))
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	return t

static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

static func label(text: String, parent: Node, size: int = 0, color: Color = PAPER) -> Label:
	var n := Label.new()
	n.text = text
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.add_theme_color_override("font_color", color)
	if size > 0:
		n.add_theme_font_size_override("font_size", size)
	parent.add_child(n)
	return n

static func button(text: String, parent: Node, callback: Callable, primary: bool = false) -> Button:
	var n := Button.new()
	n.text = text
	n.custom_minimum_size.y = 42
	n.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		n.add_theme_stylebox_override("normal", style(BRASS, BRASS, 10))
		n.add_theme_color_override("font_color", INK)
	n.pressed.connect(callback)
	parent.add_child(n)
	return n

static func row(parent: Node) -> HBoxContainer:
	var n := HBoxContainer.new()
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(n)
	return n

static func column(parent: Node) -> VBoxContainer:
	var n := VBoxContainer.new()
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(n)
	return n

static func card(parent: Node, parchment: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", style(PAPER if parchment else PANEL, Color("66716a") if parchment else Color("4b5457"), 18))
	parent.add_child(panel)
	return column(panel)

static func scroll(parent: Node) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	parent.add_child(sc)
	var col := column(sc)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return col

static func shell(root: Control, state: Dictionary, title: String, subtitle: String, on_close: Callable, compact: bool = false) -> Dictionary:
	if root.is_inside_tree():
		var focused := root.get_viewport().gui_get_focus_owner()
		if focused != null and root.is_ancestor_of(focused):
			root.set_meta("focus_text",str(focused.text) if focused is Button else "")
	clear(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = make_theme(state)
	var bg := ColorRect.new()
	bg.color = NIGHT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24 if side in ["left", "right"] else 16)
	root.add_child(margin)
	var body := column(margin)
	var head := row(body)
	var names := column(head)
	if not compact: label("S U R    /    Ж И В О Й   А Р Х И В", names, 13, BRASS)
	label(title, names, 26 if compact else 29)
	var close := button("Закрыть · Esc", head, on_close)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not subtitle.is_empty():
		label(subtitle, body, 14 if compact else 0, MUTED)
	var content := column(body)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var feedback := label("", body, 0, TEAL)
	feedback.max_lines_visible = 3
	feedback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	feedback.visible = false
	return {"body": body, "content": content, "feedback": feedback, "close": close}

static func input(parent: Node, placeholder: String, value: String = "") -> LineEdit:
	var n := LineEdit.new()
	n.placeholder_text = placeholder
	n.text = value
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.custom_minimum_size.y = 44
	parent.add_child(n)
	return n

static func text_input(parent: Node, placeholder: String, value: String = "", height: int = 110) -> TextEdit:
	var n := TextEdit.new()
	n.placeholder_text = placeholder
	n.text = value
	n.custom_minimum_size.y = height
	n.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(n)
	return n

static func option(parent: Node, labels: Array, chosen: int = 0) -> OptionButton:
	var n := OptionButton.new()
	for item in labels:
		n.add_item(str(item))
	n.selected = chosen
	n.fit_to_longest_item = false
	n.custom_minimum_size.x = 130
	n.clip_text = true
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(n)
	return n

static func check(text: String, parent: Node, checked: bool, callback: Callable) -> CheckBox:
	var line := row(parent)
	var box := CheckBox.new()
	box.button_pressed = checked
	box.tooltip_text = text
	box.custom_minimum_size = Vector2(30,34)
	box.toggled.connect(callback)
	line.add_child(box)
	var copy := label(text,line)
	copy.mouse_filter = Control.MOUSE_FILTER_STOP
	copy.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			box.button_pressed = not box.button_pressed
			box.grab_focus())
	return box

static func focus_later(fallback: Control, root: Control = null) -> void:
	# Capture IDs, not freed Nodes: Godot logs a warning before a lambda's body
	# when a captured Object was freed, even if the body checks is_instance_valid.
	var fallback_id := fallback.get_instance_id()
	var root_id := root.get_instance_id() if root != null else 0
	var action := func():
		var target = instance_from_id(fallback_id)
		var view = instance_from_id(root_id) if root_id != 0 else null
		if target == null or not target.is_inside_tree(): return
		if view != null and view.has_meta("focus_text"):
			var previous := str(view.get_meta("focus_text"))
			for button_node in view.find_children("*","Button",true,false):
				if not previous.is_empty() and str(button_node.text) == previous and button_node.is_visible_in_tree() and not button_node.disabled:
					button_node.grab_focus()
					return
		target.grab_focus()
	action.call_deferred()

static func context(state: Dictionary) -> Dictionary:
	return state.get("_adventure_ui", {})

static func records(value: Variant) -> Array:
	if value is Dictionary:
		return value.values()
	return value if value is Array else []

static func instances(state: Dictionary) -> Array:
	return records(state.get("phase_b", {}).get("quest_instances", {}))

static func instance_for(state: Dictionary, id: String) -> Dictionary:
	for item in instances(state):
		if str(item.get("profile_id", "player_01")) != "player_01" or item.has("superseded_by_instance_id"): continue
		if str(item.get("instance_id", "")) == id or str(item.get("quest_id", "")) == id:
			return item
	return {}

static func quest_for(instance: Dictionary) -> Dictionary:
	return instance.get("frozen_quest", instance.get("quest_snapshot", instance.get("snapshot", {})))

static func stages(quest: Dictionary) -> Array:
	return records(quest.get("adventure", {}).get("stages", []))

static func stage_progress(state: Dictionary, instance_id: String, stage_id: String) -> Dictionary:
	var progress: Dictionary = state.get("adventures", {}).get("progress", state.get("adventures", {}).get("instances", {})).get(instance_id, {})
	return progress.get("stages", {}).get(stage_id, {})

static func pinned(state: Dictionary) -> Array:
	return state.get("adventures", {}).get("pinned_by_profile", {}).get("player_01", ["FG01", "FG11", "FG08"])

static func status_text(status: String) -> String:
	return {"LOCKED": "Позже в истории", "AVAILABLE": "Можно начать", "IN_PROGRESS": "Продолжить", "ACTIVE": "Продолжить", "PAUSED": "Отложено", "AWAITING_REVIEW": "Покажем вместе", "SUBMITTED": "Покажем вместе", "COMPLETED": "Готово к выставке"}.get(status, "Можно начать")

static func result_text(result: Dictionary) -> String:
	if result.has("message"):
		return str(result.message)
	if not result.get("errors", []).is_empty():
		return "\n".join(PackedStringArray(result.errors))
	if bool(result.get("ok", false)):
		return "Сохранено. Можно продолжить или вернуться на станцию."
	var reasons := {
		"interaction_incomplete":"В этом этапе осталось несколько сцен. Выбери сцену без галочки и сохрани попытку.",
		"not_enough_lexemes":"В наборе пока не все слова этого этапа. Открой оставшиеся конверты и попробуй слова в сценах.",
		"real_visit_required":"Эта страница ждёт настоящего семейного выхода. Домашнее наблюдение можно сохранить отдельной работой.",
		"criteria_not_confirmed":"Посмотрите результат вместе и отметьте каждый выполненный пункт. Если нужна правка, материал сохранится.",
		"instance_not_active":"История сейчас отложена. Вернись к её путевому листу и выбери «Продолжить».",
		"own_contribution_required":"Добавь, какое решение ты выбрала или что изменила сама. Достаточно одного предложения.",
		"mixed_check_incomplete":"Пока не получилось набрать нужное число ответов без карточек. Можно повторить письма или начать новую попытку.",
		"mixed_check_attempt_required":"Сначала сохрани новую попытку смешанного эфира, затем отправь результат на совместный просмотр.",
		"save_failed":"Не получилось записать результат. Твой черновик остался здесь — можно попробовать сохранить ещё раз.",
		"additional_room_locked":"Ещё один зал откроется после финала любой истории или восьми разных личных работ. Все работы доступны в архиве.",
		"incompatible_room_template":"Эта выставка сохранена для другого вида комнаты. Выбери подходящий зал; нынешняя расстановка осталась на месте.",
		"self_attestation_required":"Отметь, что ты сохранила свой результат и подтверждаешь выполненные действия.",
		"observation_required":"Добавь своё наблюдение или изображение. Можно ограничиться одной короткой заметкой.",
		"comparison_required":"Запиши хотя бы одно различие между своими наблюдениями.",
		"registered_game_required":"Выберите сохранённую сборку игры. Взрослый может зарегистрировать её в семейной мастерской.",
		"registered_game_unavailable":"Сохранённая сборка сейчас недоступна. Вместе восстановите её в семейной мастерской; история и работы остаются.",
		"agreed_atlas_location_required":"Отметьте вместе место, к которому относится это наблюдение.",
		"try_again":"Попробуем ещё раз. Кнопка помощи подскажет, на что обратить внимание."
	}
	return reasons.get(str(result.get("reason", "")),"Сейчас не получилось сохранить. Твой черновик остался здесь — попробуем ещё раз или посмотрим вместе.")

static func texture(path: String, max_side: int = 512) -> Texture2D:
	if path.is_empty():
		return null
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > 20 * 1024 * 1024:
		return null
	var img := Image.new()
	if img.load(path) != OK or img.get_width() > 8192 or img.get_height() > 8192:
		return null
	if maxi(img.get_width(), img.get_height()) > max_side:
		var factor: float = float(max_side) / maxi(img.get_width(), img.get_height())
		img.resize(maxi(1, roundi(img.get_width() * factor)), maxi(1, roundi(img.get_height() * factor)))
	return ImageTexture.create_from_image(img)

static func _is_observation_page(data: Dictionary) -> bool:
	return str(data.get("stage_id", "")) in ["water_river", "water_fall"] or not str(data.get("artifact_id", "")).is_empty() or not str(data.get("fields", {}).get("observation", "")).strip_edges().is_empty()

static func work_pages(state: Dictionary, version: Dictionary, depth: int = 0, visited: Dictionary = {}) -> Array:
	var pages: Array = []
	if depth > 3: return pages
	var data: Dictionary = version.get("content", {})
	for page in data.get("pages", []):
		if page is Dictionary: pages.append(page.duplicate(true))
	# The caller already renders a root observation's own content. Its preparation
	# references explain provenance and must never replace the observation.
	if _is_observation_page(data): return pages
	for source in data.get("source_stage_works", {}).values():
		if not source is Dictionary: continue
		var id := str(source.get("work_id", ""))
		var vid := str(source.get("version_id", ""))
		var reference := JSON.stringify([id,vid])
		if visited.has(reference): continue
		visited[reference] = true
		var work: Dictionary = state.get("collections", {}).get("works", {}).get(id, {})
		if str(work.get("profile_id", "player_01")) != "player_01": continue
		for saved in work.get("versions", []):
			if str(saved.get("version_id", "")) != vid: continue
			var page_data: Dictionary = saved.get("content", {})
			var nested: Array = []
			if not _is_observation_page(page_data): nested = work_pages(state,saved,depth+1,visited)
			if not nested.is_empty(): pages.append_array(nested)
			else:
				var note := str(page_data.get("note", ""))
				if note.strip_edges().is_empty(): note = str(page_data.get("fields", {}).get("observation", ""))
				pages.append({"title":work.get("title", "Страница"),"note":note,"artifact_id":page_data.get("artifact_id", ""),"work_id":id,"version_id":vid})
	return pages

static func work_vocabulary(work: Dictionary, version: Dictionary) -> Array:
	# Definitions come only from the work's frozen snapshot; statuses come only
	# from this selected work version, never the live catalog or latest progress.
	var saved: Dictionary = version.get("content", {}).get("lexemes", {})
	var definitions: Array = records(work.get("source", {}).get("quest_snapshot", {}).get("adventure", {}).get("lexicon", []))
	var result: Array = []
	var seen: Dictionary = {}
	for definition in definitions:
		var id := str(definition.get("lexeme_id", ""))
		if not saved.has(id) or seen.has(id): continue
		seen[id] = true
		var item: Dictionary = definition.duplicate(true)
		item["progress"] = saved[id].duplicate(true) if saved[id] is Dictionary else {}
		result.append(item)
	return result
