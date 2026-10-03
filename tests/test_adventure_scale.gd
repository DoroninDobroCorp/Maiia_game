extends SceneTree

## Metadata benchmark: no images are created/decoded and no profile is loaded.
## Run in an isolated project/user directory, like the acceptance test suite.
const Save = preload("res://scripts/services/save_service.gd")
const Library = preload("res://scripts/services/content_library_service.gd")
const Content = preload("res://scripts/services/adventure_content.gd")
const Quests = preload("res://scripts/services/quest_service.gd")
const Adventures = preload("res://scripts/services/adventure_service.gd")
const Collections = preload("res://scripts/services/collection_service.gd")
const Artifact = preload("res://scripts/services/artifact_service.gd")
const SAMPLE_COUNT := 7
const OPEN_BUDGET_MS := 500.0
const FILTER_BUDGET_MS := 200.0
var failures: Array[String] = []
var state: Dictionary = {}
var measurements: Dictionary = {}

func _init() -> void:
	Artifact.use_test_storage(OS.get_environment("TMPDIR").path_join("sur_scale_no_media_" + str(Time.get_ticks_usec())))
	var setup_start := Time.get_ticks_usec()
	_build_fixture()
	var setup_ms := float(Time.get_ticks_usec() - setup_start) / 1000.0
	_check(state.phase_b.published_versions.size() == 100, "100 published synthetic quests")
	_check(state.phase_b.quest_instances.size() == 30, "30 active or paused instances")
	_check(state.collections.works.size() == 1000, "1000 works with three versions each")
	_check(state.collections.rooms.size() == 20, "20 gallery rooms")
	var before := JSON.stringify(state).sha256_text()
	_measure("parent_catalog", func(): return Library.list_parent_templates(state), OPEN_BUDGET_MS, 138)
	_measure("adventure_catalog", func(): return Adventures.list_adventures(state), OPEN_BUDGET_MS, 100)
	_measure("archive_all_metadata", func(): return Collections.list_works(state), OPEN_BUDGET_MS, 1000)
	_measure("archive_first_page", func(): return Collections.list_works(state, "player_01", {"offset": 0, "limit": 40}), OPEN_BUDGET_MS, 40)
	_measure("adventure_filter", func(): return Adventures.list_adventures(state, "player_01", {"search": "Scale mission 009"}), FILTER_BUDGET_MS, 10)
	_measure("archive_filter", func(): return Collections.list_works(state, "player_01", {"search": "Scale work 009", "limit": 40}), FILTER_BUDGET_MS, 10)
	_measure("rooms_metadata", func(): return Collections.list_rooms(state), OPEN_BUDGET_MS, 20)
	_measure("room_placements", func(): return Collections.list_placements(state, "gallery:player_01:1"), FILTER_BUDGET_MS, 6)
	_check(JSON.stringify(state).sha256_text() == before, "catalog/filter queries preserve all progress and rewards")
	var report := {
		"machine": OS.get_model_name(), "processor": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"os": OS.get_name(), "os_version": OS.get_version(), "godot": Engine.get_version_info().get("string", ""),
		"measured_at_utc": Time.get_datetime_string_from_system(true), "sample_count": SAMPLE_COUNT,
		"fixtures": {"quests": 100, "instances": 30, "works": 1000, "work_versions": 3000, "rooms": 20, "placements": 120},
		"mode": "headless metadata only; no media decode or rendering", "setup_ms": setup_ms,
		"budgets_ms": {"open": OPEN_BUDGET_MS, "filter": FILTER_BUDGET_MS}, "measurements": measurements,
		"passed": failures.is_empty(), "failures": failures
	}
	var report_path := OS.get_environment("TMPDIR").path_join("sur_adventure_scale_report_" + str(Time.get_ticks_usec()) + ".json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("SCALE_METRICS ", JSON.stringify(report))
	print("SCALE_REPORT ", report_path)
	print("ADVENTURE SCALE: ", "PASS" if failures.is_empty() else "FAIL")
	Artifact.restore_default_storage()
	quit(0 if failures.is_empty() else 1)

func _build_fixture() -> void:
	state = Save.get_default_state()
	state.s00_progress.station_awakened = true
	var definitions := Content.quests()
	for index in range(100):
		var quest: Dictionary = definitions[index % definitions.size()].duplicate(true)
		quest.quest_id = "SCALE%03d" % index
		quest.title = "Scale mission %04d" % index
		quest.story_title = quest.title
		quest.revision = 1
		var draft := Library.save_draft(state, quest)
		var publication := Quests.approve_and_publish(state, quest)
		if not bool(draft.get("ok", false)) or not bool(publication.get("ok", false)):
			failures.append("fixture publication failed: " + str(index) + " " + str(publication))
		if index < 30:
			var created := Quests.create_instance(state, quest.quest_id, 1, "home")
			if not bool(created.get("ok", false)):
				failures.append("fixture instance failed: " + str(index))
				continue
			var attached := Adventures.ensure_instance(state, str(created.instance.instance_id))
			if not attached.ok:
				failures.append("fixture adventure failed: " + str(index))
			if index % 2 == 0:
				Quests.pause_instance(state, str(created.instance.instance_id))
	for index in range(1000):
		var artifact_id := "scale_artifact_%04d" % index
		state.phase_b.artifacts[artifact_id] = {"artifact_id": artifact_id, "profile_id": "player_01", "media_file": artifact_id + ".png", "kind": "local_image", "media_deleted": false}
		var work := Collections.create_work(state, {"work_id": "scale_work_%04d" % index,
			"title": "Scale work %04d" % index, "kind": "image", "status": "COMPLETED",
			"quest_ids": ["SCALE%03d" % (index % 100)], "content": {"artifact_id": artifact_id, "note": "A synthetic metadata record. ".repeat(4)}})
		if not work.ok:
			failures.append("fixture work failed: " + str(index))
			continue
		Collections.add_version(state, work.work_id, {"artifact_id": artifact_id, "note": "Second immutable version"}, "Second version")
		Collections.add_version(state, work.work_id, {"artifact_id": artifact_id, "note": "Third immutable version"}, "Third version")
	for index in range(20):
		var room := Collections.create_room(state, "Scale room %02d" % index)
		if not room.ok:
			failures.append("fixture room failed: " + str(index))
			continue
		for slot in range(6):
			var work_id := "scale_work_%04d" % (index * 6 + slot)
			var exhibit := Collections.create_exhibit(state, work_id)
			var placed := Collections.place_exhibit(state, room.room_id, "frame_%02d" % (slot + 1), exhibit.exhibit_id)
			if not placed.ok:
				failures.append("fixture placement failed: " + str(index))

func _check(condition: bool, name: String) -> void:
	if condition:
		print("[PASS] ", name)
	else:
		print("[FAIL] ", name)
		failures.append(name)

func _measure(label: String, query: Callable, budget_ms: float, expected_count: int) -> void:
	# Record first-use time independently; budget checks cover every warm sample.
	var start := Time.get_ticks_usec()
	var first: Array = query.call()
	var first_ms := float(Time.get_ticks_usec() - start) / 1000.0
	_check(first.size() == expected_count, label + " result count " + str(first.size()))
	var samples: Array[float] = []
	for _sample in range(SAMPLE_COUNT):
		start = Time.get_ticks_usec()
		query.call()
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	var maximum: float = samples.back()
	measurements[label] = {"first_ms": first_ms, "median_ms": samples[SAMPLE_COUNT / 2], "max_ms": maximum, "budget_ms": budget_ms, "result_count": first.size()}
	_check(first_ms <= budget_ms and maximum <= budget_ms, "%s first %.2f / max %.2f ms <= %.0f ms" % [label, first_ms, maximum, budget_ms])
