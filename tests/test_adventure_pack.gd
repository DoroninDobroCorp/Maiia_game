extends SceneTree
func _init():
	var failed := 0
	for path in ["res://content/quests/FG01.json","res://content/quests/FG11.json","res://content/quests/FG08.json","res://assets/learning_starter/manifest.json","res://assets/learning_starter/station_light_1.0.zip"]:
		var present := FileAccess.file_exists(path)
		print("PACK ",path," ",present)
		if not present: failed += 1
	var definitions = load("res://scripts/services/adventure_content.gd")
	print("PACK QUESTS ",definitions.quests().size())
	var launcher_script = load("res://scripts/services/launch_service.gd")
	var temporary := "/tmp/sur-pack-starter-" + str(Time.get_ticks_usec())
	var launcher = launcher_script.new(temporary)
	var result: Dictionary = launcher.prepare_starter_project()
	print("PACK STARTER ",result)
	if not bool(result.get("ok",false)): failed += 1
	launcher_script._remove_tree(temporary)
	quit(0 if failed == 0 else 1)
