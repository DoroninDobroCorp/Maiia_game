class_name StationAdventureProps
extends Node3D

## Small physical changes are rebuilt from saved state. No quest rules live here.
signal prop_clicked(prop_id: String)
signal prop_hovered(prop_id: String, title: String)
signal prop_unhovered(prop_id: String)

var arcade_screen: Label3D
var arcade_lights: Array[MeshInstance3D] = []
var water_panels: Array[MeshInstance3D] = []
var water_caption: Label3D
var workshop_entry: Node3D
var water_entry: Node3D
var workshop_label: Label3D
var water_label: Label3D
var radio_tag: Node3D
var radio_tag_label: Label3D
var workshop_hit: Area3D
var water_hit: Area3D
var arcade_result: Node3D
var water_result: Node3D
var gallery_light: OmniLight3D
var favourite_labels: Array[Label3D] = []
var favourite_images: Array[MeshInstance3D] = []
var _texture_cache: Dictionary = {}
var _built := false

func _ready() -> void:
	_build()
	visible = false

func _build() -> void:
	if _built:
		return
	_built = true
	var wood := _material(Color(0.19, 0.12, 0.095))
	var brass := _material(Color(0.69, 0.47, 0.20), 0.65)
	var paper := _material(Color(0.86, 0.77, 0.59))
	var blue := _material(Color(0.08, 0.25, 0.29))
	var ink := Color(0.21, 0.17, 0.15)
	# Gallery entrance on the side wall, well away from the observatory door.
	var door := Node3D.new()
	door.position = Vector3(-2.28, 0.0, 1.98)
	door.rotation_degrees.y = 90
	add_child(door)
	_box(door, Vector3(0.91, 2.16, 0.12), Vector3(0, 1.08, 0), brass)
	_box(door, Vector3(0.78, 2.05, 0.14), Vector3(0, 1.02, 0.02), wood)
	_box(door, Vector3(0.60, 0.40, 0.035), Vector3(0, 1.63, 0.12), blue)
	_label(door, "ГАЛЕРЕЯ\nМОИХ ОТКРЫТИЙ", Vector3(0, 1.64, 0.145), 18, Color(0.96, 0.85, 0.59), 0.00165)
	_box(door, Vector3(0.03, 0.16, 0.07), Vector3(0.25, 0.97, 0.14), brass)
	_hit(door, Vector3(0, 1.04, 0.12), Vector3(0.86, 2.12, 0.20), "gallery_door", "Галерея моих открытий • войти")
	gallery_light = OmniLight3D.new()
	gallery_light.position = Vector3(-1.94, 2.18, 1.92)
	gallery_light.light_color = Color(1.0, 0.78, 0.42)
	gallery_light.omni_range = 2.8
	gallery_light.light_energy = 0.55
	add_child(gallery_light)
	# A small folded blueprint, not a new menu floating in the room.
	var plan := Node3D.new()
	workshop_entry = plan
	plan.position = Vector3(0.40, 0.949, 1.01)
	plan.rotation_degrees = Vector3(-72, 0, -8)
	add_child(plan)
	_box(plan, Vector3(0.31, 0.21, 0.014), Vector3.ZERO, blue)
	workshop_label = _label(plan, "ЧЕРТЁЖ ТЕО\nАВТОМАТ", Vector3(0, 0, 0.012), 18, Color(0.83, 0.88, 0.76), 0.0012)
	workshop_hit = _hit(plan, Vector3.ZERO, Vector3(0.33, 0.23, 0.055), "adventure_workshop", "Чертёж Тео · миссия «Автомат для станции»")
	# FG08 gets its own obvious desk object, separate from the journal, radio,
	# and Theo's blueprint. Keeping all three current mission entrances on the
	# desk makes the one-object-one-mission rule readable at a glance.
	var folio := Node3D.new()
	water_entry = folio
	folio.position = Vector3(-0.28, 0.949, 0.98)
	folio.rotation_degrees = Vector3(-72, 0, 7)
	add_child(folio)
	_box(folio, Vector3(0.40, 0.25, 0.03), Vector3.ZERO, paper)
	water_label = _label(folio, "ДВА ГОЛОСА\nВОДЫ", Vector3(0, 0, 0.022), 18, ink, 0.0015)
	water_hit = _hit(folio, Vector3.ZERO, Vector3(0.45, 0.30, 0.09), "adventure_water", "Полевой альбом · миссия «Два голоса воды»")

	# The radio is the third mission object: a paper tag on its speaker cloth names
	# the mission, so the three desk objects read as one family.
	radio_tag = Node3D.new()
	radio_tag.position = Vector3(0.74, 1.115, 0.682)
	add_child(radio_tag)
	var tag_paper := _material(Color(0.93, 0.85, 0.66))
	tag_paper.emission_enabled = true
	tag_paper.emission = Color(0.42, 0.37, 0.27)
	_box(radio_tag, Vector3(0.23, 0.12, 0.008), Vector3.ZERO, tag_paper)
	radio_tag_label = _label(radio_tag, "ЭФИР НОРЫ\nначать", Vector3(0, 0, 0.007), 22, Color(0.09, 0.07, 0.06), 0.0011)

	# FG11 result gets its own home in the observatory passage. It is not a
	# second mission entrance while the blueprint is active.
	arcade_result = Node3D.new()
	arcade_result.position = Vector3(8.48, 0.0, 0.82)
	arcade_result.rotation_degrees.y = -90
	add_child(arcade_result)
	_box(arcade_result, Vector3(0.34, 0.78, 0.28), Vector3(0, 0.49, 0), blue)
	_box(arcade_result, Vector3(0.28, 0.20, 0.018), Vector3(0, 0.64, 0.151), _material(Color(0.02, 0.035, 0.04)))
	arcade_screen = _label(arcade_result, "МОЯ ИГРА\nГОТОВА", Vector3(0, 0.64, 0.163), 16, Color(0.58, 0.86, 0.71), 0.0012)
	for i in range(5):
		arcade_lights.append(_box(arcade_result, Vector3(0.025, 0.025, 0.012), Vector3(-0.09 + i * 0.045, 0.42, 0.151), brass))
	_label(arcade_result, "ОСТАЛСЯ В МАСТЕРСКОЙ", Vector3(0, 0.02, 0.17), 13, Color(0.83, 0.78, 0.67), 0.00115)

	# FG08 result lives on the side wall by the gallery entrance, away from the desk.
	water_result = Node3D.new()
	water_result.position = Vector3(-2.24, 1.38, 1.28)
	water_result.rotation_degrees.y = 90
	add_child(water_result)
	for i in range(2):
		_box(water_result, Vector3(0.30, 0.34, 0.045), Vector3(-0.17 + i * 0.34, 0.0, 0.0), brass)
		var panel := _box(water_result, Vector3(0.25, 0.29, 0.026), Vector3(-0.17 + i * 0.34, 0.0, 0.026), _material(Color(0.20, 0.54, 0.61), 0.25))
		water_panels.append(panel)
	water_caption = _label(water_result, "МОЙ ПОЛЕВОЙ ДИПТИХ", Vector3(0, -0.25, 0.055), 14, Color(0.81, 0.85, 0.75), 0.0011)
	# Three personal favourites on the right wall, clear of all original anchors.
	for i in range(3):
		var frame := Node3D.new()
		frame.position = Vector3(2.28, 1.82, 0.32 + i * 0.61)
		frame.rotation_degrees.y = -90
		add_child(frame)
		_box(frame, Vector3(0.46, 0.40, 0.05), Vector3.ZERO, brass)
		var surface := _box(frame, Vector3(0.41, 0.35, 0.016), Vector3(0, 0, 0.033), paper.duplicate())
		favourite_images.append(surface)
		favourite_labels.append(_label(frame, "МОЯ РАБОТА", Vector3(0, -0.255, 0.045), 16, Color(0.85, 0.80, 0.66), 0.0015))
		_hit(frame, Vector3.ZERO, Vector3(0.48, 0.46, 0.13), "station_favourite_%d" % (i + 1), "Избранная работа • выбрать или посмотреть")
	# Two optional discoveries; their visibility never depends on real work.
	var secret := _box(self, Vector3(0.14, 0.10, 0.02), Vector3(5.40, 1.58, 0.78), brass)
	secret.rotation_degrees.y = 90
	_label(secret, "✦", Vector3(0, 0, 0.016), 20, ink, 0.002)
	_hit(secret, Vector3.ZERO, Vector3(0.16, 0.14, 0.08), "secret_station_star", "Карточка с отверстиями • осмотреть")
	var note := _box(self, Vector3(0.15, 0.11, 0.02), Vector3(5.40, 1.30, 1.12), paper)
	note.rotation_degrees.y = 90
	_label(note, "↶", Vector3(0, 0, 0.016), 20, ink, 0.002)
	_hit(note, Vector3.ZERO, Vector3(0.18, 0.14, 0.08), "secret_station_postcard", "Оборот старой открытки • осмотреть")

func apply_view(view: Dictionary) -> void:
	_build()
	visible = bool(view.get("awakened", false))
	if not visible:
		return
	var progress: int = int(view.get("game_steps", 0))
	var missions: Dictionary = view.get("mission_progress", {})
	workshop_label.text = _tag("ЧЕРТЁЖ ТЕО", "АВТОМАТ", missions.get("FG11", {}))
	water_label.text = _tag("ДВА ГОЛОСА ВОДЫ", "", missions.get("FG08", {}), "ДВА ГОЛОСА\nВОДЫ")
	radio_tag_label.text = _tag("ЭФИР НОРЫ", "начать", missions.get("FG01", {}), "", "в эфире")
	var workshop_complete := bool(view.get("workshop_complete", false))
	var water_complete := bool(view.get("water_complete", false))
	var river_path := str(view.get("river_image_path", ""))
	var fall_path := str(view.get("fall_image_path", ""))
	var has_water_images := not river_path.is_empty() or not fall_path.is_empty()
	var river_done := bool(view.get("river_done", false))
	var fall_done := bool(view.get("fall_done", false))

	workshop_entry.visible = not workshop_complete
	water_entry.visible = not water_complete
	workshop_hit.input_ray_pickable = not workshop_complete
	water_hit.input_ray_pickable = not water_complete
	arcade_result.visible = workshop_complete
	water_result.visible = water_complete or has_water_images or river_done or fall_done
	arcade_screen.text = "МОЯ ИГРА\nГОТОВА"
	for i in range(arcade_lights.size()):
		arcade_lights[i].visible = workshop_complete or progress > i + 1
	water_panels[0].visible = water_complete or river_done or not river_path.is_empty()
	water_panels[1].visible = water_complete or fall_done or not fall_path.is_empty()
	water_caption.text = "МОЙ ПОЛЕВОЙ ДИПТИХ"

	if not river_path.is_empty() and water_panels.size() > 0:
		var tex := _texture(river_path)
		if tex != null:
			var mat := water_panels[0].material_override as StandardMaterial3D
			if mat == null:
				mat = _material(Color.WHITE)
				water_panels[0].material_override = mat
			mat.albedo_texture = tex
			mat.albedo_color = Color.WHITE

	if not fall_path.is_empty() and water_panels.size() > 1:
		var tex := _texture(fall_path)
		if tex != null:
			var mat := water_panels[1].material_override as StandardMaterial3D
			if mat == null:
				mat = _material(Color.WHITE)
				water_panels[1].material_override = mat
			mat.albedo_texture = tex
			mat.albedo_color = Color.WHITE
	gallery_light.light_energy = 0.95 if bool(view.get("chapter_complete", false)) else 0.55
	var favourites: Array = view.get("favourites", [])
	for i in range(3):
		var item: Dictionary = favourites[i] if i < favourites.size() else {}
		favourite_labels[i].text = str(item.get("title", "МОЯ РАБОТА")).left(26)
		var mat := favourite_images[i].material_override as StandardMaterial3D
		mat.albedo_texture = _texture(str(item.get("media_path", "")))
		mat.albedo_color = Color.WHITE if mat.albedo_texture != null else Color(0.86, 0.77, 0.59)

func _texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var global_path := ProjectSettings.globalize_path(path) if (path.begins_with("user://") or path.begins_with("res://")) else path
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(global_path):
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	var im := Image.load_from_file(global_path)
	if im == null or im.is_empty():
		return null
	if maxi(im.get_width(), im.get_height()) > 512:
		var ratio: float = 512.0 / maxi(im.get_width(), im.get_height())
		im.resize(maxi(1, int(im.get_width() * ratio)), maxi(1, int(im.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(im)
	_texture_cache[path] = texture
	return texture

## Tag text for a mission object: its name, then where the player is in the path.
func _tag(title: String, idle: String, record: Dictionary, idle_full: String = "", finished_text: String = "готово") -> String:
	var total := int(record.get("total", 0))
	var done := int(record.get("done", 0))
	if total <= 0 or done <= 0:
		return idle_full if not idle_full.is_empty() else "%s\n%s" % [title, idle]
	if done >= total:
		return "%s\n%s" % [title, finished_text]
	return "%s\nшаг %d из %d" % [title, done + 1, total]

func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = 0.58
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
	return node

func _label(parent: Node3D, text_value: String, pos: Vector3, font_size: int, color: Color, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.position = pos
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	parent.add_child(label)
	return label

func _hit(parent: Node3D, pos: Vector3, size: Vector3, id: String, title: String) -> Area3D:
	var area := Area3D.new()
	area.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	area.add_child(col)
	parent.add_child(area)
	area.mouse_entered.connect(func():
		if visible:
			prop_hovered.emit(id, title)
	)
	area.mouse_exited.connect(func(): prop_unhovered.emit(id))
	area.input_event.connect(func(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int):
		if visible and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			prop_clicked.emit(id)
	)
	return area
