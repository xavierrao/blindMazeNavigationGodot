extends Control
## Hot-seat test screen for Blind Crown Quest: board + direction pad + turn controls,
## plus the wheel and shop pop-ups and the win screen.
## The whole UI is built in code, so main.tscn only needs this script on a Control.
##
## This script is the only place that knows which view shows the game. To swap the
## board for a "players and their spaces" view later, replace `_board` and the
## `_board.queue_redraw()` call in _refresh().

const PLAYER_NAMES := ["Alice", "Bob", "Cara"]
const LOG_LINES := 8
# [direction name, button text], laid out as a 3x3 pad. "" is the center cell.
const PAD := [
	["NorthWest", "NW"], ["North", "N"], ["NorthEast", "NE"],
	["West", "W"], ["", ""], ["East", "E"],
	["SouthWest", "SW"], ["South", "S"], ["SouthEast", "SE"],
]

var state := GameState.new()

var _split: BoxContainer
var _board: BoardView
var _panel: VBoxContainer
var _turn_label: Label
var _players_label: Label
var _pad_buttons := {}   # direction name -> Button
var _end_button: Button
var _shop_button: Button
var _memory_check: CheckBox
var _log_label: Label
var _log: Array = []
var _held_messages: Array = []   # messages held back while a wheel is spinning
var _wheel_popup: WheelPopup
var _shop_popup: ShopPopup
var _overlay: Control


func _ready() -> void:
	_setup_window_scaling()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

	state.message.connect(_on_message)
	state.changed.connect(_refresh)
	_board.bind(state)
	_board.tile_clicked.connect(_on_tile_clicked)
	resized.connect(_update_layout)

	state.setup(PLAYER_NAMES)
	_on_message("Game start! %s goes first." % state.current()["name"])
	_refresh()
	_update_layout()


# Scale the UI by the window's shorter side so text stays readable on phones
# (portrait or landscape) and on big screens.
func _setup_window_scaling() -> void:
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i.ZERO
	window.size_changed.connect(_apply_scale)
	_apply_scale()


func _apply_scale() -> void:
	var window := get_window()
	var shorter := float(mini(window.size.x, window.size.y))
	window.content_scale_factor = clampf(shorter / 560.0, 1.0, 4.0)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = BoardView.BG_COLOR
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	add_child(margin)

	_split = BoxContainer.new()
	_split.add_theme_constant_override("separation", 12)
	margin.add_child(_split)

	_board = BoardView.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(280, 280)
	_split.add_child(_board)

	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 8)
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split.add_child(_panel)

	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 26)
	_turn_label.add_theme_color_override("font_color", Color.BLACK)
	_panel.add_child(_turn_label)

	_players_label = Label.new()
	_players_label.add_theme_color_override("font_color", Color.BLACK)
	_panel.add_child(_players_label)

	var pad := GridContainer.new()
	pad.columns = 3
	pad.add_theme_constant_override("h_separation", 6)
	pad.add_theme_constant_override("v_separation", 6)
	_panel.add_child(pad)
	for entry in PAD:
		var direction: String = entry[0]
		var text: String = entry[1]
		if direction == "":
			var center := Label.new()
			center.text = "Move"
			center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			center.add_theme_color_override("font_color", Color.BLACK)
			center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pad.add_child(center)
			continue
		var button := Button.new()
		button.text = text
		button.custom_minimum_size = Vector2(64, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_direction_pressed.bind(direction))
		pad.add_child(button)
		_pad_buttons[direction] = button

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	_panel.add_child(action_row)
	_end_button = Button.new()
	_end_button.text = "End Turn"
	_end_button.custom_minimum_size = Vector2(0, 46)
	_end_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_button.pressed.connect(func() -> void: state.end_turn())
	action_row.add_child(_end_button)
	_shop_button = Button.new()
	_shop_button.text = "Shop"
	_shop_button.custom_minimum_size = Vector2(0, 46)
	_shop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_button.pressed.connect(_on_shop_pressed)
	action_row.add_child(_shop_button)

	_memory_check = CheckBox.new()
	_memory_check.text = "Memory Mode (spaces hide when left)"
	for color_name in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
		_memory_check.add_theme_color_override(color_name, Color.BLACK)
	_memory_check.toggled.connect(_on_memory_toggled)
	_panel.add_child(_memory_check)

	_log_label = Label.new()
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.custom_minimum_size = Vector2(0, 60)
	_log_label.clip_text = true
	_log_label.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15))
	_panel.add_child(_log_label)

	var peek := Button.new()
	peek.text = "Peek at full map (debug)"
	peek.pressed.connect(_on_peek_pressed)
	_panel.add_child(peek)


# Landscape: board on the left, controls on the right. Portrait: stacked.
func _update_layout() -> void:
	var portrait := size.y > size.x
	_split.vertical = portrait
	_board.size_flags_stretch_ratio = 1.0
	_panel.size_flags_stretch_ratio = 0.7 if not portrait else 0.9
	_panel.custom_minimum_size = Vector2(0.0 if portrait else 300.0, 0.0)


# ---------------------------------------------------------------------------
# Updating the screen
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if state.players.is_empty():
		return
	# Keep the screen still while a wheel is spinning, so the result isn't
	# given away early. It all catches up when the player presses Continue.
	if is_instance_valid(_wheel_popup):
		return

	_board.queue_redraw()

	var current_player := state.current()
	_turn_label.text = "%s's turn  (Round %d)" % [current_player["name"], state.round_number]

	var lines: Array = []
	for i in state.players.size():
		var player: Dictionary = state.players[i]
		var line := "%s %s    Gold: %d" % [">" if i == state.current_player else " ", player["name"], player["gold"]]
		var item_count := 0
		for count in player["inventory"].values():
			item_count += int(count)
		if item_count > 0:
			line += "    Items: %d" % item_count
		if player["trapped"]:
			line += "    (Shadow Realm)"
		lines.append(line)
	_players_label.text = "\n".join(lines)

	var moves := state.legal_moves()
	for direction in _pad_buttons:
		(_pad_buttons[direction] as Button).disabled = not moves.has(direction)
	_end_button.disabled = not state.can_end_turn()
	_shop_button.disabled = not state.can_shop()
	_memory_check.set_pressed_no_signal(state.memory_mode)

	if state.winner >= 0:
		_show_win()
	elif state.pending.get("kind", "") == "wheel":
		_open_wheel()


func _on_message(text: String) -> void:
	if is_instance_valid(_wheel_popup):
		_held_messages.append(text)   # shown once the wheel has finished
	else:
		_append_log(text)


func _append_log(text: String) -> void:
	_log.append(text)
	while _log.size() > LOG_LINES:
		_log.pop_front()
	var newest_first := _log.duplicate()
	newest_first.reverse()
	_log_label.text = "\n".join(newest_first)


# ---------------------------------------------------------------------------
# Pop-ups and overlays
# ---------------------------------------------------------------------------

func _open_wheel() -> void:
	_wheel_popup = WheelPopup.new()
	_wheel_popup.state = state
	_wheel_popup.closed.connect(_on_wheel_closed)
	add_child(_wheel_popup)


func _on_wheel_closed() -> void:
	_wheel_popup = null
	for text in _held_messages:
		_append_log(text)
	_held_messages.clear()
	_refresh()   # also opens the next wheel if the result triggered one


func _on_shop_pressed() -> void:
	if is_instance_valid(_shop_popup):
		return
	_shop_popup = ShopPopup.new()
	_shop_popup.state = state
	_shop_popup.closed.connect(func() -> void:
		_shop_popup = null
		_refresh())
	add_child(_shop_popup)


func _show_win() -> void:
	if is_instance_valid(_overlay):
		return
	var winner_name: String = state.players[state.winner]["name"]
	_show_map_overlay("%s wins! - Final Map" % winner_name, "New Game", func() -> void:
		_overlay.queue_free()
		_overlay = null
		_log.clear()
		_held_messages.clear()
		state.setup(PLAYER_NAMES)
		_on_message("New game! %s goes first." % state.current()["name"])
		_refresh())


func _on_peek_pressed() -> void:
	if is_instance_valid(_overlay):
		return
	_show_map_overlay("Blind Crown Quest - Full Map", "Close", func() -> void:
		_overlay.queue_free()
		_overlay = null)


func _show_map_overlay(title: String, button_text: String, on_press: Callable) -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var reveal := MapReveal.new()
	reveal.title = title
	reveal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(reveal)
	var button := Button.new()
	button.text = button_text
	button.pressed.connect(on_press)
	_overlay.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	add_child(_overlay)
	reveal.show_map(state.spaces, state.players, false)


# ---------------------------------------------------------------------------
# Input handlers
# ---------------------------------------------------------------------------

func _on_direction_pressed(direction: String) -> void:
	state.move(direction)


func _on_tile_clicked(space_id: int) -> void:
	var from: int = state.current()["position"]
	var moves := state.legal_moves()
	for direction in moves:
		if moves[direction] == space_id and GameState.distance(from, space_id) <= 1:
			state.move(direction)
			return


func _on_memory_toggled(pressed: bool) -> void:
	state.memory_mode = pressed
	state.changed.emit()
