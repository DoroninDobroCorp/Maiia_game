class_name FamilyAdventureTools
extends Control

const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Content = preload("res://scripts/services/adventure_content.gd")
signal closed
signal command_requested(operation: String, payload: Dictionary)
signal editor_requested
signal episode_requested(instance_id: String, stage_id: String)
signal quest_requested(quest_id: String)
signal legacy_console_requested

var state: Dictionary = {}
var feedback: Label
var content: VBoxContainer
var tab := 0
var registration_title: LineEdit
var registration_work: OptionButton
var registration_work_ids: Array[String] = [""]

func setup(value: Dictionary, _audio: Node = null) -> void:
	state = value.duplicate(true)
	_build()

func show_result(result: Dictionary) -> void:
	feedback.text = UI.result_text(result)
	feedback.visible = true

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()

func _build() -> void:
	var shell := UI.shell(self, state, "Делаем станцию вместе", "Содержание открывает взрослый. Результаты смотрим вместе — в удобном для семьи темпе.", func(): closed.emit())
	feedback = shell.feedback
	var row := UI.row(shell.content)
	for i in range(4):
		var chosen := i
		UI.button(["Новая глава", "Посмотрим вместе", "Мастерская игры", "Копии и перенос"][i], row, func():
			tab = chosen
			_build(), tab == i)
	content = UI.scroll(shell.content)
	match tab:
		0: _chapter()
		1: _reviews()
		2: _learning()
		3: _backups()

func _chapter() -> void:
	var intro := UI.card(content)
	UI.label("Станция на связи", intro, 24, UI.BRASS)
	UI.label("Три независимые истории: радио, собственная игра и семейные наблюдения у воды. В каждой шесть сохраняемых этапов. Можно заранее открыть все три и проходить в любом порядке.", intro)
	var published: Dictionary = state.get("phase_b", {}).get("published_versions", {})
	for q in UI.context(state).get("chapter_templates", Content.quests()):
		var box := UI.card(content)
		UI.label(str(q.get("story_title", q.get("title", ""))), box, 21)
		UI.label(str(q.get("summary", "")), box)
		for stage in q.get("adventure", {}).get("stages", []):
			var mode := "вместе" if str(stage.get("completion_policy", "")) == "joint_review" else "самостоятельно"
			UI.label("• %s — %s" % [str(stage.get("title", "")), mode], box, 14, UI.MUTED)
		var key := "%s@%d" % [q.get("quest_id", ""), int(q.get("revision", 1))]
		UI.label("Эта версия уже открыта" if published.has(key) else "Готова к семейному просмотру", box, 14, UI.TEAL)
		var definition: Dictionary = q.duplicate(true)
		UI.button("Посмотреть содержание и критерии", box, func(): command_requested.emit("preview_adventure", {"quest": definition}))
	var actions := UI.row(content)
	UI.button("Открыть эти три приключения", actions, func(): command_requested.emit("publish_chapter", {}), true)
	UI.button("Создать своё приключение", actions, func(): editor_requested.emit())
	UI.label("Публикуется точная версия. Позднейшая правка создаёт новую; начатое прохождение сохраняет прежние правила.", content, 14, UI.MUTED)
	UI.button("Прежняя консоль и каталог заданий", content, func(): legacy_console_requested.emit())

func _reviews() -> void:
	var any := false
	for instance in state.get("phase_b", {}).get("quest_instances", {}).values():
		if str(instance.get("profile_id", "")) != "player_01":
			continue
		if not str(instance.get("superseded_by_instance_id", "")).is_empty():
			continue
		var iid := str(instance.get("instance_id", ""))
		var quest: Dictionary = instance.get("quest_snapshot", {})
		for stage in quest.get("adventure", {}).get("stages", []):
			var sid := str(stage.get("stage_id", ""))
			var progress := UI.stage_progress(state, iid, sid)
			if str(progress.get("status", "")) != "AWAITING_REVIEW":
				continue
			any = true
			var box := UI.card(content)
			UI.label(str(stage.get("title", "")), box, 22)
			UI.label(str(quest.get("story_title", quest.get("title", ""))), box, 15, UI.MUTED)
			UI.button("Посмотреть результат вместе", box, func(): episode_requested.emit(iid, sid), true)
	if not any:
		UI.label("Сейчас нет результатов, ожидающих совместного просмотра. Можно открыть новую историю или посмотреть уже собранную выставку.", content)

func _learning() -> void:
	var box := UI.card(content)
	UI.label("Собери свет для станции", box, 24, UI.BRASS)
	UI.label("Отдельная учебная игра Godot: движение, три огонька, победа и перезапуск. Подготовленная основа остаётся демонстрацией, пока Майя не внесёт свои решения. Рабочая копия создаётся отдельно от встроенных ресурсов SUR.", box)
	UI.button("Создать рабочую копию основы", box, func(): command_requested.emit("prepare_learning_project", {}), true)
	UI.button("Открыть инструкцию и рабочую папку", box, func(): command_requested.emit("open_learning_project", {}))
	var registration := UI.card(content)
	UI.label("Сохранить игру для автомата", registration, 23)
	UI.label("Взрослый выбирает проверенный проект Godot или готовое приложение. SUR сохраняет собственную копию и контрольную сумму. Обновлённую сборку регистрируем как новую версию.", registration)
	registration_title = UI.input(registration, "Название игры", "Моя игра для станции")
	registration_work_ids = [""]
	var work_names: Array = ["Новая работа"]
	for work in preload("res://scripts/services/collection_service.gd").list_works(state, "player_01", {"kind": "game"}):
		registration_work_ids.append(str(work.work_id))
		work_names.append("Новая версия: " + str(work.title))
	registration_work = UI.option(registration, work_names)
	UI.button("Выбрать project.godot", registration, func(): _choose_game(false))
	UI.button("Выбрать приложение macOS", registration, func(): _choose_game(true))
	UI.label("Сам запуск основы не подтверждает этап. Собственную правку и рабочий цикл игры смотрим вместе в её приключении.", registration, 14, UI.MUTED)
	for entry in UI.context(state).get("launch_entries", []):
		var card := UI.card(content)
		UI.label(str(entry.get("version_label", entry.get("title", "Сохранённая игра"))), card, 20)
		if bool(entry.get("demonstration_only", false)):
			UI.label("Учебная демонстрация. Собственный вклад ещё не подтверждён.", card, 14, UI.MUTED)
		var launch_id := str(entry.get("launch_entry_id", entry.get("entry_id", "")))
		UI.button("Проверить и запустить", card, func(): command_requested.emit("launch_work", {"launch_entry_id": launch_id}))

func _choose_game(application: bool) -> void:
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR if application else FileDialog.FILE_MODE_OPEN_FILE
	if not application:
		fd.filters = PackedStringArray(["project.godot ; Проект Godot"])
	fd.title = "Выберите проверенное приложение .app" if application else "Выберите собственный проект"
	add_child(fd)
	var selected := func(path: String):
		command_requested.emit("register_game", {"source_path": path, "title": registration_title.text, "work_id": registration_work_ids[registration_work.selected], "kind": "application" if application else "godot_project"})
		fd.queue_free()
	fd.file_selected.connect(selected)
	fd.dir_selected.connect(selected)
	fd.canceled.connect(func(): fd.queue_free())
	fd.popup_centered_ratio(0.8)

func _backups() -> void:
	var box := UI.card(content)
	UI.label("Полная семейная копия", box, 24, UI.BRASS)
	var total_bytes := 0
	var sizes: Array[Dictionary] = []
	for artifact in state.get("phase_b", {}).get("artifacts", {}).values():
		if bool(artifact.get("media_deleted", false)):
			continue
		var bytes := int(artifact.get("byte_size", 0))
		total_bytes += bytes
		sizes.append({"title": str(artifact.get("title", "Изображение")), "bytes": bytes})
	for entry in UI.context(state).get("launch_entries", []):
		var bytes := int(entry.get("bytes", 0))
		total_bytes += bytes
		sizes.append({"title": str(entry.get("version_label", "Игра")), "bytes": bytes})
	UI.label("Зарегистрированные материалы: %.1f МБ. Исходные архивы и рабочая папка войдут в полную копию отдельно." % (float(total_bytes) / 1048576.0), box, 15, UI.MUTED)
	sizes.sort_custom(func(a, b): return int(a.bytes) > int(b.bytes))
	for item in sizes.slice(0, 5):
		UI.label("%s · %.1f МБ" % [item.title, float(item.bytes) / 1048576.0], box, 14, UI.MUTED)
	UI.label("Сохранение, личные изображения и сохранённые проекты. Обычный экспорт списка достижений не содержит все эти файлы. Копию можно сохранить в выбранную папку.", box)
	UI.button("Создать полную копию", box, func():
		var fd := FileDialog.new()
		fd.access = FileDialog.ACCESS_FILESYSTEM
		fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		fd.title = "Папка для семейной копии"
		add_child(fd)
		fd.dir_selected.connect(func(path: String):
			command_requested.emit("backup_export", {"directory": path})
			fd.queue_free())
		fd.popup_centered_ratio(0.75), true)
	UI.button("Восстановить полную копию…", box, func():
		var fd := FileDialog.new()
		fd.access = FileDialog.ACCESS_FILESYSTEM
		fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		fd.title = "Папка копии с manifest.json"
		add_child(fd)
		fd.dir_selected.connect(func(path: String):
			command_requested.emit("backup_import", {"directory": path})
			fd.queue_free())
		fd.canceled.connect(func(): fd.queue_free())
		fd.popup_centered_ratio(0.75))
	if bool(state.get("read_only", false)):
		UI.label("Этот профиль создан более новой версией SUR и открыт только для чтения. Можно запустить совместимую версию или явно восстановить подходящую копию ниже.", box, 18, UI.BRASS)
	for entry in UI.context(state).get("recovery_snapshots", []):
		if not bool(entry.get("supported", false)):
			continue
		var snapshot_path := str(entry.get("path", ""))
		UI.button("Снимок %s · %s" % [entry.get("updated_at", ""), entry.get("schema_version", "")], box, func(): command_requested.emit("restore_local_snapshot", {"path": snapshot_path}))
	UI.label("Перенос в новую версию", content, 24, UI.BRASS)
	var any := false
	for instance in state.get("phase_b", {}).get("quest_instances", {}).values():
		if str(instance.get("profile_id", "")) != "player_01":
			continue
		var q: Dictionary = instance.get("quest_snapshot", {})
		if not str(instance.get("superseded_by_instance_id", "")).is_empty():
			continue
		var replacement: Dictionary = UI.context(state).get("migration_targets", {}).get(str(instance.get("quest_id", "")), {})
		if replacement.is_empty() or int(replacement.get("revision", 0)) <= int(instance.get("revision", 0)):
			continue
		any = true
		var row := UI.card(content)
		UI.label(str(q.get("title", "Прежнее задание")), row, 20)
		var iid := str(instance.get("instance_id", ""))
		if str(instance.get("status", "")) == "COMPLETED":
			UI.label("Уже полученный результат остаётся в архиве. Можно дополнить его собственной работой; повторного XP не будет.", row)
		else:
			UI.label("Прежняя версия продолжает работать. Можно посмотреть перенос в новую историю и явно выбрать, какие действия уже выполнены.", row)
			UI.button("Посмотреть перенос", row, func(): command_requested.emit("migration_preview", {"instance_id": iid}))
	if not any:
		UI.label("Начатых прежних версий этих трёх целей нет. Остальная история станции сохранена.", content, 0, UI.MUTED)
