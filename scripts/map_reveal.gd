class_name MapReveal
extends Control
## End-of-game map reveal for Blind Crown Quest (GDScript port of map_generator.py).
##
## Usage (e.g. from your end-of-game screen):
##   var reveal: MapReveal = preload("res://scenes/map_reveal.tscn").instantiate()
##   add_child(reveal)
##   reveal.show_map(spaces, players)
##
## `spaces`  - the Array returned by GridGenerator.create_grid()
## `players` - optional Array of Dictionaries: {"name": String, "position": int}
##
## The map is drawn to fit whatever size the Control has, so it works on
## desktop, phones and the web. The legend sits to the right in landscape and
## underneath in portrait.

const GRID_SIZE := 5
const CURVE_STEPS := 60
const CURVE_MID := 30
const CURVE_STRENGTH := 0.25

const BG_COLOR := Color("#F5F5DC")
const ADJACENT_COLOR := Color(0.5, 0.5, 0.5, 0.6)

const SPACE_COLORS := {
	"Shop": Color("#FFD700"),
	"Neutral": Color("#D3D3D3"),
	"Teleport": Color("#800080"),
	"Bad": Color("#FF0000"),
	"Good": Color("#008000"),
	"Crown": Color("#FFA500"),
	"Start": Color("#0000FF"),
	"Combat": Color("#A52A2A"),
	"Shadow Realm": Color("#000000"),
}
# Space types dark enough to need white ID text.
const DARK_TYPES := ["Shadow Realm", "Combat", "Start", "Good", "Teleport"]

const CURVE_COLORS := [
	Color("#FF1493"), Color("#00CED1"), Color("#FFD700"), Color("#FF4500"),
	Color("#9370DB"), Color("#32CD32"), Color("#FF69B4"), Color("#1E90FF"),
	Color("#FFA500"), Color("#00FA9A"),
]
const PLAYER_COLORS := [Color("#FF6B6B"), Color("#4ECDC4"), Color("#95E1D3")]
# Marker shapes by player index: 0 = circle, 1 = square, 2 = triangle.

var title := "Blind Crown Quest - Final Map"

var _spaces: Array = []
var _players: Array = []

# Layout values recalculated on every draw.
var _font: Font
var _fs := 14
var _cell := 100.0
var _origin := Vector2.ZERO


func _ready() -> void:
	texture_filter = SpaceArt.FILTER
	resized.connect(queue_redraw)


func show_map(spaces: Array, players: Array = [], fade_in: bool = true) -> void:
	_spaces = spaces
	_players = players
	queue_redraw()
	if fade_in:
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.8)


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	if _spaces.is_empty():
		return

	_font = get_theme_default_font()
	var shorter := minf(size.x, size.y)
	var landscape := size.x >= size.y
	var margin := shorter * 0.04
	var title_h := shorter * 0.09
	var legend_w := clampf(size.x * 0.24, 140.0, 280.0) if landscape else 0.0
	var legend_h := 0.0 if landscape else size.y * 0.26

	var avail := Vector2(
		size.x - margin * 2.0 - legend_w,
		size.y - margin * 2.0 - title_h - legend_h)
	var board := maxf(minf(avail.x, avail.y), 10.0)
	_cell = board / GRID_SIZE
	_origin = Vector2(
		margin + (avail.x - board) / 2.0,
		margin + title_h + (avail.y - board) / 2.0)
	_fs = int(clampf(_cell * 0.15, 9.0, 26.0))

	# Title
	var title_size := int(clampf(shorter * 0.045, 14.0, 40.0))
	draw_string(_font, Vector2(0.0, margin + title_h * 0.65),
		title, HORIZONTAL_ALIGNMENT_CENTER,
		size.x - legend_w, title_size, Color.BLACK)

	var curve_labels := _draw_connections()
	_draw_nodes()
	_draw_curve_labels(curve_labels)
	_draw_players()

	if landscape:
		_draw_legend(Rect2(
			Vector2(size.x - margin - legend_w + margin * 0.5, _origin.y),
			Vector2(legend_w - margin * 0.5, board)), 1)
	else:
		_draw_legend(Rect2(
			Vector2(margin, size.y - margin - legend_h),
			Vector2(size.x - margin * 2.0, legend_h)), 2)


func _center(id: int) -> Vector2:
	var col := id % GRID_SIZE
	var row := floori(id / float(GRID_SIZE))
	return _origin + Vector2(col + 0.5, row + 0.5) * _cell


func _is_adjacent(a: int, b: int) -> bool:
	var dc := absi((a % GRID_SIZE) - (b % GRID_SIZE))
	var dr := absi(floori(a / float(GRID_SIZE)) - floori(b / float(GRID_SIZE)))
	return dc <= 1 and dr <= 1


func _draw_connections() -> Array:
	# Split connections into short (adjacent) and long-distance, each pair once.
	var seen := {}
	var adjacent_pairs: Array = []
	var curved_pairs: Array = []
	for space in _spaces:
		var a: int = space["id"]
		for conn in space["connections"]:
			var b: int = conn
			var key := mini(a, b) * 100 + maxi(a, b)
			if seen.has(key):
				continue
			seen[key] = true
			if _is_adjacent(a, b):
				adjacent_pairs.append([a, b])
			else:
				curved_pairs.append([a, b])

	# Adjacent connections: straight, thin, gray.
	for pair in adjacent_pairs:
		draw_line(_center(pair[0]), _center(pair[1]), ADJACENT_COLOR,
			maxf(2.0, _cell * 0.03), true)

	# Long-distance connections: dashed curves with a label.
	var labels: Array = []
	for i in curved_pairs.size():
		var a: int = curved_pairs[i][0]
		var b: int = curved_pairs[i][1]
		var color: Color = CURVE_COLORS[i % CURVE_COLORS.size()]
		color.a = 0.85
		var p0 := _center(a)
		var p2 := _center(b)
		var d := p2 - p0
		var ctrl := (p0 + p2) / 2.0 + Vector2(-d.y, d.x) * CURVE_STRENGTH

		var points := PackedVector2Array()
		for step in CURVE_STEPS + 1:
			var t := float(step) / CURVE_STEPS
			points.append(
				(1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * ctrl + t * t * p2)

		var width := maxf(2.5, _cell * 0.035)
		for step in CURVE_STEPS:
			if step % 6 < 3:
				draw_line(points[step], points[step + 1], color, width, true)
		draw_circle(p0, width * 1.3, color)
		draw_circle(p2, width * 1.3, color)
		labels.append([_label_point(points), "%d-%d" % [a, b], color])
	return labels


# Pick a spot on the curve for its label, sliding along the curve if the
# midpoint would sit on top of a space.
func _label_point(points: PackedVector2Array) -> Vector2:
	var clearance := _cell * 0.24 * 1.5
	for index in [CURVE_MID, 24, 36, 18, 42]:
		var candidate: Vector2 = points[index]
		var clear := true
		for space in _spaces:
			if candidate.distance_to(_center(space["id"])) < clearance:
				clear = false
				break
		if clear:
			return candidate
	return points[CURVE_MID]


func _draw_curve_labels(labels: Array) -> void:
	for item in labels:
		var label_color: Color = item[2]
		_draw_label(item[0], item[1], label_color, Color(1, 1, 1, 0.9), label_color)


func _draw_nodes() -> void:
	var radius := _cell * 0.24
	for space in _spaces:
		var id: int = space["id"]
		var type_name: String = space["type"]
		var center := _center(id)
		if SpaceArt.draw_space(self, type_name, center, _cell * 0.66):
			# With artwork, the number goes in a small badge so the picture stays visible.
			var badge_center := center + Vector2(1.0, 1.0) * _cell * 0.24
			var badge_radius := _fs * 0.85
			draw_circle(badge_center, badge_radius, Color.WHITE)
			draw_arc(badge_center, badge_radius, 0.0, TAU, 24, Color.BLACK, 2.0, true)
			_draw_text_centered(badge_center, str(id), int(_fs * 0.95), Color.BLACK)
			continue
		var color: Color = SPACE_COLORS.get(type_name, Color.WHITE)
		draw_circle(center, radius, color)
		draw_arc(center, radius, 0.0, TAU, 48, Color.BLACK, maxf(2.0, _cell * 0.03), true)
		var text_color := Color.WHITE if DARK_TYPES.has(type_name) else Color.BLACK
		_draw_text_centered(center, str(id), int(_fs * 1.15), text_color)


func _draw_players() -> void:
	var marker_radius := _cell * 0.09
	# Count players per space so shared spaces can spread their markers out.
	var totals := {}
	for p in _players:
		var raw_pos = p.get("position")
		if raw_pos != null:
			totals[int(raw_pos)] = totals.get(int(raw_pos), 0) + 1
	var drawn := {}
	for i in _players.size():
		var player: Dictionary = _players[i]
		var raw_position = player.get("position")
		if raw_position == null:
			continue
		var position_id: int = raw_position
		if position_id < 0 or position_id >= GRID_SIZE * GRID_SIZE:
			continue
		var color: Color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		# Players sharing a space are spread sideways, with names stacked.
		var rank: int = drawn.get(position_id, 0)
		drawn[position_id] = rank + 1
		var count: int = totals[position_id]
		var center := _center(position_id) + Vector2(
			(rank - (count - 1) / 2.0) * 0.28 * _cell, _cell * 0.3)
		_draw_marker(center, marker_radius, i % 3, color)
		var player_name := str(player.get("name", "Player %d" % (i + 1))).left(8)
		_draw_label(
			center + Vector2(0.0, marker_radius + _fs * 1.1 + rank * _fs * 1.7),
			player_name, color, Color(1, 1, 1, 0.9), Color(0, 0, 0, 0))


func _draw_legend(rect: Rect2, columns: int) -> void:
	var items: Array = []
	for type_name in SPACE_COLORS:
		items.append({"kind": "swatch", "color": SPACE_COLORS[type_name], "label": type_name})
	items.append({"kind": "line", "color": ADJACENT_COLOR, "label": "Adjacent"})
	items.append({"kind": "dash", "color": SPACE_COLORS["Teleport"], "label": "Non-adjacent"})
	for i in _players.size():
		var player: Dictionary = _players[i]
		items.append({
			"kind": "marker%d" % (i % 3),
			"color": PLAYER_COLORS[i % PLAYER_COLORS.size()],
			"label": str(player.get("name", "Player %d" % (i + 1))).left(12),
		})

	_draw_box(rect, Color(1, 1, 1, 0.85), Color(0.75, 0.75, 0.75), 6, 1)
	var pad := _fs * 0.8
	draw_string(_font, rect.position + Vector2(pad, pad + _font.get_ascent(_fs)),
		"Legend", HORIZONTAL_ALIGNMENT_LEFT, -1, _fs + 2, Color.BLACK)

	var rows := ceili(items.size() / float(columns))
	var top := rect.position.y + pad * 2.0 + _fs
	var row_h := minf(_fs * 2.0, (rect.end.y - pad - top) / rows)
	var col_w := (rect.size.x - pad * 2.0) / columns
	var icon_r := minf(_fs * 0.7, row_h * 0.4)

	for i in items.size():
		var item: Dictionary = items[i]
		var col := i % columns
		var row := floori(i / float(columns))
		var row_center_y := top + row * row_h + row_h / 2.0
		var icon_center := Vector2(rect.position.x + pad + col * col_w + icon_r * 1.2, row_center_y)
		var color: Color = item["color"]
		var kind: String = item["kind"]

		match kind:
			"swatch":
				if not SpaceArt.draw_space(self, item["label"], icon_center, icon_r * 2.4):
					draw_circle(icon_center, icon_r, color)
					draw_arc(icon_center, icon_r, 0.0, TAU, 24, Color.BLACK, 1.5, true)
			"line":
				draw_line(icon_center - Vector2(icon_r, 0), icon_center + Vector2(icon_r, 0),
					Color(0.5, 0.5, 0.5), 2.0, true)
			"dash":
				var dash_a := icon_center - Vector2(icon_r * 1.1, 0)
				draw_line(dash_a, dash_a + Vector2(icon_r * 0.6, 0), color, 2.5, true)
				draw_line(dash_a + Vector2(icon_r * 1.0, 0), dash_a + Vector2(icon_r * 1.6, 0),
					color, 2.5, true)
			_:
				_draw_marker(icon_center, icon_r * 0.8, int(kind.right(1)), color)

		draw_string(_font,
			Vector2(icon_center.x + icon_r * 2.0,
				row_center_y + (_font.get_ascent(_fs) - _font.get_descent(_fs)) / 2.0),
			item["label"], HORIZONTAL_ALIGNMENT_LEFT, col_w - icon_r * 3.5, _fs, Color.BLACK)


# ---------------------------------------------------------------------------
# Small drawing helpers
# ---------------------------------------------------------------------------

func _draw_marker(center: Vector2, radius: float, shape: int, color: Color) -> void:
	match shape:
		0:  # circle
			draw_circle(center, radius, color)
			draw_arc(center, radius, 0.0, TAU, 24, Color.WHITE, 2.0, true)
		1:  # square
			var rect := Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
			draw_rect(rect, color)
			draw_rect(rect, Color.WHITE, false, 2.0)
		_:  # triangle
			var tri := PackedVector2Array([
				center + Vector2(0.0, -radius * 1.15),
				center + Vector2(-radius * 1.1, radius * 0.9),
				center + Vector2(radius * 1.1, radius * 0.9),
			])
			draw_colored_polygon(tri, color)
			draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]),
				Color.WHITE, 2.0, true)


func _draw_box(rect: Rect2, fill: Color, border: Color, radius: int, border_width: int) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	draw_style_box(box, rect)


func _draw_text_centered(center: Vector2, text: String, font_size: int, color: Color) -> void:
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center.y + (_font.get_ascent(font_size) - _font.get_descent(font_size)) / 2.0
	draw_string(_font, Vector2(center.x - text_size.x / 2.0, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_label(center: Vector2, text: String, text_color: Color, fill: Color, border: Color) -> void:
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs)
	var pad := Vector2(_fs * 0.4, _fs * 0.2)
	_draw_box(Rect2(center - text_size / 2.0 - pad, text_size + pad * 2.0), fill, border, 4, 1)
	_draw_text_centered(center, text, _fs, text_color)
