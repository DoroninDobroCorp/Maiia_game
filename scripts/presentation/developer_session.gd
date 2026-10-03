extends CanvasLayer

## Exists only in a launcher-created disposable project and user directory.
const Save = preload("res://scripts/services/save_service.gd")
const Content = preload("res://scripts/services/adventure_content.gd")
const Quests = preload("res://scripts/services/quest_service.gd")
const FAMILY_SNAPSHOT := "user://.developer-family-snapshot"
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
	if mode == "family":
		if not family_info().get("available", false):
			return {}
		var snapshot: Variant = JSON.parse_string(FileAccess.get_file_as_string(FAMILY_SNAPSHOT.path_join("savegame.json")))
		return snapshot.duplicate(true) if snapshot is Dictionary else {}
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

static func family_info() -> Dictionary:
	if not FileAccess.file_exists("user://.developer-family-info.json"):
		return {"available": false, "message": "Копия сохранения Майи недоступна в этом запуске."}
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://.developer-family-info.json"))
	return info if info is Dictionary else {"available": false}

static func _copy_tree(source: String, destination: String) -> bool:
	var directory := DirAccess.open(source)
	if directory == null or DirAccess.make_dir_recursive_absolute(destination) != OK:
		return false
	for name in directory.get_files():
		if directory.is_link(name) or DirAccess.copy_absolute(source.path_join(name), destination.path_join(name)) != OK:
			return false
	for name in directory.get_directories():
		if directory.is_link(name) or not _copy_tree(source.path_join(name), destination.path_join(name)):
			return false
	return true

static func _remove_tree(path: String) -> void:
	var parent := DirAccess.open(path.get_base_dir())
	if parent != null and parent.is_link(path.get_file()):
		parent.remove(path.get_file())
		return
	var directory := DirAccess.open(path)
	if directory == null: return
	for name in directory.get_files(): directory.remove(name)
	for name in directory.get_directories():
		if directory.is_link(name): directory.remove(name)
		else: _remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)

static func _restore_family_files() -> bool:
	# All sources/destinations are inside the verified temporary user directory.
	# Stage complete copies before replacing working data; no live family paths.
	for name in ["artifacts", "launch_registry"]:
		var target := "user://".path_join(name)
		var staging := target + ".developer-restore"
		_remove_tree(staging)
		var source := FAMILY_SNAPSHOT.path_join(name)
		if DirAccess.dir_exists_absolute(source) and not _copy_tree(source, staging):
			return false
	for name in ["artifacts", "launch_registry"]:
		var target := "user://".path_join(name)
		var staging := target + ".developer-restore"
		_remove_tree(target)
		if DirAccess.dir_exists_absolute(staging) and DirAccess.rename_absolute(staging, target) != OK:
			return false
	return true

static func _start_from(mode: String) -> bool:
	if not isolated(): return false
	var state := initial_state(mode)
	if state.is_empty(): return false
	if mode == "family" and not _restore_family_files(): return false
	return Save.save_game(state)

static func prepare() -> bool:
	if not enabled():
		return true
	if not isolated():
		push_error("SUR: developer mode requires the isolated desktop launcher; startup stopped before loading any profile.")
		return false
	if not FileAccess.file_exists(Save.SAVE_PATH):
		var mode := str(ProjectSettings.get_setting("sur/developer_start", "prologue"))
		if mode == "auto":
			mode = "family" if family_info().get("available", false) else "prologue"
		return _start_from(mode)
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
	menu.min_size = Vector2i(560, 310)
	menu.get_ok_button().text = "Продолжить тест"
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	menu.add_child(body)
	var explanation := Label.new()
	explanation.text = "Ты играешь во временной копии. Оригинал Майи не меняется.\nПосле закрытия тестовый прогресс удалится.\nНовый запуск возьмёт свежее сохранение Майи."
	body.add_child(explanation)
	var info := family_info()
	var description := Label.new()
	# Give wrapping a width before its first minimum-size calculation; otherwise
	# a zero-width label can permanently grow the dialog beyond the viewport.
	description.custom_minimum_size.x = 520
	description.size.x = 520
	description.text = "Снимок при запуске: «%s»" % str(info.get("station_name", "")) if info.get("available", false) else str(info.get("message", "Сохранение Майи недоступно."))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(description)
	for entry in [["family", "Начать с сохранения Майи"], ["prologue", "Начать заново с первой сценки"], ["adventures", "Начать заново с трёх миссий"]]:
		var mode: String = entry[0]
		var button := Button.new()
		button.text = entry[1]
		if mode == "family":
			button.name = "StartFromFamilySave"
			button.disabled = not bool(info.get("available", false))
		button.pressed.connect(func():
			selected_mode = mode
			confirm.popup_centered(Vector2i(500, 160)))
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
	menu.popup_centered(Vector2i(560, 370))

func _restart() -> void:
	if not isolated():
		return
	# Existing async file jobs must finish/cancel before a new scene can own state.
	var controller: Node = get_parent().adventure_controller
	if controller.file_job != null:
		controller.file_job.cancel()
		menu.dialog_text = "Дождитесь отмены копирования, затем повторите перезапуск."
		return
	# Stop games before restoring their copied working files/registry.
	for pid in controller.launched_processes:
		if OS.is_process_running(pid): OS.kill(pid)
	controller.launched_processes.clear()
	if _start_from(selected_mode):
		get_tree().reload_current_scene()
	else:
		menu.dialog_text = "Не удалось подготовить тест. Оригинальное сохранение Майи не менялось."
