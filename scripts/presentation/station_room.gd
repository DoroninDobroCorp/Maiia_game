class_name StationRoom
extends Node3D

## 3D-комната станции SUR (Эль-Больсон, Патагония)
## Реализует утверждённый художественный бриф: дерево, латунь, сумерки за окном,
## две световые фазы, интерактивные объекты верстака.

signal prop_clicked(prop_id: String)
signal prop_hovered(prop_id: String, prop_title: String)
signal prop_unhovered(prop_id: String)

# Основные узлы сцены
var camera: Camera3D
var base_camera_pos := Vector3(0.0, 1.42, 2.05)
var base_camera_rot := Vector3(-13.5, 0.0, 0.0)

var ceiling_light: OmniLight3D
var desk_lamp_spot: SpotLight3D
var desk_lamp_omni: OmniLight3D
var radio_light: OmniLight3D
var dust_particles: CPUParticles3D

# Интерактивные 3D элементы
var sign_label: Label3D
var sign_mesh: MeshInstance3D
var prop_anchor: Node3D
var radio_dial_mesh: MeshInstance3D
var desk_lamp_bulb_mesh: MeshInstance3D
var puzzle_box_dials: Array[MeshInstance3D] = []

# Материалы для фаз
var mat_lamp_off: StandardMaterial3D
var mat_lamp_on: StandardMaterial3D
var mat_radio_off: StandardMaterial3D
var mat_radio_on: StandardMaterial3D

# Состояние
var is_stage_2: bool = false
var reduce_motion: bool = false
var hovered_prop_id: String = ""
var target_cam_offset := Vector3.ZERO
var current_cam_offset := Vector3.ZERO

func _ready() -> void:
	_setup_environment()
	_setup_camera()
	_setup_room_geometry()
	_setup_lighting()
	_setup_props()

func _process(delta: float) -> void:
	if not reduce_motion:
		current_cam_offset = current_cam_offset.lerp(target_cam_offset, delta * 4.0)
		camera.position = base_camera_pos + current_cam_offset
	else:
		camera.position = base_camera_pos

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not reduce_motion:
		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		var norm_x: float = (event.position.x / vp_size.x) * 2.0 - 1.0
		var norm_y: float = (event.position.y / vp_size.y) * 2.0 - 1.0
		target_cam_offset = Vector3(norm_x * 0.07, -norm_y * 0.04, 0.0)

# ==================== СВЕТ И СТАДИИ МИРА ====================

func set_world_stage(stage_2_awakened: bool, animate: bool = false) -> void:
	is_stage_2 = stage_2_awakened
	
	if stage_2_awakened:
		desk_lamp_bulb_mesh.material_override = mat_lamp_on
		radio_dial_mesh.material_override = mat_radio_on
		dust_particles.emitting = true
		
		if animate:
			var tween: Tween = create_tween().set_parallel(true)
			tween.tween_property(desk_lamp_spot, "light_energy", 2.2, 1.2)
			tween.tween_property(desk_lamp_omni, "light_energy", 1.0, 1.2)
			tween.tween_property(radio_light, "light_energy", 0.8, 1.2)
			tween.tween_property(ceiling_light, "light_energy", 0.7, 1.2)
		else:
			desk_lamp_spot.light_energy = 2.2
			desk_lamp_omni.light_energy = 1.0
			radio_light.light_energy = 0.8
			ceiling_light.light_energy = 0.7
	else:
		desk_lamp_bulb_mesh.material_override = mat_lamp_off
		radio_dial_mesh.material_override = mat_radio_off
		dust_particles.emitting = false
		desk_lamp_spot.light_energy = 0.0
		desk_lamp_omni.light_energy = 0.0
		radio_light.light_energy = 0.0
		ceiling_light.light_energy = 0.45

func update_station_sign(station_name: String, emblem_id: String) -> void:
	var emblem_symbols: Dictionary = {
		"feather": "🪶",
		"star": "✦",
		"sprout": "🌱",
		"gear": "⚙"
	}
	var symbol: String = emblem_symbols.get(emblem_id, "✦")
	sign_label.text = symbol + " " + station_name + " " + symbol

func update_desk_prop(prop_id: String) -> void:
	for child in prop_anchor.get_children():
		child.queue_free()
	
	match prop_id:
		"compass":
			_build_compass_prop(prop_anchor)
		"crystal":
			_build_crystal_prop(prop_anchor)
		"owl":
			_build_owl_prop(prop_anchor)
		"astrolabe":
			_build_astrolabe_prop(prop_anchor)
		_:
			_build_compass_prop(prop_anchor)

func update_dials_visual(dial_indices: Array) -> void:
	for i in range(min(dial_indices.size(), puzzle_box_dials.size())):
		var dial: MeshInstance3D = puzzle_box_dials[i]
		var idx: int = int(dial_indices[i])
		var target_rot: float = float(idx) * (TAU / 3.0)
		var tween: Tween = create_tween()
		tween.tween_property(dial, "rotation:x", target_rot, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ==================== ГЕОМЕТРИЯ И МАТЕРИАЛЫ ====================

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.16) # Сумеречное индиго
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.24, 0.22, 0.32)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.2
	
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 48.0
	camera.position = base_camera_pos
	camera.rotation_degrees = base_camera_rot
	add_child(camera)

func _setup_lighting() -> void:
	# Верхний абажурный свет (вечерний уют)
	ceiling_light = OmniLight3D.new()
	ceiling_light.position = Vector3(0.0, 2.2, 0.6)
	ceiling_light.omni_range = 7.5
	ceiling_light.light_color = Color(1.0, 0.88, 0.72)
	ceiling_light.light_energy = 0.45
	ceiling_light.shadow_enabled = true
	add_child(ceiling_light)
	
	# Сумеречный лунный свет за окном
	var window_light := DirectionalLight3D.new()
	window_light.rotation_degrees = Vector3(-25.0, 25.0, 0.0)
	window_light.light_color = Color(0.42, 0.52, 0.78)
	window_light.light_energy = 0.55
	window_light.shadow_enabled = true
	add_child(window_light)
	
	# Настольная лампа (загорается в фазе 2)
	desk_lamp_spot = SpotLight3D.new()
	desk_lamp_spot.position = Vector3(0.46, 1.48, 0.44)
	desk_lamp_spot.rotation_degrees = Vector3(-62.0, -35.0, 0.0)
	desk_lamp_spot.spot_range = 2.8
	desk_lamp_spot.spot_angle = 50.0
	desk_lamp_spot.spot_attenuation = 1.2
	desk_lamp_spot.light_color = Color(1.0, 0.85, 0.55)
	desk_lamp_spot.light_energy = 0.0
	desk_lamp_spot.shadow_enabled = true
	add_child(desk_lamp_spot)
	
	desk_lamp_omni = OmniLight3D.new()
	desk_lamp_omni.position = Vector3(0.46, 1.48, 0.44)
	desk_lamp_omni.omni_range = 1.8
	desk_lamp_omni.light_color = Color(1.0, 0.82, 0.52)
	desk_lamp_omni.light_energy = 0.0
	add_child(desk_lamp_omni)
	
	# Подсветка шкалы радио
	radio_light = OmniLight3D.new()
	radio_light.position = Vector3(0.92, 1.05, 0.55)
	radio_light.omni_range = 1.0
	radio_light.light_color = Color(1.0, 0.65, 0.25)
	radio_light.light_energy = 0.0
	add_child(radio_light)
	
	# Тёплые парящие пылинки в луче света лампы
	dust_particles = CPUParticles3D.new()
	dust_particles.position = Vector3(0.35, 1.15, 0.6)
	dust_particles.amount = 48
	dust_particles.lifetime = 4.0
	dust_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust_particles.emission_box_extents = Vector3(0.35, 0.25, 0.35)
	dust_particles.gravity = Vector3(0.0, 0.015, 0.0)
	dust_particles.initial_velocity_min = 0.01
	dust_particles.initial_velocity_max = 0.04
	dust_particles.scale_amount_min = 0.012
	dust_particles.scale_amount_max = 0.024
	dust_particles.color = Color(1.0, 0.88, 0.55, 0.65)
	dust_particles.emitting = false
	add_child(dust_particles)

func _setup_room_geometry() -> void:
	# Материалы
	var mat_wall := StandardMaterial3D.new()
	mat_wall.albedo_color = Color(0.86, 0.82, 0.74)
	mat_wall.roughness = 0.9
	
	var mat_wood_dark := StandardMaterial3D.new()
	mat_wood_dark.albedo_color = Color(0.24, 0.15, 0.09)
	mat_wood_dark.roughness = 0.7
	
	var mat_floor := StandardMaterial3D.new()
	mat_floor.albedo_color = Color(0.22, 0.14, 0.08)
	mat_floor.roughness = 0.65
	
	var mat_desk := StandardMaterial3D.new()
	mat_desk.albedo_color = Color(0.38, 0.25, 0.15)
	mat_desk.roughness = 0.45
	
	# Пол
	var floor_box := _create_box(Vector3(6.0, 0.1, 5.0), mat_floor)
	floor_box.position = Vector3(0.0, -0.05, 0.5)
	add_child(floor_box)
	
	# Задняя стена
	var back_wall := _create_box(Vector3(6.0, 3.6, 0.1), mat_wall)
	back_wall.position = Vector3(0.0, 1.8, -0.85)
	add_child(back_wall)
	
	# Левая стена (с картой)
	var left_wall := _create_box(Vector3(0.1, 3.6, 5.0), mat_wall)
	left_wall.position = Vector3(-2.4, 1.8, 0.5)
	add_child(left_wall)
	
	# Потолочные деревянные балки
	var beam_top := _create_box(Vector3(6.0, 0.2, 0.25), mat_wood_dark)
	beam_top.position = Vector3(0.0, 2.7, -0.7)
	add_child(beam_top)
	
	var beam_cross := _create_box(Vector3(0.25, 0.2, 5.0), mat_wood_dark)
	beam_cross.position = Vector3(-0.8, 2.7, 0.5)
	add_child(beam_cross)
	
	# Большое панорамное окно в центре
	_build_window_and_mountains()
	
	# Стол / Верстак станции на переднем плане
	var desk_top := _create_box(Vector3(2.6, 0.08, 1.15), mat_desk)
	desk_top.position = Vector3(0.0, 0.88, 0.72)
	add_child(desk_top)
	
	# Ножки стола
	var desk_leg_l := _create_box(Vector3(0.09, 0.88, 0.09), mat_wood_dark)
	desk_leg_l.position = Vector3(-1.2, 0.44, 1.15)
	add_child(desk_leg_l)
	
	var desk_leg_r := _create_box(Vector3(0.09, 0.88, 0.09), mat_wood_dark)
	desk_leg_r.position = Vector3(1.2, 0.44, 1.15)
	add_child(desk_leg_r)
	
	# Полка на верстаке (задний бортик)
	var desk_shelf := _create_box(Vector3(2.4, 0.22, 0.28), mat_wood_dark)
	desk_shelf.position = Vector3(0.0, 1.02, 0.24)
	add_child(desk_shelf)
	
	# Дверь в обсерваторию (справа сзади)
	_build_observatory_door()

func _build_window_and_mountains() -> void:
	var mat_frame := StandardMaterial3D.new()
	mat_frame.albedo_color = Color(0.22, 0.14, 0.08)
	mat_frame.roughness = 0.6
	
	# Оконная рама
	var frame_bottom := _create_box(Vector3(2.2, 0.1, 0.12), mat_frame)
	frame_bottom.position = Vector3(0.0, 1.18, -0.82)
	add_child(frame_bottom)
	
	var frame_top := _create_box(Vector3(2.2, 0.1, 0.12), mat_frame)
	frame_top.position = Vector3(0.0, 2.38, -0.82)
	add_child(frame_top)
	
	var frame_left := _create_box(Vector3(0.1, 1.3, 0.12), mat_frame)
	frame_left.position = Vector3(-1.05, 1.78, -0.82)
	add_child(frame_left)
	
	var frame_right := _create_box(Vector3(0.1, 1.3, 0.12), mat_frame)
	frame_right.position = Vector3(1.05, 1.78, -0.82)
	add_child(frame_right)
	
	# Крестовина окна
	var frame_mid_v := _create_box(Vector3(0.05, 1.2, 0.08), mat_frame)
	frame_mid_v.position = Vector3(0.0, 1.78, -0.82)
	add_child(frame_mid_v)
	
	var frame_mid_h := _create_box(Vector3(2.1, 0.05, 0.08), mat_frame)
	frame_mid_h.position = Vector3(0.0, 1.78, -0.82)
	add_child(frame_mid_h)
	
	# Фон за окном: небо и горные силуэты (Серро Пилтрикитрон)
	var sky_plane := MeshInstance3D.new()
	var sky_mesh := QuadMesh.new()
	sky_mesh.size = Vector2(4.5, 2.5)
	sky_plane.mesh = sky_mesh
	sky_plane.position = Vector3(0.0, 1.85, -2.5)
	
	var mat_sky := StandardMaterial3D.new()
	mat_sky.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_sky.albedo_color = Color(0.10, 0.12, 0.22) # Глубокий патагонский вечер
	sky_plane.material_override = mat_sky
	add_child(sky_plane)
	
	# Звёзды за окном
	var star_mesh := BoxMesh.new()
	star_mesh.size = Vector3(0.025, 0.025, 0.01)
	var mat_star := StandardMaterial3D.new()
	mat_star.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_star.albedo_color = Color(1.0, 1.0, 0.9)
	
	var star_positions: Array[Vector3] = [
		Vector3(-0.6, 2.15, -2.4),
		Vector3(-0.25, 2.28, -2.4),
		Vector3(0.35, 2.20, -2.4),
		Vector3(0.72, 2.12, -2.4),
		Vector3(0.15, 2.32, -2.4),
		Vector3(-0.85, 2.05, -2.4),
		Vector3(0.88, 2.25, -2.4)
	]
	for spos in star_positions:
		var st := MeshInstance3D.new()
		st.mesh = star_mesh
		st.material_override = mat_star
		st.position = spos
		add_child(st)
	
	# Луна
	var moon := MeshInstance3D.new()
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 0.09
	moon_mesh.height = 0.18
	moon.mesh = moon_mesh
	var mat_moon := StandardMaterial3D.new()
	mat_moon.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_moon.albedo_color = Color(0.95, 0.95, 0.85)
	moon.material_override = mat_moon
	moon.position = Vector3(0.55, 2.18, -2.35)
	add_child(moon)
	
	# Горные гряды (3 слоя глубины)
	var mat_mount_far := StandardMaterial3D.new()
	mat_mount_far.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_mount_far.albedo_color = Color(0.14, 0.17, 0.28) # Дальний план
	
	var mat_mount_mid := StandardMaterial3D.new()
	mat_mount_mid.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_mount_mid.albedo_color = Color(0.10, 0.13, 0.22) # Средний план
	
	var mat_mount_near := StandardMaterial3D.new()
	mat_mount_near.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_mount_near.albedo_color = Color(0.06, 0.08, 0.14) # Ближние сосны и скалы
	
	# Дальняя вершина
	_add_mountain_peak(Vector3(-0.2, 1.45, -2.2), Vector3(1.8, 0.9, 0.1), mat_mount_far)
	_add_mountain_peak(Vector3(0.8, 1.35, -2.2), Vector3(1.4, 0.7, 0.1), mat_mount_far)
	# Средняя гряда
	_add_mountain_peak(Vector3(-0.7, 1.30, -1.9), Vector3(1.5, 0.65, 0.1), mat_mount_mid)
	_add_mountain_peak(Vector3(0.4, 1.25, -1.9), Vector3(1.6, 0.6, 0.1), mat_mount_mid)
	# Ближние силуэты хребта
	_add_mountain_peak(Vector3(0.0, 1.15, -1.6), Vector3(2.4, 0.45, 0.1), mat_mount_near)

func _add_mountain_peak(pos: Vector3, msize: Vector3, mat: Material) -> void:
	var prism := MeshInstance3D.new()
	var prism_mesh := PrismMesh.new()
	prism_mesh.size = msize
	prism.mesh = prism_mesh
	prism.material_override = mat
	prism.position = pos
	add_child(prism)

func _build_observatory_door() -> void:
	var mat_door := StandardMaterial3D.new()
	mat_door.albedo_color = Color(0.26, 0.16, 0.10)
	mat_door.roughness = 0.7
	
	var mat_iron := StandardMaterial3D.new()
	mat_iron.albedo_color = Color(0.2, 0.2, 0.22)
	mat_iron.metallic = 0.9
	mat_iron.roughness = 0.4
	
	# Дверное полотно
	var door := _create_box(Vector3(0.75, 1.7, 0.06), mat_door)
	door.position = Vector3(1.85, 1.05, -0.78)
	add_child(door)
	
	# Остекление дверного арка
	var mat_glass := StandardMaterial3D.new()
	mat_glass.albedo_color = Color(0.5, 0.65, 0.7, 0.7)
	mat_glass.roughness = 0.2
	var door_window := _create_box(Vector3(0.4, 0.4, 0.07), mat_glass)
	door_window.position = Vector3(1.85, 1.45, -0.78)
	add_child(door_window)
	
	# Дверная латунная ручка
	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.88, 0.72, 0.32)
	mat_brass.metallic = 0.85
	mat_brass.roughness = 0.3
	var handle := _create_box(Vector3(0.04, 0.14, 0.08), mat_brass)
	handle.position = Vector3(1.54, 0.98, -0.74)
	add_child(handle)
	
	# Интерактивная зона двери
	_make_interactive_area(door, "door_observatory", "Дверь обсерватории [Осмотреть]", Vector3(0.8, 1.8, 0.2))

# ==================== ИНТЕРАКТИВНЫЕ ОБЪЕКТЫ ====================

func _setup_props() -> void:
	# 1. Вывеска станции над столом
	_build_station_sign()
	
	# 2. Шкатулка с дисками (мини-игра шифра)
	_build_puzzle_box()
	
	# 3. Винтажный радиоприёмник «Южный Маяк»
	_build_radio_receiver()
	
	# 4. Настенная карта долины
	_build_valley_map()
	
	# 5. Экспонат верстака (реликвия)
	prop_anchor = Node3D.new()
	prop_anchor.position = Vector3(0.02, 1.15, 0.24)
	add_child(prop_anchor)
	_build_compass_prop(prop_anchor)
	
	var prop_zone := _create_box(Vector3(0.3, 0.35, 0.3), null)
	prop_zone.position = Vector3(0.02, 1.25, 0.24)
	prop_zone.visible = false
	add_child(prop_zone)
	_make_interactive_area(prop_zone, "desk_prop", "Экспонат верстака [Осмотреть]", Vector3(0.32, 0.36, 0.32))
	
	# 6. Латунная лампа верстака
	_build_desk_lamp()
	
	# 7. Журнал станции на краю стола
	_build_station_journal()
	
	# 8. Декоративные мелочи на верстаке (линейка, карандаш, чернильница)
	_build_workbench_clutter()

func _build_station_sign() -> void:
	var mat_sign_wood := StandardMaterial3D.new()
	mat_sign_wood.albedo_color = Color(0.34, 0.20, 0.11)
	mat_sign_wood.roughness = 0.6
	
	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.88, 0.72, 0.32)
	mat_brass.metallic = 0.85
	mat_brass.roughness = 0.3
	
	# Деревянная фигурная доска
	sign_mesh = _create_box(Vector3(1.1, 0.26, 0.04), mat_sign_wood)
	sign_mesh.position = Vector3(0.0, 2.52, -0.74)
	add_child(sign_mesh)
	
	# Латунные крепления
	var brass_l := _create_box(Vector3(0.05, 0.28, 0.05), mat_brass)
	brass_l.position = Vector3(-0.48, 2.52, -0.73)
	add_child(brass_l)
	
	var brass_r := _create_box(Vector3(0.05, 0.28, 0.05), mat_brass)
	brass_r.position = Vector3(0.48, 2.52, -0.73)
	add_child(brass_r)
	
	# Текст вывески
	sign_label = Label3D.new()
	sign_label.text = "✦ Лесная станция ✦"
	sign_label.font_size = 28
	sign_label.pixel_size = 0.003
	sign_label.modulate = Color(1.0, 0.92, 0.75)
	sign_label.outline_modulate = Color(0.12, 0.08, 0.04)
	sign_label.outline_size = 4
	sign_label.position = Vector3(0.0, 2.52, -0.715)
	add_child(sign_label)
	
	_make_interactive_area(sign_mesh, "station_sign", "Вывеска станции [Оформить]", Vector3(1.15, 0.3, 0.15))

func _build_puzzle_box() -> void:
	var mat_box := StandardMaterial3D.new()
	mat_box.albedo_color = Color(0.30, 0.18, 0.10)
	mat_box.roughness = 0.5
	
	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.88, 0.72, 0.32)
	mat_brass.metallic = 0.85
	mat_brass.roughness = 0.35
	
	# Корпус шкатулки
	var box_base := _create_box(Vector3(0.42, 0.12, 0.26), mat_box)
	box_base.position = Vector3(-0.42, 0.98, 0.65)
	add_child(box_base)
	
	# Латунные уголки
	var corner := _create_box(Vector3(0.43, 0.02, 0.27), mat_brass)
	corner.position = Vector3(-0.42, 1.04, 0.65)
	add_child(corner)
	
	# 3 вращающихся диска с гравировкой
	puzzle_box_dials.clear()
	var dial_colors := [Color(0.85, 0.7, 0.3), Color(0.8, 0.65, 0.28), Color(0.85, 0.7, 0.3)]
	for i in range(3):
		var dial := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.038
		cyl.bottom_radius = 0.038
		cyl.height = 0.035
		dial.mesh = cyl
		
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = dial_colors[i]
		dmat.metallic = 0.8
		dmat.roughness = 0.3
		dial.material_override = dmat
		dial.rotation_degrees = Vector3(90, 0, 0)
		dial.position = Vector3(-0.52 + float(i) * 0.10, 1.05, 0.65)
		add_child(dial)
		puzzle_box_dials.append(dial)
	
	_make_interactive_area(box_base, "puzzle_box", "Шкатулка с дисками [Открыть шифр]", Vector3(0.46, 0.18, 0.30))

func _build_radio_receiver() -> void:
	var mat_radio_case := StandardMaterial3D.new()
	mat_radio_case.albedo_color = Color(0.24, 0.14, 0.08)
	mat_radio_case.roughness = 0.45
	
	var mat_cloth := StandardMaterial3D.new()
	mat_cloth.albedo_color = Color(0.72, 0.66, 0.52) # Бежевая тканевая решётка
	mat_cloth.roughness = 0.95
	
	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.88, 0.72, 0.32)
	mat_brass.metallic = 0.85
	mat_brass.roughness = 0.3
	
	# Корпус радио
	var radio_body := _create_box(Vector3(0.52, 0.36, 0.28), mat_radio_case)
	radio_body.position = Vector3(0.85, 1.10, 0.52)
	add_child(radio_body)
	
	# Динамик
	var speaker := _create_box(Vector3(0.26, 0.24, 0.02), mat_cloth)
	speaker.position = Vector3(0.74, 1.12, 0.66)
	add_child(speaker)
	
	# Латунные ручки настройки
	var knob1 := _create_box(Vector3(0.04, 0.04, 0.03), mat_brass)
	knob1.position = Vector3(0.98, 1.02, 0.67)
	add_child(knob1)
	
	var knob2 := _create_box(Vector3(0.04, 0.04, 0.03), mat_brass)
	knob2.position = Vector3(0.98, 1.18, 0.67)
	add_child(knob2)
	
	# Шкала частот
	mat_radio_off = StandardMaterial3D.new()
	mat_radio_off.albedo_color = Color(0.18, 0.16, 0.14)
	mat_radio_off.roughness = 0.3
	
	mat_radio_on = StandardMaterial3D.new()
	mat_radio_on.albedo_color = Color(1.0, 0.75, 0.35)
	mat_radio_on.emission_enabled = true
	mat_radio_on.emission = Color(1.0, 0.65, 0.25)
	mat_radio_on.emission_energy_multiplier = 1.8
	
	radio_dial_mesh = _create_box(Vector3(0.12, 0.20, 0.02), mat_radio_off)
	radio_dial_mesh.position = Vector3(0.98, 1.10, 0.66)
	add_child(radio_dial_mesh)
	
	# Антенна
	var antenna := _create_box(Vector3(0.015, 0.45, 0.015), mat_brass)
	antenna.position = Vector3(1.06, 1.48, 0.45)
	antenna.rotation_degrees = Vector3(0, 0, -18)
	add_child(antenna)
	
	_make_interactive_area(radio_body, "radio", "Радиоприёмник «Южный Маяк» [Слушать эфир]", Vector3(0.56, 0.42, 0.32))

func _build_valley_map() -> void:
	var mat_map := StandardMaterial3D.new()
	mat_map.albedo_color = Color(0.92, 0.88, 0.76) # Состаренный пергамент
	mat_map.roughness = 0.85
	
	var mat_pins := StandardMaterial3D.new()
	mat_pins.albedo_color = Color(0.88, 0.72, 0.32)
	mat_pins.metallic = 0.9
	
	# Лист карты на стене
	var map_mesh := _create_box(Vector3(0.02, 1.15, 0.95), mat_map)
	map_mesh.position = Vector3(-2.34, 1.75, 0.45)
	add_child(map_mesh)
	
	# Латунные кнопки по углам
	var pin1 := _create_box(Vector3(0.03, 0.03, 0.03), mat_pins)
	pin1.position = Vector3(-2.33, 2.25, 0.02)
	add_child(pin1)
	
	var pin2 := _create_box(Vector3(0.03, 0.03, 0.03), mat_pins)
	pin2.position = Vector3(-2.33, 2.25, 0.88)
	add_child(pin2)
	
	# Настенный текст-заголовок карты
	var map_title := Label3D.new()
	map_title.text = "КАРТА ДОЛИНЫ\nЭЛЬ-БОЛЬСОН\n✦ 1924 ✦"
	map_title.font_size = 20
	map_title.pixel_size = 0.0025
	map_title.modulate = Color(0.3, 0.22, 0.15)
	map_title.rotation_degrees = Vector3(0, 90, 0)
	map_title.position = Vector3(-2.32, 2.05, 0.45)
	add_child(map_title)
	
	# Условный контур реки и гор
	var map_notes := Label3D.new()
	map_notes.text = "р. Рио Асуль ───~\n▲ Серро Пилтрикитрон\n[ ? Неизведанный сектор ]"
	map_notes.font_size = 16
	map_notes.pixel_size = 0.0022
	map_notes.modulate = Color(0.38, 0.28, 0.18)
	map_notes.rotation_degrees = Vector3(0, 90, 0)
	map_notes.position = Vector3(-2.32, 1.55, 0.45)
	add_child(map_notes)
	
	_make_interactive_area(map_mesh, "map_table", "Карта долины Эль-Больсон [Изучить]", Vector3(0.15, 1.25, 1.05))

func _build_desk_lamp() -> void:
	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.88, 0.72, 0.32)
	mat_brass.metallic = 0.85
	mat_brass.roughness = 0.3
	
	# Подставка лампы
	var lamp_base := _create_box(Vector3(0.18, 0.03, 0.18), mat_brass)
	lamp_base.position = Vector3(0.42, 0.93, 0.24)
	add_child(lamp_base)
	
	# Изогнутая ножка
	var lamp_stem := _create_box(Vector3(0.03, 0.48, 0.03), mat_brass)
	lamp_stem.position = Vector3(0.42, 1.17, 0.24)
	add_child(lamp_stem)
	
	# Зелёный/латунный плафон
	var mat_shade := StandardMaterial3D.new()
	mat_shade.albedo_color = Color(0.12, 0.38, 0.26) # Благородный изумрудный
	mat_shade.roughness = 0.2
	
	var shade := _create_box(Vector3(0.24, 0.10, 0.14), mat_shade)
	shade.position = Vector3(0.44, 1.44, 0.38)
	shade.rotation_degrees = Vector3(-25, 0, 0)
	add_child(shade)
	
	# Лампочка
	mat_lamp_off = StandardMaterial3D.new()
	mat_lamp_off.albedo_color = Color(0.8, 0.75, 0.6)
	mat_lamp_off.roughness = 0.3
	
	mat_lamp_on = StandardMaterial3D.new()
	mat_lamp_on.albedo_color = Color(1.0, 0.92, 0.7)
	mat_lamp_on.emission_enabled = true
	mat_lamp_on.emission = Color(1.0, 0.85, 0.55)
	mat_lamp_on.emission_energy_multiplier = 3.5
	
	desk_lamp_bulb_mesh = _create_box(Vector3(0.16, 0.04, 0.08), mat_lamp_off)
	desk_lamp_bulb_mesh.position = Vector3(0.44, 1.41, 0.39)
	add_child(desk_lamp_bulb_mesh)

func _build_station_journal() -> void:
	var mat_leather := StandardMaterial3D.new()
	mat_leather.albedo_color = Color(0.42, 0.22, 0.12)
	mat_leather.roughness = 0.55
	
	var mat_pages := StandardMaterial3D.new()
	mat_pages.albedo_color = Color(0.95, 0.91, 0.80)
	mat_pages.roughness = 0.8
	
	# Кожаная обложка
	var journal_cover := _create_box(Vector3(0.28, 0.035, 0.38), mat_leather)
	journal_cover.position = Vector3(-0.85, 0.94, 0.78)
	journal_cover.rotation_degrees = Vector3(0, 14, 0)
	add_child(journal_cover)
	
	# Страницы
	var pages := _create_box(Vector3(0.26, 0.025, 0.36), mat_pages)
	pages.position = Vector3(-0.85, 0.945, 0.78)
	pages.rotation_degrees = Vector3(0, 14, 0)
	add_child(pages)
	
	# Тиснение на обложке
	var label_j := Label3D.new()
	label_j.text = "✦ SUR ✦\nЖУРНАЛ"
	label_j.font_size = 18
	label_j.pixel_size = 0.002
	label_j.modulate = Color(0.88, 0.72, 0.32)
	label_j.rotation_degrees = Vector3(-90, 14, 0)
	label_j.position = Vector3(-0.85, 0.965, 0.78)
	add_child(label_j)
	
	_make_interactive_area(journal_cover, "journal", "Журнал станции [Открыть записи]", Vector3(0.35, 0.12, 0.42))

func _build_workbench_clutter() -> void:
	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.88, 0.72, 0.32)
	mat_brass.metallic = 0.85
	
	var mat_wood_ruler := StandardMaterial3D.new()
	mat_wood_ruler.albedo_color = Color(0.78, 0.65, 0.45)
	
	var mat_pencil := StandardMaterial3D.new()
	mat_pencil.albedo_color = Color(0.85, 0.35, 0.25)
	
	# Деревянная чертёжная линейка
	var ruler := _create_box(Vector3(0.42, 0.008, 0.04), mat_wood_ruler)
	ruler.position = Vector3(-0.15, 0.93, 1.05)
	ruler.rotation_degrees = Vector3(0, -8, 0)
	add_child(ruler)
	
	# Графитный карандаш
	var pencil := _create_box(Vector3(0.24, 0.012, 0.012), mat_pencil)
	pencil.position = Vector3(0.18, 0.93, 1.02)
	pencil.rotation_degrees = Vector3(0, 18, 0)
	add_child(pencil)
	
	# Латунная чернильница
	var inkwell := _create_box(Vector3(0.07, 0.07, 0.07), mat_brass)
	inkwell.position = Vector3(0.45, 0.96, 0.88)
	add_child(inkwell)

# ==================== МОДЕЛИ ЭКСПОНАТОВ ====================

func _build_compass_prop(parent: Node3D) -> void:
	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.88, 0.72, 0.32)
	mat_brass.metallic = 0.9
	mat_brass.roughness = 0.25
	
	var mat_dial := StandardMaterial3D.new()
	mat_dial.albedo_color = Color(0.95, 0.92, 0.82)
	mat_dial.roughness = 0.5
	
	var mat_needle := StandardMaterial3D.new()
	mat_needle.albedo_color = Color(0.85, 0.2, 0.15)
	mat_needle.metallic = 0.5
	
	var base := _create_box(Vector3(0.18, 0.05, 0.18), mat_brass)
	parent.add_child(base)
	
	var dial := _create_box(Vector3(0.15, 0.055, 0.15), mat_dial)
	parent.add_child(dial)
	
	var needle := _create_box(Vector3(0.02, 0.06, 0.13), mat_needle)
	needle.rotation_degrees = Vector3(0, 35, 0)
	parent.add_child(needle)

func _build_crystal_prop(parent: Node3D) -> void:
	var mat_crystal := StandardMaterial3D.new()
	mat_crystal.albedo_color = Color(0.2, 0.85, 0.78, 0.85)
	mat_crystal.emission_enabled = true
	mat_crystal.emission = Color(0.15, 0.7, 0.65)
	mat_crystal.emission_energy_multiplier = 1.6
	mat_crystal.roughness = 0.1
	
	var mat_base := StandardMaterial3D.new()
	mat_base.albedo_color = Color(0.2, 0.14, 0.10)
	
	var stand := _create_box(Vector3(0.16, 0.04, 0.16), mat_base)
	parent.add_child(stand)
	
	var c1 := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.09, 0.22, 0.09)
	c1.mesh = pm
	c1.material_override = mat_crystal
	c1.position = Vector3(0, 0.11, 0)
	parent.add_child(c1)
	
	var c2 := MeshInstance3D.new()
	c2.mesh = pm
	c2.material_override = mat_crystal
	c2.position = Vector3(0.04, 0.09, 0.03)
	c2.rotation_degrees = Vector3(15, 25, -12)
	parent.add_child(c2)

func _build_owl_prop(parent: Node3D) -> void:
	var mat_cedar := StandardMaterial3D.new()
	mat_cedar.albedo_color = Color(0.48, 0.30, 0.16)
	mat_cedar.roughness = 0.6
	
	var mat_eyes := StandardMaterial3D.new()
	mat_eyes.albedo_color = Color(0.9, 0.75, 0.2)
	mat_eyes.metallic = 0.5
	
	# Тело совы
	var body := _create_box(Vector3(0.12, 0.18, 0.10), mat_cedar)
	body.position = Vector3(0, 0.09, 0)
	parent.add_child(body)
	
	# Глаза
	var eye_l := _create_box(Vector3(0.03, 0.03, 0.02), mat_eyes)
	eye_l.position = Vector3(-0.035, 0.14, 0.055)
	parent.add_child(eye_l)
	
	var eye_r := _create_box(Vector3(0.03, 0.03, 0.02), mat_eyes)
	eye_r.position = Vector3(0.035, 0.14, 0.055)
	parent.add_child(eye_r)

func _build_astrolabe_prop(parent: Node3D) -> void:
	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.88, 0.72, 0.32)
	mat_brass.metallic = 0.9
	mat_brass.roughness = 0.3
	
	var base := _create_box(Vector3(0.16, 0.03, 0.16), mat_brass)
	parent.add_child(base)
	
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.07
	torus.outer_radius = 0.09
	ring.mesh = torus
	ring.material_override = mat_brass
	ring.position = Vector3(0, 0.11, 0)
	ring.rotation_degrees = Vector3(90, 0, 0)
	parent.add_child(ring)

# ==================== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ====================

func _create_box(box_size: Vector3, mat: Material) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	inst.mesh = mesh
	if mat != null:
		inst.material_override = mat
	return inst

func _make_interactive_area(target_node: Node3D, prop_id: String, prop_title: String, col_size: Vector3) -> void:
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = col_size
	col.shape = shape
	area.add_child(col)
	target_node.add_child(area)
	
	area.mouse_entered.connect(func():
		hovered_prop_id = prop_id
		prop_hovered.emit(prop_id, prop_title)
	)
	area.mouse_exited.connect(func():
		if hovered_prop_id == prop_id:
			hovered_prop_id = ""
			prop_unhovered.emit(prop_id)
	)
	area.input_event.connect(func(_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int):
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				prop_clicked.emit(prop_id)
	)
