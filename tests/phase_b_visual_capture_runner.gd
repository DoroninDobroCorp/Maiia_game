extends SceneTree

## Автоматический visual-check новых экранов Phase B.
## Запускать на отдельной копии проекта: скрипт сбрасывает user:// текущего test-проекта.

const SaveServiceScript = preload("res://scripts/services/save_service.gd")
const ContentRepositoryScript = preload("res://scripts/services/content_repository.gd")
const QuestServiceScript = preload("res://scripts/services/quest_service.gd")
const AppRootScene = preload("res://scenes/app/app_root.tscn")

var app: Node
var frame_counter := 0
var s01_quest: Dictionary = {}
var s01_instance: Dictionary = {}

func _init() -> void:
	SaveServiceScript.reset_save()
	app = AppRootScene.instantiate()
	root.add_child(app)
	process_frame.connect(_on_process_frame)

func _prepare_phase_b_state() -> void:
	s01_quest = ContentRepositoryScript.get_template("S01")
	QuestServiceScript.approve_and_publish(app.game_state, s01_quest)
	var s01_created := QuestServiceScript.create_instance(app.game_state, "S01", int(s01_quest.get("revision", 1)))
	s01_instance = s01_created.get("instance", {})
	QuestServiceScript.submit_result(
		app.game_state,
		str(s01_instance.get("instance_id", "")),
		"visual:s01:submitted",
		"Короткая заметка для визуальной проверки состояния «на проверке»."
	)
	s01_instance = _instance(str(s01_instance.get("instance_id", "")))

	var s10 := ContentRepositoryScript.get_template("S10")
	QuestServiceScript.approve_and_publish(app.game_state, s10)
	var s10_created := QuestServiceScript.create_instance(app.game_state, "S10", int(s10.get("revision", 1)))
	var s10_instance: Dictionary = s10_created.get("instance", {})
	QuestServiceScript.submit_result(
		app.game_state,
		str(s10_instance.get("instance_id", "")),
		"visual:s10:final",
		"Финальная демонстрационная работа для визуальной проверки."
	)
	QuestServiceScript.confirm_result(app.game_state, "visual:s10:final")
	app._apply_state_to_world(false)

func _instance(instance_id: String) -> Dictionary:
	return app.game_state.get("phase_b", {}).get("quest_instances", {}).get(instance_id, {}).duplicate(true)

func _select_phase_b_journal_tab() -> void:
	if app.modal_container.get_child_count() == 0:
		return
	var modal: Node = app.modal_container.get_child(0)
	var tabs: Array[Node] = modal.find_children("*", "TabContainer", true, false)
	if not tabs.is_empty():
		(tabs[0] as TabContainer).current_tab = 1

func _capture(path: String) -> void:
	if not app.take_screenshot(path):
		push_error("Не удалось сохранить " + path)

func _on_process_frame() -> void:
	frame_counter += 1

	if frame_counter == 18:
		_prepare_phase_b_state()
		app.open_parent_console()
	elif frame_counter == 36:
		_capture("screenshots/06_phase_b_parent_console.png")
		app.open_journal()
	elif frame_counter == 50:
		_select_phase_b_journal_tab()
	elif frame_counter == 64:
		_capture("screenshots/07_phase_b_expeditions.png")
		app.open_quest_detail(s01_quest, s01_instance)
	elif frame_counter == 82:
		_capture("screenshots/08_phase_b_quest_submitted.png")
		app.open_author_dialogue_editor()
	elif frame_counter == 100:
		_capture("screenshots/09_phase_b_dialogue_editor.png")
		app._close_modals()
		app._apply_state_to_world(false)
	elif frame_counter == 110:
		# take_screenshot() показывает toast после сохранения предыдущего кадра.
		# Убираем его заранее, чтобы renderer успел отрисовать чистый world-state.
		if app.toast_panel != null:
			app.toast_panel.visible = false
	elif frame_counter == 118:
		_capture("screenshots/10_phase_b_world_effect.png")
		print("Phase B visual capture complete")
		quit(0)
