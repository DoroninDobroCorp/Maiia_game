extends SceneTree

## In-memory presentation and interaction checks. Never loads, writes or resets saves.
const Content = preload("res://scripts/services/adventure_content.gd")
const Collection = preload("res://scripts/services/collection_service.gd")
const Rules = preload("res://scripts/domain/adventure_rules.gd")
const Episode = preload("res://scripts/presentation/adventure_episode.gd")
const Hub = preload("res://scripts/presentation/adventure_hub.gd")
const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Browser = preload("res://scripts/presentation/collection_browser.gd")
var failures: Array[String] = []
var passed := 0
var commands: Array = []
var closed_count := 0
var flow_state: Dictionary = {}
var last_result: Dictionary = {}
const Adventures = preload("res://scripts/services/adventure_service.gd")
const Quests = preload("res://scripts/services/quest_service.gd")
const Save = preload("res://scripts/services/save_service.gd")
const Commit = preload("res://scripts/services/activity_commit_service.gd")

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failures.append(label)

func fixture() -> Dictionary:
	var value := {"settings":{"ui_scale":1.25},"s00_progress":{"station_awakened":true},"phase_b":{"quest_instances":{},"published_versions":{}},"adventures":{"progress":{}},"collections":{"works":{},"exhibits":{},"rooms":{},"placements":{},"snapshots":{}}}
	Collection.ensure_gallery(value)
	for quest in Content.quests():
		var id := str(quest.quest_id)
		value.phase_b.quest_instances[id] = {"instance_id":id,"quest_id":id,"profile_id":"player_01","status":"ACTIVE","quest_snapshot":quest}
		value.adventures.progress[id] = {"lexemes":{},"stages":{}}
		for stage in quest.adventure.stages:
			value.adventures.progress[id].stages[stage.stage_id] = {"status":"AVAILABLE","draft":{},"attempts":[]}
	value["_adventure_ui"] = {"catalog":Content.quests()}
	return value

func _run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_factor = 1.25
	var state := fixture()
	for path in ["res://scenes/ui/adventure_hub.tscn","res://scenes/ui/adventure_episode.tscn","res://scenes/ui/collection_browser.tscn","res://scenes/ui/adventure_editor.tscn","res://scenes/world/gallery_room.tscn"]:
		var scene = load(path)
		check(scene != null,"Load " + path)
		if scene == null: continue
		var node = scene.instantiate()
		root.add_child(node)
		node.setup(state)
		await process_frame
		await process_frame
		if node is Control:
			check(node.size.x <= 1025 and node.size.y <= 577,"125% logical viewport " + path)
			_check_layout(node,path)
		node.queue_free()
		await process_frame
	await _test_interactions(state)
	await _test_archive(state)
	await _test_signal_flow()
	await _test_archive_source_chains()
	await _test_comparison_navigation(state)
	_test_family_review_queue()
	_test_returned_review()
	check(UI.result_text({"ok":false,"reason":"interaction_incomplete"}).contains("сцен"),"Common error is explained in Russian")
	for reason in ["interaction_incomplete","not_enough_lexemes","real_visit_required","criteria_not_confirmed","instance_not_active","own_contribution_required","mixed_check_incomplete","save_failed","additional_room_locked"]:
		var message := UI.result_text({"ok":false,"reason":reason})
		check(not message.contains(reason) and not message.is_empty(),"Child-friendly error " + reason)
	check(not UI.result_text({"ok":false,"reason":"unknown_internal_code"}).contains("unknown_internal_code"),"Unknown errors do not expose technical reason codes")
	var validation_errors := ["adventure.stages[2].prerequisite_stage_ids[0]: missing stage", "adventure.interactions.water_compare.config: invalid"]
	check(UI.result_text({"ok":false,"errors":validation_errors}) == "\n".join(validation_errors),"Adult validation preserves exact paths and details")
	print("ADVENTURE UI: %d passed, %d failed" % [passed,failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_family_review_queue() -> void:
	var state := fixture()
	state.phase_b.quest_instances.FG11["superseded_by_instance_id"] = "new-game-instance"
	state.adventures.progress.FG11.stages.game_move.status = "AWAITING_REVIEW"
	state.adventures.progress.FG08.stages.water_river.status = "AWAITING_REVIEW"
	var panel := preload("res://scripts/presentation/family_adventure_tools.gd").new()
	root.add_child(panel)
	panel.tab = 1
	panel.setup(state)
	var reviews := panel.find_children("*","Button",true,false).filter(func(b): return b.text == "Посмотреть результат вместе")
	check(reviews.size() == 1,"Family review queue excludes superseded instances but retains current results")
	state.adventures.progress.FG08.stages.water_river.status = "COMPLETED"
	panel.setup(state)
	reviews = panel.find_children("*","Button",true,false).filter(func(b): return b.text == "Посмотреть результат вместе")
	check(reviews.is_empty(),"Migrated pending result does not leave an impossible family review")
	panel.free()

func _test_returned_review() -> void:
	var state := fixture()
	var response := {"fields":{"observation":"Вода обходит камень"},"criteria":[true],"visited":true,"atlas_location_id":"rio_azul"}
	state.adventures.progress.FG08.stages.water_river = {"status":"IN_PROGRESS","review_history":[{"approved":false}],"review_note":"Добавь, что ты услышала рядом с водой","attempts":[{"interaction_id":"water_river_return","success":true,"response":response}],"draft":{"interaction_id":"water_river_return","responses":{"water_river_return":response}}}
	state._adventure_ui = {"instance_id":"FG08","stage_id":"water_river","quest":Content.get_quest("FG08")}
	var node := Episode.new()
	root.add_child(node)
	node.setup(state)
	check(node.find_children("*","Label",true,false).any(func(label): return label.text == "Добавь, что ты услышала рядом с водой"),"Returned stage displays the actual family suggestion")
	check(node.response_fields.has("observation") and node.response_fields.observation.text == "Вода обходит камень" and node.replay_interaction,"Returned stage opens preserved observation for editing instead of hiding it as finished")
	node.free()

func _check_layout(node: Node, description: String) -> void:
	for control in node.find_children("*","ScrollContainer",true,false):
		if control.get_child_count() > 0:
			var child = control.get_child(0)
			check(child.size.x <= control.size.x+1,description+" no horizontal overflow")
	for control in node.find_children("*","MarginContainer",true,false):
		check(control.position.x+control.size.x <= 1025,description+" frame fits")

func _test_comparison_navigation(state: Dictionary) -> void:
	var view := state.duplicate(true)
	view._adventure_ui = {"quest":Content.get_quest("FG08"),"instance_id":"FG08","stage_id":"water_compare"}
	var episode := Episode.new()
	root.add_child(episode)
	episode.setup(view)
	var sent: Array = []
	var navigation: Array = []
	episode.command_requested.connect(func(operation,payload): sent.append({"operation":operation,"payload":payload}))
	episode.collection_requested.connect(func(): navigation.append("collection"))
	for field in episode.response_fields.values(): field.text = "Моё ещё не сохранённое сравнение"
	episode.note.text = "Продолжу после просмотра двух работ"
	for button in episode.find_children("*","Button",true,false):
		if button.text == "Посмотреть работы": button.pressed.emit(); break
	check(navigation.is_empty() and not sent.is_empty() and sent.back().operation == "stage_draft", "Archive navigation waits for comparison draft persistence")
	episode.show_result({"ok":false,"reason":"save_failed"})
	check(navigation.is_empty() and episode.note.text == "Продолжу после просмотра двух работ", "Failed archive navigation retains comparison input")
	for button in episode.find_children("*","Button",true,false):
		if button.text == "Посмотреть работы": button.pressed.emit(); break
	episode.show_result({"ok":true})
	check(navigation.size() == 1 and not sent.is_empty() and sent.back().payload.draft.note == "Продолжу после просмотра двух работ", "Successful draft retry opens archive exactly once")
	episode.free()
	await process_frame

func _test_interactions(state: Dictionary) -> void:
	var seen: Dictionary = {}
	for quest in Content.quests():
		for stage in quest.adventure.stages:
			for id in stage.interaction_ids:
				var inter: Dictionary = quest.adventure.interactions[id]
				if seen.has(inter.type) and not ["es_mixed_check","water_river_return","game_premiere_return"].has(str(id)): continue
				seen[inter.type] = true
				var view := state.duplicate(true)
				view._adventure_ui = {"quest":quest,"instance_id":quest.quest_id,"stage_id":stage.stage_id,"launch_entries":[{"launch_entry_id":"test-build","title":"Моя игра","version_label":"1.0"}]}
				var node := Episode.new()
				root.add_child(node)
				node.setup(view)
				node.interaction_index = stage.interaction_ids.find(id)
				node._build()
				await process_frame
				await process_frame
				_check_layout(node,"Renderer " + str(id))
				check(node._interaction().type == inter.type,"Renderer " + str(inter.type))
				# Fill the rendered fields; choices/pairs remain actual structured answers.
				for field in node.response_fields.values(): field.text = "Моя заметка для проверки"
				var config: Dictionary = inter.config
				match str(inter.type):
					"match_cards": node.response.pairs = config.accepted_pairs.duplicate(true)
					"order_fragments": node.response.order = config.accepted_orders[0].duplicate()
					"inspect_reveal": node.response.revealed_ids = config.required_detail_ids.duplicate()
					"assemble_selection", "exhibit_composition":
						node.response.selected_ids = config.get("required_ids", []).duplicate()
						for item in config.get("items",config.get("choices", [])):
							if node.response.selected_ids.size() < int(config.get("min_selected",1)) and not node.response.selected_ids.has(item.id): node.response.selected_ids.append(item.id)
					"scripted_dialogue":
						var current := str(config.start_node_id)
						node.response.choice_ids = []
						for _step in range(20):
							var entry: Dictionary = {}
							for item in config.nodes:
								if item.node_id == current: entry = item
							if bool(entry.get("terminal",false)): break
							for choice in entry.get("choices", []):
								if bool(choice.get("correct",true)):
									node.response.choice_ids.append(choice.id)
									current = choice.next_node_id
									break
						node.response.node_id = current
					"compare_observations": node.response.category_id = config.categories[0].id
				node._capture()
				node._prepare_response()
				check(bool(Rules.check_interaction(inter,node.response).ok),"UI response accepted " + str(id))
				if str(id) == "es_mixed_check":
					node.response.assisted_ids = ["card_1","card_2","card_3","card_4","card_5","card_6"]
					node._prepare_response()
					check(node.response.unassisted_lexeme_ids.size() == 14,"Mixed check excludes six assisted answers")
					check(bool(Rules.check_interaction(inter,node.response).ok),"Mixed check accepts fourteen actual answers")
					node._hint()
					node._hint()
					node._hint()
					node._prepare_response()
					check(node.response.unassisted_lexeme_ids.is_empty(),"Third hint marks the current twenty answers as assisted")
					var original_progress: Dictionary = node.state.get("adventures", {}).duplicate(true)
					node.successful_interactions[str(id)] = true
					node._reset_mixed_attempt()
					check(node.response.pairs.is_empty() and node.response.assisted_ids.is_empty() and node.hint_level == 0,"Fresh mixed attempt clears answers, help, and hint level")
					check(not node.response.has("sample_lexeme_ids") and not node.response.has("unassisted_lexeme_ids") and not node.successful_interactions.has(str(id)),"Fresh mixed attempt cannot reuse previous success or score")
					check(node.state.get("adventures", {}) == original_progress,"Reset retains persisted attempt history")
					for card in config.cards.slice(0,14): node.response.pairs[str(card.id)] = str(config.accepted_pairs[str(card.id)])
					node._prepare_response()
					check(node.response.unassisted_lexeme_ids.size() == 14 and bool(Rules.check_interaction(inter,node.response).ok),"Fresh fourteen real answers succeed after a fully assisted attempt")
				if str(id) == "water_river_return":
					node.command_requested.connect(func(op,payload): commands.append({"operation":op,"payload":payload}))
					node.closed.connect(func(): closed_count += 1)
					node.note.text = "Черновик не должен пропасть"
					node._close()
					check(closed_count == 0,"Escape waits for draft persistence")
					node.show_result({"ok":false,"reason":"save_failed"})
					check(closed_count == 0 and node.draft.note == "Черновик не должен пропасть","Failed save retains draft and screen")
					node._close()
					node.show_result({"ok":true})
					check(closed_count == 1,"Successful retry closes screen")
				node.free()
				await process_frame
	check(seen.size() == 8,"All eight interaction renderers")

func _test_archive(state: Dictionary) -> void:
	for i in range(37):
		Collection.create_work(state,{"title":"Работа %d" % i,"kind":"note","content":{"note":"Сохранённое наблюдение"}})
	var browser := Browser.new()
	root.add_child(browser)
	browser.setup(state)
	await process_frame
	await process_frame
	check(browser.find_children("*","GridContainer",true,false)[0].get_child_count() == 12,"Archive limits page to twelve cards")
	browser.search = "Работа 36"
	browser._build()
	await process_frame
	check(browser.find_children("*","GridContainer",true,false)[0].get_child_count() == 1,"Archive search filters metadata")
	Collection.create_work(state,{"title":"Лист наблюдений","quest_ids":["FG08"],"content":{"note":"Блики"},"source":{"quest_snapshot":{"title":"Исследование воды","story_title":"Секреты водопада"}}})
	browser.search = "Секреты водопада"
	browser.page = 3
	browser.setup(state)
	check(browser.find_children("*","GridContainer",true,false)[0].get_child_count() == 1 and browser.page == 0,"Archive finds frozen adventure title and returns to an existing page")
	var record: Dictionary = Collection.list_works(state)[0]
	browser.open_work(str(record.work_id))
	browser.editing_version = true
	browser._build()
	for field in browser.find_children("*","TextEdit",true,false):
		if field.placeholder_text == "Что изменилось?": field.text = "Новая заметка вместе с рисунком"
	for field in browser.find_children("*","LineEdit",true,false):
		if field.placeholder_text == "Короткое название изменений": field.text = "Добавила рисунок"
	var attachment: Array = []
	browser.command_requested.connect(func(operation,payload): attachment.append({"operation":operation,"payload":payload}))
	for button in browser.find_children("*","Button",true,false):
		if button.text == "Прикрепить изображение к новой версии": button.pressed.emit(); break
	check(not attachment.is_empty() and str(attachment[0].payload.get("content", {}).get("note", "")) == "Новая заметка вместе с рисунком" and str(attachment[0].payload.get("note", "")) == "Добавила рисунок", "Image attachment carries unsaved version text and change label")
	browser.free()

func _route_episode_command(node: Control, operation: String, payload: Dictionary) -> void:
	var candidate := flow_state.duplicate(true)
	# Only the OS launch verifier is a test double; no user launch registry is read.
	if str(payload.get("stage_id", "")) == "game_premiere" and operation in ["stage_submit","stage_review"]:
		var memory_save := func(_value): return true
		var registered := func(id,pid): return {"ok":id == "ui-test-build","entry":{"launch_entry_id":id,"profile_id":pid,"source_archive_file":"launch_registry/test/source.zip","demonstration_only":false}}
		if operation == "stage_submit": last_result = Commit.commit_stage(candidate,payload.instance_id,payload.stage_id,payload.get("evidence", {}),"player_self",memory_save,registered)
		else: last_result = Commit.review_stage(candidate,payload.instance_id,payload.stage_id,bool(payload.get("approved",false)),str(payload.get("note", "")),"parent_local",memory_save,payload,registered)
	else:
		last_result = Adventures.dispatch(candidate,operation,payload)
	if bool(last_result.get("ok",false)): flow_state = candidate
	node.show_result(last_result)
	if bool(last_result.get("ok",false)) and operation in ["stage_submit","stage_review"]:
		var view := flow_state.duplicate(true)
		view["_adventure_ui"] = {"instance_id":node.instance_id,"stage_id":node.stage_id,"quest":node.quest}
		node.setup(view)
		node.show_result(last_result)

func _answer(inter: Dictionary) -> Dictionary:
	var config: Dictionary = inter.config
	var response: Dictionary = {"fields":{},"note":"Собственная заметка для теста"}
	if str(inter.get("interaction_id", "")) == "game_premiere_return":
		response["launch_entry_id"] = "ui-test-build"
		response["source_archive_file"] = "ui-test-source.zip"
	match str(inter.type):
		"match_cards": response["pairs"] = config.accepted_pairs.duplicate(true)
		"order_fragments": response["order"] = config.accepted_orders[0].duplicate()
		"inspect_reveal": response["revealed_ids"] = config.required_detail_ids.duplicate()
		"assemble_selection","exhibit_composition":
			response["selected_ids"] = config.get("required_ids", []).duplicate()
			for item in config.get("items",config.get("choices", [])):
				if response.selected_ids.size() < int(config.get("min_selected",1)) and not response.selected_ids.has(item.id): response.selected_ids.append(item.id)
		"scripted_dialogue":
			var current := str(config.start_node_id)
			response["choice_ids"] = []
			for _step in range(20):
				var entry: Dictionary = {}
				for item in config.nodes:
					if item.node_id == current: entry = item
				if bool(entry.get("terminal",false)): break
				for choice in entry.get("choices", []):
					if bool(choice.get("correct",true)):
						response.choice_ids.append(choice.id)
						current = choice.next_node_id
						break
			response["node_id"] = current
		"compare_observations": response["category_id"] = str(config.categories[0].id)
	for key in config.get("required_checks", []):
		if not response.has("checks"): response["checks"] = {}
		response.checks[key] = true
	if config.has("atlas_location_id"):
		response["visited"] = true
		response["atlas_location_id"] = str(config.atlas_location_id)
	return response

func _test_signal_flow() -> void:
	flow_state = Save.get_default_state()
	flow_state.s00_progress.station_awakened = true
	for quest in Content.quests():
		check(bool(Quests.approve_and_publish(flow_state,quest).get("ok",false)),"Signal flow publishes " + str(quest.quest_id))
		var accepted := Adventures.accept(flow_state,str(quest.quest_id),int(quest.revision))
		check(bool(accepted.get("ok",false)),"Signal flow accepts " + str(quest.quest_id))
		if not bool(accepted.get("ok",false)): continue
		var iid := str(accepted.instance.instance_id)
		for stage in quest.adventure.stages:
			var view := flow_state.duplicate(true)
			view["_adventure_ui"] = {"instance_id":iid,"stage_id":stage.stage_id,"quest":quest}
			var node := Episode.new()
			root.add_child(node)
			node.setup(view)
			node.command_requested.connect(func(op,payload): _route_episode_command(node,op,payload))
			for index in range(node.interactions.size()):
				node.interaction_index = index
				node._build()
				var inter: Dictionary = node.interactions[index]
				node.response = _answer(inter)
				if str(inter.interaction_id) == "es_mixed_check":
					for _hint_index in range(3): node._hint()
					node._prepare_response()
					node._send("stage_attempt",{"interaction_id":inter.interaction_id,"response":node.response.duplicate(true)})
					check(bool(last_result.get("ok",false)) and not bool(last_result.get("success",true)),"Dispatcher records fully assisted mixed attempt without success")
					var attempted: Array = flow_state.adventures.progress[iid].stages[stage.stage_id].attempts.duplicate(true)
					node._reset_mixed_attempt()
					check(flow_state.adventures.progress[iid].stages[stage.stage_id].attempts == attempted and not attempted.is_empty(),"Fresh mixed attempt retains actual dispatcher attempt history")
					for card in inter.config.cards.slice(0,14): node.response.pairs[str(card.id)] = str(inter.config.accepted_pairs[str(card.id)])
				for field in node.response_fields.values(): field.text = "Майя выбрала и проверила одну свою деталь"
				node.note.text = "Наблюдение автора: вода огибает камень; правило игры изменилось по моему выбору"
				node._capture()
				node._prepare_response()
				node._send("stage_attempt",{"interaction_id":inter.interaction_id,"response":node.response.duplicate(true)})
				check(bool(last_result.get("ok",false)) and bool(last_result.get("success",false)),"Signal attempt → dispatcher " + str(inter.interaction_id))
				await process_frame
			if is_instance_valid(node.attest): node.attest.button_pressed = true
			node._submit()
			check(bool(last_result.get("ok",false)),"UI submit → dispatcher " + str(stage.stage_id) + " " + str(last_result.get("reason", "")))
			if bool(last_result.get("awaiting_review",false)):
				var criteria: Array = []
				for _c in stage.criteria: criteria.append(true)
				node._send("stage_review",{"approved":true,"criteria":criteria,"note":"Совместно проверили конкретные действия","assistance":"together"})
				check(bool(last_result.get("ok",false)),"UI review → dispatcher " + str(stage.stage_id))
			check(str(flow_state.adventures.progress[iid].stages[stage.stage_id].status) == "COMPLETED","UI stage completed " + str(stage.stage_id))
			node.free()
			await process_frame
		check(str(flow_state.phase_b.quest_instances[iid].status) == "COMPLETED","UI entire adventure " + str(quest.quest_id))
		if str(quest.quest_id) == "FG01": check(flow_state.adventures.progress[iid].lexemes.size() == 100,"UI earns exactly100 unique words from actual successful scenes, no manual counter commands")

func _test_archive_source_chains() -> void:
	var state := fixture()
	state.phase_b["artifacts"] = {
		"image_water_river":{"artifact_id":"image_water_river","profile_id":"player_01"},
		"image_water_fall":{"artifact_id":"image_water_fall","profile_id":"player_01"}
	}
	var refs: Dictionary = {}
	var notes := {"water_intro":"Подготовительный вопрос","water_plan":"Подготовительный план","water_river":"Река огибает камни","water_fall":"Водопад падает сверху","water_compare":"Разное направление воды","water_exhibit":"Два голоса"}
	var dependencies := {"water_intro":[],"water_plan":["water_intro"],"water_river":["water_plan"],"water_fall":["water_plan"],"water_compare":["water_river","water_fall"],"water_exhibit":["water_compare"]}
	for sid in ["water_intro","water_plan","water_river","water_fall","water_compare","water_exhibit"]:
		var sources: Dictionary = {}
		for required in dependencies[sid]: sources[required] = refs[required].duplicate()
		var data := {"stage_id":sid,"note":notes[sid],"source_stage_works":sources,"fields":{}}
		if sid in ["water_river","water_fall"]:
			data["artifact_id"] = "image_" + sid
			data.fields["observation"] = notes[sid]
		if sid == "water_fall": data.note = "" # Empty note must fall back to the observation.
		var created := Collection.create_work(state,{"title":sid,"kind":"note","content":data})
		check(bool(created.get("ok",false)),"Create source-chain fixture " + sid)
		if not bool(created.get("ok",false)): return
		refs[sid] = {"work_id":created.work_id,"version_id":created.version_id}
	var exhibition := Collection.get_version(state,refs.water_exhibit.work_id,refs.water_exhibit.version_id)
	var pages := UI.work_pages(state,exhibition)
	check(pages.size() == 2,"Production source chain resolves exactly two observation pages")
	if pages.size() == 2:
		check(pages[0].note == notes.water_river and pages[1].note == notes.water_fall,"Diptych keeps river and waterfall notes instead of preparation")
		check(pages[0].artifact_id == "image_water_river" and pages[1].artifact_id == "image_water_fall","Diptych keeps both original image references")
		check(pages[0].work_id == refs.water_river.work_id and pages[1].work_id == refs.water_fall.work_id,"Diptych retains pinned work and version references")
	check(UI.work_pages(state,exhibition) == pages,"Repeated page resolution retains both branches")
	var q := Content.get_quest("FG01")
	var saved_words: Dictionary = {}
	for i in range(q.adventure.lexicon.size()):
		var id := str(q.adventure.lexicon[i].lexeme_id)
		saved_words[id] = {"lexeme_id":id,"status":"want_review" if i == 0 else "recognized" if i == 1 else "used","recognized":true,"used":i != 1}
	var album := Collection.create_work(state,{"title":"Мой эфир","kind":"album","content":{"lexemes":saved_words},"source":{"quest_snapshot":q}})
	check(bool(album.get("ok",false)),"Create frozen vocabulary album fixture")
	if not bool(album.get("ok",false)): return
	var work := Collection.get_work(state,album.work_id)
	var version := Collection.get_version(state,album.work_id,album.version_id)
	var words := UI.work_vocabulary(work,version)
	check(words.size() == 100,"Album resolves all100 personal words from its snapshot")
	check(words[0].progress.status == "want_review" and words[1].progress.status == "recognized","Album retains individual saved statuses")
	var older := version.duplicate(true)
	older.content.lexemes = {str(q.adventure.lexicon[0].lexeme_id):saved_words[str(q.adventure.lexicon[0].lexeme_id)]}
	check(UI.work_vocabulary(work,older).size() == 1,"Older album version does not gain later words")
	var frozen_title := str(words[0].translation)
	q.adventure.lexicon[0].translation = "Изменённый текущий каталог"
	check(str(UI.work_vocabulary(work,version)[0].translation) == frozen_title,"Album wording stays frozen after catalog edits")
	var browser := Browser.new()
	root.add_child(browser)
	browser.setup(state)
	browser.open_work(album.work_id)
	await process_frame
	await process_frame
	var rendered := 0
	for node in browser.find_children("*","VBoxContainer",true,false):
		if node.has_meta("lexeme_id"): rendered += 1
	check(rendered == 100,"Browser renders all100 saved vocabulary rows")
	_check_layout(browser,"Saved vocabulary at125%")
	browser.free()
