class_name StationAdventureProps
extends Node3D

## Small physical changes are rebuilt from saved state. No quest rules live here.
signal prop_clicked(prop_id: String)
signal prop_hovered(prop_id: String, title: String)
signal prop_unhovered(prop_id: String)

var radio_card: Label3D
var arcade_screen: Label3D
var arcade_lights: Array[MeshInstance3D] = []
var water_panels: Array[MeshInstance3D] = []
var water_caption: Label3D
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
	# Letter on the receiver. It keeps the radio itself accessible.
	var letter := Node3D.new()
	letter.position = Vector3(0.84, 1.32, 0.38)
	add_child(letter)
	_box(letter, Vector3(0.28, 0.15, 0.018), Vector3.ZERO, paper)
	radio_card = _label(letter, "ВАМ ПИСЬМО", Vector3(0, 0, 0.013), 16, ink, 0.0011)
	_hit(letter, Vector3.ZERO, Vector3(0.30, 0.18, 0.06), "adventure_radio", "Письмо Норы • Голоса Южного Маяка")
	# A small folded blueprint, not a new menu floating in the room.
	var plan := Node3D.new()
	plan.position = Vector3(0.40, 0.949, 1.01)
	plan.rotation_degrees = Vector3(-72, 0, -8)
	add_child(plan)
	_box(plan, Vector3(0.31, 0.21, 0.014), Vector3.ZERO, blue)
	_label(plan, "ЧЕРТЁЖ ТЕО\n[  ?  ]", Vector3(0, 0, 0.012), 18, Color(0.83, 0.88, 0.76), 0.0012)
	_hit(plan, Vector3.ZERO, Vector3(0.33, 0.23, 0.055), "adventure_workshop", "Чертёж Тео • Автомат для станции")
	# Field folio next to the wall map.
	var folio := Node3D.new()
	folio.position = Vector3(-2.26, 1.03, 0.45)
	folio.rotation_degrees.y = 90
	add_child(folio)
	_box(folio, Vector3(0.40, 0.25, 0.03), Vector3.ZERO, paper)
	_label(folio, "ДВА ГОЛОСА\nВОДЫ", Vector3(0, 0, 0.022), 18, ink, 0.0015)
	_hit(folio, Vector3.ZERO, Vector3(0.45, 0.30, 0.09), "adventure_water", "Полевой альбом • Два голоса воды")
	# A shelf with a progressively assembled arcade and two water panels.
	var shelf := Node3D.new()
	shelf.position = Vector3(1.74, 0.0, 1.78)
	shelf.rotation_degrees.y = -28
	add_child(shelf)
	_box(shelf, Vector3(0.62, 0.06, 0.42), Vector3(0, 0.72, 0), wood)
	for x in [-0.25, 0.25]:
		_box(shelf, Vector3(0.045, 0.72, 0.045), Vector3(x, 0.36, 0.13), brass)
	_box(shelf, Vector3(0.26, 0.43, 0.19), Vector3(-0.11, 0.96, 0), blue)
	_box(shelf, Vector3(0.22, 0.16, 0.018), Vector3(-0.11, 1.05, 0.104), _material(Color(0.02, 0.035, 0.04)))
	arcade_screen = _label(shelf, "ТВОЯ\nИГРА", Vector3(-0.11, 1.05, 0.117), 16, Color(0.58, 0.86, 0.71), 0.0012)
	for i in range(5):
		arcade_lights.append(_box(shelf, Vector3(0.025, 0.025, 0.012), Vector3(-0.19 + i * 0.041, 0.91, 0.107), brass))
	_hit(shelf, Vector3(-0.11, 0.99, 0.04), Vector3(0.30, 0.46, 0.24), "adventure_workshop", "Мой игровой автомат • продолжить проект")
	for i in range(2):
		var panel := _box(shelf, Vector3(0.095, 0.025 + i * 0.10, 0.15), Vector3(0.125 + i * 0.10, 0.775 + i * 0.05, 0.04), _material(Color(0.20, 0.54, 0.61), 0.25))
		water_panels.append(panel)
	water_caption = _label(shelf, "ДВА ОКНА", Vector3(0.16, 0.92, 0.13), 14, Color(0.81, 0.85, 0.75), 0.0011)
	_hit(shelf, Vector3(0.17, 0.88, 0.03), Vector3(0.22, 0.27, 0.20), "adventure_water", "Два окна диорамы • мой атлас")
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
	var secret := _box(self, Vector3(0.14, 0.10, 0.02), Vector3(-0.38, 1.03, 0.29), brass)
	_label(secret, "✦", Vector3(0, 0, 0.016), 20, ink, 0.002)
	_hit(secret, Vector3.ZERO, Vector3(0.16, 0.14, 0.08), "secret_station_star", "Карточка с отверстиями • осмотреть")
	var note := _box(self, Vector3(0.15, 0.11, 0.02), Vector3(-1.19, 0.965, 0.44), paper)
	_label(note, "↶", Vector3(0, 0, 0.016), 20, ink, 0.002)
	_hit(note, Vector3.ZERO, Vector3(0.18, 0.14, 0.08), "secret_station_postcard", "Оборот старой открытки • осмотреть")

func apply_view(view: Dictionary) -> void:
	_build()
	visible = bool(view.get("awakened", false))
	if not visible:
		return
	radio_card.text = str(view.get("radio_label", "ВАМ ПИСЬМО")).left(28)
	var progress: int = int(view.get("game_steps", 0))
	arcade_screen.text = "МОЯ ИГРА\nГОТОВА" if progress >= 6 else ("ВЕРСИЯ\nВ РАБОТЕ" if progress > 1 else "ТВОЯ\nИГРА")
	for i in range(arcade_lights.size()):
		arcade_lights[i].visible = progress > i + 1
	water_panels[0].visible = bool(view.get("river_done", false))
	water_panels[1].visible = bool(view.get("fall_done", false))
	water_caption.text = "МОИ НАБЛЮДЕНИЯ" if water_panels[0].visible or water_panels[1].visible else "ДВА ОКНА"
	gallery_light.light_energy = 0.95 if bool(view.get("chapter_complete", false)) else 0.55
	var favourites: Array = view.get("favourites", [])
	for i in range(3):
		var item: Dictionary = favourites[i] if i < favourites.size() else {}
		favourite_labels[i].text = str(item.get("title", "МОЯ РАБОТА")).left(26)
		var mat := favourite_images[i].material_override as StandardMaterial3D
		mat.albedo_texture = _texture(str(item.get("media_path", "")))
		mat.albedo_color = Color.WHITE if mat.albedo_texture != null else Color(0.86, 0.77, 0.59)

func _texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	var im := Image.load_from_file(path)
	if im == null or im.is_empty():
		return null
	if maxi(im.get_width(), im.get_height()) > 512:
		var ratio: float = 512.0 / maxi(im.get_width(), im.get_height())
		im.resize(maxi(1, int(im.get_width() * ratio)), maxi(1, int(im.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(im)
	_texture_cache[path] = texture
	return texture

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

func _hit(parent: Node3D, pos: Vector3, size: Vector3, id: String, title: String) -> void:
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
