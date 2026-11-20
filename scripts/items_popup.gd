class_name ItemsPopup
extends Control
## Shows the current player's hand and running passives, with Use / Activate
## buttons. Set `state` before adding it to the scene. It asks for things to be
## done through signals and then closes itself:
##   use_requested(item_id)       - the player pressed Use
##   activate_requested(item_id)  - the player pressed Activate
##   closed                       - closed without doing anything

signal use_requested(item_id: String)
signal activate_requested(item_id: String)
signal closed

var state: GameState


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#2B2D3A")
	panel_style.set_corner_radius_all(12)
	panel_style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var player := state.current()
	var title := Label.new()
	title.text = "%s's items" % player["name"]
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	# Everything else scrolls, so the window always fits on the screen.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(495, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	var hand: Array = player["hand"]
	var hand_title := Label.new()
	hand_title.text = "In your hand (%d/%d)" % [hand.size(), GameState.HAND_LIMIT]
	content.add_child(hand_title)

	if hand.is_empty():
		content.add_child(_gray_label("Nothing yet. Buy items at a Shop space."))
	for entry in hand:
		content.add_child(_hand_row(entry))

	var my_traps := state.traps_owned_by(state.current_player)
	if not my_traps.is_empty():
		var traps_title := Label.new()
		traps_title.text = "Your hidden traps (only you can see these)"
		content.add_child(traps_title)
		for trap in my_traps:
			content.add_child(_gray_label("%s - set on a %s space" % [
				ItemData.find(trap["kind"])["name"], trap["space_type"]]))

	var active: Array = player["active"]
	if not active.is_empty():
		var active_title := Label.new()
		active_title.text = "Running"
		content.add_child(active_title)
		for effect in active:
			var item := ItemData.find(effect["id"])
			var left := "%s left" % ItemData.charge_text(effect["charges"], item["unit"])
			if item["unit"] == "turns" and effect["fresh"]:
				left = "%s, starting next turn" % ItemData.charge_text(effect["charges"], item["unit"])
			content.add_child(_gray_label("%s - %s" % [item["name"], left]))

	if not state.announced_items.is_empty():
		var names: Array = []
		for item_id in state.announced_items:
			names.append(ItemData.find(item_id)["name"])
		var for_sale := _gray_label("In the shops this game (not saying where): " + ", ".join(names) + ".")
		for_sale.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		for_sale.custom_minimum_size = Vector2(420, 0)
		content.add_child(for_sale)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 44)
	close.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	box.add_child(close)


func _hand_row(entry: Dictionary) -> Control:
	var item := ItemData.find(entry["id"])
	var item_id: String = entry["id"]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = "%s  (%s)" % [item["name"], ItemData.charge_text(entry["charges"], item["unit"])]
	info.add_child(name_label)
	var description := _gray_label(item["description"])
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(300, 0)
	info.add_child(description)

	var is_passive: bool = item["passive"]
	var problem := state.activate_problem(item_id) if is_passive else state.use_problem(item_id)
	# Items that need a choice (like a direction) are checked again after choosing.
	if problem == "Choose a direction first." or problem == "Choose a target first." \
			or problem == "Choose a swap first.":
		problem = ""
	if problem != "":
		var why := _gray_label(problem)
		why.add_theme_color_override("font_color", Color("#D98C8C"))
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size = Vector2(300, 0)
		info.add_child(why)

	var button := Button.new()
	button.text = "Activate\n(%d gold)" % GameState.ACTIVATION_FEE if is_passive else "Use"
	button.custom_minimum_size = Vector2(96, 48)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.disabled = problem != ""
	if is_passive:
		button.pressed.connect(func() -> void:
			activate_requested.emit(item_id)
			queue_free())
	else:
		button.pressed.connect(func() -> void:
			use_requested.emit(item_id)
			queue_free())
	row.add_child(button)
	return row


func _gray_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	return label
