class_name AdventureArt
extends Control

## Small vector illustrations remain crisp at any UI scale and need no network.
var kind := "radio"
var accent := Color("d8b676")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw_archive_portrait() -> void:
	# Small portrait for the field archive (the water mission has no character):
	# an old index card with a river on the left and a waterfall on the right.
	var w := size.x
	var h := size.y
	draw_style_box(AdventureUI.style(Color("24383f"), Color("8a7a55"), 0), Rect2(Vector2.ZERO, size))
	var card := Rect2(w * .16, h * .14, w * .68, h * .72)
	draw_rect(card, Color("e8dcc0"))
	draw_rect(card, Color("8c7a54"), false, 1.5)
	draw_line(Vector2(w * .5, card.position.y + 3), Vector2(w * .5, card.end.y - 3), Color("8c7a54"), 1.0)
	var river := PackedVector2Array([Vector2(w * .24, h * .76), Vector2(w * .31, h * .55), Vector2(w * .40, h * .47), Vector2(w * .45, h * .27)])
	draw_polyline(river, Color("4f8f94"), maxf(2.0, w * .04), true)
	for i in range(3):
		draw_line(Vector2(w * .60 + i * w * .07, h * .26), Vector2(w * .60 + i * w * .07, h * .64), Color("4f8f94"), maxf(2.0, w * .03))
	draw_arc(Vector2(w * .67, h * .72), w * .1, 0.0, PI, 12, Color("7fb3b0"), 2.0, true)

func _draw_water_example() -> void:
	# Two tiny training drawings for the "two pictures" warm-up of the water mission.
	var w := size.x
	var h := size.y
	draw_style_box(AdventureUI.style(Color("e8dcc0"), Color("8c7a54"), 0), Rect2(Vector2.ZERO, size))
	var water := Color("4f8f94")
	if kind == "example_flow":
		for row in range(3):
			var y := h * (.34 + row * .2)
			var line := PackedVector2Array()
			for step in range(21):
				var x := w * (.08 + step * .042)
				line.append(Vector2(x, y + sin(step * .9 + row) * h * .035))
			draw_polyline(line, water, 3.0, true)
		draw_circle(Vector2(w * .74, h * .78), h * .07, Color("8c7a54"))
	else:
		draw_rect(Rect2(w * .12, h * .16, w * .76, h * .1), Color("8c7a54"))
		for column in range(5):
			var x := w * (.3 + column * .1)
			draw_line(Vector2(x, h * .26), Vector2(x, h * .74), water, 3.0)
		draw_arc(Vector2(w * .5, h * .74), h * .17, 0.0, PI, 16, Color("7fb3b0"), 2.5, true)

func _draw() -> void:
	if kind == "archive_portrait":
		_draw_archive_portrait()
		return
	if kind == "example_flow" or kind == "example_fall":
		_draw_water_example()
		return
	var w := size.x
	var h := size.y
	draw_style_box(AdventureUI.style(Color("162732"), Color("46565c"), 0), Rect2(Vector2.ZERO, size))
	for i in range(16):
		var p := Vector2(fmod(i * 73.0 + 31.0, maxf(w - 30, 1)) + 15, fmod(i * 37.0 + 13.0, maxf(h * .65, 1)) + 10)
		draw_circle(p, 1, Color("738b8b"))
	var mountain := PackedVector2Array([Vector2(0,h),Vector2(0,h*.8),Vector2(w*.18,h*.48),Vector2(w*.36,h*.78),Vector2(w*.64,h*.35),Vector2(w*.82,h*.7),Vector2(w,h*.54),Vector2(w,h)])
	draw_colored_polygon(mountain, Color("233c44"))
	var c := Vector2(w*.5,h*.52)
	match kind:
		"radio", "FG01":
			var r := Rect2(c - Vector2(72,43),Vector2(144,86))
			draw_style_box(AdventureUI.style(Color("825e3f"),accent,0),r)
			draw_rect(Rect2(c-Vector2(57,29),Vector2(114,20)),Color("182b32"))
			for i in range(13):
				draw_line(c+Vector2(-50+i*8,-25),c+Vector2(-50+i*8,-15),accent,1)
			for i in range(5):
				draw_line(c+Vector2(-50,4+i*5),c+Vector2(21,4+i*5),Color("493d32"),2)
			draw_circle(c+Vector2(48,17),13,accent)
			draw_line(c+Vector2(-47,-44),c+Vector2(-60,-67),accent,3)
		"game", "FG11":
			draw_style_box(AdventureUI.style(Color("915f45"),accent,0),Rect2(c-Vector2(55,57),Vector2(110,116)))
			draw_rect(Rect2(c-Vector2(43,43),Vector2(86,66)),Color("172a33"))
			draw_rect(Rect2(c+Vector2(-23,0),Vector2(11,14)),Color("8cbbb3"))
			for i in range(3):
				draw_circle(c+Vector2(-20+i*23,-23),4,accent)
			draw_line(c+Vector2(-20,42),c+Vector2(-20,31),accent,3)
			draw_circle(c+Vector2(-20,30),5,Color("bf7151"))
			draw_circle(c+Vector2(23,40),6,accent)
		_:
			draw_rect(Rect2(c-Vector2(73,47),Vector2(146,94)),accent)
			for i in range(2):
				draw_rect(Rect2(c+Vector2(-67+i*69,-41),Vector2(64,82)),Color("34545b"))
			var river := PackedVector2Array([c+Vector2(-63,29),c+Vector2(-44,5),c+Vector2(-30,-1),c+Vector2(-19,-32)])
			draw_polyline(river,Color("b5d2cb"),7,true)
			draw_line(c+Vector2(28,-30),c+Vector2(28,22),Color("b5d2cb"),14)
			draw_arc(c+Vector2(29,25),21,0,PI,20,Color("88b1b0"),3,true)
