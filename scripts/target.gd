extends Area2D

const MatterVisual = preload("res://scripts/matter_visual.gd")
var kind: int = 0
var identity: int = 0
var selected: bool = false
var previous_selected: bool = false
var available: bool = true
var age: float = 0.0
var radius: float = 22.0
var tint := Color("f6ad66")
var body: Node2D
var components: Array[Node2D] = []
var reaction_stage: int = -1
var captured_mask: int = -1
var pair_progress: float = 0.0
var previous_position := Vector2.ZERO
var previous_rotation: float = 0.0
var motion_rotation: float = 0.0
var reaction_flash: float = 0.0
var last_rendered_flash: float = 0.0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	previous_position = position
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-110, -110, 220, 220)
	notifier.screen_entered.connect(set_process.bind(true))
	notifier.screen_exited.connect(set_process.bind(false))
	add_child(notifier)
	set_process(false)
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 30.0 if kind == 2 else 12.0
	shape.shape = circle
	add_child(shape)
	configure_reaction(kind, 3 if kind == 2 else 1)

func make_proton(size: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = preload("res://resources/white.tres")
	sprite.scale = Vector2.ONE * size
	sprite.material = preload("res://resources/proton_material.tres")
	return sprite

func make_atom() -> Node2D:
	var atom := Node2D.new()
	atom.set_script(MatterVisual)
	atom.form = 1
	return atom

func configure_reaction(stage: int, mask: int) -> void:
	if reaction_stage == stage and captured_mask == mask:
		return
	reaction_stage = stage
	captured_mask = mask
	if is_instance_valid(body):
		body.hide()
		body.queue_free()
	components.clear()
	if kind == 2 and stage < 2:
		body = Node2D.new()
		for index in range(2):
			var part: Node2D = make_atom() if mask & (1 << index) else make_proton(15.0)
			body.add_child(part)
			components.append(part)
	elif kind == 0 or stage == 0:
		body = make_proton(radius if kind == 0 else 17.0)
	else:
		body = Node2D.new()
		body.set_script(MatterVisual)
		body.form = kind
	body.top_level = true
	body.position = global_position
	add_child(body)
	set_pair_progress(pair_progress)
	queue_redraw()

func component_position(index: int) -> Vector2:
	if kind != 2 or reaction_stage >= 2:
		return position
	var separation := lerpf(60.0, 16.0, smoothstep(0.0, 1.0, pair_progress))
	var offset := Vector2(-separation if index == 0 else separation, 0).rotated(motion_rotation)
	return position + offset

func set_pair_progress(value: float) -> void:
	pair_progress = value
	var separation := lerpf(60.0, 16.0, smoothstep(0.0, 1.0, pair_progress))
	for index in range(components.size()):
		components[index].position = Vector2(-separation if index == 0 else separation, 0)

func set_simulation_position(value: Vector2, teleport: bool = false) -> void:
	previous_position = value if teleport else position
	position = value
	if teleport and is_instance_valid(body):
		body.global_position = global_position

func update_presentation(fraction: float) -> void:
	if not is_instance_valid(body):
		return
	body.global_position = get_parent().to_global(previous_position.lerp(position, fraction))
	body.rotation = lerp_angle(previous_rotation, motion_rotation, fraction)

func _process(delta: float) -> void:
	age += delta
	if selected or previous_selected or reaction_flash > 0 or last_rendered_flash > 0:
		queue_redraw()
	previous_selected = selected
	last_rendered_flash = reaction_flash

func _draw() -> void:
	var offset := body.global_position-global_position if is_instance_valid(body) else Vector2.ZERO
	if reaction_flash > 0:
		draw_arc(offset, 35 + (1.0-reaction_flash/0.4)*24, 0, TAU, 24, Color(0.6, 0.9, 1, reaction_flash*0.55), 1.5, true)
	if selected:
		var r := radius*1.8 + sin(age*3)*2
		for index in range(4):
			draw_arc(offset, r, index*PI/2+0.12, index*PI/2+0.9, 16, Color("e2f6ff"), 1.7, true)
