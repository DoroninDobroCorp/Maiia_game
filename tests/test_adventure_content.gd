extends SceneTree

## Content contracts and real launcher boundary tests. Writes only under a fresh
## OS temporary directory; never loads SaveService or a real SUR save.
const Content = preload("res://scripts/services/adventure_content.gd")
const Validation = preload("res://scripts/domain/content_validation.gd")
const Rules = preload("res://scripts/domain/adventure_rules.gd")
const Launcher = preload("res://scripts/services/launch_service.gd")

var passed := 0
var failed := 0
var scratch := ""

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, name: String, detail: Variant = "") -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL: ", name, " ", detail)

func _run() -> void:
	_content_checks()
	await _launcher_checks()
	print("ADVENTURE CONTENT + LAUNCHER: %d passed, %d failed" % [passed, failed])
	if not scratch.is_empty():
		Launcher._remove_tree(scratch)
	quit(0 if failed == 0 else 1)

func _content_checks() -> void:
	var quests := Content.quests()
	check(quests.size() == 3, "Three builtin adventures")
	var expected := {
		"FG01": ["es_intro", "es_channel_01", "es_channel_02", "es_channel_03", "es_channel_04", "es_final"],
		"FG11": ["game_concept", "game_move", "game_goal", "game_win", "game_restart", "game_premiere"],
		"FG08": ["water_intro", "water_plan", "water_river", "water_fall", "water_compare", "water_exhibit"]}
	var budgets := {"FG01": [0, 8, 8, 8, 8, 8], "FG11": [0, 12, 12, 12, 12, 12], "FG08": [0, 0, 10, 10, 10, 10]}
	for quest in quests:
		var qid := str(quest.quest_id)
		var validation := Validation.validate_quest(quest)
		check(validation.valid, "Shared schema2 validator " + qid, validation.errors)
		check(Rules.validate_adventure(quest).valid, "Stage rules " + qid)
		check(quest.revision == 2 and quest.schema_version == 2 and quest.content_status == "DRAFT", "New draft revision " + qid)
		check(quest.adventure.stages.size() == 6, "Exact stage count " + qid)
		var total := 0
		var types: Dictionary = {}
		for index in range(quest.adventure.stages.size()):
			var stage: Dictionary = quest.adventure.stages[index]
			check(stage.stage_id == expected[qid][index], "Stable stage ID " + str(stage.stage_id))
			check(int(stage.budget_share) == budgets[qid][index], "Exact stage budget " + str(stage.stage_id))
			total += int(stage.budget_share)
			check(not stage.summary.is_empty() and not stage.criteria.is_empty() and not stage.next_hint.is_empty(), "Story, criteria and stopping point " + str(stage.stage_id))
			check(quest.adventure.work_recipes.has(stage.work_recipe_id), "Frozen work recipe " + str(stage.stage_id))
			for grant_id in stage.grant_ids:
				check(quest.adventure.grant_definitions.has(grant_id), "Frozen grant " + str(grant_id))
			for iid in stage.interaction_ids:
				check(quest.adventure.interactions.has(iid), "Frozen interaction " + str(iid))
				if stage.completion_policy == "automatic":
					check(quest.adventure.interactions[iid].type != "real_world_step", "Automatic stages never claim real-world steps")
		check(total == int(quest.reward_policy.activity_budget), "Budget conserved " + qid)
		for definition in quest.adventure.interactions.values():
			types[definition.type] = true
			check(definition.hints.size() == 3, "Three contextual hints " + str(definition.interaction_id))
			check(definition.hints[0] != definition.hints[1] and definition.hints[1] != definition.hints[2], "Hints progressively differ")
			var answer := _valid_response(definition)
			var checked := Rules.check_interaction(definition, answer)
			check(checked.ok, "Authored interaction solvable " + str(definition.interaction_id), checked)
			check(not Rules.check_interaction(definition, {}).ok, "Empty answer cannot complete " + str(definition.interaction_id))
		check(types.size() >= 3, "At least three interaction types " + qid)
		# Published definitions are complete value trees, not mutable shared refs.
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify(quest))
		quest.adventure.stages[0].title = "Changed in editor"
		check(snapshot.adventure.stages[0].title != quest.adventure.stages[0].title, "Snapshot deep copy")
		check(Content.get_quest(qid).adventure.stages[0].title != "Changed in editor", "Future fetch unaffected")
	var lexicon := Content.lexicon()
	var ids: Dictionary = {}
	var lemmas: Dictionary = {}
	var channels: Dictionary = {}
	for entry in lexicon:
		check(not ids.has(entry.lexeme_id), "Unique lexeme ID")
		check(not lemmas.has(entry.base_form), "Unique base word")
		ids[entry.lexeme_id] = true
		lemmas[entry.base_form] = true
		channels[entry.channel_id] = int(channels.get(entry.channel_id, 0)) + 1
		check(not entry.translation.is_empty() and not entry.example.is_empty() and not entry.example_translation.is_empty(), "Bilingual example for every word")
		check(entry.accepted_variants.has(entry.base_form) and entry.normalization.preserve_diacritics, "Base accepted, accents significant")
	check(ids.size() == 100 and lemmas.size() == 100, "Exactly 100 unique target lexemes")
	check(channels.size() == 4 and channels.values().all(func(count): return count == 25), "Exactly 25 lexemes per channel")
	var es := Content.get_quest("FG01")
	var introduced: Dictionary = {}
	check(es.adventure.envelopes.size() == 20, "Twenty envelopes")
	for envelope in es.adventure.envelopes:
		check(envelope.lexeme_ids.size() == 5, "Five introductions per envelope")
		check(not envelope.story.is_empty() and not envelope.world_reaction.is_empty(), "Envelope situation and consequence")
		for id in envelope.review_lexeme_ids:
			check(introduced.has(id), "Review word was introduced earlier " + str(id))
		for id in envelope.lexeme_ids:
			check(ids.has(id) and not introduced.has(id), "Introduction has one stable unique lexeme")
			introduced[id] = true
	check(introduced.size() == 100, "All targets introduced once")
	for channel in es.adventure.channels:
		var types: Dictionary = {}
		for envelope in es.adventure.envelopes:
			if envelope.channel_id == channel.channel_id:
				for iid in envelope.interaction_ids:
					types[es.adventure.interactions[iid].type] = true
		check(types.size() >= 3, "Varied games in channel " + str(channel.channel_id))
	var sample: Array = es.adventure.interactions.es_mixed_check.config.lexeme_ids
	check(sample.size() == 20 and es.adventure.final_check.minimum_unassisted_correct == 14, "Published mixed check 20/14")
	var sampled_channels: Dictionary = {}
	for word in lexicon:
		if sample.has(word.lexeme_id):
			sampled_channels[word.channel_id] = int(sampled_channels.get(word.channel_id, 0)) + 1
	check(sampled_channels.size() == 4 and sampled_channels.values().all(func(count): return count == 5), "Balanced five words per channel in final")
	var mixed: Dictionary = es.adventure.interactions.es_mixed_check
	var fourteen := _valid_response(mixed)
	fourteen["assisted_ids"] = ["card_15", "card_16", "card_17", "card_18", "card_19", "card_20"]
	check(Rules.check_interaction(mixed, fourteen).ok, "Fourteen genuinely unassisted matches reach stated threshold")
	fourteen.assisted_ids.append("card_14")
	check(not Rules.check_interaction(mixed, fourteen).ok, "Thirteen unassisted answers offer practice without final pass")
	var water := Content.get_quest("FG08")
	check(water.adventure.stages[2].prerequisite_stage_ids == ["water_plan"] and water.adventure.stages[3].prerequisite_stage_ids == ["water_plan"], "River and waterfall independent")
	check(water.adventure.home_branch.completes_original_quest == false and water.adventure.home_branch.atlas_unlock_ids.is_empty(), "Home study does not assert a visit")
	var chapter := Content.chapter()
	check(chapter.secrets.size() == 6 and chapter.secret_reward.minimum_unique_finds == 3, "Six finds and any-three decoration")
	var locations := {"station": 0, "gallery": 0, "object_ui": 0}
	for secret in chapter.secrets:
		locations[secret.location_group] += 1
		check(secret.optional and secret.budget_share == 0 and secret.prerequisite_stage_ids.is_empty(), "Secret freely available without skill XP")
	check(locations.values().all(func(count): return count == 2), "Two finds per surface")
	check(chapter.finale.required_completed_quest_ids == ["FG01", "FG11", "FG08"] and chapter.finale.budget_share == 0 and chapter.finale.replay_budget_share == 0, "Finale requires three lines and grants no duplicate XP")
	var example := Content.example_package()
	var checked := Validation.validate_package(example)
	check(checked.valid, "Silhouettes example uses real schema2 package", checked.errors)
	check(example.quests[0].quest_id == "AR02", "Next family mission independent of old AR01")

func _valid_response(definition: Dictionary) -> Dictionary:
	var config: Dictionary = definition.config
	var response: Dictionary = {"fields": {}}
	for f in config.get("fields", []):
		response.fields[f.id] = "Конкретное наблюдение в тестовом профиле"
	match str(definition.type):
		"match_cards":
			response["pairs"] = config.accepted_pairs.duplicate(true)
			if config.has("lexeme_ids"):
				response["unassisted_lexeme_ids"] = config.lexeme_ids.duplicate()
		"order_fragments": response["order"] = config.accepted_orders[0].duplicate()
		"inspect_reveal": response["revealed_ids"] = config.required_detail_ids.duplicate()
		"assemble_selection", "exhibit_composition":
			var selected: Array = config.get("required_ids", []).duplicate()
			for choice in config.get("items", config.get("choices", [])):
				if selected.size() < int(config.min_selected) and not selected.has(choice.id):
					selected.append(choice.id)
			response["selected_ids"] = selected
		"scripted_dialogue":
			var node_id: String = config.start_node_id
			var choices: Array = []
			for _step in range(256):
				var node: Dictionary = {}
				for value in config.nodes:
					if value.node_id == node_id: node = value
				if node.get("terminal", false): break
				for choice in node.get("choices", []):
					if choice.correct:
						choices.append(choice.id)
						node_id = choice.next_node_id
						break
			response["choice_ids"] = choices
			response["node_id"] = node_id
		"compare_observations":
			response["comparison"] = "На первой странице линии шли вдоль берега, на второй падали сверху."
			response["category_id"] = "movement"
		"real_world_step": response["note"] = "Совместная проверка тестового результата"
	return response

func _launcher_checks() -> void:
	for version in ["0.1", "0.2", "0.3", "0.4", "1.0"]:
		var sources := Launcher._bundled_sources(version)
		check(sources.ok and sources.files.size() == 7 and sources.files.has("project.godot") and sources.files.has("main.gd"), "Packaged starter ZIP verifies all seven original sources " + version, sources.get("reason", ""))
	check(not Launcher._bundled_sources("../other").ok, "Only fixed builtin archive versions can be extracted")
	scratch = OS.get_temp_dir().path_join("sur_content_launcher_" + Crypto.new().generate_random_bytes(8).hex_encode())
	var launcher = Launcher.new(scratch.path_join("registry"))
	check(not launcher.inspect_entry("missing").ok, "Unregistered project cannot launch")
	check(not launcher.register_project(scratch.path_join("missing"), "1.0").ok, "Missing project clearly rejected")
	check(not launcher.register_app(scratch.path_join("Missing.app"), "1.0").ok, "Missing application clearly rejected")
	var prepared: Dictionary = launcher.prepare_starter_project()
	check(prepared.ok, "Prepare editable separate starter", prepared)
	if not prepared.ok: return
	check(prepared.project_dir == launcher.working_project_path(), "Working directory helper matches copy")
	check(launcher.prepare_starter_project().reused, "Preparing again keeps previous work")
	check(not launcher.prepare_starter_project(str(prepared.project_dir)).ok, "Explicit destination never overwritten")
	var denied: Dictionary = launcher.register_project(prepared.project_dir, "1.0", "player_direct")
	check(not denied.ok and denied.reason == "adult_registration_required", "Player completion cannot register executable")
	var first: Dictionary = launcher.register_project(prepared.project_dir, "1.0")
	check(first.ok, "Register working project copy", first)
	if not first.ok: return
	var entry_id: String = first.launch_entry_id
	check(first.entry.demonstration_only and first.entry.completion_evidence == false, "Unchanged working starter stays explicitly demo")
	check(not str(first.source_archive_file).contains("://") and not str(first.source_archive_file).begins_with("/"), "Archive reference is portable internal name")
	check(first.entry.source_archive_kind == "project_source", "Archive identifies actual source material")
	check(launcher.inspect_entry(entry_id).ok, "Managed snapshot available after registration")
	check(not launcher.inspect_entry(entry_id, "other_profile").ok, "Launch entries profile-scoped")
	check(launcher.list_entries().size() == 1 and launcher.list_entries("other_profile").is_empty(), "Family listing profile-scoped")
	var original_text := FileAccess.get_file_as_string(str(prepared.project_dir).path_join("lesson.json"))
	_write(str(prepared.project_dir).path_join("lesson.json"), original_text.replace('"speed": 220', '"speed": 250'))
	check(launcher.inspect_entry(entry_id).ok, "Editing working source cannot mutate registered version")
	var second: Dictionary = launcher.register_project(prepared.project_dir, "My speed")
	check(second.ok and second.launch_entry_id != entry_id, "New version gets new immutable registration")
	check(second.ok and not second.entry.demonstration_only, "Changed source distinguished from shipped demo")
	var restored = Launcher.new(scratch.path_join("registry"))
	check(restored.inspect_entry(entry_id).ok and restored.list_entries().size() == 2, "Registry persists independently of SUR save")
	var launch_result: Dictionary = restored.launch(entry_id)
	check(launch_result.ok and not launch_result.completion_evidence, "Actual separate Godot process launched without completion", launch_result)
	if launch_result.ok:
		await create_timer(1.0).timeout
		check(restored.process_status(launch_result.pid).ok, "Launched process reports running without mutating progress")
		if OS.is_process_running(launch_result.pid): OS.kill(launch_result.pid)
	var managed := scratch.path_join("registry/versions").path_join(entry_id).path_join("project/lesson.json")
	_write(managed, original_text + " ")
	var changed: Dictionary = restored.inspect_entry(entry_id)
	check(not changed.ok and changed.reason == "app_changed", "Modified registered resource denied")
	check(not restored.launch(entry_id).ok, "Changed resource cannot be executed")
	var second_dir := scratch.path_join("registry/versions").path_join(str(second.launch_entry_id))
	Launcher._remove_tree(second_dir.path_join("project"))
	var missing: Dictionary = restored.inspect_entry(second.launch_entry_id)
	check(not missing.ok and missing.reason == "app_missing", "Deleted application produces recoverable missing error")
	# Exercise OS failure reporting with a deliberately tiny, trusted test project.
	var failing := scratch.path_join("failure_fixture")
	DirAccess.make_dir_recursive_absolute(failing)
	_write(failing.path_join("project.godot"), 'config_version=5\n[application]\nconfig/name="SUR isolated failing fixture"\nrun/main_scene="res://main.tscn"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
	_write(failing.path_join("main.tscn"), '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://main.gd" id="1"]\n[node name="Fixture" type="Node"]\nscript = ExtResource("1")\n')
	_write(failing.path_join("main.gd"), 'extends Node\nfunc _ready() -> void:\n\tget_tree().quit(7)\n')
	var fixture: Dictionary = restored.register_project(failing, "failure test")
	check(fixture.ok, "Register isolated OS exit fixture")
	if fixture.ok:
		var spawned: Dictionary = restored.launch(fixture.launch_entry_id)
		check(spawned.ok, "Start controlled failure fixture")
		if spawned.ok:
			var exit_deadline := Time.get_ticks_msec() + 15000
			while OS.is_process_running(spawned.pid) and Time.get_ticks_msec() < exit_deadline:
				await create_timer(0.1).timeout
			var status: Dictionary = restored.process_status(spawned.pid)
			check(not status.ok and status.reason == "application_exited_with_error" and status.exit_code == 7, "Nonzero child exit is clear error", status)
			if OS.is_process_running(spawned.pid): OS.kill(spawned.pid)
	if OS.get_name() == "macOS":
		await _mac_app_checks(restored)
	# Corrupt registry must not silently become an empty registry and overwrite it.
	_write(scratch.path_join("registry/registry.json"), "{damaged")
	check(not restored.register_project(prepared.project_dir, "after damage").ok, "Corrupt registry prevents destructive registration")

func _mac_app_checks(launcher: RefCounted) -> void:
	# Build a disposable .app around the OS's tiny no-op native executable.
	# No shell, script interpreter, network or user files participate.
	var app := scratch.path_join("NativeFixture.app")
	DirAccess.make_dir_recursive_absolute(app.path_join("Contents/MacOS"))
	_write(app.path_join("Contents/Info.plist"), '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>NativeFixture</string><key>CFBundleIdentifier</key><string>org.sur.isolated-native-fixture</string><key>CFBundleName</key><string>SUR Test</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string></dict></plist>')
	var copy_error := DirAccess.copy_absolute("/usr/bin/true", app.path_join("Contents/MacOS/NativeFixture"), FileAccess.get_unix_permissions("/usr/bin/true"))
	check(copy_error == OK, "Prepare native disposable macOS app")
	if copy_error != OK: return
	var registered: Dictionary = launcher.register_app(app, "native fixture")
	check(registered.ok, "Register and checksum macOS app bundle", registered)
	if not registered.ok: return
	check(registered.entry.source_archive_kind == "application_bundle", "Binary bundle archive never represented as project source")
	# Alter a freshly copied bundle before the OS has launched/protected it.
	var bundle: String = launcher.storage_root.path_join("versions").path_join(str(registered.launch_entry_id)).path_join("Game.app")
	_write(bundle.path_join("Contents/additional_resource.txt"), "changed")
	var changed: Dictionary = launcher.inspect_entry(registered.launch_entry_id)
	check(not changed.ok and changed.reason == "app_changed", "Added app bundle resource blocks launch")
	registered = launcher.register_app(app, "native launch fixture")
	check(registered.ok, "Fresh native version registration after changed bundle")
	if not registered.ok: return
	var launched: Dictionary = launcher.launch(registered.launch_entry_id)
	check(launched.ok and not launched.completion_evidence, "Launch actual .app as independent process without shell", launched)
	if launched.ok:
		await create_timer(0.3).timeout
		var status: Dictionary = launcher.process_status(launched.pid)
		check(status.ok, "Native app launch remains recoverable", status)
		if OS.is_process_running(launched.pid): OS.kill(launched.pid)
	check(launcher.inspect_entry(registered.launch_entry_id).ok, "Registered bundle remains intact after native launch")

func _write(file_name: String, value: String) -> void:
	var file := FileAccess.open(file_name, FileAccess.WRITE)
	if file == null:
		printerr("TEST WRITE ERROR ", FileAccess.get_open_error(), " ", file_name)
	assert(file != null)
	file.store_string(value)
	file.close()
