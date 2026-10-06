extends SceneTree

const RitualService = preload("res://scripts/services/ritual_service.gd")
const ContentRepo = preload("res://scripts/services/content_repository.gd")
const ProgressService = preload("res://scripts/services/progress_service.gd")
const StationRoom = preload("res://scripts/presentation/station_room.gd")
const StationAdventureProps = preload("res://scripts/presentation/station_adventure_props.gd")
const AdventureHub = preload("res://scripts/presentation/adventure_hub.gd")
const SaveService = preload("res://scripts/services/save_service.gd")

func _init() -> void:
	print("==================================================")
	print("  SUR — Maya 30-day streak & Chronicle Test Suite")
	print("==================================================")

	# --- 1. RITUAL SERVICE & STREAK LOGIC ---
	var state := SaveService.get_default_state()
	var c := RitualService.ensure_challenge(state)
	assert(c.current_streak == 0, "Initial streak must be 0")
	assert(c.target_days == 30, "Target days must be 30")
	assert(c.unlocked == false, "Initial unlocked must be false")
	assert(c.today_checklist.size() == 6, "Checklist must have 6 items")
	print("[PASS] 1. Challenge initialization in default state")

	# Date math
	assert(RitualService.days_between("2026-10-01", "2026-10-02") == 1, "days_between adjacent")
	assert(RitualService.days_between("2026-10-01", "2026-10-05") == 4, "days_between 4 days")
	assert(RitualService.days_between("2026-10-02", "2026-10-01") == -1, "days_between negative")
	print("[PASS] 2. Date difference helper")

	# Toggle item
	var t_res := RitualService.toggle_challenge_item(state, "morning_run")
	assert(t_res.ok == true, "toggle morning_run succeeds")
	assert(t_res.today_checklist.morning_run == true, "morning_run is checked")
	assert(t_res.all_done_today == false, "day not done yet with 1/6 items")
	print("[PASS] 3. Toggle single item")

	# Toggle remaining 5 items for today
	for item_name in ["evening_stretch", "spanish_1", "spanish_2", "spanish_3", "spanish_4"]:
		RitualService.toggle_challenge_item(state, item_name)
	var c_done := RitualService.get_challenge_state(state)
	assert(c_done.current_streak == 1, "Day 1 complete -> streak 1")
	assert(c_done.max_streak == 1, "Max streak 1")
	var today_str := Time.get_date_string_from_system()
	assert(c_done.last_completed_date == today_str, "last_completed_date updated to today")
	print("[PASS] 4. All 6 items checked -> streak 1")

	# Untoggle and retoggle
	RitualService.toggle_challenge_item(state, "spanish_4")
	assert(RitualService.get_challenge_state(state).current_streak == 0, "Unchecking item reverts streak")
	RitualService.toggle_challenge_item(state, "spanish_4")
	assert(RitualService.get_challenge_state(state).current_streak == 1, "Re-checking item restores streak")
	print("[PASS] 5. Untoggle and retoggle streak handling")

	# Test 30 days unlock
	# Simulate 29 completed days
	var streak_data: Dictionary = state.phase_c.rituals.maya_30_streak
	streak_data.current_streak = 29
	# Make last_completed_date yesterday
	var yesterday_unix := Time.get_unix_time_from_datetime_string(today_str + "T00:00:00") - 86400
	var yesterday_dict := Time.get_date_dict_from_unix_time(yesterday_unix)
	var yesterday_str := "%04d-%02d-%02d" % [yesterday_dict.year, yesterday_dict.month, yesterday_dict.day]
	streak_data.last_completed_date = yesterday_str
	streak_data.today_checklist = {
		"morning_run": true, "evening_stretch": true,
		"spanish_1": true, "spanish_2": true, "spanish_3": true, "spanish_4": false
	}
	streak_data.history.erase(today_str)

	# Checking 6th item triggers 30th day unlock
	var res30 := RitualService.toggle_challenge_item(state, "spanish_4")
	assert(res30.current_streak == 30, "Current streak reaches 30")
	assert(res30.unlocked == true, "Challenge unlocked at 30 days")
	assert(res30.newly_unlocked == true, "newly_unlocked is true")

	var effects: Array = ProgressService.get_profile_world_effects(state, "player_01")
	assert(effects.has("challenge_30_board"), "challenge_30_board effect awarded")
	assert(effects.has("challenge_30_light"), "challenge_30_light effect awarded")
	print("[PASS] 6. 30-day completion awards world effects")

	# --- 2. STATION ROOM & 3D PLAQUE ---
	var room := StationRoom.new()
	# Call _setup_phase_b_effects directly to test plaque nodes
	room._setup_phase_b_effects()
	assert(room.challenge_board_marker != null, "challenge_board_marker exists")
	assert(room.challenge_board_light != null, "challenge_board_light exists")
	assert(room.challenge_board_marker.visible == false, "Initially invisible")

	room.apply_phase_b_world_effects(effects)
	assert(room.challenge_board_marker.visible == true, "challenge_board_marker visible after unlock")
	assert(room.challenge_board_light.light_energy > 0.0, "challenge_board_light glows after unlock")
	assert(room.phase_b_unlock_label.text.contains("30 DÍAS"), "Token 30 DÍAS visible on field archive panel")
	print("[PASS] 7. 3D Station plaque and light activate properly")
	room.free()

	# --- 3. STATION ADVENTURE PROPS & WATER PHOTOS ---
	var props := StationAdventureProps.new()
	props._build()
	assert(props.water_panels.size() == 2, "2 water panels exist in diptych")
	# View with river_done and photos
	var adv_view := {
		"awakened": true,
		"water_complete": false,
		"river_done": true,
		"fall_done": false,
		"mission_progress": {"FG08": {"done": 3, "total": 6}}
	}
	props.apply_view(adv_view)
	assert(props.water_result.visible == true, "Diptych visible when river is done")
	assert(props.water_panels[0].visible == true, "River panel visible when river is done")
	print("[PASS] 8. Water diptych panel reacts to observation")
	props.free()

	# --- 4. ADVENTURE HUB & CHRONICLE ---
	state.puzzle_solved = true
	var hub := AdventureHub.new()
	hub.setup(state)
	# Check tabs exist
	var tabs_row := hub.find_children("*", "Button", true, false)
	var tab_labels: Array[String] = []
	for b in tabs_row:
		tab_labels.append(b.text)
	assert(tab_labels.has("Летопись станции"), "Tab 'Летопись станции' is present")
	assert(tab_labels.has("Сейчас"), "Tab 'Сейчас' is present")

	# Test building Chronicle tab directly
	hub.current_tab = 1
	hub._build()
	var hub_text := ""
	for l in hub.find_children("*", "Label", true, false):
		hub_text += " " + l.text
	assert(hub_text.contains("Завершённые дела"), "Chronicle header is rendered")
	# With puzzle_solved=true in state, Prologue is in chronicle
	assert(hub_text.contains("Пробуждение станции"), "S00 Prologue must be in chronicle")
	# Unfinished missions must NOT be in chronicle!
	assert(not hub_text.contains("Автомат для станции"), "Unfinished FG11 must not be in chronicle")
	assert(not hub_text.contains("Два голоса воды"), "Unfinished FG08 must not be in chronicle")
	print("[PASS] 9. AdventureHub Chronicle tab renders ONLY completed milestones")
	hub.free()

	print("==================================================")
	print("  ALL MAYA FEATURE TESTS PASSED (9/9 checks)")
	print("==================================================")
	quit()
