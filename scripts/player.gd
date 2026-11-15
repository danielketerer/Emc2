extends Node2D

enum Form { ELECTRON, ATOM, MOLECULE }
const PROFILES = [preload("res://resources/electron.tres"), preload("res://resources/atom.tres"), preload("res://resources/molecule.tres")]
const MatterVisual = preload("res://scripts/matter_visual.gd")
var form: Form = Form.ELECTRON
var velocity := Vector2.ZERO
var steering := Vector2.ZERO
var previous_position := Vector2.ZERO
var render_position := Vector2.ZERO
var target_line: Line2D
var heading: float = 0.0
var sensor: Area2D
var candidates: Array[Area2D] = []
var target: Area2D
var locked: bool = false
var embedded: bool = false
var intro_locked: bool = false
var speed_scale: float = 1.0
var age: float = 0.0
var trail_clock: float = 0.0
var trail: Array[Vector2] = []
var trail_line: Line2D
var visual: Node2D

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	previous_position = global_position
	render_position = global_position
	sensor = Area2D.new()
	sensor.collision_layer = 0
	sensor.collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 500.0
	shape.shape = circle
	sensor.add_child(shape)
	add_child(sensor)
	sensor.area_entered.connect(func(area: Area2D): candidates.append(area))
	sensor.area_exited.connect(func(area: Area2D): candidates.erase(area))
	visual = Node2D.new()
	visual.set_script(MatterVisual)
	visual.form = int(form)
	visual.top_level = true
	add_child(visual)
	trail_line = Line2D.new()
	trail_line.top_level = true
	trail_line.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	trail_line.width = 5.0
	trail_line.antialiased = true
	trail_line.z_index = -1
	add_child(trail_line)
	update_trail_color()
	target_line = Line2D.new()
	target_line.top_level = true
	target_line.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	target_line.width = 1.3
	target_line.antialiased = true
	add_child(target_line)

func valid_candidate(area: Area2D) -> bool:
	return is_instance_valid(area) and area.visible and area.available and area.kind == int(form)

func _process(delta: float) -> void:
	if embedded or intro_locked:
		return
	age += delta
	render_position = previous_position.lerp(global_position, Engine.get_physics_interpolation_fraction())
	visual.global_position = render_position
	update_steering(get_viewport().get_mouse_position())
	if form == Form.MOLECULE:
		var desired_heading := heading
		if velocity.length_squared() > 16.0:
			desired_heading = velocity.angle() + sin(age * 1.2) * 0.12
		var cold_distance := global_position.distance_to(Vector2(2700, -1500))
		var alignment := 1.0 - smoothstep(500.0, 1000.0, cold_distance)
		desired_heading = lerp_angle(desired_heading, 0.0, alignment)
		heading = lerp_angle(heading, desired_heading, 1.0-exp(-delta*3.0))
		visual.rotation = heading
	trail_clock += delta
	var rendered_position: Vector2 = render_position
	if trail_clock >= 0.025:
		trail_clock = 0.0
		trail.push_front(rendered_position)
		if trail.size() > 22:
			trail.pop_back()
	if not trail.is_empty():
		trail[0] = rendered_position
	trail_line.points = PackedVector2Array(trail)
	if is_instance_valid(target):
		target_line.points = PackedVector2Array([render_position, target.global_position])
		target_line.default_color = Color(0.7, 0.9, 1, 0.35)
	else:
		target_line.clear_points()

func _physics_process(delta: float) -> void:
	if embedded or intro_locked:
		return
	previous_position = global_position
	var profile: Resource = PROFILES[form]
	var desired: Vector2 = steering * profile.speed * speed_scale
	velocity = velocity.move_toward(desired, (profile.braking if desired == Vector2.ZERO else profile.acceleration) * delta)
	if desired != Vector2.ZERO:
		for area in candidates:
			if not valid_candidate(area):
				continue
			var offset := area.global_position - global_position
			var distance := offset.length()
			if distance < profile.field_range and distance > 8.0:
				velocity += offset.normalized() * profile.attraction * pow(1.0-distance/profile.field_range, 2) * delta
	velocity = velocity.limit_length(profile.speed * speed_scale * 1.16)
	if not locked:
		global_position += velocity * delta
	global_position = global_position.clamp(Vector2(-5000, -4300), Vector2(6000, 4300))
	select_target()

func select_target() -> void:
	var profile: Resource = PROFILES[form]
	var best: Area2D = null
	var best_distance: float = profile.bond_range
	if valid_candidate(target):
		var distance := global_position.distance_to(target.global_position)
		if distance <= profile.bond_range * 1.15:
			best = target
			best_distance = distance * 0.72
	for area in candidates:
		if valid_candidate(area):
			var distance := global_position.distance_to(area.global_position)
			if distance < best_distance:
				best = area
				best_distance = distance
	if is_instance_valid(target):
		target.selected = false
	target = best
	if is_instance_valid(target):
		target.selected = true

func set_form(value: int) -> void:
	form = value as Form
	velocity *= 0.35
	heading = 0.0
	visual.rotation = 0.0
	visual.set_form(value)
	trail.clear()
	trail_line.clear_points()
	update_trail_color()

func reset_motion() -> void:
	velocity = Vector2.ZERO
	steering = Vector2.ZERO
	trail.clear()
	trail_line.clear_points()
	previous_position = global_position
	render_position = global_position
	visual.global_position = render_position
	reset_physics_interpolation()

func update_trail_color() -> void:
	var color := Color("8ddcff") if form == Form.ELECTRON else Color("ffe1ae")
	if form == Form.MOLECULE:
		color = Color("a4deec")
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color, 0.45))
	gradient.set_color(1, Color(color, 0))
	trail_line.gradient = gradient


func update_steering(mouse_position: Vector2) -> void:
	var profile: Resource = PROFILES[form]
	# Steering is screen-relative. Camera movement cannot change this input.
	var screen_offset := mouse_position - get_viewport_rect().size * 0.5
	var distance := screen_offset.length()
	steering = Vector2.ZERO
	if distance > profile.dead_zone and not locked:
		steering = screen_offset.normalized() * clampf((distance-profile.dead_zone)/180.0, 0, 1)

func set_embedded(value: bool) -> void:
	embedded = value
	locked = value or intro_locked
	reset_motion()
	visual.visible = not (value or intro_locked)
	trail_line.visible = not (value or intro_locked)
	target_line.visible = not (value or intro_locked)
	if is_instance_valid(target):
		target.selected = false
	target = null
	sensor.set_deferred("monitoring", not (value or intro_locked))
func set_intro_locked(value: bool) -> void:
	if intro_locked == value:
		return
	intro_locked = value
	set_embedded(embedded)