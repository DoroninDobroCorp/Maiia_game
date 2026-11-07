class_name AtlasMap
extends Control

signal location_selected(location: Dictionary)

const AtlasServiceScript = preload("res://scripts/services/atlas_service.gd")

var state_ref: Dictionary = {}
var marker_buttons: Dictionary = {}

func setup(state: Dictionary) -> void:
	state_ref = state
	custom_minimum_size = Vector2(820, 410)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not resized.is_connected(_layout_markers):
		resized.connect(_layout_markers)
	_rebuild_markers()
	queue_redraw()
	call_deferred("_layout_markers")

func _rebuild_markers() -> void:
	for child in get_children():
		child.queue_free()
	marker_buttons.clear()
	for location in AtlasServiceScript.list_locations(state_ref):
		var marker := Button.new()
		marker.focus_mode = Control.FOCUS_NONE
		marker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		marker.text = _marker_text(location)
		marker.tooltip_text = _tooltip_text(location)
		marker.custom_minimum_size = Vector2(118, 48) if str(location.get("distance", "")) != "distant" else Vector2(104, 44)
		marker.add_theme_font_size_override("font_size", 11)
		marker.add_theme_color_override("font_color", Color(1.0, 0.88, 0.58) if bool(location.get("unlocked", false)) else Color(0.77, 0.80, 0.82))
		marker.add_theme_stylebox_override("normal", _marker_style(bool(location.get("unlocked", false)), false))
		marker.add_theme_stylebox_override("hover", _marker_style(bool(location.get("unlocked", false)), true))
		var exact := location.duplicate(true)
		marker.pressed.connect(func(): location_selected.emit(exact))
		add_child(marker)
		marker_buttons[str(location.get("id", ""))] = marker

func _marker_text(location: Dictionary) -> String:
	var is_unlocked := bool(location.get("unlocked", false))
	var prefix := str(location.get("icon", "•")) if is_unlocked else "☁"
	var loc_id := str(location.get("id", ""))
	if is_unlocked:
		if loc_id == "station": prefix = "🌲"
		elif loc_id == "rio_azul": prefix = "🌊"
		elif loc_id == "waterfalls": prefix = "💧"
	return "%s  %s" % [prefix, str(location.get("marker_title", location.get("title", "")))]

func _tooltip_text(location: Dictionary) -> String:
	if bool(location.get("unlocked", false)):
		return "%s\n%s" % [str(location.get("subtitle", "")), str(location.get("description", ""))]
	return "%s\nТуман войны: место пока не открыто." % str(location.get("subtitle", ""))

func _marker_style(unlocked: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if unlocked:
		style.bg_color = Color(0.21, 0.17, 0.10, 0.96 if hovered else 0.90)
		style.border_color = Color(0.96, 0.73, 0.27, 0.98)
	else:
		style.bg_color = Color(0.12, 0.16, 0.18, 0.88 if hovered else 0.76)
		style.border_color = Color(0.48, 0.57, 0.59, 0.82 if hovered else 0.52)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style

func _layout_markers() -> void:
	if size.x < 10.0 or size.y < 10.0:
		return
	for location in AtlasServiceScript.list_locations(state_ref):
		var marker: Button = marker_buttons.get(str(location.get("id", "")))
		if marker == null:
			continue
		var center := _point_for(location)
		var marker_size := marker.size
		if marker_size.x < 2.0:
			marker_size = marker.custom_minimum_size
		var target := center - marker_size * 0.5
		target.x = clampf(target.x, 8.0, maxf(8.0, size.x - marker_size.x - 8.0))
		target.y = clampf(target.y, 8.0, maxf(8.0, size.y - marker_size.y - 8.0))
		marker.position = target

func _point_for(location: Dictionary) -> Vector2:
	var normalized: Vector2 = location.get("map_position", Vector2(0.5, 0.5))
	return Vector2(normalized.x * size.x, normalized.y * size.y)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.075, 0.095, 0.095, 1.0), true)
	draw_circle(Vector2(size.x * 0.49, size.y * 0.48), minf(size.x, size.y) * 0.31, Color(0.20, 0.25, 0.20, 0.50))
	draw_circle(Vector2(size.x * 0.53, size.y * 0.46), minf(size.x, size.y) * 0.18, Color(0.26, 0.29, 0.20, 0.42))

	var river := PackedVector2Array([
		Vector2(size.x * 0.33, size.y * 0.30),
		Vector2(size.x * 0.39, size.y * 0.39),
		Vector2(size.x * 0.42, size.y * 0.50),
		Vector2(size.x * 0.45, size.y * 0.61),
		Vector2(size.x * 0.48, size.y * 0.72)
	])
	draw_polyline(river, Color(0.22, 0.48, 0.56, 0.72), 3.0, true)

	var station_location := AtlasServiceScript.get_location(state_ref, "station")
	var station := _point_for(station_location) if not station_location.is_empty() else Vector2(size.x * 0.50, size.y * 0.52)
	for location in AtlasServiceScript.list_locations(state_ref):
		if str(location.get("id", "")) == "station":
			continue
		var point := _point_for(location)
		var is_loc_unlocked := bool(location.get("unlocked", false))
		if is_loc_unlocked:
			draw_line(station, point, Color(0.96, 0.78, 0.32, 0.85), 2.5, true)
			draw_circle(point, 14.0, Color(0.25, 0.65, 0.75, 0.22))
			draw_arc(point, 18.0, 0.0, TAU, 32, Color(0.96, 0.78, 0.32, 0.88), 2.0, true)
		else:
			var alpha := 0.19 if str(location.get("distance", "")) == "distant" else 0.28
			draw_line(station, point, Color(0.70, 0.65, 0.47, alpha), 1.0, true)
			_draw_fog(point, str(location.get("distance", "near")))

	_draw_bruno_trail(station)
	draw_circle(station, 18.0, Color(0.95, 0.70, 0.22, 0.13))
	draw_arc(station, 22.0, 0.0, TAU, 48, Color(0.98, 0.77, 0.32, 0.78), 2.0, true)
	draw_rect(rect, Color(0.75, 0.62, 0.34, 0.64), false, 2.0)

func _draw_fog(point: Vector2, distance: String) -> void:
	var radius := 54.0
	if distance == "regional":
		radius = 68.0
	elif distance == "distant":
		radius = 82.0
	draw_circle(point + Vector2(-18, 5), radius, Color(0.33, 0.40, 0.41, 0.15))
	draw_circle(point + Vector2(24, -9), radius * 0.78, Color(0.39, 0.44, 0.45, 0.12))
	draw_circle(point + Vector2(4, 22), radius * 0.66, Color(0.42, 0.47, 0.47, 0.10))

## Тропа Бруно к водопаду: семь флажков вдоль пути, красные у пройденных ступенек.
func _draw_bruno_trail(station: Vector2) -> void:
	var chapter2 = preload("res://scripts/services/chapter2_service.gd")
	if not chapter2.unlocked(state_ref, "bruno2"):
		return
	var waterfall := AtlasServiceScript.get_location(state_ref, "waterfalls")
	if waterfall.is_empty():
		return
	var target := _point_for(waterfall)
	var info: Dictionary = chapter2.mission_state(state_ref, "bruno2")
	var total := int(info.total)
	# The trail bulges to the side, clear of the markers sitting on the straight line.
	var direction := (target - station).normalized()
	var side := Vector2(direction.y, -direction.x)
	if side.y > 0.0:
		side = -side
	var bulge := minf(size.y * 0.16, 70.0)
	var points := PackedVector2Array()
	for i in range(total + 2):
		var t := float(i) / float(total + 1)
		points.append(station.lerp(target, t) + side * sin(PI * t) * bulge)
	draw_polyline(points, Color(0.88, 0.60, 0.30, 0.45), 1.5, true)
	for i in range(total):
		var pos := points[i + 1]
		var reached := i < int(info.done)
		var color := Color(0.92, 0.25, 0.20, 1.0) if reached else Color(0.70, 0.70, 0.66, 0.75)
		draw_circle(pos, 3.0, color)
		draw_line(pos, pos + Vector2(0, -18), color, 2.0, true)
		draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -18), pos + Vector2(13, -13), pos + Vector2(0, -8)]), color)
	draw_string(ThemeDB.fallback_font, Vector2(16, size.y - 14), "Тропа Бруно: %d из %d" % [int(info.done), total], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.82, 0.60, 0.95))
