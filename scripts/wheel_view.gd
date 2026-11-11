class_name WheelView
extends Control
## Draws a spinning wheel from a list of slices (see WheelData) and animates
## it landing on a chosen slice. The pointer is at the top.

signal spin_finished

var slices: Array = []
var angle := 0.0:   # how far the wheel has turned, in radians (clockwise)
	set(value):
		angle = value
		queue_redraw()


func set_slices(new_slices: Array) -> void:
	slices = new_slices
	angle = 0.0
	queue_redraw()


## Spin several times round and come to rest with slice `index` under the pointer.
func spin_to(index: int, duration: float = 3.2) -> void:
	var step := TAU / slices.size()
	var slice_center := (index + 0.5) * step + randf_range(-0.35, 0.35) * step
	var turns := ceilf((angle + TAU * 4.0 + slice_center) / TAU)
	var target := turns * TAU - slice_center
	var tween := create_tween()
	tween.tween_property(self, "angle", target, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void: spin_finished.emit())


func _draw() -> void:
	if slices.is_empty():
		return
	var font := get_theme_default_font()
	var center := size / 2.0
	var radius := minf(size.x, size.y) * 0.44
	var step := TAU / slices.size()

	# Slices
	for i in slices.size():
		var start_angle := -PI / 2.0 + angle + i * step
		var color: Color = slices[i].get("color", Color.GRAY)
		if slices.size() == 1:
			draw_circle(center, radius, color)
			continue
		var points := PackedVector2Array([center])
		for s in 25:
			var a := start_angle + step * s / 24.0
			points.append(center + Vector2(cos(a), sin(a)) * radius)
		draw_colored_polygon(points, color)
		draw_line(center, center + Vector2(cos(start_angle), sin(start_angle)) * radius,
			Color.WHITE, 2.0, true)
	draw_arc(center, radius, 0.0, TAU, 96, Color.WHITE, 4.0, true)

	# Labels, written along each slice and flipped so they are never upside-down
	var font_size := int(clampf(radius * 0.1, 11.0, 24.0))
	var band := radius * 0.62
	for i in slices.size():
		var mid := -PI / 2.0 + angle + (i + 0.5) * step
		var flipped := cos(mid) < 0.0
		draw_set_transform(center, mid + (PI if flipped else 0.0), Vector2.ONE)
		var x0 := -radius * 0.92 if flipped else radius * 0.3
		draw_string(font, Vector2(x0, font_size * 0.35), slices[i]["label"],
			HORIZONTAL_ALIGNMENT_CENTER, band, font_size, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Hub and pointer
	draw_circle(center, radius * 0.1, Color("#F5F5DC"))
	draw_arc(center, radius * 0.1, 0.0, TAU, 32, Color.BLACK, 2.0, true)
	var tip := center + Vector2(0.0, -radius + radius * 0.1)
	draw_colored_polygon(PackedVector2Array([
		tip,
		center + Vector2(-radius * 0.08, -radius - radius * 0.1),
		center + Vector2(radius * 0.08, -radius - radius * 0.1),
	]), Color("#FFC400"))
	draw_polyline(PackedVector2Array([
		tip,
		center + Vector2(-radius * 0.08, -radius - radius * 0.1),
		center + Vector2(radius * 0.08, -radius - radius * 0.1),
		tip,
	]), Color.BLACK, 2.0, true)
