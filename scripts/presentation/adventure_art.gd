class_name AdventureArt
extends Control

## Small vector illustrations remain crisp at any UI scale and need no network.
var kind := "radio"
var accent := Color("d8b676")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
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
