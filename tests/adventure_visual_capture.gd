extends SceneTree

## Isolated synthetic fixtures. No player save, media or launch registry is read.
const Hub = preload("res://scenes/ui/adventure_hub.tscn")
const Episode = preload("res://scenes/ui/adventure_episode.tscn")
const Browser = preload("res://scenes/ui/collection_browser.tscn")
const Gallery = preload("res://scenes/world/gallery_room.tscn")
const Editor = preload("res://scenes/ui/adventure_editor.tscn")
const Content = preload("res://scripts/services/adventure_content.gd")
const Collections = preload("res://scripts/services/collection_service.gd")
const Artifacts = preload("res://scripts/services/artifact_service.gd")
var state: Dictionary
var out_dir := "/tmp/sur-adventure-ui"
var failure_count := 0

func _init() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	for i in range(14): await process_frame
	# Static scenes may not emit frame_post_draw while idle; frames suffice.
	if root.get_texture().get_image().save_png(out_dir.path_join(name + ".png")) != OK: failure_count += 1

func _picture(name: String, falling: bool) -> String:
	var img := Image.create(480,320,false,Image.FORMAT_RGB8)
	img.fill(Color("d9d0b0"))
	for y in range(320):
		for x in range(480):
			if y < 118: img.set_pixel(x,y,Color("445d70"))
			var ridge := 80 + int(40*sin(x*.022)+35*sin(x*.011))
			if y > ridge and y < 170: img.set_pixel(x,y,Color("637868"))
			var water_x := 180+int(100*sin(y*.009)) if not falling else 260
			var half_width := 25+y/9 if not falling else 40
			if y > 125 and absi(x-water_x) < half_width: img.set_pixel(x,y,Color("74b9b8") if x%17 < 12 else Color("cee3d5"))
	var source := out_dir.path_join(name+"_fixture.png")
	img.save_png(source)
	var result := Artifacts.import_local_image(state,source,name)
	if not bool(result.get("ok",false)): failure_count += 1; return ""
	return str(result.artifact.artifact_id)

func work(title: String, kind: String, recipe: String, data: Dictionary) -> Dictionary:
	var created := Collections.create_work(state,{"title":title,"kind":kind,"status":"COMPLETED","authorship":{"category":"personal","contribution":"Синтетический материал для проверки интерфейса"},"content":data,"quest_ids":["FG08" if kind == "diorama" else "FG11" if kind == "game" else "FG01"]})
	var exhibit := Collections.create_exhibit(state,str(created.get("work_id", "")),recipe)
	if not bool(created.get("ok",false)) or not bool(exhibit.get("ok",false)): failure_count += 1
	return {"work_id":created.get("work_id", ""),"exhibit_id":exhibit.get("exhibit_id", ""),"version_id":created.get("version_id", "")}

func run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_factor = 1.25
	DirAccess.make_dir_recursive_absolute(out_dir)
	Artifacts.use_test_storage(out_dir.path_join("managed_media"))
	state = {"settings":{"ui_scale":1.25},"s00_progress":{"station_awakened":true},"phase_b":{"quest_instances":{},"published_versions":{}},"adventures":{"progress":{}},"collections":{}}
	Collections.ensure_gallery(state)
	var quests := Content.quests()
	for q in quests:
		var id := str(q.quest_id)
		state.phase_b.quest_instances[id] = {"instance_id":id,"quest_id":id,"profile_id":"player_01","status":"ACTIVE","quest_snapshot":q}
		state.adventures.progress[id] = {"stages":{}}
		for i in range(q.adventure.stages.size()):
			var stage: Dictionary = q.adventure.stages[i]
			state.adventures.progress[id].stages[stage.stage_id] = {"status":"AVAILABLE" if i == 0 else "LOCKED","draft":{}}
	state["_adventure_ui"] = {"catalog":quests}
	var hub := Hub.instantiate()
	root.add_child(hub)
	hub.setup(state)
	await capture("01_hub_125")
	hub.history_quest = quests[2]
	hub._build()
	await capture("02_route_125")
	hub.free()
	state._adventure_ui = {"quest":quests[0],"instance_id":"FG01","stage_id":"es_intro"}
	var episode := Episode.instantiate()
	root.add_child(episode)
	episode.setup(state)
	await capture("03_episode_125")
	episode.free()
	var river_id := _picture("Речная страница",false)
	var fall_id := _picture("Водопадная страница",true)
	var river := work("Первый голос воды","image","frame",{"artifact_id":river_id,"note":"Вода огибает камни и идёт вдоль берега."})
	var fall := work("Второй голос воды","image","frame",{"artifact_id":fall_id,"note":"Здесь вода падает сверху, а у подножия появляются брызги."})
	var diptych := work("Два голоса воды","diorama","water_diptych",{"note":"Река идёт вдоль берега, водопад падает сверху.","pages":[{"title":"Река","artifact_id":river_id,"note":"Линия воды поворачивает вокруг камней."},{"title":"Водопад","artifact_id":fall_id,"note":"Длинные вертикальные линии и брызги."}]})
	var game := work("Собери свет для станции","game","game_terminal",{"artifact_id":river_id,"note":"Версия для визуального теста","controls":"Стрелки — движение · R — новая попытка","launch_entry_id":"visual_fixture_only"})
	var album := work("Мой первый эфир","album","album",{"note":"Hola, Nora. Mi estación se llama SUR.","pages":[{"title":"Первый конверт","text":"hola · gracias · sí · no · adiós"},{"title":"Мой заказ","text":"Agua y pan, por favor."}]})
	var sculpture := work("Камни из долины","sculpture","sculpture",{"note":"Наблюдение формы: гладкие углы и тонкие светлые полосы."})
	var music := work("Ритм дождя","audio","audio",{"note":"Короткий собственный ритм записан словами: тихо, тихо, громче."})
	var note := work("Заметка на обороте","note","note",{"note":"У старой рамки есть крошечные инициалы."})
	for i in range(8): work("Страница архива %d" % i,"note","note",{"note":"Синтетическая запись для проверки страниц"})
	var room: Dictionary = Collections.list_rooms(state)[0]
	var slots := Collections.list_slots()
	var exhibits := [river,fall,game,album,diptych,note,sculpture,album,diptych,music,game,diptych]
	for i in range(12):
		var placed := Collections.place_exhibit(state,room.room_id,slots[i].slot_id,exhibits[i].exhibit_id)
		if not bool(placed.get("ok",false)): push_error("Visual fixture placement: " + str(placed)); failure_count += 1
	var second := Collections.create_room(state,"Всё про воду","dusk")
	if not bool(second.get("ok",false)): failure_count += 1
	state._adventure_ui = {}
	var browser := Browser.instantiate()
	root.add_child(browser)
	browser.setup(state)
	await capture("04_archive_125")
	browser.tab = 1
	browser._build()
	await capture("05_rooms_125")
	browser.open_work(diptych.work_id)
	await capture("07_diptych_125")
	browser.work_id = ""
	browser.open_slot(room.room_id,"terminal_01")
	await capture("08_terminal_125")
	browser.slot_id = ""
	browser.room_id = str(second.get("room", {}).get("room_id", ""))
	browser._build()
	await capture("09_second_room_125")
	browser.free()
	var gallery := Gallery.instantiate()
	root.add_child(gallery)
	gallery.setup(state)
	await capture("06_gallery_125")
	gallery.free()
	for saved_room in Collections.list_rooms(state):
		if str(saved_room.template_id) == "gallery_v1": Collections.delete_room(state,str(saved_room.room_id))
	state._adventure_ui = {"tab":1}
	var recovery := Browser.instantiate()
	root.add_child(recovery)
	recovery.setup(state)
	for i in range(3): await process_frame
	for scroll in recovery.find_children("*","ScrollContainer",true,false):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	if not recovery.find_children("*","Button",true,false).any(func(button): return button.text == "Вернуть сохранённый зал"): failure_count += 1
	await capture("11_deleted_halls_125")
	recovery.free()
	state._adventure_ui = {}
	var editor := Editor.instantiate()
	root.add_child(editor)
	editor.setup(state)
	await capture("10_editor_125")
	editor.free()
	Artifacts.restore_default_storage()
	print("Adventure visual captures: " + out_dir + " · failures: %d" % failure_count)
	quit(0 if failure_count == 0 else 1)
