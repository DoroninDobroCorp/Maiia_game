class_name AdventureEditor
extends Control

## Family content editor. The full quest remains a local draft until main commits.
## Preview requests are explicitly separate from publication and player progression.
const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Content = preload("res://scripts/services/adventure_content.gd")
const Library = preload("res://scripts/services/content_library_service.gd")
signal closed
signal command_requested(operation: String, payload: Dictionary)

var state: Dictionary = {}
var audio_service: Node
var quest: Dictionary = {}
var stage_index := 0
var selected_interaction_index := 0
var content: VBoxContainer
var feedback: Label
var fields: Dictionary = {}
var stage_fields: Dictionary = {}
var policy: OptionButton
var interaction_type: OptionButton
var config_text: TextEdit
var title: LineEdit
var hints: TextEdit
var stage_json: TextEdit
var import_text: TextEdit
var show_import := false
var pending_operation := ""
var close_after_save := false
var initial_quest_text := ""
var discard_offered := false
var pending_quest: Dictionary = {}
const TYPES := ["inspect_reveal","match_cards","order_fragments","assemble_selection","scripted_dialogue","real_world_step","compare_observations","exhibit_composition"]
const POLICIES := ["automatic","self_attest","joint_review"]

func setup(game_state: Dictionary, audio_svc: Node = null) -> void:
	state = game_state.duplicate(true)
	audio_service = audio_svc
	if quest.is_empty():
		var context := UI.context(state)
		quest = context.get("editor_quest", {}).duplicate(true)
		stage_index = int(context.get("editor_stage_index", 0))
		selected_interaction_index = int(context.get("editor_interaction_index", 0))
		initial_quest_text = str(context.get("editor_baseline", ""))
		if quest.is_empty():
			var package := Content.example_package()
			if not package.get("quests", []).is_empty():
				var example: Dictionary = package.quests[0]
				var saved := Library.get_template(state, str(example.quest_id))
				quest = _editable_copy(saved) if not saved.is_empty() else example.duplicate(true)
	if initial_quest_text.is_empty(): initial_quest_text = JSON.stringify(quest)
	_build()

func session_context() -> Dictionary:
	return {"editor_quest":quest.duplicate(true), "editor_stage_index":stage_index,
		"editor_interaction_index":selected_interaction_index, "editor_baseline":initial_quest_text}

func show_result(result: Dictionary) -> void:
	feedback.text = UI.result_text(result)
	feedback.visible = true
	if not result.get("errors", []).is_empty(): feedback.text = "\n".join(PackedStringArray(result.errors))
	var operation := pending_operation
	pending_operation = ""
	var closing := close_after_save and operation == "save_adventure_draft"
	close_after_save = false
	if not bool(result.get("ok", false)):
		pending_quest = {}
		if closing: _offer_discard()
		return
	if operation in ["save_adventure_draft", "publish_adventure"]:
		if result.get("quest", {}) is Dictionary and not result.get("quest", {}).is_empty(): quest = result.quest.duplicate(true)
		initial_quest_text = JSON.stringify(quest)
	if closing:
		closed.emit()
		return
	if operation == "save_adventure_draft" and not pending_quest.is_empty():
		var target := pending_quest.duplicate(true)
		pending_quest = {}
		_load_quest(target)
	elif operation == "import_adventure_package":
		show_import = false

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if show_import: show_import = false; _build()
		else: _save_close()

func _save_close() -> void:
	if quest.is_empty(): closed.emit(); return
	if not _capture():
		_offer_discard()
		return
	if JSON.stringify(quest) == initial_quest_text:
		closed.emit()
		return
	close_after_save = true
	pending_operation = "save_adventure_draft"
	command_requested.emit("save_adventure_draft",{"quest":quest.duplicate(true)})

func _offer_discard() -> void:
	if discard_offered: return
	discard_offered = true
	UI.button("Выйти без сохранения…",content,func():
		var confirm := ConfirmationDialog.new()
		confirm.title = "Закрыть черновик?"
		confirm.dialog_text = "Изменения в этой форме не сохранены. Закрыть редактор и оставить прежнюю версию?"
		confirm.ok_button_text = "Выйти без сохранения"
		confirm.cancel_button_text = "Продолжить редактировать"
		confirm.confirmed.connect(func(): closed.emit())
		add_child(confirm)
		confirm.popup_centered(Vector2i(500,190)))

func _build() -> void:
	var s := UI.shell(self,state,"Мастерская приключений","Семейный редактор · черновик, проверка, отдельный просмотр, затем публикация.",_save_close)
	content = s.content
	feedback = s.feedback
	fields.clear()
	stage_fields.clear()
	config_text = null
	stage_json = null
	title = null
	hints = null
	discard_offered = false
	if show_import:
		var sc := UI.scroll(content)
		UI.label("Импортировать пакет JSON",sc,23,UI.BRASS)
		UI.label("Пакет будет проверен целиком и добавлен как черновики. Публикация — отдельное действие.",sc)
		import_text = UI.text_input(sc,"Вставьте JSON пакета…","",330)
		UI.button("Проверить и импортировать",content,func():
			var parsed: Variant = JSON.parse_string(import_text.text)
			if not parsed is Dictionary:
				show_result({"ok":false,"message":"Нужен корректный JSON-объект пакета."})
				return
			pending_operation = "import_adventure_package"
			command_requested.emit("import_adventure_package",{"package":parsed}),true)
		return
	var toolbar := UI.row(content)
	UI.button("Импорт JSON…",toolbar,func(): if _capture(): show_import = true; _build())
	UI.button("Копия: три силуэта",toolbar,func():
		var pack := Content.example_package()
		if not pack.get("quests", []).is_empty(): _request_quest(_new_revision(pack.quests[0], false)))
	if quest.is_empty(): UI.label("Открой семейный шаблон или импортируй пакет.",content); return
	var sc := UI.scroll(content)
	var templates: Array[Dictionary] = []
	var template_names: Array = []
	for item in Library.list_parent_templates(state):
		if not item.has("adventure"): continue
		templates.append(item)
		var locked := _revision_locked(item)
		template_names.append("%s · %s v%d · %s" % [item.get("story_title",item.get("title", "История")),item.quest_id,int(item.revision),"новая копия" if locked else "черновик"])
	if not templates.is_empty():
		var saved_box := UI.card(sc)
		UI.label("Сохранённые истории и шаблоны", saved_box, 20, UI.BRASS)
		var template_picker := UI.option(saved_box,template_names)
		template_picker.name = "AdventureTemplatePicker"
		UI.button("Открыть выбранную историю",saved_box,func(): _request_quest(_editable_copy(templates[template_picker.selected])))
	var main := UI.card(sc)
	UI.label("История и результат",main,23,UI.BRASS)
	fields["quest_id"] = _field(main,"ID новой миссии",str(quest.get("quest_id", "")))
	fields["story_title"] = _field(main,"Название для игрока",str(quest.get("story_title",quest.get("title", ""))))
	fields["summary"] = UI.text_input(main,"Короткий замысел",str(quest.get("summary", "")),80)
	fields["entry_anchor_id"] = _field(main,"Предмет входа",str(quest.get("entry_anchor_id", "station_journal")))
	fields["revision"] = _field(main,"Ревизия",str(quest.get("revision",1)))
	UI.label("Опубликованную ревизию нельзя переписать. Для изменений выбери следующий свободный номер.",main,0,UI.MUTED)
	var stages: Array = UI.stages(quest)
	var path := UI.card(sc)
	var budget := 0
	for stage in stages:
		budget += int(stage.get("budget_share",0))
		UI.label("%s ← %s" % [str(stage.get("title", "")),", ".join(PackedStringArray(stage.get("prerequisite_stage_ids", []))) if not stage.get("prerequisite_stage_ids", []).is_empty() else "начало"],path)
	UI.label("Этапов: %d · сумма долей: %d XP" % [stages.size(),budget],path,14,UI.TEAL)
	if not stages.is_empty():
		stage_index = clampi(stage_index,0,stages.size()-1)
		var names: Array = []
		for stage in stages: names.append(str(stage.get("title", "Этап")))
		var picker := UI.option(path,names,stage_index)
		picker.item_selected.connect(func(i): if _capture(): stage_index = i; selected_interaction_index = 0; _build())
		_edit_stage(sc,stages[stage_index])
	var stage_buttons := UI.row(sc)
	UI.button("Добавить этап",stage_buttons,func():
		if not _capture(): return
		var n: int = UI.stages(quest).size()+1
		var sid := "family_step_%d" % n
		while quest.adventure.stages.any(func(item): return str(item.get("stage_id", "")) == sid) or quest.adventure.interactions.has(sid + "_interaction"):
			n += 1
			sid = "family_step_%d" % n
		var iid := sid + "_interaction"
		var recipes: Array = quest.adventure.get("work_recipes", {}).keys()
		quest.adventure.stages.append({"stage_id":sid,"title":"Новый шаг","summary":"","criteria":["Сохранена личная заметка"],"prerequisite_stage_ids":[],"completion_policy":"self_attest","budget_share":0,"grant_ids":[],"atlas_unlock_ids":[],"work_recipe_id":str(recipes[0]) if not recipes.is_empty() else "silhouette_sheet","interaction_ids":[iid],"next_hint":"Работа останется в архиве"})
		quest.adventure.interactions[iid] = {"interaction_id":iid,"type":"real_world_step","title":"Мой результат","prompt":"Что получилось?","hints":["Посмотри на свой результат","Выбери одну деталь","Можно записать одно предложение вместе"],"config":{"criteria":["Есть личная заметка"],"fields":[{"id":"note","label":"Моя заметка","required":true}],"materials":[]}}
		stage_index = quest.adventure.stages.size()-1
		_build())
	if stages.size() > 1:
		var move_up := UI.button("Этап выше ↑",stage_buttons,func():
			if not _capture(): return
			var previous: Dictionary = quest.adventure.stages[stage_index-1]
			quest.adventure.stages[stage_index-1] = quest.adventure.stages[stage_index]
			quest.adventure.stages[stage_index] = previous
			stage_index -= 1
			_build())
		move_up.disabled = stage_index == 0
		var move_down := UI.button("Этап ниже ↓",stage_buttons,func():
			if not _capture(): return
			var following: Dictionary = quest.adventure.stages[stage_index+1]
			quest.adventure.stages[stage_index+1] = quest.adventure.stages[stage_index]
			quest.adventure.stages[stage_index] = following
			stage_index += 1
			_build())
		move_down.disabled = stage_index == stages.size()-1
		UI.button("Удалить выбранный этап",stage_buttons,func():
			if not _capture(): return
			quest.adventure.stages.remove_at(stage_index)
			stage_index = maxi(0,stage_index-1)
			_build())
	var actions := UI.row(content)
	for action in [["Сохранить черновик","save_adventure_draft"],["Проверить","validate_adventure"],["Просмотреть путь","preview_adventure"],["Опубликовать","publish_adventure"]]:
		var operation: String = action[1]
		UI.button(action[0],actions,func():
			if _capture():
				pending_operation = operation
				command_requested.emit(operation,{"quest":quest.duplicate(true)}),operation == "publish_adventure")
	UI.focus_later(s.close,self)

func _revision_locked(value: Dictionary) -> bool:
	var key := "%s@%d" % [value.get("quest_id", ""),int(value.get("revision", 1))]
	return state.get("phase_b", {}).get("published_versions", {}).has(key) or not Library.get_builtin_template(str(value.get("quest_id", "")),int(value.get("revision",1))).is_empty()

func _new_revision(value: Dictionary, increment: bool = true) -> Dictionary:
	var copy := value.duplicate(true)
	var revision := int(copy.get("revision",1)) + (1 if increment else 0)
	revision = maxi(revision, Library.next_free_revision(state,str(copy.get("quest_id", ""))))
	if str(copy.get("quest_id", "")) == str(quest.get("quest_id", "")):
		revision = maxi(revision, int(quest.get("revision", 0)) + 1)
	copy.revision = revision
	copy.content_status = "DRAFT"
	return copy

func _editable_copy(value: Dictionary) -> Dictionary:
	return _new_revision(value) if _revision_locked(value) else value.duplicate(true)

func _request_quest(target: Dictionary) -> void:
	if not _capture(): return
	if str(target.get("quest_id", "")) == str(quest.get("quest_id", "")) and int(target.get("revision", 0)) == int(quest.get("revision", 0)):
		return
	if JSON.stringify(quest) == initial_quest_text:
		_load_quest(target)
		return
	pending_quest = target.duplicate(true)
	pending_operation = "save_adventure_draft"
	command_requested.emit("save_adventure_draft",{"quest":quest.duplicate(true)})

func _load_quest(value: Dictionary) -> void:
	quest = value.duplicate(true)
	initial_quest_text = JSON.stringify(quest)
	stage_index = 0
	selected_interaction_index = 0
	close_after_save = false
	show_import = false
	_build()

func _field(parent: Node, label: String, value: String) -> LineEdit:
	UI.label(label,parent,14,UI.MUTED)
	return UI.input(parent,label,value)

func _edit_stage(parent: Node, stage: Dictionary) -> void:
	var box := UI.card(parent)
	UI.label("Этап %d" % (stage_index+1),box,23,UI.BRASS)
	for pair in [["stage_id","ID этапа"],["title","Название"],["summary","Завязка"],["next_hint","Ближайшее последствие"],["work_recipe_id","Рецепт работы"],["budget_share","Доля XP"]]:
		stage_fields[pair[0]] = _field(box,pair[1],str(stage.get(pair[0], "")))
	for pair in [["criteria","Критерии — по одному на строку"],["prerequisite_stage_ids","Зависимости — ID по одному на строку"],["grant_ids","Разрешённые эффекты — ID по одному на строку"],["atlas_unlock_ids","Открытия карты — ID по одному на строку"]]:
		UI.label(pair[1],box,14,UI.MUTED)
		stage_fields[pair[0]] = UI.text_input(box,pair[1],"\n".join(PackedStringArray(stage.get(pair[0], []))),70)
	policy = UI.option(box,["Проверяется игровой попыткой", "Личная отметка", "Совместный просмотр"],maxi(0,POLICIES.find(str(stage.get("completion_policy", "automatic")))))
	UI.label("Разрешённые эффекты: " + ", ".join(PackedStringArray(Content.GRANT_IDS)),box,14,UI.MUTED)
	var ids: Array = stage.get("interaction_ids", [])
	if ids.is_empty(): return
	selected_interaction_index = clampi(selected_interaction_index,0,ids.size()-1)
	var interaction_names: Array = []
	for id in ids:
		var entry: Dictionary = quest.get("adventure", {}).get("interactions", {}).get(str(id), {})
		interaction_names.append(str(entry.get("title",id)))
	var interaction_picker := UI.option(box,interaction_names,selected_interaction_index)
	interaction_picker.item_selected.connect(func(i): if _capture(): selected_interaction_index = i; _build())
	var inter: Dictionary = quest.get("adventure", {}).get("interactions", {}).get(str(ids[selected_interaction_index]), {})
	UI.label("Основное взаимодействие",box,20,UI.BRASS)
	interaction_type = UI.option(box,TYPES,maxi(0,TYPES.find(str(inter.get("type", "real_world_step")))))
	title = _field(box,"Ситуация / инструкция",str(inter.get("prompt", "")))
	hints = UI.text_input(box,"Три подсказки — по одной на строку","\n".join(PackedStringArray(inter.get("hints", []))),100)
	UI.label("Данные взаимодействия (JSON): карточки, варианты, диалоги или поля",box,14,UI.MUTED)
	config_text = UI.text_input(box,"Объект config",JSON.stringify(inter.get("config", {}),"  "),240)
	UI.label("Все взаимодействия этапа — ID по одному на строку",box,14,UI.MUTED)
	stage_fields["interaction_ids"] = UI.text_input(box,"ID взаимодействий","\n".join(PackedStringArray(ids)),70)

func _lines(value: String) -> Array:
	var result: Array = []
	for line in value.split("\n"):
		if not line.strip_edges().is_empty(): result.append(line.strip_edges())
	return result

func _capture() -> bool:
	if quest.is_empty() or fields.is_empty(): return true
	var parsed: Variant = {}
	if is_instance_valid(config_text):
		parsed = JSON.parse_string(config_text.text)
		if not parsed is Dictionary:
			show_result({"ok":false,"message":"Данные взаимодействия должны быть корректным JSON-объектом. Черновик остался в форме."})
			return false
	for key in fields:
		quest[key] = int(fields[key].text) if key == "revision" else fields[key].text
	quest["title"] = str(quest.get("story_title",quest.get("title", "")))
	var stages: Array = UI.stages(quest)
	if stage_index < stages.size() and not stage_fields.is_empty():
		var stage: Dictionary = stages[stage_index]
		var old_ids: Array = stage.get("interaction_ids", []).duplicate()
		for key in stage_fields:
			if key in ["criteria","prerequisite_stage_ids","grant_ids","atlas_unlock_ids","interaction_ids"]: stage[key] = _lines(stage_fields[key].text)
			elif key == "budget_share": stage[key] = int(stage_fields[key].text)
			else: stage[key] = stage_fields[key].text
		stage["completion_policy"] = POLICIES[policy.selected]
		if not old_ids.is_empty() and is_instance_valid(config_text):
			var id := str(old_ids[clampi(selected_interaction_index,0,old_ids.size()-1)])
			var inter: Dictionary = quest.adventure.interactions.get(id, {})
			inter["type"] = TYPES[interaction_type.selected]
			inter["prompt"] = title.text
			inter["hints"] = _lines(hints.text)
			inter["config"] = parsed
			quest.adventure.interactions[id] = inter
	return true
