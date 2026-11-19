class_name ChoicePopup
extends Control
## A small pop-up with a title, optional text and a list of buttons. Used to
## pick a direction for an item, and to show private information ("Got it").
## Set title, body, options (and cancel_text) before adding it to the scene.
## Emits `chosen(value)` with the value of the button pressed, or `cancelled`.

signal chosen(value)
signal cancelled

var title := ""
var body := ""
var options: Array = []   # [{"label": String, "value": Variant}]
var cancel_text := ""     # leave empty for no Cancel button


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

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size = Vector2(340, 0)
	box.add_child(title_label)

	if body != "":
		var body_label := Label.new()
		body_label.text = body
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_label.custom_minimum_size = Vector2(340, 0)
		box.add_child(body_label)

	for option in options:
		var button := Button.new()
		button.text = option["label"]
		button.custom_minimum_size = Vector2(0, 46)
		button.pressed.connect(_on_option_pressed.bind(option["value"]))
		box.add_child(button)

	if cancel_text != "":
		var cancel := Button.new()
		cancel.text = cancel_text
		cancel.custom_minimum_size = Vector2(0, 40)
		cancel.pressed.connect(func() -> void:
			cancelled.emit()
			queue_free())
		box.add_child(cancel)


func _on_option_pressed(value: Variant) -> void:
	chosen.emit(value)
	queue_free()
