extends SceneTree

## Visual acceptance runner for Phase C.
## Run only from an isolated project copy because it resets user://.

const SaveServiceScript = preload("res://scripts/services/save_service.gd")
const ContentRepositoryScript = preload("res://scripts/services/content_repository.gd")
const ContentLibraryServiceScript = preload("res://scripts/services/content_library_service.gd")
const QuestServiceScript = preload("res://scripts/services/quest_service.gd")
const AppRootScene = preload("res://scenes/app/app_root.tscn")

var app: Node
var frame_counter := 0
var phase_c_quest: Dictionary = {}

func _init() -> void:
	SaveServiceScript.reset_save()
	app = AppRootScene.instantiate()
	root.add_child(app)
	process_frame.connect(_on_process_frame)

func _prepare_phase_c_state() -> void:
	phase_c_quest = ContentRepositoryScript.get_template("ES01")
	QuestServiceScript.approve_and_publish(app.game_state, phase_c_quest)

	var family := phase_c_quest.duplicate(true)
	family["quest_id"] = "FAM01"
	family["title"] = "Семейная карточка: вывеска для мастерской"
	family["summary"] = "Придумать семейную вывеску, сделать эскиз и коротко объяснить выбранные символы."
	family["provenance"] = {"origin": "parent_editor"}
	ContentLibraryServiceScript.save_draft(app.game_state, family)

func _first_tab_container() -> TabContainer:
	if app.modal_container.get_child_count() == 0:
		return null
	var modal: Node = app.modal_container.get_child(0)
	var tabs: Array[Node] = modal.find_children("*", "TabContainer", true, false)
	if tabs.is_empty():
		return null
	return tabs[0] as TabContainer

func _capture(path: String) -> void:
	if app.toast_panel != null:
		app.toast_panel.visible = false
	if not app.take_screenshot(path):
		push_error("Could not save " + path)

func _on_process_frame() -> void:
	frame_counter += 1

	if frame_counter == 18:
		_prepare_phase_c_state()
		app.open_world_explorer()
	elif frame_counter == 36:
		_capture("screenshots/11_phase_c_world_explorer.png")
		app.open_parent_console()
	elif frame_counter == 48:
		var tabs := _first_tab_container()
		if tabs != null:
			tabs.current_tab = 2
	elif frame_counter == 64:
		_capture("screenshots/12_phase_c_parent_editor.png")
		app.open_parent_console()
	elif frame_counter == 76:
		var tabs := _first_tab_container()
		if tabs != null:
			tabs.current_tab = 0
	elif frame_counter == 92:
		_capture("screenshots/13_phase_c_publication_catalog.png")
		app.open_quest_detail(phase_c_quest, {})
	elif frame_counter == 112:
		_capture("screenshots/14_phase_c_published_quest.png")
		print("Phase C visual capture complete")
		quit(0)
