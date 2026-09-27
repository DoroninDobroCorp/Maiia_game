class_name AuthorPatchService
extends RefCounted

## Минимальный безопасный редактор реплик Phase B: только два известных ключа,
## предпросмотр без мутации, публикация и откат.

const SCHEMA_VERSION := 1
const ProgressServiceScript = preload("res://scripts/services/progress_service.gd")
const ALLOWED_DIALOGUE_KEYS: Array[String] = ["radio_greeting", "archive_note"]
const DEFAULT_DIALOGUE := {
	"radio_greeting": "¡Hola, El Bolsón! Приветствуем хранительницу станции.",
	"archive_note": "В архиве появилась новая страница — следы работы остаются в истории станции."
}

static func ensure_phase_b(state: Dictionary) -> Dictionary:
	var phase_b: Dictionary = state.get("phase_b", {})
	if not phase_b.has("author_patches"):
		phase_b["author_patches"] = {}
	if not phase_b.has("dialogue_overrides"):
		phase_b["dialogue_overrides"] = {}
	if not phase_b.has("world_effects"):
		phase_b["world_effects"] = []
	state["phase_b"] = phase_b
	return phase_b

static func get_dialogue(state: Dictionary, key: String) -> String:
	var overrides: Dictionary = ensure_phase_b(state).get("dialogue_overrides", {})
	return str(overrides.get(key, DEFAULT_DIALOGUE.get(key, "")))

static func preview(package: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if int(package.get("schema_version", -1)) != SCHEMA_VERSION:
		errors.append("Неизвестная schema_version пакета.")
	var patch_id := str(package.get("patch_id", "")).strip_edges()
	if patch_id.is_empty() or patch_id.length() > 80:
		errors.append("Нужен короткий patch_id.")
	for top_key in package.keys():
		if not ["schema_version", "patch_id", "dialogue"].has(str(top_key)):
			errors.append("Неизвестное поле пакета: " + str(top_key))

	var dialogue: Dictionary = package.get("dialogue", {})
	if dialogue.is_empty():
		errors.append("Нет изменений реплик.")
	var normalized: Dictionary = {}
	for key in dialogue.keys():
		var key_text := str(key)
		if not ALLOWED_DIALOGUE_KEYS.has(key_text):
			errors.append("Эта реплика не разрешена для редактирования: " + key_text)
			continue
		var value := str(dialogue[key]).strip_edges()
		if value.is_empty() or value.length() > 400:
			errors.append("Реплика должна быть длиной 1–400 символов.")
		elif _contains_unsafe_reference(value):
			errors.append("В реплике запрещены пути и URL.")
		else:
			normalized[key_text] = value

	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {
		"ok": true,
		"preview": {
			"schema_version": SCHEMA_VERSION,
			"patch_id": patch_id,
			"dialogue": normalized
		}
	}

static func publish(state: Dictionary, package: Dictionary) -> Dictionary:
	var checked := preview(package)
	if not bool(checked.get("ok", false)):
		return checked
	var clean: Dictionary = checked.get("preview", {})
	var patch_id := str(clean.get("patch_id", ""))
	var phase_b := ensure_phase_b(state)
	var patches: Dictionary = phase_b.get("author_patches", {})
	if patches.has(patch_id) and str((patches[patch_id] as Dictionary).get("status", "")) == "PUBLISHED":
		return {"ok": false, "reason": "patch_id_already_published"}

	var overrides: Dictionary = phase_b.get("dialogue_overrides", {})
	var previous: Dictionary = {}
	for key in (clean.get("dialogue", {}) as Dictionary).keys():
		previous[key] = {"had_override": overrides.has(key), "value": overrides.get(key, "")}
		overrides[key] = clean["dialogue"][key]

	var record := {
		"patch_id": patch_id,
		"dialogue": (clean.get("dialogue", {}) as Dictionary).duplicate(true),
		"previous": previous,
		"status": "PUBLISHED",
		"published_at": Time.get_datetime_string_from_system()
	}
	patches[patch_id] = record
	var effects: Array = phase_b.get("world_effects", [])
	if not effects.has("author_patch_accepted"):
		effects.append("author_patch_accepted")
	phase_b["dialogue_overrides"] = overrides
	phase_b["author_patches"] = patches
	phase_b["world_effects"] = effects
	state["phase_b"] = phase_b
	ProgressServiceScript.ensure_phase_b(state)
	return {"ok": true, "patch": record.duplicate(true)}

static func rollback(state: Dictionary, patch_id: String) -> Dictionary:
	var phase_b := ensure_phase_b(state)
	var patches: Dictionary = phase_b.get("author_patches", {})
	if not patches.has(patch_id):
		return {"ok": false, "reason": "unknown_patch"}
	var record: Dictionary = patches[patch_id]
	if str(record.get("status", "")) != "PUBLISHED":
		return {"ok": false, "reason": "patch_not_published"}
	var overrides: Dictionary = phase_b.get("dialogue_overrides", {})
	var previous: Dictionary = record.get("previous", {})
	for key in previous.keys():
		var before: Dictionary = previous[key]
		if bool(before.get("had_override", false)):
			overrides[key] = before.get("value", "")
		else:
			overrides.erase(key)
	record["status"] = "ROLLED_BACK"
	record["rolled_back_at"] = Time.get_datetime_string_from_system()
	patches[patch_id] = record
	phase_b["dialogue_overrides"] = overrides
	phase_b["author_patches"] = patches
	state["phase_b"] = phase_b
	return {"ok": true}

static func _contains_unsafe_reference(text: String) -> bool:
	var lower := text.to_lower()
	return lower.contains("res://") or lower.contains("user://") or lower.contains("file://") or lower.contains("http://") or lower.contains("https://")
