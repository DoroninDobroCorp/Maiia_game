class_name CollectionBrowser
extends Control

## setup(state,audio=null), open_work(id), open_slot(room_id,slot_id), show_result(result).
## Placement preview is local; only the explicit confirm button emits place_exhibit.
const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Collections = preload("res://scripts/services/collection_service.gd")
const Artifacts = preload("res://scripts/services/artifact_service.gd")
signal closed
signal command_requested(operation: String, payload: Dictionary)
signal gallery_requested(room_id: String)
signal episode_requested(instance_id: String, stage_id: String)

var state: Dictionary = {}
var audio_service: Node
var content: VBoxContainer
var feedback: Label
var tab := 0
var search := ""
var kind_index := 0
var author_index := 0
var page := 0
var work_id := ""
var version_id := ""
var room_id := ""
var slot_id := ""
var preview_exhibit := ""
var preview_version := ""
var confirm_delete := false
var editing_version := false
var creating_work := false
var creation_draft: Dictionary = {}
const PAGE_SIZE := 12
const KINDS := ["", "image", "note", "album", "game", "diorama", "audio", "sculpture"]
const AUTHORSHIP := ["", "personal", "family", "story"]

func setup(game_state: Dictionary, audio_svc: Node = null) -> void:
	state = game_state.duplicate(true)
	audio_service = audio_svc
	var ctx := UI.context(state)
	work_id = str(ctx.get("work_id",work_id))
	version_id = str(ctx.get("version_id",version_id))
	room_id = str(ctx.get("room_id",room_id))
	slot_id = str(ctx.get("slot_id",slot_id))
	tab = int(ctx.get("tab", tab))
	if not slot_id.is_empty(): tab = 1
	_build()

func open_work(id: String) -> void:
	work_id = id
	version_id = ""
	_build()

func navigation_context() -> Dictionary:
	return {"work_id":work_id,"version_id":version_id,"room_id":room_id,"slot_id":slot_id,"tab":tab}

func open_slot(rid: String, sid: String) -> void:
	room_id = rid
	slot_id = sid
	tab = 1
	_build()

func show_result(result: Dictionary) -> void:
	feedback.text = UI.result_text(result)
	feedback.visible = true
	if bool(result.get("ok",false)):
		confirm_delete = false
		if result.has("work_id") and creating_work:
			work_id = str(result.work_id)
			creating_work = false
			creation_draft = {}
		if result.has("version_id"): editing_version = false; version_id = str(result.version_id)
		if result.has("placement"): preview_exhibit = ""

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_back()

func _back() -> void:
	if not preview_exhibit.is_empty(): preview_exhibit = ""; _build()
	elif editing_version: editing_version = false; _build()
	elif creating_work: creating_work = false; _build()
	elif not work_id.is_empty(): work_id = ""; _build()
	elif not slot_id.is_empty(): slot_id = ""; _build()
	else: closed.emit()

func _build() -> void:
	var s := UI.shell(self,state,"Мои работы","Здесь можно вернуться к прежним работам и выбрать, что показать на выставке.",_back)
	content = s.content
	feedback = s.feedback
	var tabs := UI.row(content)
	for i in range(3):
		var index := i
		UI.button(["Архив", "Выставочные залы", "Выставка главы"][i],tabs,func(): tab = index; work_id = ""; slot_id = ""; creating_work = false; _build(),tab == i)
	if creating_work: _create_work(); return
	if not work_id.is_empty(): _show_work(); return
	match tab:
		0: _archive()
		1: _rooms()
		2: _chapter()
	UI.focus_later(s.close,self)

func _archive() -> void:
	var filters := UI.row(content)
	var query := UI.input(filters,"Название, заметка или приключение…",search)
	query.text_submitted.connect(func(v): search = v; page = 0; _build())
	UI.button("Найти",filters,func(): search = query.text; page = 0; _build())
	var kind := UI.option(filters,["Все виды", "Изображения", "Заметки", "Альбомы", "Игры", "Диорамы", "Музыка", "Объекты"],kind_index)
	kind.item_selected.connect(func(i): kind_index = i; page = 0; _build())
	var author := UI.option(filters,["Все авторы", "Моя работа", "Семейная работа", "Находка"],author_index)
	author.item_selected.connect(func(i): author_index = i; page = 0; _build())
	var query_filters := {"search": search, "kind": KINDS[kind_index]}
	if not AUTHORSHIP[author_index].is_empty(): query_filters["authorship"] = AUTHORSHIP[author_index]
	var works := Collections.list_works(state, "player_01", query_filters)
	page = clampi(page, 0, maxi(0, ceili(float(works.size()) / PAGE_SIZE) - 1))
	var sc := UI.scroll(content)
	var head := UI.row(sc)
	UI.label("%d работ · страницы по %d" % [works.size(),PAGE_SIZE],head,14,UI.MUTED)
	UI.button("Добавить свою заметку",head,func(): creating_work = true; _build())
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	sc.add_child(grid)
	for work in works.slice(page*PAGE_SIZE,mini((page+1)*PAGE_SIZE,works.size())):
		var box := UI.card(grid)
		box.get_parent().size_flags_horizontal = SIZE_EXPAND_FILL
		var version := Collections.get_version(state,str(work.get("work_id", "")))
		var media := _media_path(version)
		var tex := UI.texture(media,256)
		if tex != null: _image(box,tex,100)
		UI.label(str(work.get("title", "Без названия")),box,21)
		UI.label(_author_label(work) + " · " + ("В процессе" if str(work.get("status", "")) != "COMPLETED" else "Завершено"),box,14,UI.TEAL)
		UI.label("Версий: %d" % work.get("versions", []).size(),box,14,UI.MUTED)
		var id := str(work.get("work_id", ""))
		UI.button("Посмотреть работу →",box,func(): open_work(id))
	if works.is_empty(): UI.label("Здесь появятся твои рисунки, наблюдения и игры. Можно сохранить первую заметку уже сейчас.",sc)
	var pagination := UI.row(content)
	var prev := UI.button("← Назад",pagination,func(): page -= 1; _build())
	prev.disabled = page == 0
	UI.label("%d / %d" % [page+1,maxi(1,ceili(float(works.size())/PAGE_SIZE))],pagination)
	var next := UI.button("Дальше →",pagination,func(): page += 1; _build())
	next.disabled = (page+1)*PAGE_SIZE >= works.size()

func _media_path(version: Dictionary) -> String:
	var data: Dictionary = version.get("content", {})
	var contextual: Dictionary = UI.context(state).get("media_paths", {})
	var id := str(data.get("artifact_id", ""))
	if contextual.has(id): return str(contextual[id])
	return Artifacts.media_path_for(state,id) if not id.is_empty() else str(data.get("media_path", ""))

func _image(parent: Node, tex: Texture2D, height: int = 220) -> void:
	var image := TextureRect.new()
	image.texture = tex
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size.y = height
	image.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(image)

func _author_label(work: Dictionary) -> String:
	return {"personal":"Моя работа","family":"Семейная работа","story":"Находка"}.get(str(work.get("authorship", {}).get("category", "personal")),"Моя работа")

func _show_work() -> void:
	var work := Collections.get_work(state,work_id)
	if work.is_empty(): UI.label("Работа недоступна в этом профиле.",content); return
	if version_id.is_empty(): version_id = str(work.get("current_version_id", ""))
	var version := Collections.get_version(state,work_id,version_id)
	var sc := UI.scroll(content)
	UI.label(str(work.get("title", "")),sc,27,UI.BRASS)
	UI.label(_author_label(work) + " · " + str(version.get("created_at", "")).left(10),sc,14,UI.MUTED)
	UI.label(str(work.get("authorship", {}).get("contribution", "")),sc)
	var versions: Array = work.get("versions", [])
	var names: Array = []
	var selected := 0
	for i in range(versions.size()):
		names.append("Версия %d · %s" % [i+1,str(versions[i].get("change_note",versions[i].get("created_at", "")))])
		if str(versions[i].get("version_id", "")) == version_id: selected = i
	var choose := UI.option(sc,names,selected)
	choose.item_selected.connect(func(i): version_id = str(versions[i].get("version_id", "")); _build())
	var tex := UI.texture(_media_path(version),1024)
	if tex != null: _image(sc,tex,270)
	elif not str(version.get("content", {}).get("artifact_id", "")).is_empty():
		UI.label("Изображение сейчас недоступно. Подпись и история работы сохранены.",sc,0,UI.MUTED)
	var data: Dictionary = version.get("content", {})
	UI.label(str(data.get("note",data.get("description", ""))),sc)
	for key in ["comparison","own_contribution","controls"]:
		if data.has(key): UI.label(str(data[key]),sc)
	var page_data := UI.work_pages(state,version)
	if not page_data.is_empty():
		var page_row: Container = UI.row(sc) if page_data.size() == 2 else UI.column(sc)
		for leaf in page_data:
			var box := UI.card(page_row)
			UI.label(str(leaf.get("title", "Страница")),box,20,UI.BRASS)
			var page_image := UI.texture(Artifacts.media_path_for(state,str(leaf.get("artifact_id", ""))),768)
			if page_image != null: _image(box,page_image,180)
			UI.label(str(leaf.get("note",leaf.get("text", ""))),box)
	_show_vocabulary(sc,work,version)
	if data.has("fields"):
		for key in data.fields: UI.label(str(data.fields[key]),sc)
	var actions := UI.row(content)
	UI.button("← Архив",actions,func(): work_id = ""; version_id = ""; editing_version = false; _build())
	UI.button("Новая версия",actions,func(): editing_version = true; _build())
	UI.button("Выставить…",actions,func():
		var existing := _exhibits_for(work_id)
		if existing.is_empty():
			command_requested.emit("create_exhibit",{"work_id":work_id,"recipe_id":_recipe_for(str(work.get("kind", "note"))),"caption":str(work.get("title", ""))})
		else:
			work_id = ""
			tab = 1
			_build(),true)
	if str(work.get("kind", "")) == "game":
		UI.label("Запуск доступен у терминала в галерее. Здесь сохраняются афиша, управление и история версий.",sc,0,UI.MUTED)
	if editing_version:
		var box := UI.card(sc)
		UI.label("Новая версия сохранит предыдущую",box,20,UI.BRASS)
		var text := UI.text_input(box,"Что изменилось?",str(data.get("note", "")))
		var changes := UI.input(box,"Короткое название изменений")
		UI.button("Сохранить новую версию",box,func():
			var revised := data.duplicate(true)
			revised["note"] = text.text
			command_requested.emit("add_work_version",{"work_id":work_id,"content":revised,"note":changes.text}),true)
		UI.button("Прикрепить изображение к новой версии",box,func():
			var revised := data.duplicate(true)
			revised["note"] = text.text
			command_requested.emit("import_image",{"work_id":work_id,"version_id":version_id,"content":revised,"note":changes.text}))

func _create_work() -> void:
	var sc := UI.scroll(content)
	var box := UI.card(sc)
	UI.label("Сохранить собственную заметку",box,24,UI.BRASS)
	var title := UI.input(box,"Название",str(creation_draft.get("title", "")))
	var text := UI.text_input(box,"Моё наблюдение, замысел или история…",str(creation_draft.get("note", "")),180)
	var author := UI.option(box,["Моя работа", "Семейная работа"])
	var contribution := UI.input(box,"Что я выбрала или сделала сама")
	UI.label("Работа появится со статусом «В процессе». Её можно выставить и продолжить позже.",box,0,UI.MUTED)
	UI.button("Сохранить в архив",content,func():
		creation_draft = {"title":title.text,"note":text.text}
		command_requested.emit("create_work",{"title":title.text,"kind":"note","authorship":{"category":"personal" if author.selected == 0 else "family","contribution":contribution.text},"content":{"note":text.text},"status":"IN_PROGRESS"}),true)

func _rooms() -> void:
	var rooms := Collections.list_rooms(state)
	if rooms.is_empty():
		UI.label("Галерея открывается после пробуждения станции.",content)
		return
	if room_id.is_empty() or not rooms.any(func(r): return str(r.get("room_id", "")) == room_id): room_id = str(rooms[0].get("room_id", ""))
	var names: Array = []
	var selected := 0
	for i in range(rooms.size()):
		names.append(str(rooms[i].get("title", "Мой зал")))
		if str(rooms[i].get("room_id", "")) == room_id: selected = i
	var header := UI.row(content)
	var picker := UI.option(header,names,selected)
	picker.item_selected.connect(func(i): room_id = str(rooms[i].get("room_id", "")); slot_id = ""; preview_exhibit = ""; _build())
	var enter := UI.button("Войти в этот зал →",header,func(): gallery_requested.emit(room_id),true)
	enter.visible = str(rooms[selected].get("template_id", "")) == "gallery_v1"
	var room: Dictionary = rooms[selected]
	var sc := UI.scroll(content)
	if not preview_exhibit.is_empty(): _preview(sc); return
	if not slot_id.is_empty(): _choose_exhibit(sc,room); return
	var occupied: Dictionary = {}
	for placement in Collections.list_placements(state,room_id): occupied[str(placement.get("slot_id", ""))] = placement
	UI.label("На выставке: %d / %d · выбери место" % [occupied.size(),Collections.list_slots(str(room.get("template_id", "gallery_v1"))).size()],sc,20,UI.BRASS)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	sc.add_child(grid)
	for slot in Collections.list_slots(str(room.get("template_id", "gallery_v1"))):
		var sid := str(slot.get("slot_id", ""))
		var box := UI.card(grid)
		UI.label(_slot_name(slot),box,20)
		var placement: Dictionary = occupied.get(sid, {})
		var exhibit := Collections.get_exhibit(state,str(placement.get("exhibit_id", "")))
		UI.label(str(exhibit.get("caption", "Свободное место")),box,0,UI.MUTED)
		UI.button("Выбрать работу" if placement.is_empty() else "Посмотреть / заменить",box,func(): slot_id = sid; _build())
	var manager := UI.card(sc)
	UI.label("Оформление и память зала",manager,24,UI.BRASS)
	var room_name := UI.input(manager,"Имя зала",str(room.get("title", "")))
	var themes := Collections.available_themes(state)
	var theme_names: Array = []
	for t in themes: theme_names.append({"warm":"Тёплая латунь","dusk":"Горные сумерки","daylight":"Дневной свет","constellation":"Созвездия находок","evening":"Вечер открытой станции"}.get(t,t))
	var theme_choice := UI.option(manager,theme_names,maxi(0,themes.find(str(room.get("theme", "warm")))))
	var frames := UI.option(manager,["Латунные рамки", "Деревянные рамки", "Светлые рамки"],maxi(0,["brass","wood","ivory"].find(str(room.get("frame_style", "brass")))))
	var buttons := UI.row(manager)
	UI.button("Применить оформление",buttons,func(): command_requested.emit("update_room",{"room_id":room_id,"name":room_name.text,"title":room_name.text,"theme":themes[theme_choice.selected],"frame_style":["brass","wood","ivory"][frames.selected]}))
	UI.button("Сохранить выставку",buttons,func(): command_requested.emit("snapshot_room",{"room_id":room_id,"name":room_name.text}),true)
	for snapshot in Collections.list_snapshots(state):
		if str(snapshot.get("room", {}).get("template_id", "")) != str(room.get("template_id", "")): continue
		var line := UI.row(manager)
		UI.label(str(snapshot.get("title", "Снимок выставки")),line)
		var id := str(snapshot.get("snapshot_id", ""))
		UI.button("Восстановить в этом зале",line,func(): command_requested.emit("restore_snapshot",{"room_id":room_id,"snapshot_id":id}))
	var new_name := UI.input(manager,"Название нового зала")
	var create := UI.button("Создать ещё один зал",manager,func(): command_requested.emit("create_room",{"name":new_name.text,"theme":"warm"}))
	create.disabled = not Collections.can_create_room(state)
	if create.disabled: UI.label("Новый зал доступен после финала одной истории или восьми разных личных работ.",manager,0,UI.MUTED)
	if str(room.get("template_id", "")) == "gallery_v1":
		UI.button("Удалить этот зал…",manager,func(): confirm_delete = not confirm_delete; _build())
	if confirm_delete and str(room.get("template_id", "")) == "gallery_v1":
		UI.label("Работы останутся в архиве. Перед удалением сохраним снимок расстановки.",manager)
		UI.button("Удалить зал и сохранить снимок",manager,func(): command_requested.emit("delete_room",{"room_id":room_id,"save_snapshot":true}))
	for snapshot in Collections.list_snapshots(state):
		if state.get("collections", {}).get("rooms", {}).has(str(snapshot.get("room_id", ""))): continue
		if str(snapshot.get("room", {}).get("template_id", "")) != "gallery_v1": continue
		var saved := UI.row(manager)
		UI.label("Сохранённый зал · " + str(snapshot.get("title", "Выставка")),saved)
		var snapshot_id := str(snapshot.get("snapshot_id", ""))
		UI.button("Вернуть сохранённый зал",saved,func(): command_requested.emit("restore_snapshot",{"snapshot_id":snapshot_id}))

func _slot_name(slot: Dictionary) -> String:
	var names := {"frame":"Рамка","pedestal":"Пьедестал","audio":"Проигрыватель","terminal":"Игровой терминал","table":"Выставочный стол","favorite":"Избранное"}
	return "%s %s" % [names.get(str(slot.get("kind", "")),"Место"),str(slot.get("slot_id", "")).get_slice("_",1).trim_prefix("0")]

func _choose_exhibit(parent: Node, room: Dictionary) -> void:
	var slot: Dictionary = {}
	for candidate in Collections.list_slots(str(room.get("template_id", "gallery_v1"))):
		if str(candidate.get("slot_id", "")) == slot_id: slot = candidate
	UI.label(_slot_name(slot) + " · выбрать работу",parent,24,UI.BRASS)
	for placement in Collections.list_placements(state,room_id):
		if str(placement.get("slot_id", "")) != slot_id: continue
		var inspected := Collections.inspect_placement(state,placement)
		UI.label("Сейчас: " + str(inspected.get("work", {}).get("title", "")),parent)
		var r := UI.row(parent)
		UI.button("Рассмотреть работу",r,func(): work_id = str(inspected.get("work", {}).get("work_id", "")); version_id = str(placement.get("version_id", "")); _build())
		UI.button("Убрать в архив",r,func(): command_requested.emit("remove_placement",{"room_id":room_id,"slot_id":slot_id}))
		if bool(inspected.get("launch_allowed",false)):
			var entry := str(inspected.get("version", {}).get("content", {}).get("launch_entry_id", ""))
			var launch := UI.button("Играть",r,func(): command_requested.emit("launch_work",{"work_id":inspected.get("work", {}).get("work_id", ""),"version_id":placement.get("version_id", ""),"launch_entry_id":entry}),true)
			launch.disabled = entry.is_empty()
	var shown := 0
	for exhibit in Collections.list_exhibits(state):
		if not slot.get("compatible_kinds", []).has(str(exhibit.get("kind", ""))): continue
		var work := Collections.get_work(state,str(exhibit.get("work_id", "")))
		var line := UI.row(parent)
		UI.label(str(work.get("title", "")),line)
		var eid := str(exhibit.get("exhibit_id", ""))
		var vid := str(work.get("current_version_id", ""))
		UI.button("Предварительный вид",line,func(): preview_exhibit = eid; preview_version = vid; _build())
		shown += 1
	if shown == 0: UI.label("Подходящих экспонатов пока нет. Открой работу в архиве и нажми «Выставить».",parent)
	UI.button("← Все места",content,func(): slot_id = ""; _build())

func _preview(parent: Node) -> void:
	var exhibit := Collections.get_exhibit(state,preview_exhibit)
	var work := Collections.get_work(state,str(exhibit.get("work_id", "")))
	var version := Collections.get_version(state,str(work.get("work_id", "")),preview_version)
	UI.label("Примерка · " + str(work.get("title", "")),parent,25,UI.BRASS)
	var tex := UI.texture(_media_path(version),768)
	if tex != null: _image(parent,tex,245)
	else: UI.label(str(version.get("content", {}).get("note",work.get("title", ""))),parent)
	var versions: Array = work.get("versions", [])
	var names: Array = []
	var chosen := 0
	for i in range(versions.size()):
		names.append("Версия %d · %s" % [i+1,str(versions[i].get("change_note", ""))])
		if str(versions[i].get("version_id", "")) == preview_version: chosen = i
	var version_picker := UI.option(parent,names,chosen)
	version_picker.item_selected.connect(func(i): preview_version = str(versions[i].get("version_id", "")); _build())
	var caption := UI.input(parent,"Подпись",str(exhibit.get("caption", "")))
	UI.label("Изображение вписывается целиком. На выставке останется выбранная версия, даже если позже появится новая.",parent,0,UI.MUTED)
	var actions := UI.row(content)
	UI.button("Отменить примерку",actions,func(): preview_exhibit = ""; _build())
	UI.button("Поставить здесь",actions,func(): command_requested.emit("place_exhibit",{"room_id":room_id,"slot_id":slot_id,"exhibit_id":preview_exhibit,"version_id":preview_version,"caption":caption.text,"decoration":{"caption":caption.text,"fit":"contain"}}),true)

func _exhibits_for(id: String) -> Array:
	return Collections.list_exhibits(state).filter(func(e): return str(e.get("work_id", "")) == id)

func _recipe_for(kind: String) -> String:
	return {"image":"frame","game":"game_terminal","album":"album","diorama":"diorama","audio":"audio","sculpture":"pedestal"}.get(kind,"card")

func _chapter() -> void:
	var sc := UI.scroll(content)
	UI.label("Вечер открытой станции",sc,28,UI.BRASS)
	UI.label("Выбери по одной работе из трёх историй. Существующая расстановка останется твоим выбором.",sc)
	var title := UI.input(sc,"Название выставки", "Станция на связи")
	var selections: Dictionary = {}
	var complete := true
	for qid in ["FG01","FG11","FG08"]:
		var works: Array = Collections.list_works(state).filter(func(w): return w.get("quest_ids", []).has(qid))
		var names: Array = ["Выбрать работу…"]
		for work in works: names.append(str(work.get("title", "")))
		var pick := UI.option(sc,names)
		pick.item_selected.connect(func(i):
			if i > 0: selections[qid] = str(works[i-1].get("work_id", ""))
			else: selections.erase(qid))
		if str(UI.instance_for(state,qid).get("status", "")) != "COMPLETED": complete = false
	var quiet := CheckButton.new()
	quiet.text = "Тихая выставка, без гостей"
	sc.add_child(quiet)
	if not complete: UI.label("Общий вечер станет доступен после трёх финалов. Маленькую выставку можно оформить в галерее уже сейчас.",sc,0,UI.MUTED)
	var submit := UI.button("Открыть выставку главы",content,func():
		if selections.size() < 3:
			show_result({"ok":false,"message":"Выбери три работы для выставки."})
			return
		command_requested.emit("chapter_finale",{"title":title.text,"work_ids":selections.values(),"selections":selections,"quiet":quiet.button_pressed}),true)
	submit.disabled = not complete

func _show_vocabulary(parent: Node, work: Dictionary, version: Dictionary) -> void:
	var words := UI.work_vocabulary(work,version)
	if words.is_empty(): return
	var box := UI.card(parent)
	UI.label("Мой словарь эфира · %d слов" % words.size(),box,23,UI.BRASS)
	UI.label("Слова и отметки этой сохранённой версии альбома",box,14,UI.MUTED)
	for word in words:
		var progress: Dictionary = word.get("progress", {})
		var status := str(progress.get("status", "encountered"))
		var markers: Array[String] = []
		if bool(progress.get("used",false)) or status == "used": markers.append("Использовала")
		elif bool(progress.get("recognized",false)) or status in ["recognized","recognised"]: markers.append("Узнаю")
		else: markers.append("Встретилось")
		if status == "want_review": markers.append("Хочу повторить")
		var line := UI.column(box)
		line.set_meta("lexeme_id",str(word.get("lexeme_id", "")))
		UI.label("%s — %s" % [str(word.get("base_form",word.get("lemma", ""))),str(word.get("translation", ""))],line,18)
		UI.label(" · ".join(markers),line,13,UI.TEAL)
		var example := str(word.get("example", ""))
		if not example.is_empty():
			UI.label(example + (" · " + str(word.get("example_translation", "")) if not str(word.get("example_translation", "")).is_empty() else ""),line,14,UI.MUTED)
