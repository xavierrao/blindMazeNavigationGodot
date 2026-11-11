class_name ShopPopup
extends Control
## Pop-up shop for the current player. Reads the item list from ItemData and the
## rules (cost, limits, being on a Shop space) from GameState. Set `state`
## before adding it to the scene. Emits `closed` when the player leaves.

signal closed

var state: GameState

var _gold_label: Label
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

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 300)
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
	_gold_label.text = "%s - Gold: %d" % [state.current()["name"], state.current()["gold"]]

	for item in ItemData.ITEMS:
		var item_id: String = item["id"]
		var bought: int = state.current()["purchases"].get(item_id, 0)
		var limit: int = item["max"]
		var limit_text := "%d/%d bought" % [bought, limit] if limit >= 0 else "%d bought" % bought

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_list.add_child(row)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var name_label := Label.new()
		name_label.text = "%s  -  %d gold  (%s)" % [item["name"], item["cost"], limit_text]
		info.add_child(name_label)
		var description := Label.new()
		description.text = item["description"]
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size = Vector2(280, 0)
		description.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		info.add_child(description)

		var buy := Button.new()
		buy.text = "Buy"
		buy.custom_minimum_size = Vector2(70, 44)
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buy.disabled = state.buy_problem(item_id) != ""
		buy.pressed.connect(_on_buy_pressed.bind(item_id))
		row.add_child(buy)


func _on_buy_pressed(item_id: String) -> void:
	if state.buy(item_id):
		_status.text = "Bought %s." % ItemData.find(item_id)["name"]
	_rebuild()
