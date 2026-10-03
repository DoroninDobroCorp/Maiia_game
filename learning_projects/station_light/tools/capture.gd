extends SceneTree
## Explicit QA tool, never loaded by the game's main scene.
## --capture-dir=<absolute path> is required; no user:// or personal saves.

var scene
var destination: String = ""

func _init() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			destination = argument.trim_prefix("--capture-dir=")
	call_deferred("_capture")

func _capture() -> void:
	if destination.is_empty() or not destination.is_absolute_path():
		printerr("An explicit absolute --capture-dir is required.")
		quit(1)
		return
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	await _save_frame("start.png")
	for index in range(3):
		var difference: Vector2 = scene.game.light_positions[index] - scene.game.hero_position
		scene.game.move_hero(difference.normalized(), difference.length() / scene.game.speed)
	await _save_frame("win.png")
	scene.restart_button.pressed.emit()
	await _save_frame("restart.png")
	print("CAPTURE: start, win and restart saved to ", destination)
	scene.queue_free()
	await process_frame
	quit(0)

func _save_frame(filename: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(destination.path_join(filename))
	if result != OK:
		printerr("Screenshot failed: ", result)
		quit(1)
