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
	var prefix := str(location.get("icon", "•")) if bool(location.get("unlocked", false)) else "☁"
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
		var alpha := 0.19 if str(location.get("distance", "")) == "distant" else 0.28
		draw_line(station, point, Color(0.70, 0.65, 0.47, alpha), 1.0, true)
		if not bool(location.get("unlocked", false)):
			_draw_fog(point, str(location.get("distance", "near")))

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
