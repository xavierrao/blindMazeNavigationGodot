class_name ShopPopup
extends Control
## Pop-up shop for the current player: buy items and sell items back. Reads the
## item list from ItemData and every rule (cost, hand limit, being on a Shop
## space) from GameState. Set `state` before adding it to the scene. Emits
## `closed` when the player leaves.
## Each Shop space has its own items and stock (see ShopBuilder).

signal closed

var state: GameState

var _gold_label: Label
var _hand_label: Label
var _list: VBoxContainer
var _status: Label


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

	var title := Label.new()
	title.text = "Shop"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	_gold_label = Label.new()
	box.add_child(_gold_label)
	_hand_label = Label.new()
	box.add_child(_hand_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(530, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

	_status = Label.new()
	_status.text = " "
	box.add_child(_status)

	var close := Button.new()
	close.text = "Leave Shop"
	close.custom_minimum_size = Vector2(0, 46)
	close.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	box.add_child(close)

	_rebuild()


func _rebuild() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var player := state.current()
	_gold_label.text = "%s - Gold: %d" % [player["name"], player["gold"]]
	_hand_label.text = "Hand: %d/%d items" % [player["hand"].size(), GameState.HAND_LIMIT]

	_list.add_child(_heading("For sale here"))
	for listing in state.shop_listing():
		_list.add_child(_buy_row(listing))

	_list.add_child(_heading("Sell back (half price, rounded down)"))
	if player["hand"].is_empty():
		_list.add_child(_gray("You aren't holding anything."))
	for entry in player["hand"]:
		_list.add_child(_sell_row(entry))


func _buy_row(listing: Dictionary) -> Control:
	var item: Dictionary = listing["item"]
	var stock: int = listing["stock"]
	var item_id: String = item["id"]
	var cost_text := "%d gold" % item["cost"]
	if item["passive"]:
		cost_text += " (+%d to activate)" % GameState.ACTIVATION_FEE
	var problem := state.buy_problem(item_id)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = "%s  -  %s  (%s)  -  %s" % [item["name"], cost_text,
		ItemData.charge_text(item["charges"], item["unit"]),
		"%d in stock" % stock if stock > 0 else "OUT OF STOCK"]
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(340, 0)
	info.add_child(name_label)
	var description := _gray(item["description"])
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(340, 0)
	info.add_child(description)
	if problem != "":
		var why := _gray(problem)
		why.add_theme_color_override("font_color", Color("#D98C8C"))
		info.add_child(why)

	var buy := Button.new()
	buy.text = "Buy"
	buy.custom_minimum_size = Vector2(70, 44)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.disabled = problem != ""
	buy.pressed.connect(func() -> void:
		if state.buy(item_id):
			_status.text = "Bought %s." % item["name"]
		_rebuild())
	row.add_child(buy)
	return row


func _sell_row(entry: Dictionary) -> Control:
	var item_id: String = entry["id"]
	var item := ItemData.find(item_id)
	var problem := state.sell_problem(item_id)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = "%s  -  sells for %d gold" % [item["name"], ItemData.sell_price(item_id)]
	info.add_child(name_label)
	if problem != "":
		var why := _gray(problem)
		why.add_theme_color_override("font_color", Color("#D98C8C"))
		info.add_child(why)

	var sell := Button.new()
	sell.text = "Sell"
	sell.custom_minimum_size = Vector2(70, 44)
	sell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sell.disabled = problem != ""
	sell.pressed.connect(func() -> void:
		if state.sell(item_id):
			_status.text = "Sold %s." % item["name"]
		_rebuild())
	row.add_child(sell)
	return row


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	return label


func _gray(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	return label
