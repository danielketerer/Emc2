extends Node2D

# Shared by the controlled particle, free H2 and collected orbiters.
var form: int = 2
var age: float = 0.0
var detail_level: int = 0
var redraw_clock: float = 0.0
var surfaces: Array[Sprite2D] = []
const SURFACE_TEXTURE = preload("res://resources/white.tres")

func _ready() -> void:
	var visibility_notifier := VisibleOnScreenNotifier2D.new()
	var extent := 100.0
	visibility_notifier.rect = Rect2(Vector2.ONE * -extent, Vector2.ONE * extent * 2.0)
	visibility_notifier.screen_entered.connect(set_process.bind(true))
	visibility_notifier.screen_exited.connect(set_process.bind(false))
	add_child(visibility_notifier)
	set_process(false)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	build_surfaces()

func set_form(value: int) -> void:
	form = value
	if is_inside_tree():
		build_surfaces()

func build_surfaces() -> void:
	for surface in surfaces:
		surface.queue_free()
	surfaces.clear()
	if form == 0:
		return
	for i in range(2 if form == 2 else 1):
		var surface := Sprite2D.new()
		surface.texture = SURFACE_TEXTURE
		surface.scale = Vector2.ONE * (15.0 if form == 2 else 17.0)
		surface.position.x = (-16.0 if i == 0 else 16.0) if form == 2 else 0.0
		surface.material = preload("res://resources/proton_material.tres")
		add_child(surface)
		surfaces.append(surface)

func _process(delta: float) -> void:
	age += delta
	redraw_clock += delta
	var screen_scale := get_global_transform_with_canvas().get_scale().abs().x
	var next_detail := 0 if screen_scale >= 0.55 else (1 if screen_scale >= 0.35 else 2)
	if next_detail != detail_level:
		detail_level = next_detail
		queue_redraw()
	if detail_level < 2 and redraw_clock >= (1.0/30.0 if detail_level == 0 else 1.0/15.0):
		redraw_clock = 0.0
		queue_redraw()

func _draw() -> void:
	var color := Color("8ddcff") if form == 0 else Color("ffe1ae")
	if form == 2:
		color = Color("a4deec")
	var radius := 8.0 if form == 0 else 18.0
	for i in range(6 if detail_level == 0 else (2 if detail_level == 1 else 0), 0, -1):
		draw_circle(Vector2.ZERO, radius + i * 3, Color(color, 0.012))
	if form == 0:
		draw_circle(Vector2.ZERO, 8, Color("4db9df"))
		draw_circle(Vector2(-2, -2), 4, Color("e8fcff"))
		return
	if form == 2:
		draw_line(Vector2(-16, 0), Vector2(16, 0), Color("d7ffff"), 8, true)
	for center in [Vector2(-16, 0), Vector2(16, 0)] if form == 2 else [Vector2.ZERO]:
		if detail_level == 2:
			draw_circle(center, 5.0, Color("b7e8f6"))
			continue
		draw_arc(center, 27, 0, TAU, 48 if detail_level == 0 else 20, Color(color, 0.6), 1.2, true)
		draw_circle(center + Vector2.from_angle(age * 3 + center.x) * 27, 3, Color("eafaff"))
