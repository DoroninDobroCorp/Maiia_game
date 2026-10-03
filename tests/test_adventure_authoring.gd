extends SceneTree

## Authoring transitions through the real controller. Uses isolated save files.
const Save = preload("res://scripts/services/save_service.gd")
const Library = preload("res://scripts/services/content_library_service.gd")
const Content = preload("res://scripts/services/adventure_content.gd")
var app: Node
var controller: Node
var failures: Array[String] = []
var checks := 0

func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
	print("AUTHOR %d %s" % [checks,label])
func settle() -> void:
	await process_frame
	await process_frame
func click(label: String) -> bool:
	for button in controller.screen.find_children("*", "Button", true, false):
		if button.text == label:
			button.pressed.emit()
			return true
	return false
func select_template(key: String) -> bool:
	var picker := controller.screen.find_child("AdventureTemplatePicker",true,false) as OptionButton
	if picker == null: return false
	for i in range(picker.item_count):
		if picker.get_item_text(i).contains(key):
			picker.select(i)
			return click("Открыть выбранную историю")
	return false
func run() -> void:
	Save.use_test_storage("user://authoring_audit_%d_" % OS.get_process_id())
	Save.cleanup_test_storage()
	var state := Save.get_default_state()
	state.puzzle_solved = true
	state.s00_progress.station_awakened = true
	state.settings.muted = true
	Save.save_game(state)
	root.size = Vector2i(1280,720)
	app = load("res://scenes/app/app_root.tscn").instantiate()
	root.add_child(app)
	await settle()
	controller = app.adventure_controller
	controller.open_editor()
	await settle()
	controller.screen.fields.story_title.text = "Мой несохранённый замысел"
	var save_path := Save.SAVE_PATH
	Save.SAVE_PATH = "user://missing_authoring_audit_directory/save.json"
	controller.screen._save_close()
	check(app.modal_container.get_child_count() == 1, "failed close keeps editor")
	controller.screen._build()
	controller.screen._save_close()
	var discard_available := false
	for button in controller.screen.find_children("*", "Button", true, false):
		if button.text == "Выйти без сохранения…": discard_available = true
	check(discard_available, "discard option remains reachable after rebuilding a failed editor")
	Save.SAVE_PATH = save_path
	click("Проверить")
	check(app.modal_container.get_child_count() == 1, "validation after failed save must not close unsaved editor")
	check(Library.get_template(Save.load_game(),"AR02",1).is_empty(), "validation alone never persists draft")
	controller.open_editor()
	controller.screen.fields.story_title.text = "Личная история после просмотра"
	controller.screen._capture()
	controller.screen.stage_index = 1
	controller.screen._build()
	var before_preview := JSON.stringify(app.game_state)
	click("Просмотреть путь")
	check(controller.preview_active, "editor preview opened")
	controller._close_screen()
	check(controller.route == "editor" and controller.screen.fields.story_title.text == "Личная история после просмотра", "preview returns exact unsaved authored story")
	check(controller.screen.stage_index == 1, "preview returns selected editor stage")
	check(JSON.stringify(app.game_state) == before_preview, "preview neither saves draft nor awards player")
	controller.open_editor()
	click("Добавить этап")
	click("Добавить этап")
	controller.screen.stage_index = 3
	controller.screen._build()
	click("Удалить выбранный этап")
	click("Добавить этап")
	var ids: Dictionary = {}
	for stage in controller.screen.quest.adventure.stages: ids[str(stage.stage_id)] = true
	check(ids.size() == controller.screen.quest.adventure.stages.size(), "delete then add keeps stage IDs unique")
	controller.open_editor()
	controller.screen.fields.story_title.text = "Сохранённый семейный замысел"
	click("Сохранить черновик")
	check(str(Library.get_template(Save.load_game(),"AR02",1).get("story_title", "")) == "Сохранённый семейный замысел", "draft is stored through actual editor button")
	controller.open_family_tools()
	controller.open_editor()
	check(controller.screen.fields.story_title.text == "Сохранённый семейный замысел", "reopening editor loads saved family draft instead of bundled example")
	controller.screen.fields.story_title.text = "Сбережённая версия перед копией"
	click("Копия: три силуэта")
	check(str(Library.get_template(Save.load_game(),"AR02",1).get("story_title", "")) == "Сбережённая версия перед копией" and int(controller.screen.quest.revision) == 2, "template switch saves current draft and chooses a distinct revision")
	var imported := Content.example_package().duplicate(true)
	imported.package_id = "authoring-audit-pack"
	imported.quests[0].quest_id = "AUDIT04"
	imported.quests[0].story_title = "Импортированная семейная история"
	imported.quests[0].title = imported.quests[0].story_title
	click("Импорт JSON…")
	controller.screen.import_text.text = JSON.stringify(imported)
	click("Проверить и импортировать")
	check(not controller.screen.show_import and not Library.get_template(Save.load_game(),"AUDIT04",1).is_empty(), "import returns to editor and persists a draft")
	check(select_template("AUDIT04 v1"), "imported story can be selected without editing JSON or scene code")
	check(str(controller.screen.quest.quest_id) == "AUDIT04", "selected imported draft opens for editing")
	click("Опубликовать")
	check(app.game_state.phase_b.published_versions.has("AUDIT04@1"), "imported draft publishes through editor")
	check(select_template("AUDIT04 v1") and int(controller.screen.quest.revision) == 2, "published story opens as next free revision")
	controller.screen.fields.story_title.text = "Новая ревизия не меняет публикацию"
	click("Сохранить черновик")
	check(str(app.game_state.phase_b.published_versions["AUDIT04@1"].quest.story_title) == "Импортированная семейная история" and not Library.get_template(Save.load_game(),"AUDIT04",2).is_empty(), "revision editing preserves frozen published snapshot")
	controller.screen.fields.story_title.text = "Останется здесь при ошибке"
	Save.SAVE_PATH = "user://missing_authoring_audit_directory/save.json"
	select_template("FG01 v2")
	check(str(controller.screen.quest.quest_id) == "AUDIT04" and controller.screen.fields.story_title.text == "Останется здесь при ошибке", "failed save prevents template switch and keeps input")
	Save.SAVE_PATH = save_path
	select_template("FG01 v2")
	check(str(controller.screen.quest.quest_id) == "FG01" and int(controller.screen.quest.revision) == 3, "builtin story opens as editable new revision after successful retry")
	click("Добавить этап")
	var new_stage: Dictionary = controller.screen.quest.adventure.stages.back()
	check(controller.screen.quest.adventure.work_recipes.has(new_stage.work_recipe_id), "new stage uses a recipe from selected adventure")
	var later_revision := Content.get_quest("FG01").duplicate(true)
	later_revision.revision = 8
	controller._run_command("save_adventure_draft",{"quest":later_revision})
	controller.open_editor()
	check(select_template("FG01 v2") and int(controller.screen.quest.revision) == 9, "copying an older template advances beyond all saved revisions")
	controller.open_family_tools()
	controller._preview_quest(Content.get_quest("FG08"))
	controller._close_screen()
	check(controller.route == "family", "family content preview returns to family panel")
	app.queue_free()
	await settle()
	app = load("res://scenes/app/app_root.tscn").instantiate()
	root.add_child(app)
	await settle()
	controller = app.adventure_controller
	controller.open_editor()
	check(select_template("AUDIT04 v2") and controller.screen.fields.story_title.text == "Останется здесь при ошибке", "saved imported draft remains selectable after complete app reload")
	app.queue_free()
	await settle()
	Save.cleanup_test_storage()
	Save.restore_default_storage()
	print("ADVENTURE AUTHORING: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
