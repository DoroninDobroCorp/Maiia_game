extends SceneTree
## Standalone acceptance suite. No SaveService, autoloads, profiles or user:// writes.
## check.py stages this script inside a temporary independent Godot project.

var passed: int = 0
var failed: int = 0
var won_events: int = 0
var collection_events: int = 0
var base: String = "res://"
var State: GDScript

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("[PASS] ", description)
	else:
		failed += 1
		printerr("[FAIL] ", description)

func _run() -> void:
	if not FileAccess.file_exists("res://game_state.gd"):
		printerr("Run: python3 learning_projects/station_light/tools/check.py")
		quit(1)
		return
	State = load(base.path_join("game_state.gd"))
	_check(State != null and State.can_instantiate(), "Learning game script loads independently")
	if State == null or not State.can_instantiate():
		quit(1)
		return
	_test_rules()
	_test_stages()
	await _test_scene()
	print("LEARNING GAME: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _walk_to(game, index: int) -> void:
	var displacement: Vector2 = game.light_positions[index] - game.hero_position
	game.move_hero(displacement.normalized(), displacement.length() / game.speed)

func _test_rules() -> void:
	var game = State.new()
	game.won.connect(func() -> void: won_events += 1)
	game.light_collected.connect(func(_index: int, _count: int) -> void: collection_events += 1)
	_check(game.count == 0 and not game.has_won and game.light_positions.size() == 3, "Fresh attempt has exactly three lights and no victory")
	var start: Vector2 = game.hero_position
	game.move_hero(Vector2.RIGHT, 0.1)
	_check(game.hero_position.is_equal_approx(start + Vector2(22, 0)), "Movement obeys speed × elapsed seconds")
	game.restart()
	game.move_hero(Vector2(1, 1), 0.1)
	_check(is_equal_approx(start.distance_to(game.hero_position), 22.0), "Diagonal movement is not faster")
	game.restart()
	game.move_hero(Vector2.LEFT, 100.0)
	_check(is_equal_approx(game.hero_position.x, State.PLAY_AREA.position.x + State.HERO_RADIUS), "Left boundary keeps the entire hero in the field")
	game.move_hero(Vector2.UP, 100.0)
	game.move_hero(Vector2.RIGHT, 100.0)
	_check(is_equal_approx(game.hero_position.y, 252.0) and is_equal_approx(game.hero_position.x, 1010.0), "Top and right boundaries clamp large movement steps")
	game.move_hero(Vector2.DOWN, 100.0)
	_check(is_equal_approx(game.hero_position.y, 516.0), "Bottom boundary keeps the hero above the status line")
	game.restart()
	game.move_hero(Vector2.RIGHT, -1.0)
	game.move_hero(Vector2(INF, 0), 0.1)
	game.move_hero(Vector2.RIGHT, NAN)
	_check(game.hero_position == game.hero_start, "Invalid movement cannot corrupt position")
	_check(not game.try_collect_light(-1) and not game.try_collect_light(3) and not game.try_collect_light(0), "Invalid indexes and distant light collection are rejected")
	for index in range(3):
		_walk_to(game, index)
		_check(game.count == index + 1 and game.collected[index], "Light %d disappears and increments once" % (index + 1))
		_check(not game.try_collect_light(index) and game.count == index + 1, "Light %d cannot be collected twice" % (index + 1))
		_check(game.has_won == (index == 2), "Victory is absent until all three lights (%d collected)" % (index + 1))
	_check(won_events == 1 and collection_events == 3, "Exactly one victory signal and three collection signals")
	var victory_position: Vector2 = game.hero_position
	game.move_hero(Vector2.LEFT, 0.5)
	_check(game.hero_position == victory_position and game.count == 3, "Winning attempt stops without phantom collections")
	var copied: Dictionary = game.snapshot()
	copied["collected"][0] = false
	copied["light_positions"][0] = Vector2.ZERO
	_check(game.collected[0] and game.light_positions[0] != Vector2.ZERO, "Snapshot array edits do not mutate the game")
	_check(game.restart() and game.count == 0 and not game.has_won and game.hero_position == game.hero_start and game.collected == [false, false, false], "Restart resets hero, all lights, count and victory")
	for index in range(3):
		_walk_to(game, index)
	_check(game.has_won and won_events == 2 and collection_events == 6, "A second complete attempt succeeds with fresh signals")
	game.restart()
	_walk_to(game, 0)
	game.restart()
	_check(game.count == 0 and not game.has_won and game.collected == [false, false, false], "Restart also clears an unfinished attempt")
	var swept = State.new({"hero_start": [110, 310], "lights": [[200, 310], [500, 475], [800, 475]]})
	swept.move_hero(Vector2.RIGHT, 1.0)
	_check(swept.count == 1 and swept.hero_position.x > 234.0, "Crossing a light between frames still collects it exactly once")
	var customized = State.new({"speed": 330, "theme": "moss", "win_message": "Мой маяк!", "lights": [[300, 300], [500, 400], [750, 300], [900, 300]]})
	_check(customized.speed == 330 and customized.theme_name == "moss" and customized.win_message == "Мой маяк!" and customized.light_positions.size() == 3, "Author choices work while the count remains exactly three")

func _test_stages() -> void:
	for stage in range(1, 6):
		var game = State.new({"stage": stage})
		for index in range(3):
			_walk_to(game, index)
		_check(game.count == (0 if stage == 1 else 3), "Stage %d enables only its intended collection behavior" % stage)
		_check(game.has_won == (stage >= 3), "Stage %d enables victory at the right lesson" % stage)
		_check(game.restart() == (stage >= 4), "Stage %d enables restart at the right lesson" % stage)

func _test_scene() -> void:
	var packed: PackedScene = load(base.path_join("main.tscn"))
	_check(packed != null, "Standalone scene can be loaded")
	if packed == null:
		return
	var scene = packed.instantiate()
	# Native focus notifications can arrive before _ready installs the InputMap.
	for action: String in ["light_left", "light_right", "light_up", "light_down"]:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	for attempt in range(3):
		scene.pointer_direction = Vector2.LEFT
		scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(scene.game == null and scene.pointer_direction == Vector2.ZERO, "Repeated focus-out before ready safely clears movement without installed actions")
	root.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	_check(scene.game != null, "Scene exposes its testable game model")
	_check(scene.game.hero_position == scene.game.hero_start and scene.game.count == 0 and not scene.victory_panel.visible, "Scene opens with a fresh attempt and no victory panel")
	var bindings: Dictionary = {"light_left": [KEY_A, KEY_LEFT], "light_right": [KEY_D, KEY_RIGHT], "light_up": [KEY_W, KEY_UP], "light_down": [KEY_S, KEY_DOWN], "light_restart": [KEY_R]}
	for action: String in bindings:
		var matching: bool = true
		for key: int in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			matching = matching and InputMap.action_has_event(action, event)
		_check(matching, "Physical keyboard mappings exist: " + action)
	var previous: Vector2 = scene.game.hero_position
	Input.action_press("light_right")
	scene._physics_process(0.1)
	Input.action_release("light_right")
	_check(scene.game.hero_position.x > previous.x, "Scene routes keyboard input to movement")
	previous = scene.game.hero_position
	scene.direction_buttons[0].button_down.emit()
	scene._physics_process(0.1)
	scene.direction_buttons[0].button_up.emit()
	_check(scene.game.hero_position.x < previous.x and scene.pointer_direction == Vector2.ZERO, "Mouse direction button moves and stops the hero")
	scene.direction_buttons[0].button_down.emit()
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(scene.pointer_direction == Vector2.ZERO, "Losing focus releases mouse movement")
	scene.direction_buttons[0].button_down.emit()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	scene._input(release)
	_check(scene.pointer_direction == Vector2.ZERO, "Releasing mouse outside the button stops movement")
	_check(scene.restart_button.visible == scene.game.can_restart(), "Restart button follows the lesson stage")
	for index in range(3):
		_walk_to(scene.game, index)
		_check(scene.victory_panel.visible == (scene.game.can_win() and index == 2), "Scene victory visibility after visiting light %d" % (index + 1))
	if scene.game.can_collect():
		_check(scene.counter_label.text.begins_with("3 / 3"), "Visible count matches all three collected lights")
	if scene.game.can_restart():
		scene.restart_button.pressed.emit()
		_check(scene.game.count == 0 and scene.game.hero_position == scene.game.hero_start and not scene.victory_panel.visible and scene.game.collected == [false, false, false], "Visible restart button resets the whole scene")
		_walk_to(scene.game, 0)
		var restart_key := InputEventKey.new()
		restart_key.physical_keycode = KEY_R
		restart_key.pressed = true
		scene._unhandled_key_input(restart_key)
		_check(scene.game.count == 0 and scene.game.hero_position == scene.game.hero_start and scene.game.collected == [false, false, false], "R resets an unfinished attempt through the scene input handler")
	scene.queue_free()
	await process_frame
