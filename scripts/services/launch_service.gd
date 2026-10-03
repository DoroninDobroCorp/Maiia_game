class_name LaunchService
extends RefCounted

## Separate local registry, deliberately absent from content packages and saves.
## Registration is an explicit adult UI operation, not an authentication system.
## A successful OS launch is never evidence of gameplay or authorship.
const MAX_VERSION_BYTES := 200 * 1024 * 1024
const MAX_FILES := 4096
const MAX_DEPTH := 24
const STARTER_PROJECT_ID := "station_arcade_starter"
const STARTER_PROJECT := "res://learning_projects/station_light"
const STARTER_ARCHIVE_ROOT := "res://assets/learning_starter"
const STARTER_FILES: Array[String] = ["project.godot", "main.tscn", "main.gd", "game_state.gd", "lesson.json", "README.md", "AUTHORSHIP.json"]
const REGISTRY_SCHEMA := 1

var storage_root: String
var _children: Dictionary = {}

func _init(root_directory: String = "user://launch_registry") -> void:
	storage_root = ProjectSettings.globalize_path(root_directory).simplify_path().trim_suffix("/")

func working_project_path() -> String:
	return storage_root.path_join("working/station_light")

func prepare_starter_project(destination: String = "") -> Dictionary:
	var target := working_project_path() if destination.is_empty() else ProjectSettings.globalize_path(destination).simplify_path().trim_suffix("/")
	if DirAccess.dir_exists_absolute(target) or FileAccess.file_exists(target):
		if destination.is_empty() and FileAccess.file_exists(target.path_join("project.godot")) and FileAccess.file_exists(target.path_join(".sur_learning_workspace.json")):
			return {"ok": true, "project_dir": target, "reused": true, "message": "Открыта прежняя рабочая копия. Ваши изменения сохранены.", "builtin_demo": true}
		return _failure("destination_exists", "Эта папка уже существует. Выберите новую пустую папку; существующие файлы не заменены.")
	var bundled := _bundled_sources("1.0")
	if not bundled.ok:
		return bundled
	if DirAccess.make_dir_recursive_absolute(target) != OK:
		return _failure("working_copy_failed", "Не удалось создать рабочую папку учебного проекта.")
	for relative in bundled.files:
		var output := target.path_join(str(relative))
		var destination_file := FileAccess.open(output, FileAccess.WRITE)
		if destination_file == null:
			_remove_tree(target)
			return _failure("working_copy_failed", "Не удалось подготовить рабочую копию. Попробуйте другую папку.")
		destination_file.store_buffer(bundled.files[relative])
		destination_file.flush()
		var wrote := destination_file.get_error() == OK
		destination_file.close()
		if not wrote:
			_remove_tree(target)
			return _failure("working_copy_failed", "Не удалось сохранить исходники учебной основы.")
	var marker := FileAccess.open(target.path_join(".sur_learning_workspace.json"), FileAccess.WRITE)
	if marker == null:
		_remove_tree(target)
		return _failure("working_copy_failed", "Не удалось сохранить сведения об учебной основе.")
	marker.store_string(JSON.stringify({"starter_project_id": STARTER_PROJECT_ID, "prepared_foundation": "SUR", "completion_evidence": false}))
	marker.close()
	return {"ok": true, "project_dir": target, "reused": false, "builtin_demo": true, "message": "Готова отдельная рабочая копия основы. Вместе откройте её в Godot и внесите собственную правку; запуск основы не завершает миссию."}

func register_starter(version_label: String = "1.0", actor_id: String = "parent_local", profile_id: String = "player_01") -> Dictionary:
	if not ["0.1", "0.2", "0.3", "0.4", "1.0"].has(version_label):
		return _failure("unknown_starter_version", "Такой версии учебной основы нет.")
	return register_project(STARTER_PROJECT.path_join("versions").path_join(version_label), version_label, actor_id, profile_id)

func register_project(project_directory: String, version_label: String, actor_id: String = "parent_local", profile_id: String = "player_01") -> Dictionary:
	if not OS.has_feature("editor"):
		return _failure("godot_editor_required", "Для исходного проекта нужен установленный Godot. В сборке SUR зарегистрируйте экспортированное приложение.")
	var source := ProjectSettings.globalize_path(project_directory).simplify_path().trim_suffix("/")
	if not FileAccess.file_exists(source.path_join("project.godot")):
		return _failure("project_missing", "Папка проекта или project.godot отсутствует. Выберите сохранённую версию вместе со взрослым.")
	var config := ConfigFile.new()
	if config.load(source.path_join("project.godot")) != OK or str(config.get_value("application", "run/main_scene", "")).is_empty():
		return _failure("project_not_runnable", "У проекта нет начальной сцены. Сначала проверьте его запуск в Godot.")
	var result := _register(source, "godot_project", version_label, actor_id, profile_id)
	return result

func register_app(app_directory: String, version_label: String, actor_id: String = "parent_local", profile_id: String = "player_01") -> Dictionary:
	if OS.get_name() != "macOS":
		return _failure("unsupported_platform", "Эта версия запуска приложений рассчитана на macOS. Исходники и история остаются доступны.")
	var source := ProjectSettings.globalize_path(app_directory).simplify_path().trim_suffix("/")
	if not source.ends_with(".app") or not FileAccess.file_exists(source.path_join("Contents/Info.plist")) or not DirAccess.dir_exists_absolute(source.path_join("Contents/MacOS")):
		return _failure("app_missing", "Приложение .app отсутствует или неполно. Выберите рабочую сборку вместе со взрослым.")
	if _app_executable(source).is_empty():
		return _failure("app_executable_missing", "Нужна сборка Godot .app с XML Info.plist и доступным исполняемым файлом внутри Contents/MacOS.")
	return _register(source, "macos_app", version_label, actor_id, profile_id)

func list_entries(profile_id: String = "player_01") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var loaded := _load_registry()
	if not loaded.ok:
		return result
	for entry in loaded.registry.entries.values():
		if entry is Dictionary and str(entry.get("profile_id", "")) == profile_id:
			result.append(_portable_entry(entry))
	return result

func inspect_entry(launch_entry_id: String, profile_id: String = "player_01") -> Dictionary:
	var loaded := _load_registry()
	if not loaded.ok:
		return loaded
	var entry: Dictionary = loaded.registry.entries.get(launch_entry_id, {})
	if entry.is_empty() or str(entry.get("profile_id", "")) != profile_id:
		return _failure("unknown_entry", "Для этой работы ещё нет зарегистрированной сборки в текущем профиле.")
	if not _safe_name(launch_entry_id) or str(entry.get("launch_entry_id", "")) != launch_entry_id:
		return _failure("registry_invalid", "Запись запуска повреждена. Зарегистрируйте сохранённую сборку заново.")
	var kind := str(entry.get("kind", ""))
	if not ["godot_project", "macos_app"].has(kind):
		return _failure("unsupported_entry", "Этот тип запуска не поддерживается.")
	if str(entry.get("platform", "")) != OS.get_name():
		return _failure("unsupported_platform", "Эта сборка зарегистрирована на другой платформе. Архив и история доступны.")
	var directory := _entry_directory(launch_entry_id)
	var payload := directory.path_join("project" if kind == "godot_project" else "Game.app")
	if not DirAccess.dir_exists_absolute(payload):
		return _failure("app_missing", "Сохранённая сборка отсутствует. Восстановите её или зарегистрируйте новую версию; результат миссии сохранён.")
	var scanned := _scan_tree(payload, kind == "godot_project")
	if not scanned.ok:
		return scanned
	if _fingerprint(scanned.files) != str(entry.get("checksum", "")):
		return _failure("app_changed", "Файлы сборки изменились после регистрации. Вместе проверьте новую версию и зарегистрируйте её отдельно.")
	var archive := directory.path_join("source.zip")
	if not FileAccess.file_exists(archive):
		return _failure("source_archive_missing", "Копия исходников отсутствует. Восстановите архив перед запуском.")
	if FileAccess.get_sha256(archive) != str(entry.get("source_checksum", "")):
		return _failure("source_archive_changed", "Архив сохранённой версии изменился. Нужна повторная регистрация.")
	if kind == "godot_project":
		if not OS.has_feature("editor") or not FileAccess.file_exists(OS.get_executable_path()):
			return _failure("godot_missing", "Godot для запуска исходного проекта сейчас недоступен.")
		if OS.get_executable_path() != str(entry.get("engine_path", "")) or FileAccess.get_sha256(OS.get_executable_path()) != str(entry.get("engine_checksum", "")):
			return _failure("engine_changed", "Godot изменился после регистрации. Проверьте и зарегистрируйте проект с текущим движком.")
	return {"ok": true, "available": true, "entry": _portable_entry(entry), "launch_entry_id": launch_entry_id}

func launch(launch_entry_id: String, profile_id: String = "player_01") -> Dictionary:
	var checked := inspect_entry(launch_entry_id, profile_id)
	if not checked.ok:
		return checked
	var entry: Dictionary = checked.entry
	var payload := _entry_directory(launch_entry_id).path_join("project" if entry.kind == "godot_project" else "Game.app")
	var pid := -1
	if entry.kind == "godot_project":
		# Godot recommends create_instance for the current engine on macOS.
		# Arguments are constructed here; no argument strings come from JSON.
		pid = OS.create_instance(PackedStringArray(["--path", payload]))
	else:
		var executable := _app_executable(payload)
		if executable.is_empty():
			return _failure("app_executable_missing", "Не удалось найти исполняемый файл зарегистрированной сборки.")
		pid = OS.create_process(executable, PackedStringArray(), false)
	if pid <= 0:
		return _failure("launch_failed", "Система не смогла открыть приложение. Проверьте сборку вместе со взрослым; архив и результат миссии сохранены.")
	_children[pid] = {"launch_entry_id": launch_entry_id, "profile_id": profile_id}
	return {"ok": true, "pid": pid, "launch_entry_id": launch_entry_id, "completion_evidence": false, "message": "Игра открыта отдельно. Сам запуск не подтверждает прохождение или авторство."}

func process_status(pid: int, profile_id: String = "player_01") -> Dictionary:
	if not _children.has(pid) or str(_children[pid].profile_id) != profile_id:
		return _failure("unknown_process", "Этот процесс не запускался из текущего профиля.")
	if OS.is_process_running(pid):
		return {"ok": true, "running": true, "completion_evidence": false}
	var exit_code := OS.get_process_exit_code(pid)
	if exit_code > 0:
		var result := _failure("application_exited_with_error", "Приложение завершилось с ошибкой. Предыдущие версии и результаты миссии остались в архиве.")
		result["exit_code"] = exit_code
		return result
	return {"ok": true, "running": false, "exit_code": exit_code, "completion_evidence": false}

func _register(source: String, kind: String, version_label: String, actor_id: String, profile_id: String) -> Dictionary:
	if actor_id != "parent_local":
		return _failure("adult_registration_required", "Сборку регистрируют отдельным действием во взрослом разделе.")
	if profile_id.strip_edges().is_empty() or version_label.strip_edges().is_empty() or version_label.length() > 80:
		return _failure("metadata_required", "Нужны профиль и название версии.")
	if storage_root == source or storage_root.begins_with(source + "/") or source.begins_with(storage_root.path_join("versions") + "/"):
		return _failure("recursive_source", "Выберите рабочую папку вне реестра запуска.")
	var loaded := _load_registry()
	if not loaded.ok:
		return loaded
	var scanned := _scan_tree(source, kind == "godot_project")
	if not scanned.ok:
		return scanned
	var entry_id := "launch_" + Crypto.new().generate_random_bytes(12).hex_encode()
	var directory := _entry_directory(entry_id)
	var payload := directory.path_join("project" if kind == "godot_project" else "Game.app")
	if DirAccess.make_dir_recursive_absolute(payload) != OK:
		return _failure("storage_failed", "Не удалось подготовить папку сохранённой версии.")
	for relative in scanned.files:
		var original := source.path_join(str(relative))
		var destination := payload.path_join(str(relative))
		if _is_link(original) or DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK:
			_remove_tree(directory)
			return _failure("copy_failed", "Не удалось сохранить самостоятельную копию проекта.")
		if DirAccess.copy_absolute(original, destination, FileAccess.get_unix_permissions(original)) != OK:
			_remove_tree(directory)
			return _failure("copy_failed", "Не удалось скопировать файл сохранённой версии.")
	var copied := _scan_tree(payload, kind == "godot_project")
	if not copied.ok or _fingerprint(copied.get("files", {})) != _fingerprint(scanned.files):
		_remove_tree(directory)
		return _failure("source_changed_during_copy", "Исходник изменился во время копирования. Сохраните проект и повторите регистрацию.")
	var packed := _archive_tree(payload, copied.files, directory.path_join("source.zip"))
	if not packed.ok:
		_remove_tree(directory)
		return packed
	var entry := {"launch_entry_id": entry_id, "profile_id": profile_id, "kind": kind,
		"version_label": version_label.strip_edges(), "title": source.get_file(),
		"platform": OS.get_name(), "checksum": _fingerprint(copied.files),
		"source_checksum": FileAccess.get_sha256(directory.path_join("source.zip")),
		"source_archive_file": "launch_registry/versions/" + entry_id + "/source.zip", "source_archive_kind": "project_source" if kind == "godot_project" else "application_bundle", "bytes": copied.bytes,
		"registered_by": actor_id, "registered_at": Time.get_datetime_string_from_system(),
		"demonstration_only": _is_builtin_demo(source, copied.files) if kind == "godot_project" else false, "completion_evidence": false}
	if kind == "godot_project":
		entry["engine_path"] = OS.get_executable_path()
		entry["engine_checksum"] = FileAccess.get_sha256(OS.get_executable_path())
		if str(entry.engine_checksum).is_empty():
			_remove_tree(directory)
			return _failure("engine_unreadable", "Не удалось проверить контрольную сумму Godot.")
	var registry: Dictionary = loaded.registry
	registry.entries[entry_id] = entry
	if not _save_registry(registry):
		_remove_tree(directory)
		return _failure("registry_save_failed", "Не удалось сохранить реестр. Регистрация не выполнена; исходный проект не изменён.")
	return {"ok": true, "launch_entry_id": entry_id, "entry": _portable_entry(entry), "source_archive_file": entry.source_archive_file}

func _scan_tree(directory: String, skip_cache: bool, relative: String = "", accumulator: Dictionary = {}) -> Dictionary:
	if relative.is_empty():
		accumulator = {"ok": true, "files": {}, "bytes": 0}
		if _is_link(directory):
			return _failure("symlink_not_allowed", "Нужна самостоятельная папка, без символических ссылок.")
	if relative.split("/").size() > MAX_DEPTH:
		return _failure("tree_too_deep", "У проекта слишком много вложенных папок.")
	var dir := DirAccess.open(directory.path_join(relative))
	if dir == null:
		return _failure("app_missing", "Не удалось прочитать сохранённую сборку.")
	dir.include_hidden = true
	dir.include_navigational = false
	if dir.list_dir_begin() != OK:
		return _failure("read_failed", "Не удалось прочитать папку проекта.")
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not _safe_name(file_name):
			dir.list_dir_end()
			return _failure("invalid_file_name", "В проекте есть неподдерживаемое имя файла.")
		var child := file_name if relative.is_empty() else relative.path_join(file_name)
		# Only generated Godot cache is excluded; every executable/source resource
		# and each added file is covered by the digest.
		if skip_cache and file_name == ".godot" and dir.current_is_dir():
			file_name = dir.get_next()
			continue
		if dir.is_link(file_name):
			dir.list_dir_end()
			return _failure("symlink_not_allowed", "В сборке есть символическая ссылка. Зарегистрируйте самостоятельную копию без ссылок.")
		if dir.current_is_dir():
			var nested := _scan_tree(directory, skip_cache, child, accumulator)
			if not nested.ok:
				dir.list_dir_end()
				return nested
		else:
			var file := FileAccess.open(directory.path_join(child), FileAccess.READ)
			if file == null:
				dir.list_dir_end()
				return _failure("read_failed", "Не удалось прочитать один из файлов сборки.")
			accumulator.bytes += file.get_length()
			file.close()
			if accumulator.bytes > MAX_VERSION_BYTES or accumulator.files.size() >= MAX_FILES:
				dir.list_dir_end()
				return _failure("version_too_large", "Версия превышает 200 МБ или 4096 файлов. Подготовьте отдельную небольшую сборку.")
			var checksum := FileAccess.get_sha256(directory.path_join(child))
			if checksum.is_empty():
				dir.list_dir_end()
				return _failure("checksum_failed", "Не удалось проверить файл сборки.")
			accumulator.files[child] = checksum
		file_name = dir.get_next()
	dir.list_dir_end()
	return accumulator

func _archive_tree(directory: String, files: Dictionary, archive: String) -> Dictionary:
	var writer := ZIPPacker.new()
	if writer.open(archive) != OK:
		return _failure("archive_failed", "Не удалось создать архив исходников.")
	var names := files.keys()
	names.sort()
	for relative in names:
		var file := FileAccess.open(directory.path_join(str(relative)), FileAccess.READ)
		if file == null or writer.start_file(str(relative)) != OK:
			writer.close()
			return _failure("archive_failed", "Не удалось прочитать исходник для архива.")
		while file.get_position() < file.get_length():
			if writer.write_file(file.get_buffer(mini(65536, file.get_length() - file.get_position()))) != OK:
				writer.close()
				return _failure("archive_failed", "Не удалось сохранить архив исходников.")
		file.close()
		if writer.close_file() != OK:
			writer.close()
			return _failure("archive_failed", "Не удалось завершить файл в архиве.")
	if writer.close() != OK:
		return _failure("archive_failed", "Не удалось завершить архив исходников.")
	return {"ok": true}

func _load_registry() -> Dictionary:
	var file_name := storage_root.path_join("registry.json")
	if not FileAccess.file_exists(file_name):
		return {"ok": true, "registry": {"schema_version": REGISTRY_SCHEMA, "entries": {}}}
	var file := FileAccess.open(file_name, FileAccess.READ)
	if file == null or file.get_length() > 8 * 1024 * 1024:
		return _failure("registry_unreadable", "Реестр запуска недоступен; сохранённые работы не изменены.")
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return _failure("registry_invalid", "Реестр запуска повреждён. Нужна его сохранённая копия или новая регистрация.")
	var registry: Dictionary = parser.data
	if int(registry.get("schema_version", 0)) != REGISTRY_SCHEMA or not registry.get("entries") is Dictionary:
		return _failure("registry_version_unsupported", "Нужна совместимая версия реестра запуска.")
	return {"ok": true, "registry": registry}

func _save_registry(registry: Dictionary) -> bool:
	if DirAccess.make_dir_recursive_absolute(storage_root) != OK:
		return false
	var temporary := storage_root.path_join("registry.json.tmp")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(registry, "\t"))
	file.flush()
	var succeeded := file.get_error() == OK
	file.close()
	return succeeded and DirAccess.rename_absolute(temporary, storage_root.path_join("registry.json")) == OK

func _entry_directory(entry_id: String) -> String:
	return storage_root.path_join("versions").path_join(entry_id)

static func _app_executable(bundle: String) -> String:
	# Godot exports an XML plist. Only this explicit bundle format is supported;
	# no shell/plist command or executable name is accepted from mission JSON.
	var parser := XMLParser.new()
	if parser.open(bundle.path_join("Contents/Info.plist")) != OK:
		return ""
	var inside_key := false
	var executable_key := false
	var inside_value := false
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				inside_key = parser.get_node_name() == "key"
				inside_value = executable_key and parser.get_node_name() == "string"
			XMLParser.NODE_TEXT:
				var value := parser.get_node_data().strip_edges()
				if inside_key:
					executable_key = value == "CFBundleExecutable"
				elif inside_value and _safe_name(value):
					var executable := bundle.path_join("Contents/MacOS").path_join(value)
					return executable if FileAccess.file_exists(executable) and not _is_link(executable) else ""
			XMLParser.NODE_ELEMENT_END:
				inside_key = false
				inside_value = false
	return ""

func _is_builtin_demo(source: String, files: Dictionary) -> bool:
	if source.contains("/learning_projects/"):
		return true
	# A copied unchanged foundation remains a demo. File ownership alone is not
	# authorship; actual contribution is recorded by the separate joint review.
	var comparable := files.duplicate(true)
	comparable.erase(".sur_learning_workspace.json")
	for file_name in comparable.keys():
		if str(file_name).ends_with(".uid") or str(file_name) == ".DS_Store": comparable.erase(file_name)
	for version in ["0.1", "0.2", "0.3", "0.4", "1.0"]:
		var original := _starter_manifest_entry(version)
		if not original.is_empty() and _fingerprint(original.get("source_sha256", {})) == _fingerprint(comparable):
			return true
	return false

static func _starter_manifest_entry(version: String) -> Dictionary:
	var parser := JSON.new()
	var manifest_file := STARTER_ARCHIVE_ROOT.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_file) or parser.parse(FileAccess.get_file_as_string(manifest_file)) != OK or not parser.data is Dictionary:
		return {}
	if str(parser.data.get("starter_project_id", "")) != STARTER_PROJECT_ID:
		return {}
	for entry in parser.data.get("versions", []):
		if entry is Dictionary and str(entry.get("version", "")) == version:
			return entry
	return {}

static func _bundled_sources(version: String) -> Dictionary:
	# This only extracts the developer's constant seven-file starter archive.
	# Registered/user-provided archives remain opaque and are never extracted.
	if version not in ["0.1", "0.2", "0.3", "0.4", "1.0"]:
		return _failure("unknown_starter_version", "Такой версии основы нет.")
	var manifest := _starter_manifest_entry(version)
	var archive_file := STARTER_ARCHIVE_ROOT.path_join("station_light_" + version + ".zip")
	if manifest.is_empty() or not FileAccess.file_exists(archive_file):
		return _failure("starter_archive_missing", "Учебные исходники не включены в эту сборку SUR. Нужны архив основы и его манифест.")
	if FileAccess.get_sha256(archive_file) != str(manifest.get("sha256", "")):
		return _failure("starter_archive_changed", "Контрольная сумма встроенной основы не совпадает. Восстановите ресурсы SUR.")
	var reader := ZIPReader.new()
	if reader.open(archive_file) != OK:
		return _failure("starter_archive_invalid", "Не удалось открыть встроенную основу.")
	var names := reader.get_files()
	if names.size() != STARTER_FILES.size():
		reader.close()
		return _failure("starter_archive_invalid", "У встроенной основы изменился состав исходников.")
	var result: Dictionary = {}
	var total := 0
	for file_name in STARTER_FILES:
		var name := "station_light_" + version + "/" + file_name
		if not names.has(name):
			reader.close()
			return _failure("starter_archive_invalid", "В основе отсутствует обязательный исходник.")
		var data := reader.read_file(name)
		total += data.size()
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(data)
		if data.size() > 2 * 1024 * 1024 or total > 5 * 1024 * 1024 or digest.finish().hex_encode() != str(manifest.get("source_sha256", {}).get(file_name, "")):
			reader.close()
			return _failure("starter_archive_invalid", "Исходник основы не прошёл проверку размера или контрольной суммы.")
		result[file_name] = data
	reader.close()
	return {"ok": true, "files": result}

static func _fingerprint(files: Dictionary) -> String:
	var names := files.keys()
	names.sort()
	var parts: Array[String] = []
	for file_name in names:
		parts.append(JSON.stringify([file_name, files[file_name]]))
	return "\n".join(parts).sha256_text()

static func _safe_name(value: String) -> bool:
	for index in value.length():
		if value.unicode_at(index) < 32:
			return false
	return not value.is_empty() and value not in [".", ".."] and not value.contains("/") and not value.contains("\\") and not value.contains(":")

static func _is_link(absolute: String) -> bool:
	var parent := DirAccess.open(absolute.get_base_dir())
	return parent != null and parent.is_link(absolute.get_file())

static func _portable_entry(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate(true)
	result.erase("engine_path")
	return result

static func _failure(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": message, "completion_evidence": false}

static func _remove_tree(directory: String) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	dir.include_hidden = true
	for child in dir.get_directories():
		if not dir.is_link(child):
			_remove_tree(directory.path_join(child))
	for child in dir.get_files():
		dir.remove(child)
	DirAccess.remove_absolute(directory)
