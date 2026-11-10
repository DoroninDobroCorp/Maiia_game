class_name StepMission
extends Control

## Экран миссии главы 2 (Тео, Бруно, Нора): герой, весь путь и текущий шаг.
## Шаг может требовать фото (окно как в миссии воды), числа, имена, текст, ответы на задания Норы
## и отметку «взрослый был рядом». Экран только показывает снимок состояния; проверку делает
## Chapter2Service, команды идут контроллеру. Context (через _adventure_ui): mid.
const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Guide = preload("res://scripts/presentation/mission_guide.gd")
const C2G = preload("res://scripts/presentation/chapter2_guide.gd")
const C2 = preload("res://scripts/services/chapter2_service.gd")
signal closed
signal command_requested(operation: String, payload: Dictionary)
signal hub_requested
signal collection_requested
signal finale_requested(key: String)

var state: Dictionary = {}
var audio_service: Node
var mid := ""
var def: Dictionary = {}
var feedback: Label
var voiced := false
## Что Майя уже ввела; живёт между перерисовками экрана.
var inputs: Dictionary = {}
var story_choices: Dictionary = {}
var adult_checked: Dictionary = {}
var reaction := ""

func setup(game_state: Dictionary, audio_svc: Node = null) -> void:
	state = game_state.duplicate(true)
	audio_service = audio_svc
	if mid.is_empty():
		mid = str(UI.context(state).get("mid", ""))
	def = C2G.mission(mid)
	_build()

func show_result(result: Dictionary) -> void:
	if bool(result.get("applied", false)) and not str(result.get("reaction", "")).is_empty():
		reaction = str(result.reaction)
		UI.voice(audio_service, str(def.get("hero", "")), "happy")
	if feedback == null:
		return
	_build()
	if feedback != null and not bool(result.get("applied", false)):
		feedback.text = UI.result_text(result)
		feedback.visible = true

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()

func _build() -> void:
	if def.is_empty():
		return
	var info := C2.mission_state(state, mid)
	var hero_id := str(def.hero)
	var s := UI.shell(self, state, str(def.title), str(def.label), func(): closed.emit(), true)
	feedback = s.feedback
	var content: VBoxContainer = s.content
	var sc := UI.scroll(content)
	var columns := UI.row(sc)
	columns.add_theme_constant_override("separation", 18)
	var left := UI.column(columns)
	left.size_flags_stretch_ratio = 1.25
	var right := UI.column(columns)
	# What to do now comes first; the story of the mission sits below it.
	if bool(info.completed):
		_build_done_card(left)
	else:
		if not reaction.is_empty():
			var card := UI.card(left)
			card.name = "StepReaction"
			UI.label("«" + reaction + "»", card, 16, UI.TEAL)
		if bool(info.awaiting_adult):
			var wait_card := UI.card(left)
			wait_card.name = "StepAwaitingAdult"
			UI.label("Все перехваты услышаны. Осталось отметить темы вместе со взрослым в «Вместе · P», и миссия выполнена.", wait_card, 15, UI.BRASS)
		_build_current(left, info)
	_build_hero(left, hero_id, info)
	_build_path(right, info)
	var footer := UI.row(content)
	UI.button("Все миссии", footer, func(): hub_requested.emit())
	if not voiced:
		voiced = true
		UI.voice(audio_service, hero_id, "greet")

func _build_hero(parent: Node, hero_id: String, info: Dictionary) -> void:
	var card := UI.card(parent)
	var head := UI.row(card)
	head.add_theme_constant_override("separation", 14)
	var portrait := Guide.portrait_path(hero_id, "happy" if bool(info.completed) else "neutral")
	if not portrait.is_empty():
		UI.portrait(portrait, 130, head)
	var who := UI.column(head)
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	var hero := Guide.character(hero_id)
	UI.label(str(hero.get("name", "")), who, 22, UI.BRASS)
	UI.label(str(hero.get("role", "")), who, 14, UI.TEAL)
	UI.label("«" + str(hero.get("tagline", "")) + "»", who, 14, UI.MUTED)
	UI.label("ЦЕЛЬ", card, 12, UI.TEAL)
	UI.label(str(def.goal), card, 16)
	for pair in [["ЧТО ПОЯВИТСЯ НА СТАНЦИИ", "payoff"], ["СКОЛЬКО ВРЕМЕНИ", "rhythm"], ["ЧТО ПОНАДОБИТСЯ", "needs"]]:
		UI.label(str(pair[0]), card, 12, UI.TEAL)
		UI.label(str(def.get(pair[1], "")), card, 13, UI.MUTED)

func _build_done_card(parent: Node) -> void:
	var card := UI.card(parent)
	card.name = "StepDone"
	UI.label("✦ Миссия выполнена", card, 22, UI.BRASS)
	if not reaction.is_empty():
		UI.label("«" + reaction + "»", card, 15, UI.TEAL)
	var row := UI.row(card)
	var replay := UI.button("✦ Посмотреть финал", row, func(): finale_requested.emit(str(def.finale_key)), true)
	replay.name = "StepFinaleReplay"
	UI.button("Мои работы", row, func(): collection_requested.emit())

func _step_index(info: Dictionary, sid: String) -> int:
	for i in range(info.steps.size()):
		if str(info.steps[i].id) == sid:
			return i
	return 0

func _build_current(parent: Node, info: Dictionary) -> void:
	var sid := C2.current_step_id(state, mid)
	var step := C2G.step_def(mid, sid)
	if step.is_empty():
		return
	var card := UI.card(parent)
	card.name = "StepCurrent"
	var head := UI.row(card)
	head.add_theme_constant_override("separation", 12)
	var portrait := Guide.portrait_path(str(def.hero), "neutral")
	if not portrait.is_empty():
		UI.portrait(portrait, 84, head)
	var who := UI.column(head)
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.label("ШАГ %d ИЗ %d · %s" % [_step_index(info, sid) + 1, int(info.total), str(step.title).to_upper()], who, 12, UI.TEAL)
	UI.label("«" + str(step.say) + "»", who, 16, UI.PAPER)
	UI.label("ЧТО ДЕЛАТЬ", card, 12, UI.TEAL)
	UI.label(str(step.task), card, 15)
	if str(step.kind) == "story":
		_build_story_choice(card, sid, step)
	_build_fields(card, sid, step)
	if str(step.get("photo", "")) != "":
		_build_photo(card, sid, step)
	if bool(step.get("adult", false)):
		var check := CheckBox.new()
		check.name = "StepAdult"
		check.text = "Взрослый был рядом"
		check.button_pressed = bool(adult_checked.get(sid, false))
		check.toggled.connect(func(on: bool): adult_checked[sid] = on)
		card.add_child(check)
	var go := UI.button("Готово ✓ · отметить шаг", card, func(): _submit(sid, step), true)
	go.name = "StepSubmit"

func _build_fields(parent: Node, sid: String, step: Dictionary) -> void:
	for field in step.get("fields", []):
		var fid := str(field.id)
		var key := sid + ":" + fid
		var label := str(field.label)
		if bool(field.get("numeric", false)) and not str(field.get("unit", "")).is_empty():
			label += " (" + str(field.unit) + ")"
		UI.label(label + (" *" if bool(field.get("required", false)) else ""), parent, 13, UI.MUTED)
		if fid == "catch" and mid == "nora2":
			# The words from Maya's school dispatches are raw material for Nora's catches.
			var glossary: Array[Dictionary] = preload("res://scripts/services/ritual_service.gd").school_glossary(state)
			if not glossary.is_empty():
				var words: Array[String] = []
				for entry in glossary.slice(maxi(0, glossary.size() - 8)):
					words.append(str(entry.word))
				var hint := UI.label("Твои слова из школы: " + ", ".join(PackedStringArray(words)), parent, 13, UI.TEAL)
				hint.name = "SchoolWordsHint"
		if bool(field.get("multiline", false)):
			var area := UI.text_input(parent, "", str(inputs.get(key, "")), 80)
			area.name = "StepField_" + fid
			area.text_changed.connect(func(): inputs[key] = area.text)
		else:
			var line := UI.input(parent, "", str(inputs.get(key, "")))
			line.name = "StepField_" + fid
			line.text_changed.connect(func(value: String): inputs[key] = value)

## Выбор с последствием: реакция героя видна сразу, правильных ответов нет.
func _build_story_choice(parent: Node, sid: String, step: Dictionary) -> void:
	var choice: Dictionary = step.choice
	UI.label(str(choice.prompt).to_upper(), parent, 12, UI.TEAL)
	var picked := str(story_choices.get(sid, ""))
	var options := UI.column(parent)
	options.name = "StoryChoices"
	for option in choice.options:
		var option_id := str(option.id)
		var pick := UI.button(str(option.text), options, func():
			story_choices[sid] = option_id
			_build(), picked == option_id)
		pick.name = "StoryOption_" + option_id
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for option in choice.options:
		if str(option.id) == picked:
			var echo := UI.card(parent)
			echo.name = "StoryChoiceReaction"
			UI.label(str(Guide.character(str(def.hero)).get("name", "")) + ": «" + str(option.reaction) + "»", echo, 15, UI.TEAL)

## Окно фото, как в миссии воды: предпросмотр и кнопка выбора файла.
func _build_photo(parent: Node, sid: String, step: Dictionary) -> void:
	var required := str(step.photo) == "required"
	var box := UI.card(parent)
	box.name = "StepPhoto"
	UI.label("ФОТО " + ("(нужно приложить)" if required else "(по желанию)"), box, 12, UI.TEAL)
	var path := C2.photo_path(state, mid, sid)
	var texture := UI.texture(path, 512) if not path.is_empty() else null
	if texture != null:
		var preview := TextureRect.new()
		preview.name = "StepPhotoPreview"
		preview.texture = texture
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.custom_minimum_size = Vector2(0, 170)
		box.add_child(preview)
	else:
		UI.label("📷 Здесь появится снимок. Нажми кнопку ниже, чтобы выбрать файл.", box, 13, UI.MUTED)
	var pick := UI.button("Заменить фото 📷" if texture != null else "Выбрать фото 📷", box, func(): command_requested.emit("c2_attach_photo", {"mid": mid, "sid": sid}))
	pick.name = "StepPhotoPick"

func _submit(sid: String, step: Dictionary) -> void:
	var fields: Dictionary = {}
	for field in step.get("fields", []):
		fields[str(field.id)] = str(inputs.get(sid + ":" + str(field.id), ""))
	command_requested.emit("c2_step_done", {"mid": mid, "sid": sid, "adult": bool(adult_checked.get(sid, false)),
		"data": {"fields": fields, "choice": str(story_choices.get(sid, ""))}})

func _record_summary(step: Dictionary, record: Dictionary) -> String:
	var fields: Dictionary = record.get("fields", {})
	match str(step.kind):
		"names":
			var names: Array[String] = []
			for key in ["tool_1", "tool_2", "tool_3"]:
				if not str(fields.get(key, "")).is_empty():
					names.append(str(fields[key]))
			return "Имена: " + ", ".join(PackedStringArray(names))
		"number":
			var bits: Array[String] = []
			if not str(fields.get("minutes", "")).is_empty():
				bits.append("%s мин" % str(fields.minutes))
			if not str(fields.get("meters", "")).is_empty():
				bits.append("%s м" % str(fields.meters))
			return ", ".join(PackedStringArray(bits)) if not bits.is_empty() else "записано"
		"story":
			return "кусочек сообщения: " + str(step.reveal.es)
		"text":
			return "«" + str(fields.get("reply", "")).left(60) + "»"
	return "готово" + (" · с фото" if record.has("artifact_id") else "")

func _build_path(parent: Node, info: Dictionary) -> void:
	var header := UI.row(parent)
	UI.label("ПУТЬ · %d из %d" % [int(info.done), int(info.total)], header, 14, UI.BRASS)
	var bar := ProgressBar.new()
	bar.max_value = int(info.total)
	bar.value = int(info.done)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(120, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(bar)
	for i in range(info.steps.size()):
		var row_info: Dictionary = info.steps[i]
		var step := C2G.step_def(mid, str(row_info.id))
		var status := str(row_info.status)
		var panel := PanelContainer.new()
		panel.name = "PathRow_" + str(row_info.id)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var current := status == "CURRENT"
		panel.add_theme_stylebox_override("panel", UI.style(Color("233843") if current else UI.PANEL, UI.BRASS if current else Color("4b5457"), 12))
		parent.add_child(panel)
		var line := UI.row(panel)
		var badge := Label.new()
		badge.text = "✓" if status == "DONE" else str(i + 1)
		badge.custom_minimum_size = Vector2(30, 30)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 20)
		badge.add_theme_color_override("font_color", UI.TEAL if status == "DONE" else UI.BRASS if current else UI.MUTED)
		line.add_child(badge)
		var text := UI.column(line)
		UI.label(str(step.title), text, 16, UI.MUTED if status == "LOCKED" else UI.PAPER)
		if status == "DONE":
			UI.label(_record_summary(step, row_info.record), text, 12, UI.TEAL)
		if bool(step.get("confirm", false)):
			var agreed := bool(info.confirmed.get(str(row_info.id), false))
			UI.label("взрослый отметил ✓" if agreed else "тему отметит взрослый в «Вместе · P»", text, 12, UI.BRASS if agreed else UI.MUTED)
		if status != "DONE":
			var tags: Array[String] = []
			if bool(step.get("adult", false)):
				tags.append("со взрослым")
			if str(step.get("photo", "")) == "required":
				tags.append("нужно фото")
			elif str(step.get("photo", "")) == "optional":
				tags.append("фото по желанию")
			if not tags.is_empty():
				UI.label(" · ".join(PackedStringArray(tags)), text, 12, UI.MUTED)
