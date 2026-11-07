class_name MissionFinale
extends Control

## The closing scene of a mission, of the 30-day challenge or of the whole chapter.
##
## A few short speeches by the heroes (one per page, text appears letter by letter,
## any key finishes it), then a last page that says what really changed on the
## station. Read-only projection: it changes nothing and never blocks anything.
## Context (via _adventure_ui): finale_key ("FG01" | "FG11" | "FG08" | "challenge" |
## "chapter"), instance_id and, for FG08, images {river, fall} with file paths.
## Wording lives in MissionGuide.FINALES.
const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Guide = preload("res://scripts/presentation/mission_guide.gd")
signal closed
signal collection_requested
signal hub_requested

const REVEAL_SECONDS := 1.6

var state: Dictionary = {}
var audio_service: Node
var finale_key := ""
var data: Dictionary = {}
var images: Dictionary = {}
## Extra lines for the last page (e.g. the dispatches of the school report).
var extra_lines: Array = []
var page := 0
var sparks: Control
var page_box: VBoxContainer
var dots_label: Label
var next_button: Button
var back_button: Button
var footer: HBoxContainer
var speech_label: Label
var reveal_tween: Tween
var last_voiced := ""
## Buttons that exist only on the last page.
var summary_buttons: Array[Control] = []

## Floating warm sparks behind the scene. Pure decoration, ignores the mouse.
class Sparks extends Control:
	var motes: Array[Dictionary] = []
	var elapsed := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in range(42):
			motes.append({"x": rng.randf(), "y": rng.randf(), "speed": rng.randf_range(0.015, 0.05),
				"size": rng.randf_range(1.5, 4.0), "phase": rng.randf() * TAU, "drift": rng.randf_range(-0.01, 0.01)})

	func _process(delta: float) -> void:
		elapsed += delta
		for mote in motes:
			mote.y = fmod(float(mote.y) - float(mote.speed) * delta + 1.0, 1.0)
			mote.x = fmod(float(mote.x) + float(mote.drift) * delta + 1.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		for mote in motes:
			var glow := 0.35 + 0.35 * sin(elapsed * 1.7 + float(mote.phase))
			var center := Vector2(float(mote.x) * size.x, float(mote.y) * size.y)
			draw_circle(center, float(mote.size) * 2.4, Color(1.0, 0.78, 0.38, glow * 0.12))
			draw_circle(center, float(mote.size), Color(1.0, 0.88, 0.55, glow))

func setup(game_state: Dictionary, audio_svc: Node = null) -> void:
	state = game_state.duplicate(true)
	audio_service = audio_svc
	var ctx := UI.context(state)
	finale_key = str(ctx.get("finale_key", ""))
	images = ctx.get("images", {})
	extra_lines = ctx.get("extra_lines", [])
	data = Guide.finale(finale_key)
	page = clampi(int(ctx.get("page", 0)), 0, _beats().size())
	_build()

## The speeches of the scene. In the chapter finale Bruno joins in if the 30-day
## challenge was won: he stands next to his board and speaks before Nora's last word.
func _beats() -> Array:
	var beats: Array = data.get("beats", []).duplicate()
	var extra: Dictionary = data.get("challenge_beat", {})
	if finale_key == "chapter" and not extra.is_empty() and beats.size() > 1:
		var ritual: Dictionary = state.get("phase_c", {}).get("rituals", {}).get("maya_30_streak", {})
		if bool(ritual.get("unlocked", false)):
			beats.insert(beats.size() - 1, extra)
	return beats

func _last_page() -> int:
	return _beats().size()

func show_result(_result: Dictionary) -> void:
	pass

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			closed.emit()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_RIGHT:
			get_viewport().set_input_as_handled()
			_next()
		KEY_LEFT:
			get_viewport().set_input_as_handled()
			_back()

func _build() -> void:
	var title := str(data.get("title", "Финал"))
	var s := UI.shell(self, state, title, "", func(): closed.emit(), true)
	sparks = Sparks.new()
	sparks.name = "FinaleSparks"
	add_child(sparks)
	move_child(sparks, 1)
	var content: VBoxContainer = s.content
	UI.label(str(data.get("kicker", "")), content, 13, UI.TEAL)
	page_box = UI.column(content)
	page_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dots_label = UI.label("", content, 14, UI.BRASS)
	dots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer = UI.row(content)
	back_button = UI.button("◂ Назад", footer, _back)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(space)
	next_button = UI.button("Дальше ▸", footer, _next, true)
	next_button.name = "FinaleNext"
	_show_page()

func _show_page() -> void:
	if reveal_tween != null:
		reveal_tween.kill()
		reveal_tween = null
	UI.clear(page_box)
	for extra in summary_buttons:
		if is_instance_valid(extra):
			footer.remove_child(extra)
			extra.queue_free()
	summary_buttons.clear()
	var beats := _beats()
	var on_summary := page >= beats.size()
	back_button.visible = page > 0
	next_button.visible = not on_summary
	var dots := ""
	for i in range(beats.size() + 1):
		dots += ("● " if i == page else "○ ")
	dots_label.text = dots.strip_edges()
	if on_summary:
		_build_summary()
	else:
		_build_beat(beats[page])
	UI.focus_later(next_button if not on_summary else _primary_summary_button(), self)

func _build_beat(beat: Dictionary) -> void:
	var who := str(beat.get("who", ""))
	var hero := Guide.character(who)
	page_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var card := UI.card(page_box, false, 24)
	var head := UI.row(card)
	head.add_theme_constant_override("separation", 28)
	var portrait_path := Guide.portrait_path(who, str(data.get("mood", "happy")))
	if not portrait_path.is_empty():
		UI.portrait(portrait_path, 280, head)
	var column := UI.column(head)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.label(str(hero.get("name", who)), column, 28, UI.BRASS)
	UI.label(str(hero.get("role", "")), column, 15, UI.TEAL)
	speech_label = UI.label(str(beat.get("text", "")), column, 23)
	speech_label.name = "FinaleSpeech"
	_reveal(speech_label)
	if who != last_voiced:
		last_voiced = who
		UI.voice(audio_service, who, "happy")

func _reveal(label: Label) -> void:
	label.visible_ratio = 0.0
	reveal_tween = create_tween()
	reveal_tween.tween_property(label, "visible_ratio", 1.0, REVEAL_SECONDS)

## True while the current speech is still being typed out.
func revealing() -> bool:
	return reveal_tween != null and reveal_tween.is_valid() and speech_label != null and speech_label.visible_ratio < 1.0

func finish_reveal() -> void:
	if reveal_tween != null:
		reveal_tween.kill()
		reveal_tween = null
	if speech_label != null:
		speech_label.visible_ratio = 1.0

func _next() -> void:
	if revealing():
		finish_reveal()
		return
	if page < _last_page():
		page += 1
		_show_page()

func _back() -> void:
	if page > 0:
		page -= 1
		_show_page()

func _build_summary() -> void:
	if audio_service != null and audio_service.has_method("play_sfx"):
		audio_service.play_sfx("chime_solve")
	page_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	var sc := UI.scroll(page_box)
	var photos := _photo_items()
	var layout := UI.row(sc)
	layout.add_theme_constant_override("separation", 18)
	var left := UI.column(layout)
	left.size_flags_stretch_ratio = 1.6 if not photos.is_empty() else 1.0
	var hero_id := _closing_hero()
	var card := UI.card(left)
	var head := UI.row(card)
	head.add_theme_constant_override("separation", 18)
	var portrait_path := Guide.portrait_path(hero_id, "happy")
	if not portrait_path.is_empty():
		UI.portrait(portrait_path, 120, head)
	var column := UI.column(head)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.label("✦  " + str(data.get("title", "")), column, 26, UI.BRASS)
	UI.label(str(data.get("summary_label", "ЧТО ИЗМЕНИЛОСЬ НА СТАНЦИИ")), column, 12, UI.TEAL)
	var list := UI.column(card)
	list.name = "FinaleChanges"
	for line in data.get("changes", []):
		UI.label("✦  " + str(line), list, 17)
	if not extra_lines.is_empty():
		var extra := UI.card(left)
		extra.name = "FinaleExtra"
		for line in extra_lines:
			UI.label(str(line), extra, 15, UI.PAPER)
	var last := str(data.get("last", ""))
	if not last.is_empty():
		var quote := UI.card(left, true)
		var text := UI.label("«" + last + "»", quote, 16, UI.INK)
		text.name = "FinaleLast"
	if not photos.is_empty():
		var right := UI.column(layout)
		_build_photos(right, photos)
	# Footer: where to go next. "На станцию" is the primary, closing action.
	var collection := UI.button("Мои работы", footer, func(): collection_requested.emit())
	collection.name = "FinaleCollection"
	footer.move_child(collection, 1)
	var hub := UI.button("Все миссии", footer, func(): hub_requested.emit())
	hub.name = "FinaleHub"
	footer.move_child(hub, 2)
	var done := UI.button("Готово ✦", footer, func(): closed.emit(), true)
	done.name = "FinaleDone"
	summary_buttons.append_array([collection, hub, done])

func _primary_summary_button() -> Control:
	var done := footer.find_child("FinaleDone", true, false)
	return done if done != null else next_button

## Who closes the scene: the last speaker of the speeches.
func _closing_hero() -> String:
	var beats := _beats()
	return str(beats.back().get("who", "")) if not beats.is_empty() else ""

## The real photos of the river and the waterfall (FG08 only); empty when there are none.
func _photo_items() -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	for pair in [["river", "Río Azul · река"], ["fall", "Nahuel Pan · водопад"]]:
		var path := str(images.get(pair[0], ""))
		var tex := UI.texture(path, 640) if not path.is_empty() else null
		if tex != null:
			shown.append({"tex": tex, "caption": pair[1]})
	return shown

func _build_photos(parent: Node, shown: Array[Dictionary]) -> void:
	var card := UI.card(parent)
	UI.label("ДИПТИХ «ДВА ГОЛОСА ВОДЫ» · ФОТО: МАЙЯ", card, 12, UI.TEAL)
	var column := UI.column(card)
	column.name = "FinalePhotos"
	column.add_theme_constant_override("separation", 10)
	for item in shown:
		var cell := UI.column(column)
		var frame := TextureRect.new()
		frame.texture = item.tex
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.custom_minimum_size = Vector2(0, 150)
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(frame)
		var caption := UI.label(str(item.caption), cell, 13, UI.MUTED)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
