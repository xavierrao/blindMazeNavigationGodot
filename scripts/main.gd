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
var _seed_label: Label
var _seed_edit: LineEdit
var _pad_buttons := {}   # direction name -> Button
var _end_button: Button
var _shop_button: Button
var _items_button: Button
var _memory_check: CheckBox
var _log_label: Label
var _log: Array = []
var _held_messages: Array = []   # messages held back while a wheel is spinning
var _wheel_popup: WheelPopup
var _shop_popup: ShopPopup
var _items_popup: ItemsPopup
var _choice_popup: ChoicePopup
var _prompt_popup: ChoicePopup   # yes/no questions from the rules (like the Anchor's Teleport question)
var _info_queue: Array = []   # private messages waiting to be shown: {"player": int, "text": String}
var _overlay: Control


func _ready() -> void:
	_setup_window_scaling()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

	state.message.connect(_on_message)
	state.private_message.connect(_on_private_message)
	state.changed.connect(_refresh)
	_board.bind(state)
	_board.tile_clicked.connect(_on_tile_clicked)
	resized.connect(_update_layout)

	_start_new_game()
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

	_seed_label = Label.new()
	_seed_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
	_panel.add_child(_seed_label)

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
	_items_button = Button.new()
	_items_button.text = "Items"
	_items_button.custom_minimum_size = Vector2(0, 46)
	_items_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_button.pressed.connect(_on_items_pressed)
	action_row.add_child(_items_button)

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

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	_panel.add_child(seed_row)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "Seed (blank = random)"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)
	var new_game := Button.new()
	new_game.text = "New Game"
	new_game.pressed.connect(_start_new_game)
	seed_row.add_child(new_game)

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
	_seed_label.text = "Seed: %d  (type it below to replay this game)" % state.game_seed

	var current_player := state.current()
	_turn_label.text = "%s's turn  (Round %d)" % [current_player["name"], state.round_number]

	var lines: Array = []
	for i in state.players.size():
		var player: Dictionary = state.players[i]
		var line := "%s %s    Gold: %d" % [">" if i == state.current_player else " ", player["name"], player["gold"]]
		if not player["hand"].is_empty():
			line += "    Items: %d" % player["hand"].size()
		if player["trapped"]:
			line += "    (Shadow Realm)"
		lines.append(line)
	_players_label.text = "\n".join(lines)

	var moves := state.legal_moves()
	for direction in _pad_buttons:
		(_pad_buttons[direction] as Button).disabled = not moves.has(direction)
	_end_button.disabled = not state.can_end_turn()
	_shop_button.disabled = not state.can_shop()
	_items_button.text = "Items (%d)" % state.current()["hand"].size()
	_memory_check.set_pressed_no_signal(state.memory_mode)

	if state.winner >= 0:
		_show_win()
	elif state.pending.get("kind", "") == "wheel":
		_open_wheel()
	elif state.pending.get("kind", "") == "choice":
		_open_prompt()


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


# The rules are asking a yes/no question (right now only: "block this Teleport?").
func _open_prompt() -> void:
	if is_instance_valid(_prompt_popup):
		return
	var player_index: int = state.pending["player"]
	var effect := state.active_effect(player_index, "anchor")
	var left: int = effect.get("charges", 0)
	_prompt_popup = ChoicePopup.new()
	_prompt_popup.title = "%s - Teleporter!" % state.players[player_index]["name"]
	_prompt_popup.body = "You landed on a Teleport space and will be thrown somewhere random. " \
		+ "Use your Anchor to stay put? (%d %s left)" % [left, "block" if left == 1 else "blocks"]
	_prompt_popup.options = [
		{"label": "Block it (spend 1 charge)", "value": true},
		{"label": "Let it teleport me", "value": false},
	]
	_prompt_popup.chosen.connect(func(accept: bool) -> void:
		_prompt_popup = null
		state.resolve_choice(accept))
	add_child(_prompt_popup)


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


func _on_items_pressed() -> void:
	if is_instance_valid(_items_popup):
		return
	_items_popup = ItemsPopup.new()
	_items_popup.state = state
	_items_popup.use_requested.connect(_on_use_requested)
	_items_popup.activate_requested.connect(func(item_id: String) -> void:
		_items_popup = null
		state.activate_item(item_id))
	_items_popup.closed.connect(func() -> void: _items_popup = null)
	add_child(_items_popup)


func _on_use_requested(item_id: String) -> void:
	_items_popup = null
	var item := ItemData.find(item_id)
	if item["target"] == "direction":
		_ask_direction(item_id)
	elif item["target"] == "swap":
		var swaps := ItemEffects.swap_options(state)
		if swaps.size() == 1:
			state.use_item(item_id, {"pair": swaps[0]})
		else:
			_ask_swap(item_id, swaps)
	elif item["target"] == "opponent":
		var options := ItemEffects.target_options(state, item_id)
		if options.size() == 1:
			state.use_item(item_id, {"target": options[0]})
		else:
			_ask_target(item_id, options)
	else:
		state.use_item(item_id)


func _ask_direction(item_id: String) -> void:
	var options: Array = []
	for direction in GameState.DIRECTIONS:
		var label := ""
		for i in direction.length():
			if i > 0 and direction[i] == direction[i].to_upper():
				label += " "
			label += direction[i]
		options.append({"label": label, "value": direction})
	_choice_popup = ChoicePopup.new()
	_choice_popup.title = "%s - choose a direction" % ItemData.find(item_id)["name"]
	_choice_popup.options = options
	_choice_popup.cancel_text = "Cancel"
	_choice_popup.chosen.connect(func(direction: String) -> void:
		_choice_popup = null
		state.use_item(item_id, {"direction": direction})
		_show_next_info())
	_choice_popup.cancelled.connect(func() -> void: _choice_popup = null)
	add_child(_choice_popup)


func _ask_swap(item_id: String, pairs: Array) -> void:
	var choices: Array = []
	for pair in pairs:
		var a: int = pair[0]
		var b: int = pair[1]
		var label := ""
		if a == state.current_player:
			label = "Swap places with %s" % state.players[b]["name"]
		elif b == state.current_player:
			label = "Swap places with %s" % state.players[a]["name"]
		else:
			label = "Swap %s and %s" % [state.players[a]["name"], state.players[b]["name"]]
		choices.append({"label": label, "value": pair})
	_choice_popup = ChoicePopup.new()
	_choice_popup.title = "%s - choose a swap" % ItemData.find(item_id)["name"]
	_choice_popup.options = choices
	_choice_popup.cancel_text = "Cancel"
	_choice_popup.chosen.connect(func(pair: Array) -> void:
		_choice_popup = null
		state.use_item(item_id, {"pair": pair})
		_show_next_info())
	_choice_popup.cancelled.connect(func() -> void: _choice_popup = null)
	add_child(_choice_popup)


func _ask_target(item_id: String, options: Array) -> void:
	var choices: Array = []
	for player_index in options:
		choices.append({"label": state.players[player_index]["name"], "value": player_index})
	_choice_popup = ChoicePopup.new()
	_choice_popup.title = "%s - choose a target" % ItemData.find(item_id)["name"]
	_choice_popup.options = choices
	_choice_popup.cancel_text = "Cancel"
	_choice_popup.chosen.connect(func(player_index: int) -> void:
		_choice_popup = null
		state.use_item(item_id, {"target": player_index})
		_show_next_info())
	_choice_popup.cancelled.connect(func() -> void: _choice_popup = null)
	add_child(_choice_popup)


# Information items answer privately. On one shared screen we show it in a
# pop-up for the player who used it; in multiplayer it would go only to them.
func _on_private_message(player_index: int, text: String) -> void:
	_info_queue.append({"player": player_index, "text": text})
	_show_next_info()


func _show_next_info() -> void:
	if _info_queue.is_empty() or is_instance_valid(_choice_popup):
		return
	var info: Dictionary = _info_queue.pop_front()
	_choice_popup = ChoicePopup.new()
	_choice_popup.title = "Private - only %s should look!" % state.players[info["player"]]["name"]
	_choice_popup.body = info["text"]
	_choice_popup.options = [{"label": "Got it", "value": null}]
	_choice_popup.chosen.connect(func(_value: Variant) -> void:
		_choice_popup = null
		_show_next_info())
	add_child(_choice_popup)


func _show_win() -> void:
	if is_instance_valid(_overlay):
		return
	var winner_name: String = state.players[state.winner]["name"]
	_show_map_overlay("%s wins! - Final Map" % winner_name, "New Game", func() -> void:
		_overlay.queue_free()
		_overlay = null
		_start_new_game())


# Starts a fresh game. A number in the seed box replays that seed; blank is random.
func _start_new_game() -> void:
	for popup in [_wheel_popup, _shop_popup, _items_popup, _choice_popup, _prompt_popup]:
		if is_instance_valid(popup):
			popup.queue_free()
	_wheel_popup = null
	_shop_popup = null
	_items_popup = null
	_choice_popup = null
	_prompt_popup = null
	_info_queue.clear()
	_log.clear()
	_held_messages.clear()
	var seed_value := -1
	if _seed_edit.text.strip_edges().is_valid_int():
		seed_value = absi(int(_seed_edit.text.strip_edges()))
	state.setup(PLAYER_NAMES, 12, seed_value)
	_on_message("Game start! Seed %d. %s goes first." % [state.game_seed, state.current()["name"]])
	_refresh()


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
	reveal.show_map(state.spaces, state.players, false, state.goblin_space)


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
