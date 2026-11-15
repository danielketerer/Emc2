extends Node2D

# Background stays black throughout the three phases. Visible dots are simulated matter.
var camera: Camera2D
var background: ColorRect

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	background = ColorRect.new()
	background.color = Color.BLACK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
