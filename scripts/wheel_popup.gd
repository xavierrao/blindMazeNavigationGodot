class_name WheelPopup
extends Control
## Pop-up that shows the wheel waiting in GameState.pending, lets the player
## press Spin, animates the result, then says "Continue". Set `state` before
## adding it to the scene. Emits `closed` when the player continues.

signal closed

var state: GameState

var _wheel: WheelView
var _result: Label
var _button: Button
var _spun := false


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
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var wheel_name: String = state.pending.get("wheel", "")
	title.text = "%s - %s" % [state.current()["name"], WheelData.title(wheel_name)]
	box.add_child(title)

	_wheel = WheelView.new()
	_wheel.custom_minimum_size = Vector2(320, 320)
	_wheel.set_slices(state.pending_slices())
	box.add_child(_wheel)

	_result = Label.new()
	_result.add_theme_font_size_override("font_size", 22)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.text = " "
	box.add_child(_result)

	_button = Button.new()
	_button.text = "Spin!"
	_button.custom_minimum_size = Vector2(0, 52)
	_button.pressed.connect(_on_button_pressed)
	box.add_child(_button)

	state.wheel_spun.connect(_on_wheel_spun)


func _on_button_pressed() -> void:
	if not _spun:
		_button.disabled = true
		state.spin()   # -> wheel_spun fires, which starts the animation
	else:
		closed.emit()
		queue_free()


func _on_wheel_spun(_wheel_name: String, slices: Array, index: int) -> void:
	_spun = true
	_wheel.spin_finished.connect(func() -> void:
		_result.text = slices[index]["label"]
		_button.text = "Continue"
		_button.disabled = false)
	_wheel.spin_to(index)
