extends CanvasLayer

## Exists only in a launcher-created disposable project and user directory.
const Save = preload("res://scripts/services/save_service.gd")
const Content = preload("res://scripts/services/adventure_content.gd")
const Quests = preload("res://scripts/services/quest_service.gd")
var menu: AcceptDialog
var confirm: ConfirmationDialog
var selected_mode := "prologue"

static func enabled() -> bool:
	return bool(ProjectSettings.get_setting("sur/developer_session", false))

static func isolated() -> bool:
	var expected := str(ProjectSettings.get_setting("sur/isolated_user_dir", ""))
	if expected.is_empty() or OS.get_user_data_dir().simplify_path() != expected.simplify_path():
		return false
	if not FileAccess.file_exists("user://.sur-temporary-session.json"):
		return false
	var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://.sur-temporary-session.json"))
	return marker is Dictionary and marker.get("kind") == "sur_temporary_session" and str(marker.get("user_dir", "")).simplify_path() == expected.simplify_path() and str(marker.get("project", "")).simplify_path() == ProjectSettings.globalize_path("res://").trim_suffix("/").simplify_path()

static func initial_state(mode: String) -> Dictionary:
	var state := Save.get_default_state()
	state.settings.muted = DisplayServer.get_name() == "headless"
	state.station_name = "Тестовая станция"
	if mode == "adventures":
		state.station_name = "Тест трёх историй"
		state.puzzle_solved = true
		state.puzzle_state = [0, 0, 0]
		state.radio_powered = true
		state.s00_progress = {"sign_named": true, "prop_arranged": true, "puzzle_solved": true, "station_awakened": true}
		for quest in Content.quests():
			Quests.approve_and_publish(state, quest)
	return state

static func prepare() -> bool:
	if not enabled():
		return true
	if not isolated():
		push_error("SUR: developer mode requires the isolated desktop launcher; startup stopped before loading any profile.")
		return false
	if not FileAccess.file_exists(Save.SAVE_PATH):
		return Save.save_game(initial_state(str(ProjectSettings.get_setting("sur/developer_start", "prologue"))))
	return true

func _ready() -> void:
	layer = 100
	DisplayServer.window_set_title("SUR · РАЗРАБОТЧИК · временный прогресс")
	var banner := Button.new()
	banner.name = "DeveloperSessionBanner"
	banner.text = "ТЕСТ · прогресс до закрытия · меню F9"
	banner.add_theme_font_size_override("font_size", 12)
	banner.add_theme_color_override("font_color", Color("ffc56e"))
	banner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	banner.position = Vector2(18, -88)
	banner.pressed.connect(_show_menu)
	add_child(banner)
	menu = AcceptDialog.new()
	menu.title = "Сессия разработчика"
	menu.min_size = Vector2i(530, 250)
	menu.get_ok_button().text = "Продолжить тест"
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	menu.add_child(body)
	var explanation := Label.new()
	explanation.text = "Все изменения живут только в этом запуске.\nСохранение Майи не загружается и не меняется.\nЗакрой игру — следующий запуск начнётся с нуля."
	body.add_child(explanation)
	for entry in [["prologue", "Начать заново с первой сценки"], ["adventures", "Начать заново с трёх миссий"]]:
		var mode: String = entry[0]
		var button := Button.new()
		button.text = entry[1]
		button.pressed.connect(func():
			selected_mode = mode
			confirm.popup_centered())
		body.add_child(button)
	add_child(menu)
	confirm = ConfirmationDialog.new()
	confirm.title = "Перезапустить этот тест?"
	confirm.dialog_text = "Текущий временный прогресс будет сброшен.\nСохранение Майи останется без изменений."
	confirm.get_ok_button().text = "Начать тест заново"
	confirm.get_cancel_button().text = "Отмена"
	confirm.confirmed.connect(_restart)
	add_child(confirm)
	call_deferred("_show_menu")

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_show_menu()
		get_viewport().set_input_as_handled()

func _show_menu() -> void:
	menu.popup_centered()

func _restart() -> void:
	if not isolated():
		return
	# Existing async file jobs must finish/cancel before a new scene can own state.
	var controller: Node = get_parent().adventure_controller
	if controller.file_job != null:
		controller.file_job.cancel()
		menu.dialog_text = "Дождитесь отмены копирования, затем повторите перезапуск."
		return
	if Save.save_game(initial_state(selected_mode)):
		get_tree().reload_current_scene()
