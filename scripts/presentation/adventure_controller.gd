class_name AdventureController
extends Node

## Application adapter: presentation commands become one persisted candidate.
## Content and stage decisions belong to services, not to 3D anchors or buttons.
const Save = preload("res://scripts/services/save_service.gd")
const Content = preload("res://scripts/services/adventure_content.gd")
const Library = preload("res://scripts/services/content_library_service.gd")
const Quest = preload("res://scripts/services/quest_service.gd")
const Artifacts = preload("res://scripts/services/artifact_service.gd")
const Collections = preload("res://scripts/services/collection_service.gd")
const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Guide = preload("res://scripts/presentation/mission_guide.gd")
const CURRENT_STORY_QUEST_IDS := ["FG01", "FG11", "FG08"]

var app: Node
var screen: Control
var gallery: Node3D
var route := "hub"
var route_context: Dictionary = {}
var navigation_bar: HBoxContainer
var gallery_nav_button: Button
var preview_state: Dictionary = {}
var preview_active := false
var preview_return_route := "editor"
var preview_return_context: Dictionary = {}
var _read_only := false
var launch_service: RefCounted
var _initialised := false
var launched_processes: Array[int] = []
var file_job: RefCounted
var file_job_mode := ""
var file_job_label: Label
var file_job_progress: ProgressBar
## Missions whose briefing page was already shown in this session.
var _briefed: Dictionary = {}
## True after a mission object in the room opened the flow: closing returns to the room.
var _opened_from_room := false

func setup(root: Node) -> void:
	app = root
	_read_only = bool(app.game_state.get("read_only", false)) or bool(app.game_state.get("save_read_only", false))
	_initialise()
	navigation_bar = HBoxContainer.new()
	navigation_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	navigation_bar.position = Vector2(-360, -48)
	navigation_bar.add_theme_constant_override("separation", 8)
	app.hud_root.add_child(navigation_bar)
	UI.button("Журнал · J", navigation_bar, open_hub)
	gallery_nav_button = UI.button("Галерея", navigation_bar, func(): open_gallery(""))
	gallery_nav_button.visible = false
	UI.button("Вместе · P", navigation_bar, open_family_tools)
	var launch_poll := Timer.new()
	launch_poll.wait_time = 1.0
	launch_poll.timeout.connect(_poll_launches)
	add_child(launch_poll)
	launch_poll.start()
	var file_poll := Timer.new()
	file_poll.wait_time = 0.1
	file_poll.timeout.connect(_poll_file_job)
	add_child(file_poll)
	file_poll.start()
	call_deferred("_present_pending")

func _initialise() -> void:
	if _read_only:
		return
	var core := load("res://scripts/services/adventure_service.gd")
	if core != null and core.has_method("ensure_adventures"):
		core.ensure_adventures(app.game_state)
		if not _initialised:
			core.migrate_legacy(app.game_state)
	Collections.ensure_collections(app.game_state)
	if bool(app.game_state.get("puzzle_solved", false)):
		Collections.ensure_gallery(app.game_state)
	_initialised = true

func _state() -> Dictionary:
	return preview_state if preview_active else app.game_state

func _view(extra: Dictionary = {}) -> Dictionary:
	var value := _state().duplicate(true)
	var context := extra.duplicate(true)
	var catalog: Array[Dictionary] = []
	var seen: Dictionary = {}
	for item in Quest.list_player_quests(value):
		var qid := str(item.get("quest_id", ""))
		if item.has("adventure") and int(item.get("revision", 0)) > int(seen.get(qid, {}).get("revision", 0)):
			seen[qid] = item
	for instance in value.get("phase_b", {}).get("quest_instances", {}).values():
		if str(instance.get("profile_id", "")) == "player_01" and instance.get("quest_snapshot", {}).has("adventure") and not instance.has("superseded_by_instance_id"):
			seen[str(instance.get("quest_id", ""))] = instance.quest_snapshot
	for q in seen.values():
		catalog.append(q)
	catalog.sort_custom(func(a, b): return int(a.get("goal_order", 99)) < int(b.get("goal_order", 99)))
	context["catalog"] = catalog
	context["chapter_templates"] = _chapter_templates(value)
	context["migration_targets"] = _migration_targets(value)
	context["launch_entries"] = _launcher().list_entries()
	context["recovery_snapshots"] = Save.list_recovery_snapshots()
	context["preview"] = preview_active
	value["_adventure_ui"] = context
	return value

func _chapter_templates(value: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for builtin in Content.quests():
		var q: Dictionary = builtin.duplicate(true)
		var qid := str(q.quest_id)
		var rev := int(q.revision)
		while true:
			var existing := Library.get_template(value, qid, rev)
			if existing.is_empty() or preload("res://scripts/domain/content_validation.gd").content_hash(existing) == preload("res://scripts/domain/content_validation.gd").content_hash(q):
				break
			rev += 1
			q["revision"] = rev
		result.append(q)
	return result

func _migration_targets(value: Dictionary) -> Dictionary:
	var targets: Dictionary = {}
	var definitions := Library.list_parent_templates(value)
	definitions.append_array(_chapter_templates(value))
	for q in definitions:
		var qid := str(q.get("quest_id", ""))
		if q.has("adventure") and int(q.get("revision", 0)) > int(targets.get(qid, {}).get("revision", 0)):
			targets[qid] = q
	return targets

func _show(kind: String, extra: Dictionary = {}) -> void:
	app._close_modals()
	route = kind
	route_context = extra.duplicate(true)
	var paths := {
		"hub": "res://scripts/presentation/adventure_hub.gd",
		"episode": "res://scripts/presentation/adventure_episode.gd",
		"mission": "res://scripts/presentation/mission_page.gd",
		"collection": "res://scripts/presentation/collection_browser.gd",
		"editor": "res://scripts/presentation/adventure_editor.gd",
		"family": "res://scripts/presentation/family_adventure_tools.gd",
		"water_photos": "res://scripts/presentation/water_photo_upload.gd"
	}
	var script: Script = load(str(paths[kind]))
	screen = script.new()
	app.modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	app.modal_container.add_child(screen)
	_connect_screen(screen)
	screen.setup(_view(extra), app.audio_service)
	refresh_navigation()

func _connect_screen(node: Node) -> void:
	if node.has_signal("closed"):
		node.connect("closed", leave_gallery if node is Node3D else _close_screen)
	if node.has_signal("command_requested"):
		node.connect("command_requested", _on_command)
	if node.has_signal("quest_requested"):
		node.connect("quest_requested", func(qid: String): open_quest(qid))
	if node.has_signal("episode_requested"):
		node.connect("episode_requested", open_episode)
	if node.has_signal("collection_requested"):
		node.connect("collection_requested", func(): open_collection())
	if node.has_signal("work_requested"):
		node.connect("work_requested", func(work_id: String): open_collection({"work_id":work_id}))
	if node.has_signal("gallery_requested"):
		node.connect("gallery_requested", open_gallery)
	if node.has_signal("map_requested"):
		node.connect("map_requested", app.open_world_explorer)
	if node.has_signal("editor_requested"):
		node.connect("editor_requested", open_editor)
	if node.has_signal("family_requested"):
		node.connect("family_requested", open_family_tools)
	if node.has_signal("legacy_console_requested"):
		node.connect("legacy_console_requested", app.open_parent_console)
	if node.has_signal("legacy_journal_requested"):
		node.connect("legacy_journal_requested", app.open_legacy_journal)
	if node.has_signal("mission_requested"):
		node.connect("mission_requested", func(qid: String): open_mission(qid))
	if node.has_signal("water_photos_requested"):
		node.connect("water_photos_requested", func(): open_water_photos())
	if node.has_signal("hub_requested"):
		node.connect("hub_requested", open_hub)
	if node.has_signal("weather_requested"):
		node.connect("weather_requested", func():
			app._close_modals()
			app._interact_radio())
	if node.has_signal("secret_requested"):
		node.connect("secret_requested", open_secret)
	if node.has_signal("prop_clicked"):
		node.connect("prop_clicked", handle_prop)

func _close_screen() -> void:
	if file_job != null:
		file_job.cancel()
		return
	if preview_active:
		preview_active = false
		preview_state = {}
		var target := preview_return_route
		var context := preview_return_context.duplicate(true)
		preview_return_context = {}
		_show(target, context)
	elif route in ["episode", "mission"]:
		if _opened_from_room:
			app._close_modals()
			screen = null
		else:
			open_hub()
	else:
		app._close_modals()
		screen = null
		if is_in_gallery():
			if Collections.list_rooms(_state()).any(func(r): return str(r.get("template_id", "")) == "gallery_v1"):
				gallery.setup(_view({"room_id": gallery.room_id}), app.audio_service)
			else:
				leave_gallery()
	refresh_navigation()

func request_close() -> bool:
	if not is_instance_valid(screen) or screen.get_parent() != app.modal_container:
		return false
	if screen.has_method("_close"):
		screen._close()
	elif screen.has_method("_save_close"):
		screen._save_close()
	else:
		_close_screen()
	return true

func open_hub() -> void:
	if not bool(_state().get("puzzle_solved", false)):
		app.open_legacy_journal()
		return
	_opened_from_room = false
	_ensure_current_story_chapter()
	_show("hub")

func open_collection(extra: Dictionary = {}) -> void:
	_show("collection", extra)

func open_editor() -> void:
	_show("editor")

func open_family_tools() -> void:
	_show("family")

func open_episode(instance_id: String, stage_id: String) -> void:
	var inst: Dictionary = _state().get("phase_b", {}).get("quest_instances", {}).get(instance_id, {})
	if inst.is_empty():
		app.show_toast("Это прохождение не найдено.")
		return
	_show("episode", {"instance_id": instance_id, "stage_id": stage_id, "quest": inst.get("quest_snapshot", {})})

func open_quest(qid: String, instance_id: String = "") -> void:
	var inst := _ensure_instance(qid, instance_id)
	if inst.is_empty():
		return
	if not inst.get("quest_snapshot", {}).has("adventure"):
		app.open_quest_detail(inst.get("quest_snapshot", {}), inst)
		return
	var iid := str(inst.get("instance_id", ""))
	# First visit to a current mission: explain the story, the goal and the path
	# before the first question. Later visits go straight to the next step.
	if not preview_active and CURRENT_STORY_QUEST_IDS.has(qid) and not _briefed.has(qid) and (_mission_is_fresh(iid) or _mission_has_no_completed_stages(inst)):
		_show_mission(qid, inst)
		return
	var chosen := _next_open_stage(inst)
	if chosen.is_empty():
		if CURRENT_STORY_QUEST_IDS.has(qid):
			_show_mission(qid, inst)
		else:
			_show("hub", {"quest": inst.quest_snapshot, "history_quest_id": qid})
	else:
		open_episode(iid, chosen)

## Mission page: story, goal, path and payoff of one current mission.
func open_mission(qid: String, instance_id: String = "") -> void:
	var inst := _ensure_instance(qid, instance_id)
	if inst.is_empty():
		return
	if not inst.get("quest_snapshot", {}).has("adventure"):
		app.open_quest_detail(inst.get("quest_snapshot", {}), inst)
		return
	_show_mission(qid, inst)

## Dedicated screen for Maya's river and waterfall photo upload & Clara's reportage.
func open_water_photos(instance_id: String = "") -> void:
	var inst := _ensure_instance("FG08", instance_id)
	if inst.is_empty():
		return
	var iid := str(inst.get("instance_id", ""))
	_briefed["FG08"] = true
	_show("water_photos", {"instance_id": iid, "quest": inst.get("quest_snapshot", {})})

func _show_mission(qid: String, inst: Dictionary) -> void:
	_briefed[qid] = true
	_show("mission", {"instance_id": str(inst.get("instance_id", "")), "quest": inst.get("quest_snapshot", {})})

func _ensure_instance(qid: String, instance_id: String = "") -> Dictionary:
	if CURRENT_STORY_QUEST_IDS.has(qid):
		if not _ensure_current_story_chapter():
			return {}
	var inst: Dictionary = {}
	for existing in _state().get("phase_b", {}).get("quest_instances", {}).values():
		if str(existing.get("profile_id", "")) != "player_01" or existing.has("superseded_by_instance_id"):
			continue
		if (not instance_id.is_empty() and str(existing.get("instance_id", "")) == instance_id) or (instance_id.is_empty() and str(existing.get("quest_id", "")) == qid):
			inst = existing
	if inst.is_empty():
		var result := _run_command("start_adventure", {"quest_id": qid})
		if not bool(result.get("ok", false)):
			open_family_tools()
			_result(result)
			return {}
		inst = result.get("instance", {})
		if inst.is_empty():
			for existing in _state().get("phase_b", {}).get("quest_instances", {}).values():
				if str(existing.get("quest_id", "")) == qid and str(existing.get("profile_id", "")) == "player_01":
					inst = existing
	return inst

func _next_open_stage(inst: Dictionary) -> String:
	var iid := str(inst.get("instance_id", ""))
	for stage in inst.get("quest_snapshot", {}).get("adventure", {}).get("stages", []):
		var sid := str(stage.get("stage_id", ""))
		var status := str(UI.stage_progress(_state(), iid, sid).get("status", "AVAILABLE"))
		if status in ["AVAILABLE", "IN_PROGRESS", "AWAITING_REVIEW"]:
			return sid
	return ""

func _mission_has_no_completed_stages(inst: Dictionary) -> bool:
	var iid := str(inst.get("instance_id", ""))
	for stage in inst.get("quest_snapshot", {}).get("adventure", {}).get("stages", []):
		var sid := str(stage.get("stage_id", ""))
		if str(UI.stage_progress(_state(), iid, sid).get("status", "")) == "COMPLETED":
			return false
	return true

func _mission_is_fresh(iid: String) -> bool:
	var progress: Dictionary = _state().get("adventures", {}).get("progress", {}).get(iid, {})
	for record in progress.get("stages", {}).values():
		if str(record.get("status", "AVAILABLE")) not in ["AVAILABLE", "LOCKED"]:
			return false
		if not record.get("attempts", []).is_empty() or not record.get("draft", {}).is_empty():
			return false
	return true

func _ensure_current_story_chapter() -> bool:
	if preview_active:
		return true
	var result := _run_command("ensure_story_chapter", {})
	if not bool(result.get("ok", false)):
		_result(result)
		return false
	return true

func open_gallery(room_id: String = "") -> void:
	if not bool(_state().get("puzzle_solved", false)):
		app.show_toast("Галерея откроется, когда станция проснётся.")
		return
	if preview_active:
		open_collection()
		return
	var ensured := _run_command("ensure_gallery", {})
	if not bool(ensured.get("ok", false)):
		_result(ensured)
		return
	if str(ensured.get("room_id", "")).is_empty():
		if is_in_gallery(): leave_gallery()
		open_collection({"tab": 1})
		return
	app._close_modals()
	screen = null
	app.hud_root.visible = false
	if gallery != null:
		gallery.get_parent().remove_child(gallery)
		gallery.queue_free()
	gallery = load("res://scripts/presentation/gallery_room.gd").new()
	app.station_room.visible = false
	app.station_room.process_mode = Node.PROCESS_MODE_DISABLED
	if app.station_room.get_parent() == app:
		app.remove_child(app.station_room)
	app.add_child(gallery)
	_connect_screen(gallery)
	if gallery.has_signal("return_requested"):
		gallery.connect("return_requested", leave_gallery)
	if gallery.has_signal("slot_selected"):
		gallery.connect("slot_selected", func(rid: String, sid: String): open_collection({"room_id": rid, "slot_id": sid}))
	if gallery.has_signal("slot_requested"):
		gallery.connect("slot_requested", func(rid: String, sid: String): open_collection({"room_id": rid, "slot_id": sid}))
	gallery.setup(_view({"room_id": room_id}), app.audio_service)
	navigation_bar.visible = false
	refresh_navigation()

func leave_gallery() -> void:
	app._close_modals()
	screen = null
	app.hud_root.visible = true
	if is_instance_valid(gallery):
		gallery.get_parent().remove_child(gallery)
		gallery.queue_free()
	gallery = null
	if app.station_room.get_parent() == null:
		app.add_child(app.station_room)
	app.station_room.visible = true
	app.station_room.process_mode = Node.PROCESS_MODE_INHERIT
	app.station_room.camera.make_current()
	refresh_world()
	refresh_navigation()

func is_in_gallery() -> bool:
	return is_instance_valid(gallery)

func refresh_navigation() -> void:
	if not is_instance_valid(app):
		return
	var free: bool = app.modal_container.get_child_count() == 0
	if is_instance_valid(gallery) and gallery.has_method("set_navigation_enabled"):
		gallery.set_navigation_enabled(free)
	app.station_room.set_navigation_enabled(free and not is_in_gallery())

func refresh_world() -> void:
	if app == null:
		return
	_initialise()
	var view := {"awakened": bool(app.game_state.get("puzzle_solved", false)), "favourites": []}
	view["chapter_complete"] = bool(app.game_state.get("adventures", {}).get("chapters_by_profile", {}).get("player_01", {}).get("completed", false))
	for inst in app.game_state.get("phase_b", {}).get("quest_instances", {}).values():
		if str(inst.get("profile_id", "")) != "player_01":
			continue
		var qid := str(inst.get("quest_id", ""))
		var iid := str(inst.get("instance_id", ""))
		var completed := 0
		var stages: Array = inst.get("quest_snapshot", {}).get("adventure", {}).get("stages", [])
		for stage in stages:
			var sid := str(stage.get("stage_id", ""))
			if str(UI.stage_progress(app.game_state, iid, sid).get("status", "")) == "COMPLETED":
				completed += 1
				if sid == "water_river": view["river_done"] = true
				if sid == "water_fall": view["fall_done"] = true
		var quest_complete := str(inst.get("status", "")) == "COMPLETED" or (not stages.is_empty() and completed >= stages.size())
		var mission_progress: Dictionary = view.get("mission_progress", {})
		mission_progress[qid] = {"done": completed, "total": stages.size()}
		view["mission_progress"] = mission_progress
		if qid == "FG11":
			view["game_steps"] = completed
			view["workshop_complete"] = quest_complete
		if qid == "FG08":
			view["water_complete"] = quest_complete
			var r_path := _find_stage_image_path(iid, "water_river")
			var f_path := _find_stage_image_path(iid, "water_fall")
			if not r_path.is_empty(): view["river_image_path"] = r_path
			if not f_path.is_empty(): view["fall_image_path"] = f_path
			var inst_prog: Dictionary = app.game_state.get("adventures", {}).get("progress", {}).get(iid, {})
			if bool(inst_prog.get("water_photos_submitted", false)):
				view["water_photos_submitted"] = true
	for room in Collections.list_rooms(app.game_state):
		if str(room.get("template_id", "")) != "station_favorites":
			continue
		for slot in Collections.list_slots("station_favorites"):
			var item: Dictionary = {}
			for placement in Collections.list_placements(app.game_state, str(room.room_id)):
				if str(placement.slot_id) == str(slot.slot_id):
					var info := Collections.inspect_placement(app.game_state, placement)
					item = {"title": info.get("work", {}).get("title", "Моя работа"), "media_path": info.get("media_path", "")}
			view.favourites.append(item)
	app.station_room.apply_adventure_view(view)
	app.station_room.apply_phase_b_world_effects(preload("res://scripts/services/progress_service.gd").get_profile_world_effects(app.game_state.duplicate(true), "player_01"))
	if is_instance_valid(gallery_nav_button):
		gallery_nav_button.visible = bool(view.get("chapter_complete", false))
	if is_instance_valid(navigation_bar):
		navigation_bar.visible = bool(view.awakened) and not is_in_gallery()

func _find_stage_image_path(iid: String, sid: String) -> String:
	var progress: Dictionary = app.game_state.get("adventures", {}).get("progress", {}).get(iid, {})
	var stage_data: Dictionary = progress.get("stages", {}).get(sid, {})
	var artifact_id := str(stage_data.get("draft", {}).get("artifact_id", ""))
	if artifact_id.is_empty():
		for attempt in stage_data.get("attempts", []):
			var aid := str(attempt.get("evidence", {}).get("artifact_id", ""))
			if not aid.is_empty():
				artifact_id = aid
				break
	if not artifact_id.is_empty():
		return Artifacts.media_path_for(app.game_state, artifact_id)
	return ""

func handle_prop(id: String) -> bool:
	if not bool(app.game_state.get("puzzle_solved", false)):
		return false
	if id in ["radio", "adventure_workshop", "adventure_water"]:
		_opened_from_room = true
	match id:
		"radio": open_quest("FG01")
		"radio_weather": app._interact_radio()
		"adventure_workshop": open_quest("FG11")
		"arcade_cabinet":
			var inst := UI.instance_for(app.game_state, "FG11")
			if str(inst.get("status", "")) == "COMPLETED":
				app.audio_service.play_sfx("click_dial")
				app.show_toast("Твой игровой автомат работает! Запустить игру можно через терминал мастерской.")
			else:
				open_quest("FG11")
		"adventure_water":
			var inst := UI.instance_for(app.game_state, "FG08")
			var iid := str(inst.get("instance_id", ""))
			var inst_prog: Dictionary = app.game_state.get("adventures", {}).get("progress", {}).get(iid, {})
			var photos_submitted := bool(inst_prog.get("water_photos_submitted", false))
			var has_photos := not _find_stage_image_path(iid, "water_river").is_empty() or not _find_stage_image_path(iid, "water_fall").is_empty()
			if photos_submitted or has_photos or _briefed.get("FG08", false):
				open_water_photos()
			else:
				open_quest("FG08")
		"gallery_door": open_gallery("")
		_:
			if id.begins_with("station_favourite_"):
				for room in Collections.list_rooms(app.game_state):
					if str(room.get("template_id", "")) == "station_favorites":
						open_collection({"room_id": room.room_id, "slot_id": "favorite_%02d" % int(id.get_slice("_", 2))})
			elif id.begins_with("secret_"):
				var aliases := {"secret_station_star": "brass_stars", "secret_station_postcard": "postcard_back"}
				open_secret(str(aliases.get(id, id.trim_prefix("secret_"))))
			else:
				return false
	return true

func _result(result: Dictionary) -> void:
	if is_instance_valid(screen) and screen.has_method("show_result"):
		screen.show_result(result)
	elif is_in_gallery():
		gallery.show_result(result)
	else:
		app.show_toast(UI.result_text(result))

func _on_command(operation: String, payload: Dictionary) -> void:
	if operation == "preview_adventure":
		_preview_quest(payload.get("quest", {}))
		return
	if operation in ["prepare_learning_project", "open_learning_project", "open_starter_project", "register_game", "launch_work", "backup_export", "backup_import", "restore_local_snapshot", "attach_stage_media", "import_image", "migration_preview", "attach_water_photo", "submit_water_photos", "open_water_photos"]:
		_external_command(operation, payload)
		return
	var result := _run_command(operation, payload)
	_result(result)
	if bool(result.get("ok", false)):
		# The browser can navigate within its snapshot. Refresh its current view,
		# not the work/version that originally opened the screen.
		if route == "collection" and is_instance_valid(screen) and screen.has_method("navigation_context"):
			route_context.merge(screen.navigation_context(), true)
		if route == "collection" and operation in ["create_room", "restore_snapshot"]:
			route_context["room_id"] = str(result.get("room_id", ""))
			route_context["slot_id"] = ""
			route_context["tab"] = 1
		refresh_world()
		if operation == "stage_attempt" and bool(result.get("success", false)):
			app.audio_service.play_sfx("click_dial")
		if operation == "toggle_challenge_item":
			var Ritual = preload("res://scripts/services/ritual_service.gd")
			var checklist: Dictionary = Ritual.get_challenge_state(_state().duplicate(true)).get("today_checklist", {})
			var item_done := bool(checklist.get(str(payload.get("item_key", "")), false))
			var day_done: bool = Ritual.CHALLENGE_ITEMS.all(func(key): return bool(checklist.get(key, false)))
			if bool(result.get("newly_unlocked", false)):
				app.audio_service.play_sfx("chime_solve")
				app.audio_service.play_voice("bruno", "happy")
			elif day_done:
				app.audio_service.play_voice("bruno", "happy")
			elif item_done:
				app.audio_service.play_voice("bruno", "greet")
			else:
				app.audio_service.play_sfx("click_dial")
		if operation in ["stage_submit", "stage_review"] and bool(result.get("applied", false)) and not bool(result.get("awaiting_review", false)) and not bool(result.get("needs_revision", false)):
			app.audio_service.play_sfx("chime_solve")
			call_deferred("_present_pending")
		if operation in ["stage_submit", "stage_review", "publish_chapter", "pin_quest", "pause_adventure", "resume_adventure", "place_exhibit", "remove_placement", "create_room", "update_room", "delete_room", "snapshot_room", "restore_snapshot", "create_work", "create_exhibit", "add_work_version", "save_adventure_draft", "import_adventure_package", "publish_adventure", "chapter_finale", "toggle_challenge_item"]:
			if is_instance_valid(screen):
				screen.setup(_view(route_context), app.audio_service)
				_result(result)

func _run_command(operation: String, payload: Dictionary) -> Dictionary:
	# Filled by the service dispatcher; only this adapter persists UI operations.
	return _dispatch_command(operation, payload)

func _dispatch_command(operation: String, payload: Dictionary) -> Dictionary:
	if _read_only and not preview_active:
		return {"ok": false, "reason": "read_only_save", "message": "Сохранение создано более новой версией. Оно открыто только для чтения."}
	var candidate := _state().duplicate(true)
	var result := _mutate(candidate, operation, payload)
	if not bool(result.get("ok", false)):
		return result
	if preview_active:
		preview_state = candidate
	elif not Save.save_game(candidate):
		return {"ok": false, "reason": "save_failed", "message": "Не удалось сохранить. Результат не зачислен, черновик можно повторить."}
	else:
		app.game_state = candidate
	return result

func _mutate(candidate: Dictionary, operation: String, payload: Dictionary) -> Dictionary:
	match operation:
		"ensure_gallery":
			return Collections.ensure_gallery(candidate)
		"ensure_story_chapter":
			return _ensure_story_templates(candidate, "station_story")
		"publish_chapter":
			return _ensure_story_templates(candidate, "parent_local")
		"create_work":
			var result := Collections.create_work(candidate, payload)
			if bool(result.get("ok", false)):
				Collections.create_exhibit(candidate, str(result.work_id), "frame")
			return result
		"add_work_version":
			return Collections.add_version(candidate, str(payload.get("work_id", "")), payload.get("content", {}), str(payload.get("note", "")))
		"create_exhibit":
			return Collections.create_exhibit(candidate, str(payload.get("work_id", "")), str(payload.get("recipe_id", "frame")), str(payload.get("caption", "")))
		"create_room":
			return Collections.create_room(candidate, str(payload.get("name", "Мои открытия")), str(payload.get("theme", "warm")))
		"update_room":
			return Collections.update_room(candidate, str(payload.get("room_id", "")), payload)
		"delete_room":
			return Collections.delete_room(candidate, str(payload.get("room_id", "")), bool(payload.get("save_snapshot", true)))
		"place_exhibit":
			return Collections.place_exhibit(candidate, str(payload.get("room_id", "")), str(payload.get("slot_id", "")), str(payload.get("exhibit_id", "")), str(payload.get("version_id", "")), "player_01", {"caption": str(payload.get("caption", ""))})
		"remove_placement":
			return Collections.remove_placement(candidate, str(payload.get("room_id", "")), str(payload.get("slot_id", "")))
		"snapshot_room":
			return Collections.save_exhibition(candidate, str(payload.get("room_id", "")), str(payload.get("name", "")))
		"restore_snapshot":
			return Collections.restore_exhibition(candidate, str(payload.get("snapshot_id", "")), str(payload.get("room_id", "")))
		"save_adventure_draft":
			return Library.save_draft(candidate, payload.get("quest", {}))
		"validate_adventure":
			var checked := preload("res://scripts/domain/content_validation.gd").validate_quest(payload.get("quest", {}))
			return {"ok": bool(checked.get("valid", false)), "errors": checked.get("errors", []), "message": "Содержание проверено." if bool(checked.get("valid", false)) else "Исправьте отмеченные поля."}
		"publish_adventure":
			return Quest.approve_and_publish(candidate, payload.get("quest", {}))
		"import_adventure_package":
			return Library.import_package(candidate, payload.get("package", {}))
		"toggle_challenge_item":
			var Ritual = preload("res://scripts/services/ritual_service.gd")
			return Ritual.toggle_challenge_item(candidate, str(payload.get("item_key", "")))
	var core := load("res://scripts/services/adventure_service.gd")
	return core.dispatch(candidate, operation, payload, "player_01", _launcher().inspect_entry)

func _ensure_story_templates(candidate: Dictionary, approved_by: String) -> Dictionary:
	var published := Quest.list_player_quests(candidate)
	for q in _chapter_templates(candidate):
		var qid := str(q.get("quest_id", ""))
		var revision := int(q.get("revision", 0))
		var already_available := published.any(func(existing: Dictionary):
			return str(existing.get("quest_id", "")) == qid and int(existing.get("revision", 0)) == revision
		)
		if already_available:
			continue
		var ensured := Quest.approve_and_publish(candidate, q, approved_by)
		if not bool(ensured.get("ok", false)):
			return ensured
		published = Quest.list_player_quests(candidate)
	return {"ok": true, "message": "Три первые истории доступны на станции и в журнале."}

func open_secret(secret_id: String) -> void:
	var secret: Dictionary = {}
	for definition in Content.secrets():
		if str(definition.get("secret_id", "")) == secret_id:
			secret = definition
	if secret.is_empty():
		return
	app._close_modals()
	screen = Control.new()
	app.modal_container.add_child(screen)
	app.modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	var shell := UI.shell(screen, app.game_state, str(secret.title), "Маленькая находка станции", func(): app._close_modals())
	var card := UI.card(UI.scroll(shell.content), true)
	UI.label(str(secret.get("interaction", {}).get("prompt", "")), card, 24, UI.INK)
	var reveal := UI.column(card)
	reveal.visible = false
	for detail in secret.get("interaction", {}).get("config", {}).get("details", []):
		UI.label(str(detail.get("text", "")), reveal, 22, UI.INK)
	UI.button("Рассмотреть", card, func():
		var result := _run_command("discover_secret", {"secret_id": secret_id})
		if bool(result.get("ok", false)):
			reveal.visible = true
			shell.feedback.text = "Находка осталась в твоём архиве."
			shell.feedback.visible = true
		else:
			shell.feedback.text = UI.result_text(result)
			shell.feedback.visible = true, true)
	refresh_navigation()

func _preview_quest(quest: Dictionary) -> void:
	if quest.is_empty():
		_result({"ok": false, "message": "Выберите приключение для просмотра."})
		return
	preview_state = Save.get_default_state()
	preview_state.puzzle_solved = true
	preview_state.s00_progress.station_awakened = true
	# Isolated in-memory profile: no disk, no reference to the player's dictionaries.
	var published := Quest.approve_and_publish(preview_state, quest, "parent_preview")
	if not bool(published.get("ok", false)):
		_result(published)
		preview_state = {}
		return
	preview_return_route = "family" if route == "family" else "editor"
	preview_return_context = {}
	if route == "editor" and is_instance_valid(screen) and screen.has_method("session_context"):
		preview_return_context = screen.session_context()
	elif preview_return_route == "editor":
		preview_return_context = {"editor_quest":quest.duplicate(true)}
	preview_active = true
	_initialise_preview()
	open_quest(str(quest.quest_id))

func _initialise_preview() -> void:
	var core := load("res://scripts/services/adventure_service.gd")
	core.ensure_adventures(preview_state)
	Collections.ensure_gallery(preview_state)

func _launcher() -> RefCounted:
	if launch_service == null:
		launch_service = load("res://scripts/services/launch_service.gd").new()
	return launch_service

func _external_command(operation: String, payload: Dictionary) -> void:
	if preview_active:
		_result({"ok": false, "message": "В предпросмотре файлы и приложения не изменяются. Вернитесь к обычному прохождению."})
		return
	if _read_only and operation not in ["backup_import", "restore_local_snapshot", "backup_export"]:
		_result({"ok": false, "message": "Сохранение доступно только для чтения."})
		return
	match operation:
		"prepare_learning_project":
			_result(_launcher().prepare_starter_project())
		"open_learning_project", "open_starter_project":
			var result: Dictionary = _launcher().prepare_starter_project()
			if bool(result.get("ok", false)):
				var directory := str(result.get("project_dir", ""))
				if not directory.is_empty():
					OS.shell_open(directory)
			_result(result)
		"register_game":
			var source := str(payload.get("source_path", ""))
			var result: Dictionary
			if str(payload.get("kind", "godot_project")) == "application":
				result = _launcher().register_app(source, str(payload.get("title", "Моя игра")))
			else:
				result = _launcher().register_project(source.get_base_dir() if source.get_file() == "project.godot" else source, str(payload.get("title", "Моя игра")))
			if bool(result.get("ok", false)):
				var candidate: Dictionary = app.game_state.duplicate(true)
				var version_content := {"launch_entry_id": str(result.get("launch_entry_id", "")), "source_archive_file": str(result.get("source_archive_file", "")), "source_archive_kind": str(result.get("source_archive_kind", result.get("entry", {}).get("source_archive_kind", "project_source"))), "demonstration_only": bool(result.get("entry", {}).get("demonstration_only", false)), "note": "Сохранённая версия игры"}
				var created: Dictionary
				if not str(payload.get("work_id", "")).is_empty():
					created = Collections.add_version(candidate, str(payload.work_id), version_content, str(payload.get("title", "Новая сборка")))
					created["work_id"] = str(payload.work_id)
				else:
					created = Collections.create_work(candidate, {"title": str(payload.get("title", "Моя игра")), "kind": "game", "quest_ids": ["FG11"], "authorship": {"category": "family", "contribution": "Проверенная семейная версия. Свой вклад описан в приключении."}, "content": version_content})
				if bool(created.get("ok", false)):
					Collections.create_exhibit(candidate, str(created.work_id), "terminal")
					if Save.save_game(candidate):
						app.game_state = candidate
						result["work_id"] = created.work_id
					else:
						result = {"ok": false, "message": "Сборка сохранена, но карточка работы не записалась. Её можно привязать позже из мастерской."}
				else:
					result = created
			if bool(result.get("ok", false)):
				_show("family")
			_result(result)
		"launch_work":
			var launch_id := str(payload.get("launch_entry_id", ""))
			if launch_id.is_empty():
				var version := Collections.get_version(app.game_state, str(payload.get("work_id", "")), str(payload.get("version_id", "")))
				launch_id = str(version.get("content", {}).get("launch_entry_id", ""))
			var launched: Dictionary = _launcher().launch(launch_id)
			if bool(launched.get("ok", false)):
				launched_processes.append(int(launched.pid))
			_result(launched)
		"backup_export":
			var path := str(payload.get("directory", "")).path_join("SUR-family-" + Time.get_datetime_string_from_system().replace(":", "-"))
			_start_file_job("export", path)
		"backup_import":
			_preview_backup(str(payload.get("directory", "")))
		"restore_local_snapshot":
			_preview_local_restore(str(payload.get("path", "")))
		"attach_stage_media", "import_image":
			_attach_media(payload)
		"attach_water_photo":
			_attach_water_photo(payload)
		"submit_water_photos":
			_submit_water_photos(payload)
		"open_water_photos":
			open_water_photos(str(payload.get("instance_id", "")))
		"migration_preview":
			_migration_preview(str(payload.get("instance_id", "")))

func _poll_launches() -> void:
	for pid in launched_processes.duplicate():
		var status: Dictionary = _launcher().process_status(pid)
		if not bool(status.get("running", false)):
			launched_processes.erase(pid)
			if not bool(status.get("ok", false)):
				_result(status)

func _present_pending() -> void:
	if _read_only or preview_active:
		return
	var candidate: Dictionary = app.game_state.duplicate(true)
	var pending: Array = load("res://scripts/services/activity_commit_service.gd").pending_presentations(candidate)
	if pending.is_empty():
		return
	var titles: Array[String] = []
	for event in pending:
		var work := Collections.get_work(candidate, str(event.get("work_id", "")))
		if not work.is_empty():
			titles.append(str(work.title))
		candidate.adventures.pending_presentations[str(event.event_id)].shown = true
	_result({"ok": true, "message": "В твоём архиве: " + ", ".join(titles) + ". Можно выбрать место в галерее."})
	# Presentation acknowledgement never grants XP. A failed acknowledgement can
	# repeat this quiet reminder, while the completed result remains committed.
	if Save.save_game(candidate):
		app.game_state = candidate

func _attach_media(payload: Dictionary) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Изображения"])
	app.add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		var candidate: Dictionary = app.game_state.duplicate(true)
		var imported := Artifacts.import_local_image(candidate, path, "Моя работа")
		if bool(imported.get("ok", false)):
			var result: Dictionary
			if payload.has("work_id"):
				var previous := Collections.get_version(candidate, str(payload.work_id), str(payload.get("version_id", "")))
				var content: Dictionary = payload.get("content", previous.get("content", {})).duplicate(true)
				content["artifact_id"] = imported.artifact.artifact_id
				var change_note := str(payload.get("note", "")).strip_edges()
				result = Collections.add_version(candidate, str(payload.work_id), content, change_note if not change_note.is_empty() else "Прикреплено изображение")
			else:
				var draft: Dictionary = payload.get("draft", {}).duplicate(true)
				draft["artifact_id"] = imported.artifact.artifact_id
				result = _mutate(candidate, "stage_draft", {"instance_id": payload.get("instance_id", ""), "stage_id": payload.get("stage_id", ""), "draft": draft})
			if bool(result.get("ok", false)) and Save.save_game(candidate):
				app.game_state = candidate
				var context := route_context.duplicate(true)
				if payload.has("work_id"):
					context["work_id"] = str(payload.work_id)
					context["version_id"] = str(result.version_id)
				_show(route, context)
				_result({"ok": true, "message": "Изображение сохранено вместе с черновиком."})
			else:
				_result({"ok": false, "message": "Не удалось сохранить вложение. Исходный файл остался на месте."})
		else:
			_result(imported)
		dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered_ratio(0.8)

func _attach_water_photo(payload: Dictionary) -> void:
	var target := str(payload.get("target", "river"))
	if payload.has("path") and not str(payload.path).is_empty():
		_process_water_photo(target, str(payload.path), payload)
		return
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Изображения"])
	app.add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		_process_water_photo(target, path, payload)
		dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered_ratio(0.8)

func _process_water_photo(target: String, path: String, payload: Dictionary) -> void:
	var candidate: Dictionary = app.game_state.duplicate(true)
	var title := "Фото реки Río Azul · Майя" if target == "river" else "Фото водопада Cascada Escondida · Майя"
	var imported := Artifacts.import_local_image(candidate, path, title)
	if bool(imported.get("ok", false)):
		var artifact_id: String = imported.artifact.artifact_id
		var iid := str(payload.get("instance_id", ""))
		if iid.is_empty():
			iid = str(UI.instance_for(candidate, "FG08").get("instance_id", ""))
		var stage_id := "water_river" if target == "river" else "water_fall"
		_apply_stage_artifact(candidate, iid, stage_id, artifact_id, path)
		if payload.has("river_note") and not str(payload.river_note).strip_edges().is_empty():
			candidate.adventures.progress[iid].stages["water_river"].draft["note"] = str(payload.river_note).strip_edges()
		if payload.has("fall_note") and not str(payload.fall_note).strip_edges().is_empty():
			candidate.adventures.progress[iid].stages["water_fall"].draft["note"] = str(payload.fall_note).strip_edges()
		if payload.has("diff_note") and not str(payload.diff_note).strip_edges().is_empty():
			if not candidate.adventures.progress[iid].stages.has("water_compare"):
				candidate.adventures.progress[iid].stages["water_compare"] = {"stage_id": "water_compare", "status": "IN_PROGRESS", "draft": {}, "attempts": []}
			candidate.adventures.progress[iid].stages["water_compare"].draft["note"] = str(payload.diff_note).strip_edges()
		var loc_id := "rio_azul" if target == "river" else "waterfalls"
		AtlasService.unlock(candidate, loc_id)
		if Save.save_game(candidate):
			app.game_state = candidate
			refresh_world()
			if route == "water_photos" and is_instance_valid(screen):
				screen.setup(_view(route_context), app.audio_service)
			elif route == "episode" and is_instance_valid(screen):
				screen.setup(_view(route_context), app.audio_service)
			_result({"ok": true, "message": "Фотография сохранена: %s ✓" % ("река" if target == "river" else "водопад")})
		else:
			_result({"ok": false, "message": "Не удалось сохранить фотографию."})
	else:
		_result(imported)

func _apply_stage_artifact(candidate: Dictionary, iid: String, stage_id: String, artifact_id: String, original_path: String = "") -> void:
	if iid.is_empty():
		return
	if not candidate.has("adventures"):
		candidate["adventures"] = {}
	if not candidate.adventures.has("progress"):
		candidate.adventures["progress"] = {}
	if not candidate.adventures.progress.has(iid):
		candidate.adventures.progress[iid] = {"instance_id": iid, "stages": {}}
	var inst_prog: Dictionary = candidate.adventures.progress[iid]
	if not inst_prog.has("stages"):
		inst_prog["stages"] = {}
	if not inst_prog.stages.has(stage_id):
		inst_prog.stages[stage_id] = {"stage_id": stage_id, "status": "IN_PROGRESS", "draft": {}, "attempts": []}
	var stage_data: Dictionary = inst_prog.stages[stage_id]
	if not stage_data.has("draft"):
		stage_data["draft"] = {}
	stage_data.draft["artifact_id"] = artifact_id
	if not original_path.is_empty():
		stage_data.draft["source_path"] = original_path
	if str(stage_data.get("status", "LOCKED")) == "LOCKED":
		stage_data["status"] = "IN_PROGRESS"

func _submit_water_photos(payload: Dictionary) -> void:
	var candidate: Dictionary = app.game_state.duplicate(true)
	var iid := str(payload.get("instance_id", ""))
	if iid.is_empty():
		iid = str(UI.instance_for(candidate, "FG08").get("instance_id", ""))
	if iid.is_empty():
		_result({"ok": false, "message": "Миссия не найдена."})
		return

	var r_note := str(payload.get("river_note", "")).strip_edges()
	var f_note := str(payload.get("fall_note", "")).strip_edges()
	var d_note := str(payload.get("diff_note", "")).strip_edges()

	if not candidate.has("adventures"): candidate["adventures"] = {}
	if not candidate.adventures.has("progress"): candidate.adventures["progress"] = {}
	if not candidate.adventures.progress.has(iid): candidate.adventures.progress[iid] = {"instance_id": iid, "stages": {}}
	var inst_prog: Dictionary = candidate.adventures.progress[iid]
	if not inst_prog.has("stages"): inst_prog["stages"] = {}

	if not inst_prog.stages.has("water_river"):
		inst_prog.stages["water_river"] = {"stage_id": "water_river", "status": "IN_PROGRESS", "draft": {}, "attempts": []}
	if not r_note.is_empty():
		inst_prog.stages["water_river"]["draft"]["note"] = r_note
		if not inst_prog.stages["water_river"]["draft"].has("responses"):
			inst_prog.stages["water_river"]["draft"]["responses"] = {}
		inst_prog.stages["water_river"]["draft"]["responses"]["water_river_return"] = {"fields": {"observation": r_note}}

	if not inst_prog.stages.has("water_fall"):
		inst_prog.stages["water_fall"] = {"stage_id": "water_fall", "status": "IN_PROGRESS", "draft": {}, "attempts": []}
	if not f_note.is_empty():
		inst_prog.stages["water_fall"]["draft"]["note"] = f_note
		if not inst_prog.stages["water_fall"]["draft"].has("responses"):
			inst_prog.stages["water_fall"]["draft"]["responses"] = {}
		inst_prog.stages["water_fall"]["draft"]["responses"]["water_fall_return"] = {"fields": {"observation": f_note}}

	if not inst_prog.stages.has("water_compare"):
		inst_prog.stages["water_compare"] = {"stage_id": "water_compare", "status": "IN_PROGRESS", "draft": {}, "attempts": []}
	if not d_note.is_empty():
		inst_prog.stages["water_compare"]["draft"]["note"] = d_note
		if not inst_prog.stages["water_compare"]["draft"].has("responses"):
			inst_prog.stages["water_compare"]["draft"]["responses"] = {}
		inst_prog.stages["water_compare"]["draft"]["responses"]["water_compare_pages"] = {"fields": {"difference": d_note}}

	var silent := bool(payload.get("silent", false))
	if not silent:
		inst_prog["water_photos_submitted"] = true
	AtlasService.unlock(candidate, "rio_azul")
	AtlasService.unlock(candidate, "waterfalls")

	if Save.save_game(candidate):
		app.game_state = candidate
		refresh_world()
		if route == "water_photos" and is_instance_valid(screen):
			screen.setup(_view(route_context), app.audio_service)
			if not silent and screen.has_method("show_clara_submission_success"):
				screen.show_clara_submission_success()
		if not silent:
			_result({"ok": true, "message": "Снимки переданы Кларе! Героиня появится позже."})
	else:
		_result({"ok": false, "message": "Не удалось сохранить фоторепортаж."})

func _preview_backup(directory: String) -> void:
	# Apply the same bounded JSON read as the worker before using preview fields.
	var manifest := preload("res://scripts/services/backup_service.gd")._read_json(directory.path_join("manifest.json"))
	if manifest.get("format", "") != "sur_family_backup" or manifest.get("version", 0) != 1 or not manifest.get("media") is Array or not manifest.get("launch_media", []) is Array:
		_result({"ok": false, "message": "В выбранной папке нет полной семейной копии SUR."})
		return
	_restore_confirmation("Копия от %s. Изображений: %d. Файлов проектов: %d." % [manifest.get("created_at", ""), manifest.get("media", []).size(), manifest.get("launch_media", []).size()], func():
		_start_file_job("import", directory))

func _start_file_job(mode: String, directory: String) -> void:
	if file_job != null: return
	file_job = load("res://scripts/services/local_file_job.gd").new()
	file_job_mode = mode
	app._close_modals()
	screen = Control.new()
	app.modal_container.add_child(screen)
	app.modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	var shell := UI.shell(screen, app.game_state, "Семейная копия", "Файлы проверяются и копируются. Прогресс игры изменится только после успешного восстановления.", func(): file_job.cancel())
	file_job_label = UI.label("Подготавливаем файлы…", shell.content)
	file_job_progress = ProgressBar.new()
	file_job_progress.custom_minimum_size.y = 24
	shell.content.add_child(file_job_progress)
	UI.button("Отменить", shell.content, func(): file_job.cancel())
	var error: Error = file_job.start_export(app.game_state, directory) if mode == "export" else file_job.start_import(directory)
	if error != OK:
		file_job = null
		open_family_tools()
		_result({"ok": false, "message": "Не удалось начать копирование файлов."})

func _poll_file_job() -> void:
	if file_job == null: return
	var status: Dictionary = file_job.snapshot()
	if is_instance_valid(file_job_label):
		file_job_label.text = "Отменяем, текущий прогресс сохранён…" if bool(status.cancelled) else "Файлы: %d / %d" % [int(status.done), int(status.total)]
		file_job_progress.value = 100.0 * float(status.done) / maxi(1, int(status.total))
	if not file_job.poll(): return
	var result: Dictionary = file_job.result
	var mode := file_job_mode
	file_job = null
	if mode == "import" and bool(result.get("ok", false)) and not bool(status.cancelled):
		_finish_restore(Save.restore_snapshot(result.state))
		return
	open_family_tools()
	if bool(status.cancelled) or str(result.get("reason", "")) == "cancelled":
		_result({"ok": true, "message": "Копирование отменено. Текущий прогресс не изменён."})
	else:
		if bool(result.get("ok", false)):
			result.message = "Полная копия сохранена: " + str(result.get("backup_path", ""))
		_result(result)

func _preview_local_restore(path: String) -> void:
	var found := false
	for entry in Save.list_recovery_snapshots():
		if str(entry.path) == path and bool(entry.get("supported", false)):
			found = true
	if not found:
		_result({"ok": false, "message": "Эта резервная копия недоступна для восстановления."})
		return
	_restore_confirmation("Локальный снимок: " + path.get_file(), func(): _finish_restore(Save.restore_from_backup(path)))

func _restore_confirmation(description: String, restore: Callable) -> void:
	app._close_modals()
	screen = Control.new()
	app.modal_container.add_child(screen)
	app.modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	var shell := UI.shell(screen, app.game_state, "Восстановить семейную копию", description, open_family_tools)
	var body := UI.scroll(shell.content)
	UI.label("Выбранная копия заменит текущий прогресс. Перед восстановлением SUR отдельно сохранит нынешний файл. Работы и исходники восстановятся; запуск игры на этом компьютере нужно зарегистрировать заново.", body)
	UI.button("Восстановить выбранную копию", body, restore, true)
	UI.button("Оставить текущий прогресс", body, open_family_tools)

func _finish_restore(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_result(result)
		return
	if is_in_gallery():
		leave_gallery()
	app.game_state = result.state
	_read_only = false
	_initialised = false
	app._apply_state_to_world()
	app._apply_settings(app.game_state.get("settings", {}))
	open_family_tools()
	_result({"ok": true, "message": "Копия восстановлена. Предыдущий файл сохранён отдельно."})

func _migration_preview(instance_id: String) -> void:
	var old: Dictionary = app.game_state.get("phase_b", {}).get("quest_instances", {}).get(instance_id, {})
	var replacement: Dictionary = _migration_targets(app.game_state).get(str(old.get("quest_id", "")), {})
	if old.is_empty() or replacement.is_empty() or int(replacement.get("revision", 0)) <= int(old.get("revision", 0)):
		_result({"ok": false, "message": "Более новой версии для переноса пока нет."})
		return
	app._close_modals()
	screen = Control.new()
	app.modal_container.add_child(screen)
	app.modal_container.mouse_filter = Control.MOUSE_FILTER_STOP
	var shell := UI.shell(screen, app.game_state, "Перенос в новую историю", "Прежняя запись и уже полученный опыт останутся в архиве.", open_family_tools)
	var body := UI.scroll(shell.content)
	var budget := int(old.get("quest_snapshot", {}).get("reward_policy", {}).get("activity_budget", 0))
	var awarded := int(old.get("awarded_budget", 0))
	UI.label("Версия %d → %d. Уже получено %d XP; на продолжение остаётся не более %d XP." % [int(old.revision), int(replacement.revision), awarded, maxi(0, budget-awarded)], body, 20, UI.BRASS)
	UI.label("Сопоставьте конкретные подтверждённые действия. Незаполненные шаги останутся доступными. Общий статус начатой миссии не означает, что её новые этапы уже выполнены.", body)
	var source_ids: Array = [""]
	var source_labels: Array = ["Пройти этот шаг в новой истории"]
	var sources: Dictionary = {}
	var source_progress: Dictionary = app.game_state.get("adventures", {}).get("progress", {}).get(instance_id, {}).get("stages", {})
	for stage in old.get("quest_snapshot", {}).get("adventure", {}).get("stages", []):
		var sid := str(stage.get("stage_id", ""))
		if str(source_progress.get(sid, {}).get("status", "")) == "COMPLETED":
			source_ids.append(sid)
			source_labels.append("Зачтённый шаг: " + str(stage.title))
			sources[sid] = sid
	if not old.get("quest_snapshot", {}).has("adventure"):
		for activity in app.game_state.get("phase_b", {}).get("activities", {}).values():
			if str(activity.get("instance_id", "")) == instance_id and str(activity.get("status", "")) == "CONFIRMED":
				var aid := str(activity.activity_id)
				source_ids.append(aid)
				source_labels.append("Подтверждённая запись: " + str(activity.get("note", "Веха %d" % (int(activity.get("milestone_index", 0))+1))).substr(0,100))
				sources[aid] = {"source_activity_id": aid, "note": "Сопоставлено вместе при переносе"}
	var pickers: Dictionary = {}
	for stage in replacement.get("adventure", {}).get("stages", []):
		UI.label(str(stage.get("title", "")), body, 18, UI.BRASS)
		for criterion in stage.get("criteria", []):
			UI.label("• " + str(criterion), body, 14, UI.MUTED)
		pickers[str(stage.stage_id)] = UI.option(body, source_labels)
	if sources.is_empty():
		UI.label("Отдельных подтверждённых действий пока нет. Сохраним прежние материалы и начнём новые шаги без предположений о выполненной работе.", body)
	UI.button("Подтвердить перенос и открыть эту версию", body, func():
		var mapping: Dictionary = {}
		for sid in pickers:
			var selected := str(source_ids[pickers[sid].selected])
			if not selected.is_empty(): mapping[sid] = sources[selected]
		var candidate: Dictionary = app.game_state.duplicate(true)
		var result := Quest.approve_and_publish(candidate, replacement)
		if bool(result.get("ok", false)):
			result = load("res://scripts/services/adventure_service.gd").migrate_instance(candidate, instance_id, int(replacement.revision), mapping)
		if bool(result.get("ok", false)) and Save.save_game(candidate):
			app.game_state = candidate
			open_quest(str(replacement.quest_id), str(result.instance.instance_id))
		else:
			_result(result if not bool(result.get("ok", false)) else {"ok": false, "reason": "save_failed"}), true)
	UI.button("Остаться в прежней истории", body, open_family_tools)

func _exit_tree() -> void:
	# Temporary developer copies disappear on exit. Stop their registered games
	# first; Godot's OS.create_process may detach them from the parent's group.
	if bool(ProjectSettings.get_setting("sur/developer_session", false)):
		for pid in launched_processes:
			if OS.is_process_running(pid):
				OS.kill(pid)
		launched_processes.clear()
	if file_job != null:
		file_job.stop()
		file_job = null
	if is_instance_valid(app) and is_instance_valid(app.station_room) and app.station_room.get_parent() == null:
		app.station_room.free()
