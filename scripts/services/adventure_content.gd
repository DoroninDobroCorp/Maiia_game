class_name AdventureContent
extends RefCounted

## Immutable authored resources; callers receive independent trees suitable for
## inclusion in QuestInstance.quest_snapshot. This service never touches saves.
const INTERACTION_TYPES: Array[String] = ["inspect_reveal", "match_cards", "order_fragments", "assemble_selection", "scripted_dialogue", "real_world_step", "compare_observations", "exhibit_composition"]
const CAPABILITY_IDS: Array[String] = ["adventure_v1", "exhibits_v1", "lexicon_v1", "registered_launch_v1"]
const GRANT_IDS: Array[String] = [
	"radio_first_contact", "radio_menu", "station_word_label", "valley_postcard", "radio_album", "radio_callsign",
	"game_concept_card", "arcade_movement", "arcade_counter", "arcade_victory_lamp", "arcade_restart_button", "arcade_premiere",
	"water_question_card", "field_album", "river_diagram_panel", "fall_diagram_panel", "water_compare_switch", "water_diptych",
	"silhouette_frame", "gallery_evening_light", "chapter_card", "secret_constellation_theme"
]
const WORK_RECIPE_IDS: Array[String] = ["radio_contact_card", "radio_menu", "station_word_label", "valley_postcard", "radio_album", "radio_episode_card", "game_concept_card", "game_project_version", "game_premiere", "water_question_card", "field_plan", "water_observation_page", "water_comparison", "water_diptych", "home_water_study", "silhouette_sheet", "silhouette_frame", "chapter_album", "story_find"]
const QUEST_FILES: Array[String] = ["res://content/quests/FG01.json", "res://content/quests/FG11.json", "res://content/quests/FG08.json"]

static func quests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for file_name in QUEST_FILES:
		var quest := _read_dictionary(file_name)
		if not quest.is_empty():
			result.append(quest)
	return result

static func get_quest(quest_id: String) -> Dictionary:
	for quest in quests():
		if str(quest.get("quest_id", "")) == quest_id:
			return quest
	return {}

static func lexicon() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _read_dictionary("res://content/lexicons/es_first_100.json").get("lexemes", []):
		if entry is Dictionary:
			result.append(entry.duplicate(true))
	return result

static func chapter() -> Dictionary:
	return _read_dictionary("res://content/chapters/station_on_air.json")

static func secrets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in chapter().get("secrets", []):
		if entry is Dictionary:
			result.append(entry.duplicate(true))
	return result

static func example_package() -> Dictionary:
	return _read_dictionary("res://content/examples/three_silhouettes.schema2.json")

static func package() -> Dictionary:
	return {"schema_version": 2, "package_type": "sur_quest_pack", "package_id": "sur_station_on_air_v1", "required_capabilities": ["adventure_v1", "exhibits_v1"], "quests": quests()}

static func _read_dictionary(file_name: String) -> Dictionary:
	if not FileAccess.file_exists(file_name):
		push_error("Adventure content missing: " + file_name)
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(file_name)) != OK or not parser.data is Dictionary:
		push_error("Adventure content invalid: " + file_name)
		return {}
	return (parser.data as Dictionary).duplicate(true)
