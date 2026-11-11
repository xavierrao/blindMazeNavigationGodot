class_name BoardView
extends Control
## Draws the playable 5x5 board from a GameState and reports tile clicks/taps.
## Face-down spaces show "?"; face-up spaces show their artwork (see SpaceArt),
## or a colored circle if a picture is missing.

signal tile_clicked(space_id: int)

const GRID_SIZE := 5
const BG_COLOR := Color("#F5F5DC")
const HIDDEN_FILL := Color("#3E4261")
const HIDDEN_BORDER := Color("#2A2D45")
const HIGHLIGHT := Color("#FFC400")

var state: GameState

var _font: Font
var _cell := 100.0
var _origin := Vector2.ZERO


func _ready() -> void:
	texture_filter = SpaceArt.FILTER
	resized.connect(queue_redraw)


# The screen (main.gd) calls queue_redraw() when it wants this view refreshed.
func bind(game_state: GameState) -> void:
	state = game_state
	queue_redraw()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	_update_layout()
	var grid_pos := (click.position - _origin) / _cell
	if grid_pos.x < 0.0 or grid_pos.y < 0.0 or grid_pos.x >= GRID_SIZE or grid_pos.y >= GRID_SIZE:
		return
	tile_clicked.emit(int(grid_pos.y) * GRID_SIZE + int(grid_pos.x))


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _update_layout() -> void:
	var margin := minf(size.x, size.y) * 0.03
	var side := maxf(minf(size.x, size.y) - margin * 2.0, 10.0)
	_cell = side / GRID_SIZE
	_origin = (size - Vector2(side, side)) / 2.0


func _tile_center(id: int) -> Vector2:
	var col := id % GRID_SIZE
	var row := floori(id / float(GRID_SIZE))
	return _origin + (Vector2(col, row) + Vector2(0.5, 0.5)) * _cell


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	if state == null or state.spaces.is_empty():
		return

	_font = get_theme_default_font()
	_update_layout()
	var font_size := int(clampf(_cell * 0.17, 9.0, 28.0))
	var radius := _cell * 0.44
	var hint_targets := _adjacent_targets()
	var current_pos: int = state.current()["position"]
	var current_color: Color = MapReveal.PLAYER_COLORS[
		state.current_player % MapReveal.PLAYER_COLORS.size()]

	for id in GRID_SIZE * GRID_SIZE:
		var center := _tile_center(id)
		if state.is_face_up(id):
			_draw_face_up(center, radius, state.space_type(id), font_size)
		else:
			_draw_face_down(center, radius)
		if hint_targets.has(id):
			draw_circle(center, radius, Color(HIGHLIGHT, 0.18))
			draw_arc(center, radius, 0.0, TAU, 48, HIGHLIGHT, 5.0, true)
		if id == current_pos:
			draw_arc(center, radius + 3.0, 0.0, TAU, 48, current_color, 5.0, true)

	_draw_tokens()


func _draw_face_up(center: Vector2, radius: float, type_name: String, font_size: int) -> void:
	if SpaceArt.draw_space(self, type_name, center, radius * 2.0):
		return
	# No picture for this type: colored circle with the name on it.
	var fill: Color = MapReveal.SPACE_COLORS.get(type_name, Color.WHITE)
	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 48, Color.BLACK, 3.0, true)
	var text_color := Color.WHITE if MapReveal.DARK_TYPES.has(type_name) else Color.BLACK
	_draw_text_lines(center - Vector2(0.0, _cell * 0.1), type_name, font_size, text_color)


func _draw_face_down(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, HIDDEN_FILL)
	draw_arc(center, radius, 0.0, TAU, 48, HIDDEN_BORDER, 3.0, true)
	_draw_text_lines(center - Vector2(0.0, _cell * 0.05), "?", int(_cell * 0.4), Color(1, 1, 1, 0.35))


# Adjacent spaces the current player can step to. Long-distance exits are not
# highlighted - those are only available from the direction pad.
func _adjacent_targets() -> Dictionary:
	var result := {}
	var moves := state.legal_moves()
	var from: int = state.current()["position"]
	for direction in moves:
		var target: int = moves[direction]
		if GameState.distance(from, target) <= 1:
			result[target] = true
	return result


func _draw_tokens() -> void:
	var by_tile := {}
	for i in state.players.size():
		var pos: int = state.players[i]["position"]
		if not by_tile.has(pos):
			by_tile[pos] = []
		by_tile[pos].append(i)

	for id in by_tile:
		var group: Array = by_tile[id]
		var tile_center := _tile_center(id)
		for rank in group.size():
			var player_index: int = group[rank]
			var color: Color = MapReveal.PLAYER_COLORS[
				player_index % MapReveal.PLAYER_COLORS.size()]
			var offset_x := (rank - (group.size() - 1) / 2.0) * _cell * 0.26
			var center := tile_center + Vector2(offset_x, _cell * 0.28)
			var radius := _cell * (0.125 if player_index == state.current_player else 0.1)
			_draw_marker(center, radius, player_index % 3, color)


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


# Draws text centered on a point, splitting on spaces ("Shadow Realm" -> 2 lines).
func _draw_text_lines(center: Vector2, text: String, font_size: int, color: Color) -> void:
	var lines := text.split(" ")
	for i in lines.size():
		var line := lines[i]
		var line_size := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var y := center.y + (i - (lines.size() - 1) / 2.0) * font_size * 1.15
		var baseline := y + (_font.get_ascent(font_size) - _font.get_descent(font_size)) / 2.0
		draw_string(_font, Vector2(center.x - line_size.x / 2.0, baseline), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
