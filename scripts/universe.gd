extends Node2D

signal intro_ended
signal first_protons

const DARK_END: float = 0.65
const INTRO_END: float = 2.8
const PROTON_START: float = 6.8
const ATOM_START: float = 9.5
const MOLECULE_START: float = 12.5
const ELECTRON_COUNT: int = 1024
const BURST_COUNT: int = 256
const WORLD_MIN = Vector2(-5600, -5400)
const WORLD_MAX = Vector2(6800, 5400)
var world: Node2D
var elapsed: float = 0.0
var reduced_effects: bool = false
var center := Vector2.ZERO
var homes: Array[Vector2] = []
var birth_times := PackedFloat32Array()
var masks := PackedInt32Array()
var pair_progress := PackedFloat32Array()
var electron_position := PackedVector2Array()
var electron_previous := PackedVector2Array()
var electron_velocity := PackedVector2Array()
var electron_state := PackedByteArray()
var electron_target := PackedInt32Array()
var electron_component := PackedInt32Array()
var target_electrons: Dictionary = {}
var blocked: Dictionary = {}
var multimesh: MultiMesh
var particles: MultiMeshInstance2D
var previous_elapsed: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 30
	particles = MultiMeshInstance2D.new()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(6, 6)
	multimesh.mesh = quad
	multimesh.instance_count = ELECTRON_COUNT
	particles.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://art/electron.gdshader")
	particles.material = material
	particles.z_index = -1
	add_child(particles)
	reset()

func reset() -> void:
	elapsed = 0
	previous_elapsed = 0
	center = world.player.position
	blocked.clear()
	homes.assign(world.spawn_positions)
	birth_times.resize(world.targets.size())
	masks.resize(world.targets.size())
	masks.fill(0)
	pair_progress.resize(world.targets.size())
	pair_progress.fill(0)
	electron_position.resize(ELECTRON_COUNT)
	electron_previous.resize(ELECTRON_COUNT)
	electron_velocity.resize(ELECTRON_COUNT)
	electron_state.resize(ELECTRON_COUNT)
	electron_state.fill(0)
	electron_target.resize(ELECTRON_COUNT)
	electron_target.fill(-1)
	electron_component.resize(ELECTRON_COUNT)
	electron_component.fill(0)
	target_electrons.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 384192
	for index in range(ELECTRON_COUNT):
		var angle := rng.randf_range(0, TAU)
		if index < BURST_COUNT:
			electron_position[index] = center + Vector2.from_angle(angle)*rng.randf_range(0, 7)
			electron_velocity[index] = Vector2.from_angle(angle)*rng.randf_range(160, 480)
		else:
			electron_position[index] = Vector2(rng.randf_range(-4300, 5400), rng.randf_range(-4500, 3500))
			electron_velocity[index] = Vector2.from_angle(angle)*rng.randf_range(20, 60)
	var next_electron := BURST_COUNT
	for target in world.targets:
		var identity: int = target.identity
		birth_times[identity] = PROTON_START + fposmod(identity*1.618034, 4.2)
		if identity == 0:
			birth_times[identity] = PROTON_START
		target.configure_reaction(0, 0)
		target.set_pair_progress(0)
		target.available = false
		target.reaction_flash = 0
		target.selected = false
		target.hide()
		target.set_simulation_position(homes[identity], true)
		target.previous_rotation = 0
		target.motion_rotation = 0
		if target.kind == 0:
			continue
		var assigned: Array[int] = []
		for component in range(2 if target.kind == 2 else 1):
			assert(next_electron < ELECTRON_COUNT, "Ambient electron pool must cover all reactive nuclei")
			var angle := rng.randf_range(0, TAU)
			electron_position[next_electron] = homes[identity] + Vector2.from_angle(angle)*rng.randf_range(170, 420)
			electron_target[next_electron] = identity
			electron_component[next_electron] = component
			assigned.append(next_electron)
			next_electron += 1
		target_electrons[identity] = assigned
	electron_previous = electron_position.duplicate()
	refresh_visibility()
	update_presentation()
	queue_redraw()

func intro_active() -> bool:
	return elapsed < INTRO_END

func set_blocked(identities: Array[int]) -> void:
	var next: Dictionary = {}
	for identity in identities:
		next[identity] = true
	if next == blocked:
		return
	blocked = next
	refresh_visibility()

func drift(identity: int) -> Vector2:
	var target: Area2D = world.targets[identity]
	var radius := 28.0 if target.kind == 2 else (65.0 if target.kind == 1 else 95.0)
	var phase := float(identity)*2.399963
	return Vector2(sin(elapsed*0.18+phase), cos(elapsed*0.15+phase*1.3))*radius

func reanchor(identity: int, point: Vector2) -> void:
	homes[identity] = point-drift(identity)
	world.targets[identity].set_simulation_position(point, true)

func _physics_process(delta: float) -> void:
	previous_elapsed = elapsed
	elapsed += delta
	if previous_elapsed < INTRO_END and elapsed >= INTRO_END:
		intro_ended.emit()
	if previous_elapsed < PROTON_START and elapsed >= PROTON_START:
		first_protons.emit()
	for target in world.targets:
		var identity: int = target.identity
		target.reaction_flash = maxf(0, target.reaction_flash-delta)
		if blocked.has(identity):
			continue
		if elapsed >= birth_times[identity]:
			target.set_simulation_position(homes[identity]+drift(identity))
			target.previous_rotation = target.motion_rotation
			target.motion_rotation = sin(elapsed*0.35+identity)*0.25 if target.kind == 2 else 0.0
		if target.kind == 2 and masks[identity] == 3 and pair_progress[identity] < 1 and elapsed >= MOLECULE_START and world.player.form >= 1:
			pair_progress[identity] = minf(1, pair_progress[identity]+delta/1.8)
			target.set_pair_progress(pair_progress[identity])
			if pair_progress[identity] >= 1:
				target.configure_reaction(2, 3)
				target.reaction_flash = 0.15 if reduced_effects else 0.4
		refresh_target(target)
	advance_electrons(delta)
	if elapsed <= INTRO_END or previous_elapsed <= INTRO_END:
		queue_redraw()

func refresh_target(target: Area2D) -> void:
	var identity: int = target.identity
	var visible_matter: bool = elapsed >= birth_times[identity] and not blocked.has(identity)
	target.visible = visible_matter
	var mature: bool = target.kind == 0 or (target.kind == 1 and masks[identity] == 1) or (target.kind == 2 and pair_progress[identity] >= 1)
	target.available = visible_matter and mature and elapsed >= birth_times[identity]+0.65
	if is_instance_valid(target.body):
		target.body.modulate.a = clampf((elapsed-birth_times[identity])/0.8, 0, 1)

func refresh_visibility() -> void:
	for target in world.targets:
		refresh_target(target)

func advance_electrons(delta: float) -> void:
	for index in range(ELECTRON_COUNT):
		electron_previous[index] = electron_position[index]
		var start_time := DARK_END if index < BURST_COUNT else INTRO_END
		if elapsed < start_time or electron_state[index] == 2:
			continue
		electron_state[index] = 1
		var assigned := electron_target[index]
		var reacting := assigned >= 0 and elapsed >= ATOM_START and elapsed >= birth_times[assigned]+0.5 and not blocked.has(assigned)
		if reacting:
			var target: Area2D = world.targets[assigned]
			var offset: Vector2 = target.component_position(electron_component[index])-electron_position[index]
			if offset.length_squared() < 144:
				electron_state[index] = 2
				masks[assigned] |= 1 << electron_component[index]
				target.configure_reaction(1, masks[assigned])
				target.reaction_flash = 0.12 if reduced_effects else 0.3
				refresh_target(target)
				continue
			var speed := minf(260, 65+offset.length()*0.8)
			electron_velocity[index] = electron_velocity[index].move_toward(offset.normalized()*speed, delta*500)
		elif elapsed >= INTRO_END:
			var angle := float(index)*2.399963+elapsed*0.035
			var desired := Vector2.from_angle(angle)*(35.0+float(index%7)*5.0)
			electron_velocity[index] = electron_velocity[index].move_toward(desired, delta*45)
		electron_position[index] += electron_velocity[index]*delta
		if not reacting:
			var point := electron_position[index]
			var reflected_velocity := electron_velocity[index]
			if point.x < WORLD_MIN.x or point.x > WORLD_MAX.x:
				reflected_velocity.x *= -1
			if point.y < WORLD_MIN.y or point.y > WORLD_MAX.y:
				reflected_velocity.y *= -1
			electron_velocity[index] = reflected_velocity
			electron_position[index] = point.clamp(WORLD_MIN, WORLD_MAX)

func _process(_delta: float) -> void:
	update_presentation()

func update_presentation() -> void:
	var fraction := Engine.get_physics_interpolation_fraction()
	for index in range(ELECTRON_COUNT):
		var active := electron_state[index] == 1
		var point := electron_previous[index].lerp(electron_position[index], fraction)
		var velocity := electron_velocity[index]
		var stretch := 1.0+minf(velocity.length()/220.0, 1.5)
		var transform := Transform2D(velocity.angle(), point)
		transform.x *= stretch if active else 0.0
		transform.y *= 1.0 if active else 0.0
		multimesh.set_instance_transform_2d(index, transform)
		var alpha := 0.55+float(index%5)*0.08
		multimesh.set_instance_color(index, Color(0.45, 0.8, 1, alpha if active else 0.0))
	for target in world.targets:
		if target.visible:
			target.update_presentation(fraction)

func restore_legacy() -> void:
	var previous_locations: Array[Vector2] = []
	for target in world.targets:
		previous_locations.append(target.position)
	reset()
	elapsed = 40
	previous_elapsed = elapsed
	for target in world.targets:
		var identity: int = target.identity
		homes[identity] = previous_locations[identity]-drift(identity)
		target.set_simulation_position(previous_locations[identity], true)
		target.motion_rotation = sin(elapsed*0.35+identity)*0.25 if target.kind == 2 else 0.0
		target.previous_rotation = target.motion_rotation
		masks[identity] = 3 if target.kind == 2 else (1 if target.kind == 1 else 0)
		pair_progress[identity] = 1 if target.kind == 2 else 0
		target.configure_reaction(target.kind, masks[identity])
		target.set_pair_progress(pair_progress[identity])
	for index in range(ELECTRON_COUNT):
		electron_state[index] = 2 if electron_target[index] >= 0 else 1
		electron_previous[index] = electron_position[index]
	refresh_visibility()
	update_presentation()
	queue_redraw()

func serialize() -> Dictionary:
	var matter: Array = []
	for index in range(homes.size()):
		matter.append([homes[index].x, homes[index].y, masks[index], pair_progress[index]])
	var electrons: Array = []
	for index in range(ELECTRON_COUNT):
		electrons.append([electron_position[index].x, electron_position[index].y, electron_velocity[index].x, electron_velocity[index].y, electron_state[index]])
	return {"elapsed":elapsed, "center":[center.x, center.y], "matter":matter, "electrons":electrons}

func restore(data: Dictionary) -> void:
	reset()
	elapsed = maxf(0, float(data.get("elapsed", 0)))
	previous_elapsed = elapsed
	var origin: Array = data.get("center", [center.x, center.y])
	center = Vector2(float(origin[0]), float(origin[1]))
	var matter: Array = data.get("matter", [])
	for index in range(mini(matter.size(), homes.size())):
		var entry: Array = matter[index]
		homes[index] = Vector2(float(entry[0]), float(entry[1]))
		masks[index] = int(entry[2])
		pair_progress[index] = clampf(float(entry[3]), 0, 1)
	var electrons: Array = data.get("electrons", [])
	for index in range(mini(electrons.size(), ELECTRON_COUNT)):
		var entry: Array = electrons[index]
		electron_position[index] = Vector2(float(entry[0]), float(entry[1]))
		electron_previous[index] = electron_position[index]
		electron_velocity[index] = Vector2(float(entry[2]), float(entry[3]))
		electron_state[index] = clampi(int(entry[4]), 0, 2)
	for target in world.targets:
		var identity: int = target.identity
		var stage := 2 if target.kind == 2 and pair_progress[identity] >= 1 else (1 if masks[identity] > 0 else 0)
		target.configure_reaction(stage, masks[identity])
		target.set_pair_progress(pair_progress[identity])
		target.set_simulation_position(homes[identity]+drift(identity) if elapsed >= birth_times[identity] else homes[identity], true)
		target.motion_rotation = sin(elapsed*0.35+identity)*0.25 if target.kind == 2 else 0.0
		target.previous_rotation = target.motion_rotation
	refresh_visibility()
	update_presentation()
	queue_redraw()

func _draw() -> void:
	if elapsed <= DARK_END or elapsed >= INTRO_END:
		return
	var progress := (elapsed-DARK_END)/(INTRO_END-DARK_END)
	var strength := 0.35 if reduced_effects else 1.0
	var fade := sin(progress*PI)
	for index in range(5, 0, -1):
		draw_circle(center, 7+index*8+progress*38, Color(0.65, 0.86, 1, fade*0.035*strength))
	draw_circle(center, maxf(2, 9*(1-progress)), Color(0.9, 0.97, 1, fade*strength))
	draw_arc(center, progress*680, 0, TAU, 96, Color(0.6, 0.85, 1, (1-progress)*0.22*strength), 2.0, true)
