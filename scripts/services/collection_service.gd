class_name CollectionService
extends RefCounted

## Metadata only: no original images are decoded by archive queries.
## Mutators edit the supplied candidate state; the caller persists that candidate.
const ArtifactServiceScript = preload("res://scripts/services/artifact_service.gd")
const THEMES := ["warm", "dusk", "daylight"]
const RECIPES := {
	"frame": "image", "image": "image", "note": "note", "legacy_card": "note",
	"album": "album", "radio_album": "album", "menu": "image", "postcard": "image",
	"terminal": "game", "game": "game", "game_terminal": "game", "game_version": "game",
	"diorama": "diorama", "water_diptych": "diorama", "diptych": "diorama",
	"audio": "audio", "sculpture": "sculpture", "observation": "note",
	"radio_contact_card": "note", "radio_menu": "album", "station_word_label": "note",
	"radio_episode_card": "album", "game_concept_card": "game", "game_project_version": "game",
	"game_premiere": "game", "water_question_card": "note", "field_plan": "note",
	"water_observation_page": "note", "water_comparison": "note", "home_water_study": "note",
	"silhouette_sheet": "image", "silhouette_frame": "image", "chapter_album": "album", "story_find": "note"
}

static func ensure_collections(state: Dictionary) -> Dictionary:
	if not state.has("collections"):
		state["collections"] = {}
	for key in ["works", "exhibits", "rooms", "placements", "snapshots", "retired_room_ids"]:
		if not state.collections.has(key):
			state.collections[key] = {}
	return state.collections

static func _id(prefix: String, records: Dictionary) -> String:
	var index := records.size() + 1
	while records.has(prefix + str(index)):
		index += 1
	return prefix + str(index)

static func _owned(record: Dictionary, profile_id: String) -> bool:
	return not record.is_empty() and str(record.get("profile_id", "")) == profile_id

static func _safe_content(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if str(key).to_lower() in ["path", "file_path", "source_path", "command", "shell", "script", "base64"]:
				return false
			if not _safe_content(value[key]):
				return false
	elif value is Array:
		for item in value:
			if not _safe_content(item):
				return false
	elif value is String:
		if value.begins_with("/") or value.contains("://") or value.begins_with("../"):
			return false
	return true

static func get_work(state: Dictionary, work_id: String, profile_id: String = "player_01") -> Dictionary:
	var work: Dictionary = state.get("collections", {}).get("works", {}).get(work_id, {})
	return work.duplicate(true) if _owned(work, profile_id) else {}

static func list_works(state: Dictionary, profile_id: String = "player_01", filters: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var query := str(filters.get("search", filters.get("query", ""))).strip_edges().to_lower()
	for work in state.get("collections", {}).get("works", {}).values():
		if not _owned(work, profile_id):
			continue
		if not query.is_empty() and not _searchable_text(work).contains(query):
			continue
		if filters.has("kind") and str(filters.kind) != "" and str(work.get("kind", "")) != str(filters.kind):
			continue
		if filters.has("status") and str(work.get("status", "")) != str(filters.status):
			continue
		if filters.has("authorship") and str(work.get("authorship", {}).get("category", "personal")) != str(filters.authorship):
			continue
		if filters.has("quest_id") and not work.get("quest_ids", []).has(str(filters.quest_id)):
			continue
		result.append(work.duplicate(true))
	result.sort_custom(func(a, b): return str(a.get("created_at", "")) + str(a.work_id) > str(b.get("created_at", "")) + str(b.work_id))
	var offset := maxi(0, int(filters.get("offset", 0)))
	var limit := maxi(0, int(filters.get("limit", result.size())))
	return result.slice(offset, mini(result.size(), offset + limit))

static func _searchable_text(work: Dictionary) -> String:
	var quest: Dictionary = work.get("source", {}).get("quest_snapshot", {})
	var parts: Array[String] = [str(work.get("title", "")), str(work.get("note", "")),
		str(work.get("quest_ids", [])), str(work.get("authorship", {})),
		str(quest.get("title", "")), str(quest.get("story_title", ""))]
	for version in work.get("versions", []):
		parts.append(str(version.get("content", {}).get("note", "")))
	return " ".join(parts).to_lower()

static func create_work(state: Dictionary, data: Dictionary, profile_id: String = "player_01") -> Dictionary:
	for key in ["content", "authorship", "source"]:
		if data.has(key) and not data[key] is Dictionary:
			return {"ok": false, "reason": "invalid_work", "field": key}
	if data.has("quest_ids") and not data.quest_ids is Array:
		return {"ok": false, "reason": "invalid_work", "field": "quest_ids"}
	if profile_id.is_empty() or str(data.get("title", "")).strip_edges().is_empty():
		return {"ok": false, "reason": "title_and_profile_required"}
	var content: Dictionary = data.get("content", {})
	if not _safe_content(content):
		return {"ok": false, "reason": "unmanaged_content"}
	var artifact_id := str(content.get("artifact_id", ""))
	if not artifact_id.is_empty() and not _owned(state.get("phase_b", {}).get("artifacts", {}).get(artifact_id, {}), profile_id):
		return {"ok": false, "reason": "unknown_artifact"}
	var collections := ensure_collections(state)
	var work_id := str(data.get("work_id", _id("work:", collections.works)))
	if collections.works.has(work_id):
		return {"ok": false, "reason": "work_id_exists"}
	var version_id := work_id + ":v1"
	var now := Time.get_datetime_string_from_system()
	var work := {"work_id": work_id, "profile_id": profile_id,
		"title": str(data.title).strip_edges().substr(0, 160), "kind": str(data.get("kind", "note")),
		"authorship": data.get("authorship", {"category": "personal"}).duplicate(true),
		"quest_ids": data.get("quest_ids", []).duplicate(true), "status": data.get("status", "IN_PROGRESS"),
		"created_at": now, "current_version_id": version_id,
		"versions": [{"version_id": version_id, "content": content.duplicate(true),
			"change_note": str(data.get("change_note", "Первая версия")), "created_at": now,
			"assistance": str(data.get("assistance", ""))}]}
	if data.has("source"):
		work["source"] = data.source.duplicate(true)
	collections.works[work_id] = work
	return {"ok": true, "work": work.duplicate(true), "work_id": work_id, "version_id": version_id}

static func add_version(state: Dictionary, work_id: String, content: Dictionary, change_note: String = "", assistance: String = "", profile_id: String = "player_01") -> Dictionary:
	var work := get_work(state, work_id, profile_id)
	if work.is_empty():
		return {"ok": false, "reason": "unknown_work"}
	if not _safe_content(content):
		return {"ok": false, "reason": "unmanaged_content"}
	var artifact_id := str(content.get("artifact_id", ""))
	if not artifact_id.is_empty() and not _owned(state.get("phase_b", {}).get("artifacts", {}).get(artifact_id, {}), profile_id):
		return {"ok": false, "reason": "unknown_artifact"}
	var version_id := work_id + ":v" + str(work.versions.size() + 1)
	work.versions.append({"version_id": version_id, "content": content.duplicate(true), "change_note": change_note,
		"created_at": Time.get_datetime_string_from_system(), "assistance": assistance})
	work.current_version_id = version_id
	state.collections.works[work_id] = work
	return {"ok": true, "work": work.duplicate(true), "version_id": version_id}

static func get_version(state: Dictionary, work_id: String, version_id: String = "", profile_id: String = "player_01") -> Dictionary:
	var work := get_work(state, work_id, profile_id)
	var selected := version_id if not version_id.is_empty() else str(work.get("current_version_id", ""))
	for version in work.get("versions", []):
		if str(version.get("version_id", "")) == selected:
			return version.duplicate(true)
	return {}

static func create_exhibit(state: Dictionary, work_id: String, recipe_id: String = "frame", caption: String = "", profile_id: String = "player_01") -> Dictionary:
	var work := get_work(state, work_id, profile_id)
	if work.is_empty():
		return {"ok": false, "reason": "unknown_work"}
	var collections := ensure_collections(state)
	var exhibit_id := "exhibit:" + JSON.stringify([profile_id, work_id, recipe_id]).sha256_text()
	if collections.exhibits.has(exhibit_id):
		return {"ok": true, "applied": false, "exhibit_id": exhibit_id, "exhibit": collections.exhibits[exhibit_id].duplicate(true)}
	# Custom frozen work recipes can choose a work kind; unknown decoration gets a card.
	var kind := str(RECIPES.get(recipe_id, work.get("kind", "note")))
	if not ["image", "note", "album", "game", "diorama", "audio", "sculpture"].has(kind):
		kind = "note"
	var exhibit := {"exhibit_id": exhibit_id, "profile_id": profile_id, "work_id": work_id,
		"recipe_id": recipe_id, "kind": kind, "caption": caption if not caption.is_empty() else str(work.title),
		"interactions": ["inspect", "versions"] if kind != "game" else ["inspect", "versions", "launch"]}
	collections.exhibits[exhibit_id] = exhibit
	return {"ok": true, "applied": true, "exhibit_id": exhibit_id, "exhibit": exhibit.duplicate(true)}

static func get_exhibit(state: Dictionary, exhibit_id: String, profile_id: String = "player_01") -> Dictionary:
	var exhibit: Dictionary = state.get("collections", {}).get("exhibits", {}).get(exhibit_id, {})
	return exhibit.duplicate(true) if _owned(exhibit, profile_id) else {}

static func list_exhibits(state: Dictionary, profile_id: String = "player_01") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for exhibit in state.get("collections", {}).get("exhibits", {}).values():
		if _owned(exhibit, profile_id):
			result.append(exhibit.duplicate(true))
	return result

static func list_slots(template_id: String = "gallery_v1") -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	if template_id == "station_favorites":
		for number in range(1, 4):
			slots.append({"slot_id": "favorite_%02d" % number, "kind": "favorite", "compatible_kinds": ["image", "note", "album", "game", "diorama", "audio", "sculpture"]})
	elif template_id == "gallery_v1":
		for number in range(1, 7):
			slots.append({"slot_id": "frame_%02d" % number, "kind": "frame", "compatible_kinds": ["image", "note", "game", "diorama", "album"]})
		for number in range(1, 4):
			slots.append({"slot_id": "pedestal_%02d" % number, "kind": "pedestal", "compatible_kinds": ["sculpture", "diorama", "album", "note"]})
		slots.append({"slot_id": "audio_01", "kind": "audio", "compatible_kinds": ["audio", "note"]})
		slots.append({"slot_id": "terminal_01", "kind": "terminal", "compatible_kinds": ["game", "image", "note", "album"]})
		slots.append({"slot_id": "table_01", "kind": "table", "compatible_kinds": ["album", "diorama", "image", "note"]})
	return slots

static func list_rooms(state: Dictionary, profile_id: String = "player_01") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room in state.get("collections", {}).get("rooms", {}).values():
		if _owned(room, profile_id):
			result.append(room.duplicate(true))
	result.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return result

static func ensure_gallery(state: Dictionary, profile_id: String = "player_01") -> Dictionary:
	if not bool(state.get("s00_progress", {}).get("station_awakened", false)):
		return {"ok": false, "reason": "prologue_required"}
	var collections := ensure_collections(state)
	var room_id := "gallery:" + profile_id + ":first"
	var reserved := _reserved_room_ids(collections)
	if not reserved.has(room_id) and not list_rooms(state, profile_id).any(func(r): return str(r.get("template_id", "")) == "gallery_v1"):
		collections.rooms[room_id] = {"room_id": room_id, "profile_id": profile_id, "template_id": "gallery_v1", "title": "Первые открытия", "theme": "warm", "frame_style": "brass", "order": 0}
	var favorites_id := "station_favorites:" + profile_id
	if not collections.rooms.has(favorites_id):
		collections.rooms[favorites_id] = {"room_id": favorites_id, "profile_id": profile_id, "template_id": "station_favorites", "title": "Избранное на станции", "theme": "warm", "frame_style": "brass", "order": 9999}
	for room in list_rooms(state, profile_id):
		if str(room.get("template_id", "")) == "gallery_v1":
			return {"ok": true, "room_id": str(room.room_id), "room": room}
	return {"ok": true, "room_id": "", "room": {}}

static func _reserved_room_ids(collections: Dictionary) -> Dictionary:
	# Snapshots also reserve identities for saves written before deletion markers.
	var reserved: Dictionary = collections.get("retired_room_ids", {}).duplicate()
	for id in collections.get("rooms", {}): reserved[id] = true
	for snapshot in collections.get("snapshots", {}).values():
		reserved[str(snapshot.get("room_id", ""))] = true
	return reserved

static func can_create_room(state: Dictionary, profile_id: String = "player_01") -> bool:
	for instance in state.get("phase_b", {}).get("quest_instances", {}).values():
		if _owned(instance, profile_id) and str(instance.get("quest_id", "")) in ["FG01", "FG11", "FG08"] and str(instance.get("status", "")) == "COMPLETED":
			return true
	var count := 0
	for work in state.get("collections", {}).get("works", {}).values():
		if _owned(work, profile_id) and str(work.get("authorship", {}).get("category", "personal")) == "personal":
			count += 1
	return count >= 8

static func available_themes(state: Dictionary, profile_id: String = "player_01") -> Array[String]:
	var themes: Array[String] = []
	for theme in THEMES: themes.append(str(theme))
	for grant in state.get("adventures", {}).get("grants", {}).values():
		if str(grant.get("profile_id", "")) != profile_id: continue
		var effect_id := str(grant.get("effect_id", ""))
		if effect_id == "secret_constellation_theme" and not themes.has("constellation"):
			themes.append("constellation")
		if effect_id == "gallery_evening_light" and not themes.has("evening"):
			themes.append("evening")
	return themes

static func create_room(state: Dictionary, title: String, theme: String = "warm", profile_id: String = "player_01") -> Dictionary:
	if not can_create_room(state, profile_id):
		return {"ok": false, "reason": "additional_room_locked"}
	if title.strip_edges().is_empty() or not available_themes(state, profile_id).has(theme):
		return {"ok": false, "reason": "invalid_room_settings"}
	var collections := ensure_collections(state)
	var room_id := _id("gallery:" + profile_id + ":", _reserved_room_ids(collections))
	var room := {"room_id": room_id, "profile_id": profile_id, "template_id": "gallery_v1", "title": title.substr(0, 120), "theme": theme, "frame_style": "brass", "order": list_rooms(state, profile_id).size()}
	collections.rooms[room_id] = room
	return {"ok": true, "room_id": room_id, "room": room.duplicate(true)}

static func update_room(state: Dictionary, room_id: String, changes: Dictionary, profile_id: String = "player_01") -> Dictionary:
	var room: Dictionary = state.get("collections", {}).get("rooms", {}).get(room_id, {}).duplicate(true)
	if not _owned(room, profile_id):
		return {"ok": false, "reason": "unknown_room"}
	if changes.has("theme") and not available_themes(state, profile_id).has(str(changes.theme)):
		return {"ok": false, "reason": "unknown_theme"}
	for key in ["title", "theme", "frame_style", "order"]:
		if changes.has(key):
			room[key] = changes[key]
	state.collections.rooms[room_id] = room
	return {"ok": true, "room": room.duplicate(true)}

static func list_placements(state: Dictionary, room_id: String, profile_id: String = "player_01") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for placement in state.get("collections", {}).get("placements", {}).values():
		if _owned(placement, profile_id) and str(placement.get("room_id", "")) == room_id:
			result.append(placement.duplicate(true))
	return result

static func place_exhibit(state: Dictionary, room_id: String, slot_id: String, exhibit_id: String, version_id: String = "", profile_id: String = "player_01", decoration: Dictionary = {}) -> Dictionary:
	var room: Dictionary = state.get("collections", {}).get("rooms", {}).get(room_id, {})
	var exhibit := get_exhibit(state, exhibit_id, profile_id)
	if not _owned(room, profile_id) or exhibit.is_empty():
		return {"ok": false, "reason": "unknown_room_or_exhibit"}
	var slot: Dictionary = {}
	for candidate in list_slots(str(room.get("template_id", ""))):
		if str(candidate.slot_id) == slot_id:
			slot = candidate
	if slot.is_empty() or not slot.compatible_kinds.has(str(exhibit.kind)):
		return {"ok": false, "reason": "incompatible_slot"}
	var version := get_version(state, str(exhibit.work_id), version_id, profile_id)
	if version.is_empty():
		return {"ok": false, "reason": "unknown_version"}
	var placement_id := JSON.stringify([profile_id, room_id, slot_id]).sha256_text()
	var placement := {"placement_id": placement_id, "profile_id": profile_id, "room_id": room_id,
		"slot_id": slot_id, "exhibit_id": exhibit_id, "version_id": version.version_id,
		"decoration": decoration.duplicate(true), "launch_allowed": str(slot.kind) == "terminal" and str(exhibit.kind) == "game"}
	state.collections.placements[placement_id] = placement
	return {"ok": true, "placement": placement.duplicate(true)}

static func remove_placement(state: Dictionary, room_id: String, slot_id: String, profile_id: String = "player_01") -> Dictionary:
	var room: Dictionary = state.get("collections", {}).get("rooms", {}).get(room_id, {})
	if not _owned(room, profile_id):
		return {"ok": false, "reason": "unknown_room"}
	var placement_id := JSON.stringify([profile_id, room_id, slot_id]).sha256_text()
	state.collections.placements.erase(placement_id)
	return {"ok": true}

static func save_exhibition(state: Dictionary, room_id: String, title: String = "", profile_id: String = "player_01") -> Dictionary:
	var room: Dictionary = state.get("collections", {}).get("rooms", {}).get(room_id, {})
	if not _owned(room, profile_id):
		return {"ok": false, "reason": "unknown_room"}
	var collections := ensure_collections(state)
	var snapshot_id := _id("exhibition:", collections.snapshots)
	var snapshot := {"snapshot_id": snapshot_id, "profile_id": profile_id, "title": title if not title.is_empty() else str(room.title),
		"room_id": room_id, "room": room.duplicate(true), "placements": list_placements(state, room_id, profile_id), "created_at": Time.get_datetime_string_from_system()}
	collections.snapshots[snapshot_id] = snapshot
	return {"ok": true, "snapshot_id": snapshot_id, "snapshot": snapshot.duplicate(true)}

static func list_snapshots(state: Dictionary, profile_id: String = "player_01") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for snapshot in state.get("collections", {}).get("snapshots", {}).values():
		if _owned(snapshot, profile_id):
			result.append(snapshot.duplicate(true))
	return result

static func restore_exhibition(state: Dictionary, snapshot_id: String, room_id: String = "", profile_id: String = "player_01") -> Dictionary:
	var snapshot: Dictionary = state.get("collections", {}).get("snapshots", {}).get(snapshot_id, {})
	if not _owned(snapshot, profile_id):
		return {"ok": false, "reason": "unknown_snapshot"}
	var candidate := state.duplicate(true)
	var destination := room_id if not room_id.is_empty() else str(snapshot.room_id)
	if not candidate.collections.rooms.has(destination):
		if destination != str(snapshot.room_id):
			return {"ok": false, "reason": "unknown_room"}
		candidate.collections.rooms[destination] = snapshot.room.duplicate(true)
	if not _owned(candidate.collections.rooms[destination], profile_id):
		return {"ok": false, "reason": "unknown_room"}
	if str(candidate.collections.rooms[destination].get("template_id", "")) != str(snapshot.get("room", {}).get("template_id", "")):
		return {"ok": false, "reason": "incompatible_room_template"}
	for placement in list_placements(candidate, destination, profile_id):
		candidate.collections.placements.erase(str(placement.placement_id))
	var unavailable: Array[String] = []
	var used_slots: Dictionary = {}
	for placement in snapshot.get("placements", []):
		var slot_id := str(placement.get("slot_id", ""))
		if used_slots.has(slot_id):
			return {"ok": false, "reason": "duplicate_snapshot_slot"}
		used_slots[slot_id] = true
		var placed := place_exhibit(candidate, destination, slot_id, str(placement.exhibit_id), str(placement.version_id), profile_id, placement.get("decoration", {}))
		if not bool(placed.ok):
			unavailable.append(str(placement.exhibit_id))
	if destination == str(snapshot.room_id):
		candidate.collections.rooms[destination] = snapshot.room.duplicate(true)
	state["collections"] = candidate.collections
	return {"ok": true, "room_id": destination, "unavailable_exhibit_ids": unavailable}

static func delete_room(state: Dictionary, room_id: String, keep_snapshot: bool = true, profile_id: String = "player_01") -> Dictionary:
	var room: Dictionary = state.get("collections", {}).get("rooms", {}).get(room_id, {})
	if not _owned(room, profile_id):
		return {"ok": false, "reason": "unknown_room"}
	if str(room.get("template_id", "")) == "station_favorites":
		return {"ok": false, "reason": "fixed_station_slots", "message": "Три места избранного остаются на станции. Любой предмет можно убрать в архив."}
	var snapshot_id := ""
	if keep_snapshot:
		snapshot_id = str(save_exhibition(state, room_id, "", profile_id).get("snapshot_id", ""))
	for placement in list_placements(state, room_id, profile_id):
		state.collections.placements.erase(str(placement.placement_id))
	state.collections.rooms.erase(room_id)
	ensure_collections(state).retired_room_ids[room_id] = profile_id
	return {"ok": true, "snapshot_id": snapshot_id}

static func inspect_placement(state: Dictionary, placement: Dictionary, profile_id: String = "player_01") -> Dictionary:
	if not _owned(placement, profile_id):
		return {}
	var exhibit := get_exhibit(state, str(placement.get("exhibit_id", "")), profile_id)
	var work := get_work(state, str(exhibit.get("work_id", "")), profile_id)
	var version := get_version(state, str(work.get("work_id", "")), str(placement.get("version_id", "")), profile_id)
	var artifact_id := str(version.get("content", {}).get("artifact_id", ""))
	var media_path := "" if artifact_id.is_empty() else ArtifactServiceScript.media_path_for(state, artifact_id)
	return {"work": work, "version": version, "exhibit": exhibit, "media_path": media_path,
		"placeholder": version.is_empty() or (not artifact_id.is_empty() and media_path.is_empty()),
		"launch_allowed": bool(placement.get("launch_allowed", false))}
