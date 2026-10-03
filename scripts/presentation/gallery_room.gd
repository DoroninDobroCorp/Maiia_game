class_name GalleryRoom
extends Node3D

## A separate navigable 3D gallery; setup rebuilds solely from saved placements.
## Navigation signals main opens: slot_requested(room_id,slot_id), work_requested(work_id),
## gallery_requested(room_id), collection_requested(), closed(). All 12 places are
## accessible through Tab-focused HUD buttons as well as physical raycast targets.
const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Collections = preload("res://scripts/services/collection_service.gd")
const Content = preload("res://scripts/services/adventure_content.gd")
const Artifacts = preload("res://scripts/services/artifact_service.gd")
signal closed
signal command_requested(operation: String, payload: Dictionary)
signal gallery_requested(room_id: String)
signal collection_requested
signal slot_requested(room_id: String, slot_id: String)
signal work_requested(work_id: String)
signal prop_clicked(prop_id: String)

var state: Dictionary = {}
var audio_service: Node
var room_id := ""
var camera: Camera3D
var geometry: Node3D
var hud: CanvasLayer
var feedback: Label
var navigation_enabled := true
var yaw := 0.0
var focus_slot := ""
var info: Label
var slots: Array = []
var room: Dictionary = {}
var material_wood: StandardMaterial3D
var material_brass: StandardMaterial3D
var material_paper: StandardMaterial3D
var material_wall: StandardMaterial3D
var material_dark: StandardMaterial3D

func setup(game_state: Dictionary, audio_svc: Node = null) -> void:
	state = game_state.duplicate(true)
	audio_service = audio_svc
	room_id = str(UI.context(state).get("room_id",room_id))
	if is_inside_tree(): _build()

func _ready() -> void:
	_build()

func set_navigation_enabled(enabled: bool) -> void:
	navigation_enabled = enabled

func enter_room(id: String) -> bool:
	for record in Collections.list_rooms(state):
		if str(record.get("room_id", "")) == id and str(record.get("template_id", "")) == "gallery_v1":
			room_id = id
			_build()
			return true
	return false

func show_result(result: Dictionary) -> void:
	if feedback != null:
		feedback.text = UI.result_text(result)
		feedback.visible = true

func _material(color: Color, roughness: float = .8, metallic: float = 0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

func _box(parent: Node3D, pos: Vector3, dimensions: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = dimensions
	mesh.mesh = shape
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	return mesh

func _label(parent: Node3D, text: String, pos: Vector3, font_size: int = 40, width: float = 600) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.font_size = font_size
	label.pixel_size = .002
	label.modulate = Color("f0e3c8")
	label.outline_size = 3
	label.width = width
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var rooms: Array = Collections.list_rooms(state).filter(func(record): return str(record.get("template_id", "")) == "gallery_v1")
	room = {}
	for record in rooms:
		if str(record.get("room_id", "")) == room_id: room = record
	if room.is_empty() and not rooms.is_empty(): room = rooms[0]; room_id = str(room.get("room_id", ""))
	geometry = Node3D.new()
	geometry.name = "GalleryGeometry"
	add_child(geometry)
	var theme_name := str(room.get("theme", "warm"))
	var frame_color: Color = {"brass":Color("b8965e"),"wood":Color("624633"),"ivory":Color("dfd3ba")}.get(str(room.get("frame_style", "brass")),Color("b8965e"))
	material_wood = _material(Color("826548"))
	material_wood.albedo_texture = load("res://assets/textures/walnut.png")
	material_brass = _material(frame_color,.3,.65)
	material_paper = _material(Color("e3d4b3"))
	material_wall = _material(Color("404751") if theme_name in ["dusk","constellation"] else Color("797160") if theme_name == "daylight" else Color("665644"))
	material_wall.albedo_texture = load("res://assets/textures/plaster.png")
	material_wall.uv1_scale = Vector3(3,2,1)
	material_dark = _material(Color("17242b"))
	_box(geometry,Vector3(0,-.08,0),Vector3(10,.16,12),material_wood)
	for x in range(-5,6):
		_box(geometry,Vector3(x*.9,.005,0),Vector3(.012,.012,12),material_dark)
	_box(geometry,Vector3(0,2,-5),Vector3(10,4,.18),material_wall)
	_box(geometry,Vector3(-5,2,0),Vector3(.18,4,10),material_wall)
	_box(geometry,Vector3(5,2,0),Vector3(.18,4,10),material_wall)
	_box(geometry,Vector3(0,4,0),Vector3(10,.1,10),material_dark)
	for x in [-4.88,4.88]:
		_box(geometry,Vector3(x,.22,0),Vector3(.08,.42,10),material_wood)
	_box(geometry,Vector3(0,.22,-4.88),Vector3(10,.42,.08),material_wood)
	_box(geometry,Vector3(0,3.35,-4.87),Vector3(4,.52,.08),material_dark)
	_label(geometry,str(room.get("title", "Моя галерея")),Vector3(0,3.35,-4.8),54,1500)
	_label(geometry,"S U R   /   Л И Ч Н Ы Й   А Р Х И В",Vector3(0,2.9,-4.81),24,1600)
	# Entrance is independent from the station's observatory passage.
	_box(geometry,Vector3(4.88,1.35,3.3),Vector3(.08,2.7,1.35),material_wood)
	var exit_sign := _label(geometry,"← СТАНЦИЯ",Vector3(4.77,2.0,3.3),32)
	exit_sign.rotation.y = -PI/2
	# Narrow brass cornice and four gentle pools of light.
	for x in [-4.8,4.8]:
		_box(geometry,Vector3(x,3.65,0),Vector3(.12,.09,10),material_brass)
	for pos in [Vector3(-3,3.2,-2),Vector3(3,3.2,-2),Vector3(-3,3.2,2),Vector3(3,3.2,2)]:
		var lamp := OmniLight3D.new()
		lamp.position = pos
		lamp.omni_range = 6.5
		lamp.light_energy = 1.5 if theme_name in ["daylight","evening"] else 1.1
		lamp.light_color = Color("b7c9e3") if theme_name in ["dusk","constellation"] else Color("ffd8a0")
		geometry.add_child(lamp)
		_box(geometry,pos,Vector3(.14,.25,.14),material_brass)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("152332")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bbc2cf")
	environment.ambient_light_energy = .42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	geometry.add_child(env)
	camera = Camera3D.new()
	camera.position = Vector3(0,1.75,4.3)
	camera.rotation_degrees.x = -5
	camera.fov = 68
	camera.current = true
	geometry.add_child(camera)
	yaw = 0
	slots = Collections.list_slots(str(room.get("template_id", "gallery_v1")))
	var placements: Dictionary = {}
	for p in Collections.list_placements(state,room_id): placements[str(p.get("slot_id", ""))] = p
	for i in range(slots.size()): _build_slot(i,slots[i],placements.get(str(slots[i].get("slot_id", "")), {}))
	if theme_name == "constellation":
		var star_mat := _material(Color("dfc792"))
		star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for i in range(32):
			var star := _box(geometry,Vector3(-4.5+fmod(i*1.71,9),3.95,-4.1+fmod(i*2.34,8.2)),Vector3(.04,.02,.04),star_mat)
			star.rotation.y = i
	if bool(state.get("adventures", {}).get("chapters_by_profile", {}).get("player_01", {}).get("completed",false)):
		var evening_light := OmniLight3D.new()
		evening_light.position = Vector3(0,2.9,-3)
		evening_light.light_color = Color("ffce84")
		evening_light.light_energy = .7
		evening_light.omni_range = 4
		geometry.add_child(evening_light)
	_build_discoveries()
	_build_hud(rooms)

func _build_slot(index: int, slot: Dictionary, placement: Dictionary) -> void:
	var sid := str(slot.get("slot_id", ""))
	var anchor := Node3D.new()
	anchor.name = sid
	geometry.add_child(anchor)
	var kind := str(slot.get("kind", "frame"))
	if index < 3: anchor.position = Vector3(-3.15+index*3.15,1.95,-4.76)
	elif index < 6:
		anchor.position = Vector3(-4.77,1.95,-2.4+(index-3)*2.5)
		anchor.rotation.y = PI/2
	elif index < 9: anchor.position = Vector3(-2.8+(index-6)*2.8,0,-1.2)
	elif kind == "audio": anchor.position = Vector3(3.75,0,2.5); anchor.rotation.y = -PI/3
	elif kind == "terminal": anchor.position = Vector3(4.3,0,-2.7); anchor.rotation.y = -PI/3
	else: anchor.position = Vector3(-1.3,0,2.15)
	var view := Collections.inspect_placement(state,placement) if not placement.is_empty() else {}
	var caption := str(placement.get("decoration", {}).get("caption",view.get("exhibit", {}).get("caption", "Свободное место")))
	var surface_pos := Vector3.ZERO
	var surface_size := Vector2(1.5,1.02)
	if kind == "frame":
		_box(anchor,Vector3.ZERO,Vector3(1.68,1.2,.09),material_brass)
		_box(anchor,Vector3(0,0,.06),Vector3(1.5,1.02,.04),material_paper)
		surface_pos = Vector3(0,0,.09)
		_label(anchor,caption,Vector3(0,-.82,.08),24,740)
	elif kind == "pedestal":
		_box(anchor,Vector3(0,.55,0),Vector3(.9,1.1,.9),material_wood)
		_box(anchor,Vector3(0,1.12,0),Vector3(1.08,.09,1.08),material_brass)
		_box(anchor,Vector3(0,1.38,0),Vector3(.72,.45,.12),material_paper)
		surface_pos = Vector3(0,1.39,.07)
		surface_size = Vector2(.66,.38)
		_label(anchor,caption,Vector3(0,.87,.465),22,420)
	elif kind == "terminal":
		_box(anchor,Vector3(0,.75,0),Vector3(1.2,1.5,.7),material_wood)
		_box(anchor,Vector3(0,1.55,0),Vector3(1.28,.7,.55),material_brass)
		_box(anchor,Vector3(0,1.55,.29),Vector3(1.08,.51,.035),material_dark)
		_box(anchor,Vector3(0,1.06,.41),Vector3(1.28,.12,.35),material_brass)
		surface_pos = Vector3(0,1.55,.32)
		surface_size = Vector2(1.04,.46)
		_label(anchor,caption,Vector3(0,.72,.38),25,540)
		_label(anchor,"ИГРАТЬ / ВЕРСИИ" if not placement.is_empty() else "МОЯ ПЕРВАЯ ИГРА",Vector3(0,1.97,.06),20,750)
	elif kind == "audio":
		_box(anchor,Vector3(0,.58,0),Vector3(1.1,1.16,.7),material_wood)
		var platter := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = .34
		disc.bottom_radius = .34
		disc.height = .04
		platter.mesh = disc
		platter.material_override = material_dark
		platter.position = Vector3(0,1.19,0)
		anchor.add_child(platter)
		_box(anchor,Vector3(.31,1.24,.06),Vector3(.035,.035,.4),material_brass)
		surface_pos = Vector3(0,.83,.36)
		surface_size = Vector2(.8,.4)
		_label(anchor,caption,Vector3(0,.35,.37),22,510)
	else:
		_box(anchor,Vector3(0,.77,0),Vector3(2.1,.12,1.22),material_wood)
		for x in [-.9,.9]:
			for z in [-.46,.46]: _box(anchor,Vector3(x,.36,z),Vector3(.1,.72,.1),material_brass)
		_box(anchor,Vector3(0,1.04,-.2),Vector3(1.6,.44,.09),material_paper)
		_box(anchor,Vector3(0,1.04,-.13),Vector3(.025,.44,.025),material_brass)
		surface_pos = Vector3(0,1.04,-.14)
		surface_size = Vector2(1.52,.38)
		_label(anchor,caption,Vector3(0,.7,.66),22,900)
	_render_surface(anchor,surface_pos,surface_size,view)
	var area := Area3D.new()
	area.input_ray_pickable = true
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8,1.5,.4) if kind == "frame" else Vector3(1.35,2,1.15)
	collider.shape = box
	collider.position.y = 0 if kind == "frame" else 1
	area.add_child(collider)
	anchor.add_child(area)
	area.input_event.connect(func(_camera,event,_position,_normal,_shape):
		if navigation_enabled and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			slot_requested.emit(room_id,sid))
	area.mouse_entered.connect(func():
		focus_slot = sid
		if info != null: info.text = caption + "  ·  Enter — рассмотреть")
	area.mouse_exited.connect(func():
		focus_slot = ""
		if info != null: info.text = "W/S — шаг · A/D — поворот · Tab — выбрать место · Esc — станция")

func _render_surface(parent: Node3D, pos: Vector3, dimensions: Vector2, view: Dictionary) -> void:
	var pages := UI.work_pages(state,view.get("version", {}))
	if pages.size() >= 2:
		for i in range(2):
			var page: Dictionary = pages[i]
			var child_view := {"media_path":Artifacts.media_path_for(state,str(page.get("artifact_id", ""))),"work":{"title":page.get("title", "Страница")},"version":{"content":{"note":page.get("note", "")}}}
			_render_surface(parent,pos+Vector3((i-.5)*dimensions.x*.51,0,.017),Vector2(dimensions.x*.47,dimensions.y),child_view)
		return
	var texture := UI.texture(str(view.get("media_path", "")),768)
	if texture != null:
		var plane := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		var aspect := float(texture.get_width()) / maxf(1,texture.get_height())
		var w := minf(dimensions.x,dimensions.y*aspect)
		mesh.size = Vector2(w,w/aspect)
		plane.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		plane.material_override = material
		plane.position = pos + Vector3(0,0,.015)
		parent.add_child(plane)
	else:
		var text := "＋\nМесто для истории"
		if not view.is_empty():
			var data: Dictionary = view.get("version", {}).get("content", {})
			text = str(view.get("work", {}).get("title", "Работа")) + "\n" + str(data.get("note", "")).left(100)
			if bool(view.get("placeholder",false)): text += "\nМатериал недоступен"
		var label := _label(parent,text,pos+Vector3(0,0,.02),22,dimensions.x/.002)
		label.modulate = Color("25343b") if dimensions.x > 1.2 or dimensions.x < .7 else Color("e3d4b3")

func _build_hud(rooms: Array) -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.make_theme(state)
	hud.add_child(root)
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 12
	root.add_child(top)
	var header := UI.row(top)
	UI.label("S U R  /  " + str(room.get("title", "Галерея")),header,22,UI.BRASS)
	var names: Array = []
	var selected := 0
	for i in range(rooms.size()):
		names.append(str(rooms[i].get("title", "Зал")))
		if str(rooms[i].get("room_id", "")) == room_id: selected = i
	var picker := UI.option(header,names,selected)
	picker.item_selected.connect(func(i): gallery_requested.emit(str(rooms[i].get("room_id", ""))))
	UI.button("Архив / оформить",header,func(): collection_requested.emit())
	UI.button("На станцию · Esc",header,func(): closed.emit())
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.offset_top = -184
	bottom.offset_bottom = -12
	root.add_child(bottom)
	var col := UI.column(bottom)
	info = UI.label("W/S — шаг · A/D — поворот · Tab — выбрать место · Esc — станция",col,14,UI.MUTED)
	var row := UI.row(col)
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		var sid := str(slot.get("slot_id", ""))
		var icon := "Р" if i < 6 else "П" if i < 9 else "♪" if i == 9 else "И" if i == 10 else "А"
		var btn := UI.button("%s%d" % [icon,i+1],row,func(): slot_requested.emit(room_id,sid))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = str(slot.get("kind", "")) + " · " + sid
		btn.focus_entered.connect(func(): info.text = "Место %d · Enter — выбрать работу" % (i+1))
	var secrets := UI.row(col)
	for secret in Content.secrets():
		if str(secret.get("location_group", "")) != "gallery": continue
		var sid := str(secret.get("secret_id", ""))
		UI.button("Инициалы на рамке" if sid == "frame_initial" else "Прислушаться у скамьи",secrets,func(): prop_clicked.emit("secret_"+sid))
	feedback = UI.label("",col,14,UI.TEAL)
	feedback.visible = false

func _process(delta: float) -> void:
	if not navigation_enabled or camera == null: return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit: return
	var turn := float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)) - float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
	yaw += turn * delta * 1.25
	camera.rotation.y = yaw
	var forward := float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
	camera.position += -camera.basis.z * forward * delta * 2.1
	camera.position.x = clampf(camera.position.x,-4.15,4.15)
	camera.position.z = clampf(camera.position.z,-3.8,4.35)
	camera.position.y = 1.75

func _unhandled_key_input(event: InputEvent) -> void:
	if not navigation_enabled: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			closed.emit()
		elif event.keycode == KEY_ENTER and not focus_slot.is_empty():
			get_viewport().set_input_as_handled()
			slot_requested.emit(room_id,focus_slot)

func _build_discoveries() -> void:
	# Two visible, optional details are independent of mission completion.
	var navy := _material(Color("233c4a"))
	_box(geometry,Vector3(0,.017,.8),Vector3(3.65,.012,6.2),navy)
	for x in [-1.75,1.75]: _box(geometry,Vector3(x,.025,.8),Vector3(.028,.01,5.98),material_brass)
	var window := Node3D.new()
	window.position = Vector3(4.86,2.5,.2)
	window.rotation.y = -PI/2
	geometry.add_child(window)
	_box(window,Vector3.ZERO,Vector3(2.25,1.65,.08),material_brass)
	var glass := _material(Color("142a40"))
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_box(window,Vector3(0,0,.06),Vector3(2.09,1.5,.04),glass)
	var moon := MeshInstance3D.new()
	var circle := SphereMesh.new()
	circle.radius = .16
	circle.height = .32
	moon.mesh = circle
	moon.position = Vector3(.65,.4,.12)
	moon.scale.z = .05
	moon.material_override = _material(Color("dccd9e"))
	window.add_child(moon)
	for i in range(3):
		var ridge := _box(window,Vector3(-.6+i*.55,-.45,.12),Vector3(.55,.42,.035),navy)
		ridge.rotation.z = .4 if i%2 == 0 else -.35
	_box(window,Vector3(0,0,.16),Vector3(.05,1.5,.05),material_wood)
	_box(window,Vector3(0,-.8,.1),Vector3(2.3,.11,.28),material_wood)
	var bench := Node3D.new()
	bench.position = Vector3(3.95,0,.5)
	bench.rotation.y = -PI/2
	geometry.add_child(bench)
	_box(bench,Vector3(0,.44,0),Vector3(1.8,.12,.65),material_wood)
	for x in [-.65,.65]: _box(bench,Vector3(x,.22,0),Vector3(.1,.44,.5),material_brass)
	var plaque := Node3D.new()
	plaque.position = Vector3(-3.83,1.37,-4.67)
	geometry.add_child(plaque)
	_box(plaque,Vector3.ZERO,Vector3(.18,.11,.025),material_brass)
	_label(plaque,"S · R",Vector3(0,0,.022),22,200)
	for secret in Content.secrets():
		if str(secret.get("location_group", "")) != "gallery": continue
		var sid := str(secret.get("secret_id", ""))
		var parent: Node3D = plaque if sid == "frame_initial" else bench
		var area := Area3D.new()
		var hit := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(.38,.3,.3) if sid == "frame_initial" else Vector3(1.9,.75,.85)
		hit.shape = shape
		if sid != "frame_initial": hit.position.y = .4
		area.add_child(hit)
		parent.add_child(area)
		area.input_event.connect(func(_camera,event,_position,_normal,_shape):
			if navigation_enabled and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				prop_clicked.emit("secret_"+sid))
