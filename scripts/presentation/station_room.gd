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
var base_camera_pos := Vector3(0.0, 1.50, 2.42)
var base_camera_rot := Vector3(-8.5, 0.0, 0.0)

var ceiling_light: OmniLight3D
var desk_lamp_spot: SpotLight3D
var desk_lamp_omni: OmniLight3D
var radio_light: OmniLight3D
var window_glow_light: OmniLight3D
var dust_particles: CPUParticles3D

# Интерактивные 3D элементы
var sign_label: Label3D
var sign_mesh: MeshInstance3D
var prop_anchor: Node3D
var radio_dial_mesh: MeshInstance3D
var desk_lamp_bulb_mesh: MeshInstance3D
var power_strip_mesh: MeshInstance3D
var puzzle_box_dials: Array[MeshInstance3D] = []
var puzzle_box_root: Node3D
var history_cabinet: Node3D
var phase_b_unlock_panel: Node3D
var phase_b_unlock_label: Label3D
var observatory_unlock_light: OmniLight3D
var movement_ritual_marker: Node3D
var movement_ritual_light: OmniLight3D
var challenge_board_marker: Node3D
var challenge_board_light: OmniLight3D
var alarm_clock_mesh: Node3D
var adventure_props: StationAdventureProps

# Материалы для фаз
var mat_lamp_off: StandardMaterial3D
var mat_lamp_on: StandardMaterial3D
var mat_radio_off: StandardMaterial3D
var mat_radio_on: StandardMaterial3D
var mat_power_off: StandardMaterial3D
var mat_power_on: StandardMaterial3D

# Состояние
var is_stage_2: bool = false
var reduce_motion: bool = false
var hovered_prop_id: String = ""
var target_cam_offset := Vector3.ZERO
var current_cam_offset := Vector3.ZERO
var navigation_enabled := true
var current_room_id := "station_main"
var player_position := Vector3(0.0, 1.50, 2.42)
var player_yaw := 0.0
const WALK_SPEED := 1.35
const STRAFE_SPEED := 1.0
const TURN_SPEED := 72.0
const PUZZLE_DESK_POS := Vector3(-0.42, 0.98, 0.65)
const PUZZLE_ARCHIVE_POS := Vector3(7.0, 0.68, -0.24)
const ROOM_BOUNDS := {
	"station_main": {"min_x": -1.75, "max_x": 1.75, "min_z": 0.15, "max_z": 2.55},
	"observatory_annex": {"min_x": 5.55, "max_x": 8.45, "min_z": 0.15, "max_z": 2.75}
}
const ROOM_SPAWNS := {
	"station_main": {"position": Vector3(0.0, 1.50, 2.42), "yaw": 0.0},
	"observatory_annex": {"position": Vector3(7.0, 1.50, 2.42), "yaw": 0.0}
}

func _ready() -> void:
	_setup_environment()
	_setup_camera()
	_setup_room_geometry()
	_setup_observatory_annex()
	_setup_lighting()
	_setup_props()
	_setup_phase_b_effects()
	adventure_props = preload("res://scripts/presentation/station_adventure_props.gd").new()
	add_child(adventure_props)
	adventure_props.prop_clicked.connect(func(id: String): prop_clicked.emit(id))
	adventure_props.prop_hovered.connect(func(id: String, title: String): prop_hovered.emit(id, title))
	adventure_props.prop_unhovered.connect(func(id: String): prop_unhovered.emit(id))

func apply_adventure_view(view: Dictionary) -> void:
	if adventure_props != null:
		adventure_props.apply_view(view)
	if alarm_clock_mesh != null:
		alarm_clock_mesh.visible = bool(view.get("awakened", false)) and bool(view.get("has_alarm_clock", false))

func _process(delta: float) -> void:
	_update_navigation(delta)
	if not reduce_motion:
		current_cam_offset = current_cam_offset.lerp(target_cam_offset, delta * 4.0)
		var right := Vector3(cos(deg_to_rad(player_yaw)), 0.0, sin(deg_to_rad(player_yaw)))
		camera.position = player_position + right * current_cam_offset.x + Vector3(0.0, current_cam_offset.y, 0.0)
	else:
		camera.position = player_position
	camera.rotation_degrees = Vector3(base_camera_rot.x, player_yaw, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not reduce_motion:
		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		var norm_x: float = (event.position.x / vp_size.x) * 2.0 - 1.0
		var norm_y: float = (event.position.y / vp_size.y) * 2.0 - 1.0
		target_cam_offset = Vector3(norm_x * 0.07, -norm_y * 0.04, 0.0)

func set_navigation_enabled(enabled: bool) -> void:
	navigation_enabled = enabled

func enter_room(room_id: String) -> bool:
	if not ROOM_SPAWNS.has(room_id):
		return false
	current_room_id = room_id
	var spawn: Dictionary = ROOM_SPAWNS[room_id]
	player_position = spawn.get("position", player_position)
	player_yaw = float(spawn.get("yaw", 0.0))
	target_cam_offset = Vector3.ZERO
	current_cam_offset = Vector3.ZERO
	return true

func _update_navigation(delta: float) -> void:
	if not navigation_enabled:
		return
	var turn_axis := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		turn_axis -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		turn_axis += 1.0
	player_yaw += turn_axis * TURN_SPEED * delta

	var move_axis := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move_axis += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move_axis -= 1.0
	var strafe_axis := 0.0
	if Input.is_key_pressed(KEY_Q):
		strafe_axis -= 1.0
	if Input.is_key_pressed(KEY_E):
		strafe_axis += 1.0

	var yaw_rad := deg_to_rad(player_yaw)
	var forward := Vector3(sin(yaw_rad), 0.0, -cos(yaw_rad))
	var right := Vector3(cos(yaw_rad), 0.0, sin(yaw_rad))
	player_position += forward * move_axis * WALK_SPEED * delta
	player_position += right * strafe_axis * STRAFE_SPEED * delta
	_clamp_player_to_room()

func _clamp_player_to_room() -> void:
	var bounds: Dictionary = ROOM_BOUNDS.get(current_room_id, ROOM_BOUNDS["station_main"])
	player_position.x = clampf(player_position.x, float(bounds.get("min_x", -1.75)), float(bounds.get("max_x", 1.75)))
	player_position.z = clampf(player_position.z, float(bounds.get("min_z", 0.15)), float(bounds.get("max_z", 2.55)))
	player_position.y = 1.50

# ==================== СВЕТ И СТАДИИ МИРА ====================

func set_world_stage(stage_2_awakened: bool, animate: bool = false) -> void:
	is_stage_2 = stage_2_awakened
	_apply_station_object_layout(stage_2_awakened)
	
	if stage_2_awakened:
		desk_lamp_bulb_mesh.material_override = mat_lamp_on
		radio_dial_mesh.material_override = mat_radio_on
		power_strip_mesh.material_override = mat_power_on
		dust_particles.emitting = true
		
		if animate:
			var tween: Tween = create_tween().set_parallel(true)
			tween.tween_property(desk_lamp_spot, "light_energy", 3.2, 1.25)
			tween.tween_property(desk_lamp_omni, "light_energy", 1.35, 1.25)
			tween.tween_property(radio_light, "light_energy", 1.1, 1.25)
			tween.tween_property(ceiling_light, "light_energy", 0.62, 1.25)
			tween.tween_property(window_glow_light, "light_energy", 0.48, 1.5)
		else:
			desk_lamp_spot.light_energy = 3.2
			desk_lamp_omni.light_energy = 1.35
			radio_light.light_energy = 1.1
			ceiling_light.light_energy = 0.62
			window_glow_light.light_energy = 0.48
	else:
		desk_lamp_bulb_mesh.material_override = mat_lamp_off
		radio_dial_mesh.material_override = mat_radio_off
		power_strip_mesh.material_override = mat_power_off
		dust_particles.emitting = false
		desk_lamp_spot.light_energy = 0.0
		desk_lamp_omni.light_energy = 0.0
		radio_light.light_energy = 0.0
		ceiling_light.light_energy = 0.28
		window_glow_light.light_energy = 0.18

func _apply_station_object_layout(awakened: bool) -> void:
	# Only the solved puzzle box leaves the desk: it moves to the history cabinet
	# in the observatory passage. The owl (or any other chosen exhibit) is the
	# player's own symbol and stays on the desk shelf.
	if puzzle_box_root != null:
		puzzle_box_root.position = PUZZLE_ARCHIVE_POS if awakened else PUZZLE_DESK_POS

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

func apply_phase_b_world_effects(effect_ids: Array) -> void:
	if phase_b_unlock_panel == null:
		return
	var tokens := {
		"atlas_first_page": "ATLAS I",
		"radio_channel_01_unlocked": "CH 01",
		"workbench_blueprint": "PLANO",
		"station_emblem_art": "ARTE",
		"station_motif": "♫",
		"author_artifact_card": "OBRA",
		"expedition_pack": "EXP",
		"wind_parameter_saved": "VIENTO",
		"display_room_sign": "SEÑAL",
		"observatory_view_01": "OBS I",
		"author_patch_accepted": "PATCH",
		"movement_ritual_light": "5 DÍAS",
		"challenge_30_board": "30 DÍAS"
	}
	var visible_tokens: Array[String] = []
	for effect_id in tokens.keys():
		if effect_ids.has(effect_id):
			visible_tokens.append(str(tokens[effect_id]))
	phase_b_unlock_panel.visible = not visible_tokens.is_empty()
	phase_b_unlock_label.text = "ARCHIVO DE CAMPO  •  " + "  ✦  ".join(visible_tokens)
	if observatory_unlock_light != null:
		observatory_unlock_light.light_energy = 1.35 if effect_ids.has("observatory_view_01") else 0.0
	if movement_ritual_marker != null:
		movement_ritual_marker.visible = effect_ids.has("movement_ritual_light")
	if movement_ritual_light != null:
		movement_ritual_light.light_energy = 1.1 if effect_ids.has("movement_ritual_light") else 0.0
	if challenge_board_marker != null:
		challenge_board_marker.visible = effect_ids.has("challenge_30_board")
	if challenge_board_light != null:
		challenge_board_light.light_energy = 1.3 if effect_ids.has("challenge_30_board") else 0.0

func _setup_phase_b_effects() -> void:
	phase_b_unlock_panel = Node3D.new()
	# Табличка полевого архива и обсерватории расположена над дверью обсерватории (справа),
	# освещается её холодным фонарём и больше не перекрывает вывеску станции.
	phase_b_unlock_panel.position = Vector3(1.85, 2.08, -0.74)
	add_child(phase_b_unlock_panel)

	var plaque_mat := StandardMaterial3D.new()
	plaque_mat.albedo_color = Color(0.14, 0.10, 0.07)
	plaque_mat.metallic = 0.18
	plaque_mat.roughness = 0.52
	var plaque := _create_box(Vector3(0.72, 0.13, 0.03), plaque_mat)
	phase_b_unlock_panel.add_child(plaque)

	phase_b_unlock_label = Label3D.new()
	phase_b_unlock_label.position = Vector3(0.0, 0.0, 0.02)
	phase_b_unlock_label.font_size = 14
	phase_b_unlock_label.modulate = Color(0.95, 0.79, 0.46)
	phase_b_unlock_label.outline_size = 4

	movement_ritual_marker = Node3D.new()
	movement_ritual_marker.position = Vector3(-1.65, 1.62, 0.55)
	movement_ritual_marker.visible = false
	add_child(movement_ritual_marker)
	var ritual_mat := StandardMaterial3D.new()
	ritual_mat.albedo_color = Color(0.88, 0.72, 0.35)
	ritual_mat.emission_enabled = true
	ritual_mat.emission = Color(0.75, 0.48, 0.18)
	ritual_mat.emission_energy_multiplier = 1.7
	var ritual_marker_mesh := _create_box(Vector3(0.12, 0.12, 0.12), ritual_mat)
	movement_ritual_marker.add_child(ritual_marker_mesh)
	var ritual_label := Label3D.new()
	ritual_label.position = Vector3(0.0, 0.18, 0.0)
	ritual_label.text = "5 ✦"
	ritual_label.font_size = 24
	ritual_label.modulate = Color(1.0, 0.87, 0.55)
	movement_ritual_marker.add_child(ritual_label)
	movement_ritual_light = OmniLight3D.new()
	movement_ritual_light.position = Vector3(-1.65, 1.68, 0.65)
	movement_ritual_light.omni_range = 1.5
	movement_ritual_light.light_color = Color(1.0, 0.68, 0.32)
	movement_ritual_light.light_energy = 0.0
	add_child(movement_ritual_light)

	# Памятная латунная доска челленджа 30 дней
	challenge_board_marker = Node3D.new()
	challenge_board_marker.position = Vector3(-1.72, 1.18, 0.55)
	challenge_board_marker.rotation_degrees.y = 90
	challenge_board_marker.visible = false
	add_child(challenge_board_marker)
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.78, 0.58, 0.22)
	board_mat.metallic = 0.75
	board_mat.roughness = 0.28
	var board_mesh := _create_box(Vector3(0.42, 0.26, 0.03), board_mat)
	challenge_board_marker.add_child(board_mesh)
	var board_label := Label3D.new()
	board_label.position = Vector3(0.0, 0.0, 0.02)
	board_label.text = "МАЙЯ\n30 ДНЕЙ РИТМА\n✦ ✦ ✦"
	board_label.font_size = 18
	board_label.pixel_size = 0.0017
	board_label.modulate = Color(0.98, 0.92, 0.72)
	board_label.outline_size = 3
	board_label.outline_modulate = Color(0.12, 0.08, 0.04)
	challenge_board_marker.add_child(board_label)

	_make_interactive_area(board_mesh, "challenge_board", "Доска почёта • 30 дней чемпионского ритма", Vector3(0.46, 0.30, 0.12))

	challenge_board_light = OmniLight3D.new()
	challenge_board_light.position = Vector3(-1.48, 1.25, 0.55)
	challenge_board_light.omni_range = 1.8
	challenge_board_light.light_color = Color(1.0, 0.82, 0.42)
	challenge_board_light.light_energy = 0.0
	add_child(challenge_board_light)
	phase_b_unlock_label.outline_modulate = Color(0.05, 0.035, 0.025, 0.95)
	phase_b_unlock_panel.add_child(phase_b_unlock_label)
	phase_b_unlock_panel.visible = false

	observatory_unlock_light = OmniLight3D.new()
	observatory_unlock_light.position = Vector3(1.75, 1.85, -0.35)
	observatory_unlock_light.omni_range = 1.7
	observatory_unlock_light.light_color = Color(0.56, 0.72, 1.0)
	observatory_unlock_light.light_energy = 0.0
	add_child(observatory_unlock_light)

# ==================== ГЕОМЕТРИЯ И МАТЕРИАЛЫ ====================

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.045, 0.08) # Сумеречное индиго
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.18, 0.27)
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.12
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 52.0
	camera.position = base_camera_pos
	camera.rotation_degrees = base_camera_rot
	add_child(camera)

func _setup_lighting() -> void:
	# Верхний абажурный свет (вечерний уют)
	ceiling_light = OmniLight3D.new()
	ceiling_light.position = Vector3(0.0, 2.2, 0.6)
	ceiling_light.omni_range = 7.5
	ceiling_light.light_color = Color(1.0, 0.88, 0.72)
	ceiling_light.light_energy = 0.28
	ceiling_light.shadow_enabled = true
	add_child(ceiling_light)
	
	# Сумеречный лунный свет за окном
	var window_light := DirectionalLight3D.new()
	window_light.rotation_degrees = Vector3(-25.0, 25.0, 0.0)
	window_light.light_color = Color(0.42, 0.52, 0.78)
	window_light.light_energy = 0.42
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

	# Холодный отражённый свет окна. После пробуждения в нём появляется тёплая примесь.
	window_glow_light = OmniLight3D.new()
	window_glow_light.position = Vector3(0.0, 1.55, -0.45)
	window_glow_light.omni_range = 4.2
	window_glow_light.light_color = Color(0.48, 0.58, 0.92)
	window_glow_light.light_energy = 0.18
	window_glow_light.shadow_enabled = false
	add_child(window_glow_light)
	
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
	var mat_wall := _textured_material("res://assets/textures/plaster.png", Color(0.80, 0.78, 0.72), 0.95, Vector3(2.6, 1.8, 2.6))
	var mat_wood_dark := _textured_material("res://assets/textures/walnut.png", Color(0.42, 0.28, 0.18), 0.72, Vector3(3.2, 3.2, 3.2))
	var mat_floor := _textured_material("res://assets/textures/floorboards.png", Color(0.52, 0.34, 0.20), 0.70, Vector3(2.8, 2.8, 2.8))
	var mat_desk := _textured_material("res://assets/textures/desk_wood.png", Color(0.70, 0.45, 0.25), 0.48, Vector3(2.1, 2.1, 2.1))
	var mat_rug := StandardMaterial3D.new()
	mat_rug.albedo_color = Color(0.16, 0.23, 0.25)
	mat_rug.roughness = 0.96
	
	# Пол
	var floor_box := _create_box(Vector3(6.0, 0.1, 5.0), mat_floor)
	floor_box.position = Vector3(0.0, -0.05, 0.5)
	add_child(floor_box)
	
	# Задняя стена собрана вокруг настоящего оконного проёма. Раньше цельная
	# плоскость перекрывала горы и небо, поэтому окно выглядело как рама на стене.
	var back_wall_left := _create_box(Vector3(1.9, 3.6, 0.1), mat_wall)
	back_wall_left.position = Vector3(-2.05, 1.8, -0.85)
	add_child(back_wall_left)
	var back_wall_right := _create_box(Vector3(1.9, 3.6, 0.1), mat_wall)
	back_wall_right.position = Vector3(2.05, 1.8, -0.85)
	add_child(back_wall_right)
	var back_wall_top := _create_box(Vector3(2.2, 1.22, 0.1), mat_wall)
	back_wall_top.position = Vector3(0.0, 2.99, -0.85)
	add_child(back_wall_top)
	var back_wall_bottom := _create_box(Vector3(2.2, 1.18, 0.1), mat_wall)
	back_wall_bottom.position = Vector3(0.0, 0.59, -0.85)
	add_child(back_wall_bottom)
	
	# Левая стена (с картой)
	var left_wall := _create_box(Vector3(0.1, 3.6, 5.0), mat_wall)
	left_wall.position = Vector3(-2.4, 1.8, 0.5)
	add_child(left_wall)

	# Правая стена замыкает композицию и даёт комнате ощущение реального объёма.
	var right_wall := _create_box(Vector3(0.1, 3.6, 5.0), mat_wall)
	right_wall.position = Vector3(2.4, 1.8, 0.5)
	add_child(right_wall)
	
	# Потолочные деревянные балки
	var beam_top := _create_box(Vector3(6.0, 0.2, 0.25), mat_wood_dark)
	beam_top.position = Vector3(0.0, 2.7, -0.7)
	add_child(beam_top)
	
	var beam_cross := _create_box(Vector3(0.25, 0.2, 5.0), mat_wood_dark)
	beam_cross.position = Vector3(-0.8, 2.7, 0.5)
	add_child(beam_cross)

	var beam_cross_r := _create_box(Vector3(0.20, 0.18, 5.0), mat_wood_dark)
	beam_cross_r.position = Vector3(1.55, 2.72, 0.5)
	add_child(beam_cross_r)

	# Тёмный цоколь и тонкая рейка сильно убирают ощущение «голых коробок».
	for x in [-2.30, 2.30]:
		var baseboard_side := _create_box(Vector3(0.08, 0.22, 4.8), mat_wood_dark)
		baseboard_side.position = Vector3(x, 0.12, 0.5)
		add_child(baseboard_side)
	var baseboard_back := _create_box(Vector3(4.7, 0.22, 0.08), mat_wood_dark)
	baseboard_back.position = Vector3(0.0, 0.12, -0.79)
	add_child(baseboard_back)
	
	# Большое панорамное окно в центре
	_build_window_and_mountains()
	
	# Стол / Верстак станции на переднем плане
	var desk_top := _create_box(Vector3(2.6, 0.08, 1.15), mat_desk)
	desk_top.position = Vector3(0.0, 0.88, 0.72)
	add_child(desk_top)

	# Тонкий ковёр под рабочим местом добавляет цвет и отделяет верстак от пола.
	var rug := _create_box(Vector3(2.55, 0.018, 1.62), mat_rug)
	rug.position = Vector3(0.0, 0.018, 0.92)
	add_child(rug)
	
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

	var desk_front_rail := _create_box(Vector3(2.38, 0.13, 0.08), mat_wood_dark)
	desk_front_rail.position = Vector3(0.0, 0.70, 1.24)
	add_child(desk_front_rail)

	mat_power_off = StandardMaterial3D.new()
	mat_power_off.albedo_color = Color(0.10, 0.08, 0.06)
	mat_power_off.roughness = 0.55
	mat_power_on = StandardMaterial3D.new()
	mat_power_on.albedo_color = Color(1.0, 0.62, 0.23)
	mat_power_on.emission_enabled = true
	mat_power_on.emission = Color(1.0, 0.42, 0.08)
	mat_power_on.emission_energy_multiplier = 3.0
	power_strip_mesh = _create_box(Vector3(0.78, 0.018, 0.035), mat_power_off)
	power_strip_mesh.position = Vector3(0.0, 1.145, 0.10)
	add_child(power_strip_mesh)
	
	# Дверь в обсерваторию (справа сзади)
	_build_observatory_door()

func _setup_observatory_annex() -> void:
	# Небольшой переход уже доступен как настоящая вторая комната. Дальняя дверь
	# остаётся сюжетной границей, поэтому архитектуру можно расширять новыми ROOM_SPAWNS.
	var mat_wall := _textured_material("res://assets/textures/plaster.png", Color(0.58, 0.60, 0.64), 0.92, Vector3(2.2, 1.8, 2.2))
	var mat_floor := _textured_material("res://assets/textures/floorboards.png", Color(0.37, 0.29, 0.24), 0.78, Vector3(2.5, 2.5, 2.5))
	var mat_wood := _textured_material("res://assets/textures/walnut.png", Color(0.30, 0.22, 0.18), 0.72, Vector3(2.8, 2.8, 2.8))
	var mat_door := StandardMaterial3D.new()
	mat_door.albedo_color = Color(0.20, 0.17, 0.18)
	mat_door.roughness = 0.66
	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.72, 0.58, 0.28)
	mat_brass.metallic = 0.75
	mat_brass.roughness = 0.32

	var floor_box := _create_box(Vector3(3.4, 0.10, 3.5), mat_floor)
	floor_box.position = Vector3(7.0, -0.05, 1.05)
	add_child(floor_box)
	var back_wall := _create_box(Vector3(3.4, 3.2, 0.10), mat_wall)
	back_wall.position = Vector3(7.0, 1.60, -0.65)
	add_child(back_wall)
	for x in [5.30, 8.70]:
		var side_wall := _create_box(Vector3(0.10, 3.2, 3.5), mat_wall)
		side_wall.position = Vector3(x, 1.60, 1.05)
		add_child(side_wall)
	var beam := _create_box(Vector3(3.3, 0.18, 0.24), mat_wood)
	beam.position = Vector3(7.0, 2.65, -0.50)
	add_child(beam)

	var title := Label3D.new()
	title.position = Vector3(7.0, 2.20, -0.56)
	title.text = "ПЕРЕХОД К ОБСЕРВАТОРИИ"
	title.font_size = 24
	title.pixel_size = 0.0022
	title.modulate = Color(0.78, 0.83, 0.92)
	title.outline_size = 5
	add_child(title)

	var return_door := _create_box(Vector3(0.78, 1.72, 0.08), mat_wood)
	return_door.position = Vector3(6.25, 1.02, -0.56)
	add_child(return_door)
	var return_handle := _create_box(Vector3(0.04, 0.12, 0.08), mat_brass)
	return_handle.position = Vector3(6.52, 0.96, -0.49)
	add_child(return_handle)
	_make_interactive_area(return_door, "door_station_return", "Вернуться на станцию [Войти]", Vector3(0.86, 1.82, 0.22))

	var inner_door := _create_box(Vector3(0.78, 1.72, 0.08), mat_door)
	inner_door.position = Vector3(7.76, 1.02, -0.56)
	add_child(inner_door)
	var inner_handle := _create_box(Vector3(0.04, 0.12, 0.08), mat_brass)
	inner_handle.position = Vector3(7.49, 0.96, -0.49)
	add_child(inner_handle)
	var inner_label := Label3D.new()
	inner_label.position = Vector3(7.76, 1.72, -0.49)
	inner_label.text = "ОБСЕРВАТОРИЯ"
	inner_label.font_size = 17
	inner_label.pixel_size = 0.0022
	inner_label.modulate = Color(0.60, 0.72, 0.92)
	add_child(inner_label)
	_make_interactive_area(inner_door, "observatory_inner_door", "Дальняя дверь обсерватории [Осмотреть]", Vector3(0.86, 1.82, 0.22))

	var annex_light := OmniLight3D.new()
	annex_light.position = Vector3(7.0, 2.12, 0.65)
	annex_light.omni_range = 4.2
	annex_light.light_color = Color(0.62, 0.72, 0.94)
	annex_light.light_energy = 0.72
	add_child(annex_light)

func _build_window_and_mountains() -> void:
	var mat_frame := _textured_material("res://assets/textures/walnut.png", Color(0.46, 0.30, 0.18), 0.66, Vector3(2.0, 2.0, 2.0))
	
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
	mat_sky.albedo_color = Color(0.035, 0.055, 0.13) # Глубокий патагонский вечер
	sky_plane.material_override = mat_sky
	add_child(sky_plane)
	
	# Звёзды за окном
	var star_mesh := BoxMesh.new()
	star_mesh.size = Vector3(0.025, 0.025, 0.01)
	var mat_star := StandardMaterial3D.new()
	mat_star.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_star.albedo_color = Color(1.0, 1.0, 0.9)
	mat_star.emission_enabled = true
	mat_star.emission = Color(0.85, 0.90, 1.0)
	mat_star.emission_energy_multiplier = 1.8
	
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
	mat_moon.albedo_color = Color(0.95, 0.96, 0.86)
	mat_moon.emission_enabled = true
	mat_moon.emission = Color(0.78, 0.84, 1.0)
	mat_moon.emission_energy_multiplier = 1.2
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

	# Силуэты нескольких сосен перед хребтом создают масштаб и узнаваемую Патагонию.
	for tree_data in [
		[Vector3(-0.82, 1.20, -1.42), 0.34],
		[Vector3(-0.64, 1.16, -1.43), 0.26],
		[Vector3(0.73, 1.18, -1.42), 0.31],
		[Vector3(0.89, 1.15, -1.43), 0.23]
	]:
		_add_pine_silhouette(tree_data[0], float(tree_data[1]), mat_mount_near)

func _add_pine_silhouette(pos: Vector3, height: float, mat: Material) -> void:
	var trunk := _create_box(Vector3(height * 0.06, height, 0.03), mat)
	trunk.position = pos
	add_child(trunk)
	for i in range(3):
		var crown := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = height * (0.22 - float(i) * 0.035)
		cone.height = height * 0.33
		crown.mesh = cone
		crown.material_override = mat
		crown.position = pos + Vector3(0.0, height * (0.10 + float(i) * 0.16), 0.0)
		add_child(crown)

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

	# Шкаф истории стоит в переходе к обсерватории: туда уходит шкатулка первой тайны.
	_build_history_cabinet()
	
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

	# 9. Будильник Чемпиона (подарок тренера Бруно)
	_build_bruno_alarm_clock()

func _build_station_sign() -> void:
	var mat_sign_wood := _textured_material("res://assets/textures/desk_wood.png", Color(0.62, 0.38, 0.19), 0.60, Vector3(1.8, 1.8, 1.8))
	
	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.88, 0.72, 0.32)
	mat_brass.metallic = 0.85
	mat_brass.roughness = 0.3
	
	# Деревянная фигурная доска
	sign_mesh = _create_box(Vector3(1.1, 0.26, 0.04), mat_sign_wood)
	sign_mesh.position = Vector3(0.0, 2.43, -0.74)
	add_child(sign_mesh)
	
	# Латунные крепления
	var brass_l := _create_box(Vector3(0.05, 0.28, 0.05), mat_brass)
	brass_l.position = Vector3(-0.48, 2.43, -0.73)
	add_child(brass_l)
	
	var brass_r := _create_box(Vector3(0.05, 0.28, 0.05), mat_brass)
	brass_r.position = Vector3(0.48, 2.43, -0.73)
	add_child(brass_r)
	
	# Текст вывески
	sign_label = Label3D.new()
	sign_label.text = "✦ Лесная станция ✦"
	sign_label.font_size = 28
	sign_label.pixel_size = 0.003
	sign_label.modulate = Color(1.0, 0.92, 0.75)
	sign_label.outline_modulate = Color(0.12, 0.08, 0.04)
	sign_label.outline_size = 4
	sign_label.position = Vector3(0.0, 2.43, -0.715)
	add_child(sign_label)
	
	_make_interactive_area(sign_mesh, "station_sign", "Вывеска станции [Оформить]", Vector3(1.15, 0.3, 0.15))

func _build_puzzle_box() -> void:
	var mat_box := _textured_material("res://assets/textures/walnut.png", Color(0.55, 0.31, 0.14), 0.52, Vector3(2.8, 2.8, 2.8))
	
	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.88, 0.72, 0.32)
	mat_brass.metallic = 0.85
	mat_brass.roughness = 0.35
	
	# Вся шкатулка живёт под одним корнем: после S00 этот же объект переезжает
	# в шкаф истории, а не дублируется и не исчезает.
	puzzle_box_root = Node3D.new()
	puzzle_box_root.position = PUZZLE_DESK_POS
	add_child(puzzle_box_root)

	# Корпус шкатулки
	var box_base := _create_box(Vector3(0.42, 0.12, 0.26), mat_box)
	box_base.position = Vector3.ZERO
	puzzle_box_root.add_child(box_base)
	
	# Латунные уголки
	var corner := _create_box(Vector3(0.43, 0.02, 0.27), mat_brass)
	corner.position = Vector3(0.0, 0.06, 0.0)
	puzzle_box_root.add_child(corner)
	
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
		dial.position = Vector3(-0.10 + float(i) * 0.10, 0.07, 0.0)
		puzzle_box_root.add_child(dial)
		puzzle_box_dials.append(dial)
	
	_make_interactive_area(box_base, "puzzle_box", "Старинная шкатулка [Первая тайна станции]", Vector3(0.46, 0.18, 0.30))

func _build_radio_receiver() -> void:
	var mat_radio_case := _textured_material("res://assets/textures/walnut.png", Color(0.48, 0.26, 0.12), 0.48, Vector3(2.4, 2.4, 2.4))
	
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
	
	# Латунные ручки настройки — цилиндры читаются гораздо лучше коробок.
	var knob1 := _create_cylinder(0.025, 0.028, mat_brass)
	knob1.position = Vector3(0.98, 1.02, 0.68)
	knob1.rotation_degrees = Vector3(90, 0, 0)
	add_child(knob1)
	
	var knob2 := _create_cylinder(0.025, 0.028, mat_brass)
	knob2.position = Vector3(0.98, 1.18, 0.68)
	knob2.rotation_degrees = Vector3(90, 0, 0)
	add_child(knob2)
	
	# Шкала частот
	mat_radio_off = StandardMaterial3D.new()
	mat_radio_off.albedo_color = Color(0.18, 0.16, 0.14)
	mat_radio_off.roughness = 0.3
	
	mat_radio_on = StandardMaterial3D.new()
	mat_radio_on.albedo_color = Color(1.0, 0.75, 0.35)
	mat_radio_on.emission_enabled = true
	mat_radio_on.emission = Color(1.0, 0.65, 0.25)
	mat_radio_on.emission_energy_multiplier = 1.25
	
	radio_dial_mesh = _create_box(Vector3(0.12, 0.20, 0.02), mat_radio_off)
	radio_dial_mesh.position = Vector3(0.98, 1.10, 0.66)
	add_child(radio_dial_mesh)
	
	# Антенна
	var antenna := _create_box(Vector3(0.015, 0.45, 0.015), mat_brass)
	antenna.position = Vector3(1.06, 1.48, 0.45)
	antenna.rotation_degrees = Vector3(0, 0, -18)
	add_child(antenna)
	
	_make_interactive_area(radio_body, "radio", "Радио Норы · миссия «Голоса Южного Маяка»", Vector3(0.56, 0.42, 0.32))
	# Погода остаётся функцией того же приёмника, но живёт на отдельной ручке,
	# поэтому основной клик по радио всегда ведёт в ровно одну миссию.
	_make_interactive_area(knob2, "radio_weather", "Ручка погоды • прогноз Эль-Больсона", Vector3(0.07, 0.07, 0.07))

func _build_history_cabinet() -> void:
	# =========================================================================
	# АРХИТЕКТУРА ШКАФА ИСТОРИИ (History Cabinet Relics Architecture):
	# Шкаф истории в переходе к обсерватории рассчитан на ТРИ ключевые реликвии:
	# - Нижняя полка (y = 0.62, PUZZLE_ARCHIVE_POS): шкатулка S00 (первая тайна станции, уже лежит);
	# - Средняя полка (y = 1.12, свободно): зарезервировано под ключевой артефакт 2-й главы;
	# - Верхняя полка (y = 1.60, свободно): зарезервировано под ключевой артефакт 3-й главы/финала.
	# Шкаф не на одну вещь: две верхние полки ждут следующие сюжетные находки Майи.
	# =========================================================================
	history_cabinet = Node3D.new()
	history_cabinet.position = Vector3(7.0, 0.0, -0.42)
	add_child(history_cabinet)

	var wood := _textured_material("res://assets/textures/walnut.png", Color(0.28, 0.18, 0.12), 0.68, Vector3(2.4, 2.4, 2.4))
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.72, 0.58, 0.28)
	brass.metallic = 0.72
	brass.roughness = 0.34

	for x in [-0.34, 0.34]:
		var side := _create_box(Vector3(0.06, 1.58, 0.34), wood)
		side.position = Vector3(x, 0.82, 0.0)
		history_cabinet.add_child(side)
	for y in [0.14, 0.62, 1.12, 1.60]:
		var shelf := _create_box(Vector3(0.74, 0.055, 0.34), wood)
		shelf.position = Vector3(0.0, y, 0.0)
		history_cabinet.add_child(shelf)
	var trim := _create_box(Vector3(0.78, 0.07, 0.38), brass)
	trim.position = Vector3(0.0, 1.66, 0.0)
	history_cabinet.add_child(trim)

	var label := Label3D.new()
	label.text = "ШКАФ ИСТОРИИ\nреликвии станции"
	label.position = Vector3(0.0, 1.82, 0.18)
	label.font_size = 18
	label.pixel_size = 0.0017
	label.modulate = Color(0.92, 0.80, 0.53)
	label.outline_size = 4
	history_cabinet.add_child(label)

	var hit_anchor := Node3D.new()
	hit_anchor.position = Vector3(0.0, 0.86, 0.10)
	history_cabinet.add_child(hit_anchor)
	_make_interactive_area(hit_anchor, "history_cabinet", "Шкаф истории • реликвии станции (шкатулка S00 и свободные полки)", Vector3(0.82, 1.72, 0.46))

func _build_valley_map() -> void:
	var mat_map := _textured_material("res://assets/textures/parchment.png", Color(0.94, 0.87, 0.70), 0.88, Vector3(1.6, 1.6, 1.6))
	
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
	var lamp_base := _create_cylinder(0.105, 0.035, mat_brass)
	lamp_base.position = Vector3(0.42, 0.93, 0.24)
	add_child(lamp_base)
	
	# Тонкая круглая ножка
	var lamp_stem := _create_cylinder(0.018, 0.48, mat_brass)
	lamp_stem.position = Vector3(0.42, 1.17, 0.24)
	add_child(lamp_stem)
	
	# Зелёный/латунный плафон
	var mat_shade := StandardMaterial3D.new()
	mat_shade.albedo_color = Color(0.12, 0.38, 0.26) # Благородный изумрудный
	mat_shade.roughness = 0.2
	
	var shade := MeshInstance3D.new()
	var shade_mesh := PrismMesh.new()
	shade_mesh.size = Vector3(0.27, 0.12, 0.18)
	shade.mesh = shade_mesh
	shade.material_override = mat_shade
	shade.position = Vector3(0.44, 1.44, 0.38)
	shade.rotation_degrees = Vector3(-18, 0, 0)
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
	
	desk_lamp_bulb_mesh = _create_sphere(0.055, mat_lamp_off)
	desk_lamp_bulb_mesh.position = Vector3(0.44, 1.41, 0.39)
	add_child(desk_lamp_bulb_mesh)

func _build_station_journal() -> void:
	var mat_leather := StandardMaterial3D.new()
	mat_leather.albedo_color = Color(0.42, 0.22, 0.12)
	mat_leather.roughness = 0.55
	
	var mat_pages := StandardMaterial3D.new()
	mat_pages.albedo_color = Color(0.95, 0.91, 0.80)
	mat_pages.roughness = 0.8

	var journal_root := Node3D.new()
	journal_root.position = Vector3(-0.85, 0.94, 0.78)
	journal_root.rotation_degrees = Vector3(0, 14, 0)
	add_child(journal_root)

	# Нижняя крышка кожаного переплёта
	var bottom_cover := _create_box(Vector3(0.28, 0.006, 0.38), mat_leather)
	bottom_cover.position = Vector3(0.0, -0.015, 0.0)
	journal_root.add_child(bottom_cover)

	# Блок страниц (кремовая бумага) — строго внутри переплёта, не перекрывает крышки
	var pages := _create_box(Vector3(0.26, 0.024, 0.36), mat_pages)
	pages.position = Vector3(0.006, 0.0, 0.0)
	journal_root.add_child(pages)

	# Кожаный корешок переплёта с левой стороны
	var spine := _create_box(Vector3(0.008, 0.036, 0.38), mat_leather)
	spine.position = Vector3(-0.136, 0.0, 0.0)
	journal_root.add_child(spine)

	# Верхняя крышка кожаного переплёта — полностью закрывает блок страниц сверху
	var top_cover := _create_box(Vector3(0.28, 0.006, 0.38), mat_leather)
	top_cover.position = Vector3(0.0, 0.015, 0.0)
	journal_root.add_child(top_cover)

	# Золотое тиснение на верхней крышке
	var label_j := Label3D.new()
	label_j.text = "✦ SUR ✦\nЖУРНАЛ"
	label_j.font_size = 18
	label_j.pixel_size = 0.002
	label_j.modulate = Color(0.88, 0.72, 0.32)
	label_j.render_priority = 1
	label_j.rotation_degrees = Vector3(-90, 0, 0)
	label_j.position = Vector3(0.0, 0.019, 0.0)
	journal_root.add_child(label_j)
	
	_make_interactive_area(journal_root, "journal", "Журнал станции [Открыть записи]", Vector3(0.35, 0.12, 0.42))

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
	ruler.position = Vector3(-1.18, 0.93, 1.10)
	ruler.rotation_degrees = Vector3(0, -8, 0)
	add_child(ruler)
	
	# Графитный карандаш
	var pencil := _create_box(Vector3(0.24, 0.012, 0.012), mat_pencil)
	pencil.position = Vector3(1.02, 0.93, 1.08)
	pencil.rotation_degrees = Vector3(0, 18, 0)
	add_child(pencil)
	
	# Латунная чернильница
	var inkwell := _create_cylinder(0.045, 0.07, mat_brass)
	inkwell.position = Vector3(1.22, 0.96, 0.92)
	add_child(inkwell)

func _build_bruno_alarm_clock() -> void:
	alarm_clock_mesh = Node3D.new()
	alarm_clock_mesh.name = "bruno_alarm_clock"
	alarm_clock_mesh.position = Vector3(-0.55, 1.17, 0.24)
	alarm_clock_mesh.rotation_degrees = Vector3(0, 12, 0)
	alarm_clock_mesh.visible = false
	add_child(alarm_clock_mesh)

	var mat_orange := StandardMaterial3D.new()
	mat_orange.albedo_color = Color(0.96, 0.48, 0.12)
	mat_orange.roughness = 0.45

	var mat_brass := StandardMaterial3D.new()
	mat_brass.albedo_color = Color(0.88, 0.72, 0.32)
	mat_brass.metallic = 0.85
	mat_brass.roughness = 0.28

	var mat_dial := StandardMaterial3D.new()
	mat_dial.albedo_color = Color(0.96, 0.95, 0.90)

	var mat_dark := StandardMaterial3D.new()
	mat_dark.albedo_color = Color(0.14, 0.12, 0.10)

	# Корпус (оранжевый круглый будильник)
	var body := _create_cylinder(0.045, 0.035, mat_orange)
	body.rotation_degrees.x = 90
	alarm_clock_mesh.add_child(body)

	# Циферблат
	var face := _create_cylinder(0.040, 0.004, mat_dial)
	face.rotation_degrees.x = 90
	face.position = Vector3(0.0, 0.0, 0.018)
	alarm_clock_mesh.add_child(face)

	# Стрелки часов (направлены на вечернюю растяжку!)
	var hand_h := _create_box(Vector3(0.003, 0.022, 0.002), mat_dark)
	hand_h.position = Vector3(0.006, 0.008, 0.021)
	hand_h.rotation_degrees.z = -35
	alarm_clock_mesh.add_child(hand_h)

	var hand_m := _create_box(Vector3(0.0025, 0.032, 0.002), mat_dark)
	hand_m.position = Vector3(-0.004, 0.012, 0.021)
	hand_m.rotation_degrees.z = 25
	alarm_clock_mesh.add_child(hand_m)

	# Центральная заклёпка
	var pin := _create_sphere(0.004, mat_brass)
	pin.position = Vector3(0.0, 0.0, 0.022)
	alarm_clock_mesh.add_child(pin)

	# Два латунных колокольчика сверху
	var bell_l := _create_sphere(0.016, mat_brass)
	bell_l.position = Vector3(-0.032, 0.052, 0.0)
	alarm_clock_mesh.add_child(bell_l)

	var bell_r := _create_sphere(0.016, mat_brass)
	bell_r.position = Vector3(0.032, 0.052, 0.0)
	alarm_clock_mesh.add_child(bell_r)

	# Молоток между колокольчиками
	var hammer := _create_box(Vector3(0.005, 0.014, 0.005), mat_brass)
	hammer.position = Vector3(0.0, 0.054, 0.0)
	alarm_clock_mesh.add_child(hammer)

	# Латунные ножки
	var leg_l := _create_box(Vector3(0.005, 0.015, 0.005), mat_brass)
	leg_l.position = Vector3(-0.028, -0.048, 0.0)
	leg_l.rotation_degrees.z = 20
	alarm_clock_mesh.add_child(leg_l)

	var leg_r := _create_box(Vector3(0.005, 0.015, 0.005), mat_brass)
	leg_r.position = Vector3(0.028, -0.048, 0.0)
	leg_r.rotation_degrees.z = -20
	alarm_clock_mesh.add_child(leg_r)

	_make_interactive_area(alarm_clock_mesh, "bruno_alarm_clock", "Будильник Чемпиона • подарок тренера Бруно [Позвонить]", Vector3(0.16, 0.18, 0.14))

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
	
	var base := _create_cylinder(0.105, 0.045, mat_brass)
	parent.add_child(base)
	
	var dial := _create_cylinder(0.086, 0.052, mat_dial)
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

	var mat_cedar_dark := StandardMaterial3D.new()
	mat_cedar_dark.albedo_color = Color(0.31, 0.18, 0.09)
	mat_cedar_dark.roughness = 0.72

	var mat_beak := StandardMaterial3D.new()
	mat_beak.albedo_color = Color(0.72, 0.48, 0.18)
	mat_beak.roughness = 0.55
	
	var mat_eyes := StandardMaterial3D.new()
	mat_eyes.albedo_color = Color(0.9, 0.75, 0.2)
	mat_eyes.metallic = 0.5
	
	# Тело и голова: лёгкая асимметрия и отдельный силуэт делают фигурку читаемой из комнаты.
	var body := _create_sphere(0.075, mat_cedar)
	body.scale = Vector3(0.85, 1.25, 0.78)
	body.position = Vector3(0, 0.09, 0)
	parent.add_child(body)

	var head := _create_sphere(0.062, mat_cedar)
	head.scale = Vector3(1.05, 0.86, 0.92)
	head.position = Vector3(0, 0.155, 0.004)
	parent.add_child(head)

	# Ушные пучки.
	for side in [-1.0, 1.0]:
		var ear := _create_sphere(0.021, mat_cedar_dark)
		ear.scale = Vector3(0.42, 1.05, 0.42)
		ear.position = Vector3(0.042 * side, 0.202, 0.0)
		ear.rotation_degrees = Vector3(0, 0, -18.0 * side)
		parent.add_child(ear)

	# Крылья имеют собственный объём и три ряда резных перьев с каждой стороны.
	for side in [-1.0, 1.0]:
		var wing := _create_sphere(0.058, mat_cedar_dark)
		wing.scale = Vector3(0.48, 1.38, 0.45)
		wing.position = Vector3(0.064 * side, 0.094, -0.002)
		wing.rotation_degrees = Vector3(7, 0, -13.0 * side)
		parent.add_child(wing)

		for feather_i in range(3):
			var feather := _create_sphere(0.027, mat_cedar)
			feather.scale = Vector3(0.42, 1.15 + float(feather_i) * 0.16, 0.32)
			feather.position = Vector3(
				(0.073 + float(feather_i) * 0.008) * side,
				0.115 - float(feather_i) * 0.030,
				0.031 + float(feather_i) * 0.002
			)
			feather.rotation_degrees = Vector3(10, 0, (-18.0 - float(feather_i) * 4.0) * side)
			parent.add_child(feather)

	# Глаза и клюв.
	var eye_l := _create_sphere(0.018, mat_eyes)
	eye_l.scale.z = 0.55
	eye_l.position = Vector3(-0.028, 0.166, 0.054)
	parent.add_child(eye_l)
	
	var eye_r := _create_sphere(0.018, mat_eyes)
	eye_r.scale.z = 0.55
	eye_r.position = Vector3(0.028, 0.166, 0.054)
	parent.add_child(eye_r)

	var beak := MeshInstance3D.new()
	var beak_mesh := PrismMesh.new()
	beak_mesh.size = Vector3(0.026, 0.035, 0.022)
	beak.mesh = beak_mesh
	beak.material_override = mat_beak
	beak.position = Vector3(0, 0.145, 0.069)
	beak.rotation_degrees = Vector3(82, 0, 0)
	parent.add_child(beak)

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

func _create_cylinder(radius: float, height: float, mat: Material) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	inst.mesh = mesh
	if mat != null:
		inst.material_override = mat
	return inst

func _create_sphere(radius: float, mat: Material) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	inst.mesh = mesh
	if mat != null:
		inst.material_override = mat
	return inst

func _textured_material(path: String, tint: Color, roughness: float, uv_scale: Vector3) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = roughness
	var tex := load(path) as Texture2D
	if tex != null:
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mat.texture_repeat = true
		mat.uv1_scale = uv_scale
	return mat

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
