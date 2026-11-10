class_name StoryReader
extends Control

## Экран сюжетной серии (письма Южного Маяка): письмо героя, выбор с последствием и свободный ответ.
## Ничего не проверяется на «правильно». Показывает снимок состояния, команды идут контроллеру.
## Context (через _adventure_ui): series, view ("journal" — журнал эфира).
const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Guide = preload("res://scripts/presentation/mission_guide.gd")
const SG = preload("res://scripts/presentation/story_guide.gd")
const Story = preload("res://scripts/services/story_service.gd")
signal closed
signal command_requested(operation: String, payload: Dictionary)
signal mission_requested(quest_id: String)
signal collection_requested

const REVEAL_SECONDS := 1.3

var state: Dictionary = {}
var audio_service: Node
var series := ""
var feedback: Label
var scene: Dictionary = {}
var chosen := ""
var inputs: Dictionary = {}
var echo := ""
var show_journal := false
var text_label: Label
var reveal_tween: Tween
var voiced_scene := ""

func setup(game_state: Dictionary, audio_svc: Node = null) -> void:
	state = game_state.duplicate(true)
	audio_service = audio_svc
	var ctx := UI.context(state)
	if series.is_empty():
		series = str(ctx.get("series", ""))
		show_journal = str(ctx.get("view", "")) == "journal"
	scene = Story.next_scene(state, series)
	if not scene.is_empty() and chosen != "" and not _has_option(scene, chosen):
		chosen = ""
	_build()

func _has_option(item: Dictionary, option_id: String) -> bool:
	for option in item.get("choice", {}).get("options", []):
		if str(option.id) == option_id:
			return true
	return false

func show_result(result: Dictionary) -> void:
	if bool(result.get("applied", false)):
		chosen = ""
		show_journal = false
		scene = Story.next_scene(state, series)
		_build()
		return
	if feedback != null:
		feedback.text = UI.result_text(result)
		feedback.visible = true

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()

func _build() -> void:
	var meta: Dictionary = SG.series(series)
	if meta.is_empty():
		return
	var progress := Story.progress(state, series)
	var subtitle := "Прослушано писем: %d из %d" % [int(progress.done), int(progress.total)]
	var title := str(meta.title)
	if not scene.is_empty() and not show_journal:
		subtitle = "%s · письмо %d из %d" % [str(scene.chapter_title), int(progress.done) + 1, int(progress.total)]
	var s := UI.shell(self, state, title, subtitle, func(): closed.emit(), true)
	feedback = s.feedback
	var content: VBoxContainer = s.content
	if scene.is_empty() or show_journal:
		_build_journal(content, progress)
	else:
		_build_scene(content)

func _build_scene(content: VBoxContainer) -> void:
	var sc := UI.scroll(content)
	if not echo.is_empty():
		var echo_card := UI.card(sc)
		echo_card.name = "StoryEcho"
		UI.label(echo, echo_card, 15, UI.TEAL)
	var card := UI.card(sc, false, 22)
	card.name = "StoryLetter"
	var head := UI.row(card)
	head.add_theme_constant_override("separation", 24)
	var who := str(scene.who)
	var hero := Guide.character(who)
	var portrait := Guide.portrait_path(who, "neutral")
	if not portrait.is_empty():
		UI.portrait(portrait, 190, head)
	var column := UI.column(head)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.label(str(hero.get("name", who)) + " · " + str(hero.get("role", "")), column, 15, UI.BRASS)
	UI.label(str(scene.title), column, 22, UI.PAPER)
	text_label = UI.label(Story.text_for(state, series, str(scene.text)), column, 18)
	text_label.name = "StoryText"
	_reveal(text_label)
	if voiced_scene != str(scene.id):
		voiced_scene = str(scene.id)
		UI.voice(audio_service, who, "greet")
	var choice: Dictionary = scene.get("choice", {})
	if not choice.is_empty():
		UI.label(str(choice.prompt).to_upper(), sc, 12, UI.TEAL)
		var options := UI.column(sc)
		options.name = "StoryChoices"
		for option in choice.options:
			var option_id := str(option.id)
			var pick := UI.button(str(option.text), options, func():
				chosen = option_id
				_build(), chosen == option_id)
			pick.name = "StoryOption_" + option_id
			pick.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not chosen.is_empty():
			for option in choice.options:
				if str(option.id) == chosen:
					var reaction := UI.card(sc)
					reaction.name = "StoryReaction"
					UI.label(str(hero.get("name", "")) + ": " + Story.text_for(state, series, str(option.reaction)), reaction, 16, UI.TEAL)
	for reply in scene.get("replies", []):
		var key := str(scene.id) + ":" + str(reply.id)
		UI.label(str(reply.prompt) + (" *" if bool(reply.get("required", false)) else ""), sc, 14, UI.PAPER)
		var area := UI.text_input(sc, str(reply.get("hint", "")), str(inputs.get(key, "")), 70)
		area.name = "StoryReply_" + str(reply.id)
		area.text_changed.connect(func(): inputs[key] = area.text)
	var footer := UI.row(content)
	UI.button("Журнал эфира", footer, func():
		show_journal = true
		_build())
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(space)
	var heard := Story.progress(state, series)
	var last: bool = int(heard.done) + 1 >= int(heard.total)
	var next := UI.button("Выйти в эфир ▸" if last else "Дальше ▸", footer, _submit, true)
	next.name = "StoryNext"

func _reveal(label: Label) -> void:
	if reveal_tween != null:
		reveal_tween.kill()
	label.visible_ratio = 0.0
	reveal_tween = create_tween()
	reveal_tween.tween_property(label, "visible_ratio", 1.0, REVEAL_SECONDS)

func finish_reveal() -> void:
	if reveal_tween != null:
		reveal_tween.kill()
		reveal_tween = null
	if text_label != null:
		text_label.visible_ratio = 1.0

func _submit() -> void:
	var replies: Dictionary = {}
	for reply in scene.get("replies", []):
		replies[str(reply.id)] = str(inputs.get(str(scene.id) + ":" + str(reply.id), ""))
	# What the hero says about the answer stays at the top of the next letter.
	var after := str(scene.get("reply_reaction", ""))
	if not after.is_empty():
		echo = str(Guide.character(str(scene.who)).get("name", "")) + ": " + Story.text_for(state, series, after)
	else:
		echo = ""
	command_requested.emit("story_scene_done", {"series": series, "scene": str(scene.id), "choice": chosen, "replies": replies})

func _build_journal(content: VBoxContainer, progress: Dictionary) -> void:
	var sc := UI.scroll(content)
	var card := UI.card(sc)
	card.name = "StoryJournal"
	if bool(progress.finished):
		UI.label("✦ Все письма прослушаны", card, 22, UI.BRASS)
		UI.label("Нора сохранила всё, что ты выбрала и написала: это журнал вашего эфира.", card, 14, UI.MUTED)
	else:
		UI.label("Журнал эфира", card, 22, UI.BRASS)
		UI.label("Здесь собрано всё, что ты выбрала и написала. Следующее письмо ждёт тебя.", card, 14, UI.MUTED)
	var entries := Story.journal(state, series)
	if entries.is_empty():
		UI.label("Пока пусто: первое письмо ещё не отправлено.", card, 14, UI.MUTED)
	for entry in entries:
		var row := UI.card(sc)
		UI.label(str(entry.title), row, 16, UI.BRASS)
		if not str(entry.choice).is_empty():
			UI.label("Ты выбрала: " + str(entry.choice), row, 14)
		for text in entry.replies:
			UI.label("«" + str(text) + "»", row, 14, UI.TEAL)
	var footer := UI.row(content)
	UI.button("К миссии", footer, func(): mission_requested.emit(str(SG.series(series).get("quest", "FG01"))))
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(space)
	if not scene.is_empty():
		var back := UI.button("Продолжить эфир ▸", footer, func():
			show_journal = false
			_build(), true)
		back.name = "StoryContinue"
	else:
		UI.button("Мои работы", footer, func(): collection_requested.emit())
