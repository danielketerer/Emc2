extends Node2D

signal incorporated(source_identity: int)
signal milestone_reached

enum Phase { MOLECULE, NUCLEATING, EDGE }
const Surface = preload("res://scripts/crystal_surface.gd")
const MoleculeVisual = preload("res://scripts/matter_visual.gd")
const SPACING: float = 86.0
const CAPTURE_RADIUS: float = 400.0
const TARGET_SIZE: int = 32
const SEED_OFFSETS = [Vector2(-440, -100), Vector2(0, -160), Vector2(440, -100)]
const DIRECTIONS = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
const DEPOSITS = [Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
var targets: Array[Area2D] = []
var control: Phase = Phase.MOLECULE
var origin := Vector2.ZERO
var occupied: Dictionary = {}
var frontier: Dictionary = {}
var pending: Dictionary = {}
var milestone: bool = false
var selected_seed: int = -1
var selected_cell := Vector2i.ZERO
var has_selection: bool = false
var selected_source: int = -1
var bounds := Rect2()
var surface: Node2D
var seed_patches: Array[Node2D] = []
var neighbors: Array[Node2D] = []
var neighbor_stages: Array[int] = []
var neighbor_age: float = 0.0
var moving_molecule: Node2D
var selection_line: Line2D
var guide_line: Line2D
var pulse_line: Line2D
var pulse_time: float = 0.0
var effect_strength: float = 1.0
var marker_radius: float = 4.0
var marker_width: float = 1.5

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var shelf := Polygon2D.new()
	shelf.polygon = PackedVector2Array([Vector2(-3200, 470), Vector2(-2400, 160), Vector2(-1200, 20), Vector2(1200, 20), Vector2(2500, 170), Vector2(3200, 500), Vector2(3200, 1000), Vector2(-3200, 1000)])
	shelf.color = Color.BLACK
	shelf.z_index = -1
	add_child(shelf)
	var surface_edge := Line2D.new()
	surface_edge.points = PackedVector2Array([Vector2(-3200,470), Vector2(-2400,160), Vector2(-1200,20), Vector2(1200,20), Vector2(2500,170), Vector2(3200,500)])
	surface_edge.default_color = Color(0.13,0.28,0.34,0.5)
	surface_edge.width = 1.5
	surface_edge.z_index = -1
	add_child(surface_edge)
	surface = make_surface(Vector2.ZERO)
	for offset in SEED_OFFSETS:
		var patch := make_surface(offset)
		patch.show_facets = false
		seed_patches.append(patch)
	var neighbor_offsets := [Vector2(-1100, -500), Vector2(1150, -700), Vector2(700, -1300)]
	for offset in neighbor_offsets:
		var neighbor := make_surface(offset)
		neighbor.hide()
		neighbors.append(neighbor)
		neighbor_stages.append(-1)
	selection_line = make_line(2.0, Color("bbecff"))
	guide_line = make_line(1.0, Color(0.6, 0.9, 1, 0.4))
	pulse_line = make_line(2.0, Color("d8faff"))
	pulse_line.hide()
	reset()

func make_surface(offset: Vector2) -> Node2D:
	var mesh := Node2D.new()
	mesh.set_script(Surface)
	mesh.position = offset
	mesh.spacing = SPACING
	add_child(mesh)
	return mesh

func make_line(width: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.antialiased = true
	add_child(line)
	return line

func reset() -> void:
	if is_instance_valid(moving_molecule):
		moving_molecule.queue_free()
	moving_molecule = null
	control = Phase.MOLECULE
	origin = Vector2.ZERO
	occupied.clear()
	frontier.clear()
	pending.clear()
	milestone = false
	neighbor_age = 0
	pulse_time = 0
	clear_selection()
	var deposits: Dictionary = {}
	for cell in DEPOSITS:
		deposits[cell] = -3
	for patch in seed_patches:
		patch.show()
		patch.set_cells(deposits)
	for index in range(neighbors.size()):
		neighbors[index].hide()
		neighbor_stages[index] = -1
	refresh_geometry()

func cell_position(cell: Vector2i) -> Vector2:
	return origin + Vector2(cell.x + cell.y * 0.5, cell.y * sqrt(3.0) * 0.5) * SPACING

func cell_world(cell: Vector2i) -> Vector2:
	return to_global(cell_position(cell))

func world_cell(point: Vector2) -> Vector2i:
	var local := (to_local(point) - origin) / SPACING
	var r := local.y / (sqrt(3.0) * 0.5)
	var q := local.x - r * 0.5
	var cube := Vector3(q, -q-r, r)
	var rounded := cube.round()
	var error := (rounded-cube).abs()
	if error.x > error.y and error.x > error.z:
		rounded.x = -rounded.y-rounded.z
	elif error.y > error.z:
		rounded.y = -rounded.x-rounded.z
	else:
		rounded.z = -rounded.x-rounded.y
	return Vector2i(int(rounded.x), int(rounded.z))

func seed_distance(point: Vector2) -> float:
	var result := INF
	for offset in SEED_OFFSETS:
		result = minf(result, point.distance_to(to_global(offset)))
	return result

func update_selection(mouse_world: Vector2, player_world: Vector2, form: int) -> void:
	if not pending.is_empty() or form != 2:
		clear_selection()
		return
	if control == Phase.MOLECULE:
		var seed := -1
		for index in range(SEED_OFFSETS.size()):
			var point := to_global(SEED_OFFSETS[index])
			if mouse_world.distance_to(point) < 65 and player_world.distance_to(point) < 280:
				seed = index
		if seed == selected_seed:
			return
		clear_selection()
		selected_seed = seed
		if seed >= 0:
			show_selection(SEED_OFFSETS[seed], true)
		return
	var cell := world_cell(mouse_world)
	if not frontier.has(cell):
		clear_selection()
		return
	if has_selection and cell == selected_cell:
		return
	clear_selection()
	selected_cell = cell
	has_selection = true
	selected_source = nearest_source(cell)
	show_selection(cell_position(cell), selected_source >= 0)
	if selected_source >= 0:
		targets[selected_source].selected = true
		guide_line.points = PackedVector2Array([to_local(targets[selected_source].position), cell_position(cell)])

func clear_selection() -> void:
	if selected_source >= 0 and selected_source < targets.size():
		targets[selected_source].selected = false
	selected_source = -1
	selected_seed = -1
	has_selection = false
	if is_instance_valid(selection_line):
		selection_line.clear_points()
		guide_line.clear_points()

func show_selection(point: Vector2, reachable: bool) -> void:
	var outline: PackedVector2Array = surface.hexagon(point)
	outline.append(outline[0])
	selection_line.points = outline
	selection_line.default_color = Color("c9f2ff") if reachable else Color("637c8a")

func begin_seed(start: Vector2, heading: float) -> bool:
	if control != Phase.MOLECULE or selected_seed < 0 or not pending.is_empty():
		return false
	var chosen := selected_seed
	if start.distance_to(to_global(SEED_OFFSETS[chosen])) > 280:
		return false
	origin = SEED_OFFSETS[chosen]
	for cell in DEPOSITS:
		occupied[cell] = -3
	seed_patches[chosen].hide()
	control = Phase.NUCLEATING
	start_arrival(Vector2i.ZERO, -2, start, heading, true)
	refresh_geometry()
	return true

func nearest_source(cell: Vector2i) -> int:
	var nearest := -1
	var distance_limit := CAPTURE_RADIUS * CAPTURE_RADIUS
	var destination := cell_world(cell)
	for target in targets:
		if target.kind != 2 or not target.visible or not target.available:
			continue
		var distance := destination.distance_squared_to(target.position)
		if distance < distance_limit:
			nearest = target.identity
			distance_limit = distance
	return nearest

func request_growth(cell: Vector2i) -> bool:
	if control != Phase.EDGE or not pending.is_empty() or not frontier.has(cell):
		return false
	var source := nearest_source(cell)
	if source < 0:
		return false
	var target := targets[source]
	start_arrival(cell, source, target.position, target.body.rotation, false)
	target.hide()
	return true

func start_arrival(cell: Vector2i, source: int, start: Vector2, heading: float, seed: bool) -> void:
	clear_selection()
	pending = {"cell":cell, "source":source, "start":start, "heading":heading, "elapsed":0.0, "duration":clampf(start.distance_to(cell_world(cell))/260.0, 0.8, 1.7), "seed":seed}
	create_moving_visual()

func create_moving_visual() -> void:
	if is_instance_valid(moving_molecule):
		moving_molecule.queue_free()
	moving_molecule = Node2D.new()
	moving_molecule.set_script(MoleculeVisual)
	moving_molecule.form = 2
	moving_molecule.position = to_local(pending.start)
	moving_molecule.rotation = pending.heading
	add_child(moving_molecule)

func _process(delta: float) -> void:
	if not pending.is_empty():
		pending.elapsed += delta
		var progress: float = clampf(pending.elapsed / pending.duration, 0, 1)
		var blend := smoothstep(0.0, 1.0, progress)
		var destination := cell_world(pending.cell)
		var position_world: Vector2 = (pending.start as Vector2).lerp(destination, blend)
		position_world += Vector2(0, -sin(progress*PI)*32)
		moving_molecule.position = to_local(position_world)
		moving_molecule.rotation = lerp_angle(pending.heading, 0.0, blend)
		if progress >= 1.0:
			finish_arrival()
	if pulse_time > 0:
		pulse_time = maxf(0, pulse_time-delta)
		pulse_line.modulate.a = pulse_time / 0.35 * effect_strength
		pulse_line.scale = Vector2.ONE * (1.0 + (1.0-pulse_time/0.35)*0.7)
		pulse_line.visible = pulse_time > 0
	if milestone:
		neighbor_age = minf(5, neighbor_age+delta)
		update_neighbors()

func finish_arrival() -> void:
	var cell: Vector2i = pending.cell
	var source: int = pending.source
	occupied[cell] = source
	control = Phase.EDGE
	pending.clear()
	moving_molecule.queue_free()
	moving_molecule = null
	refresh_geometry()
	pulse_time = 0.35
	pulse_line.position = cell_position(cell)
	var ring := PackedVector2Array()
	for index in range(33):
		ring.append(Vector2.from_angle(float(index)/32.0*TAU)*32)
	pulse_line.points = ring
	pulse_line.show()
	var reached := occupied.size() >= TARGET_SIZE and not milestone
	if reached:
		milestone = true
	incorporated.emit(source)
	if reached:
		milestone_reached.emit()

func refresh_geometry() -> void:
	frontier.clear()
	bounds = Rect2(origin, Vector2.ZERO)
	for cell: Vector2i in occupied:
		bounds = bounds.expand(cell_position(cell))
		for direction in DIRECTIONS:
			var adjacent: Vector2i = cell + direction
			if not occupied.has(adjacent):
				frontier[adjacent] = true
	surface.position = origin
	surface.set_cells(occupied)
	clear_selection()
	queue_redraw()

func focus_position() -> Vector2:
	if control == Phase.NUCLEATING and is_instance_valid(moving_molecule):
		return moving_molecule.global_position
	return to_global(bounds.get_center())

func desired_zoom(viewport_size: Vector2) -> float:
	var fit := minf(viewport_size.x/(bounds.size.x+1000), viewport_size.y/(bounds.size.y+750))
	var scale_cap := 0.64 / (1.0+maxi(0, occupied.size()-4)*0.012)
	if milestone:
		scale_cap = minf(scale_cap, 0.34)
	return minf(fit, scale_cap)

func set_view_scale(zoom: float) -> void:
	var radius := 3.5 / maxf(zoom, 0.12)
	if absf(radius-marker_radius) > 1.0:
		marker_radius = radius
		marker_width = 1.1 / maxf(zoom, 0.12)
		queue_redraw()
	selection_line.width = 1.7 / maxf(zoom, 0.12)
	guide_line.width = 1.0 / maxf(zoom, 0.12)
	surface.set_view_scale(zoom)
	for neighbor in neighbors:
		neighbor.set_view_scale(zoom)

func update_neighbors() -> void:
	var shape := [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
	for index in range(neighbors.size()):
		var age := neighbor_age - index*0.6
		var stage := clampi(int(age/0.38), 0, shape.size())
		if stage == neighbor_stages[index]:
			continue
		neighbor_stages[index] = stage
		var cells: Dictionary = {}
		for point in shape.slice(0, stage):
			cells[point] = -3
		neighbors[index].visible = stage > 0
		neighbors[index].set_cells(cells)

func reserved_sources() -> Array[int]:
	var result: Array[int] = []
	for identity in occupied.values():
		if int(identity) >= 0:
			result.append(int(identity))
	if not pending.is_empty() and int(pending.source) >= 0:
		result.append(int(pending.source))
	return result

func serialize() -> Dictionary:
	var cells: Array = []
	for cell: Vector2i in occupied:
		cells.append([cell.x, cell.y, occupied[cell]])
	var motion: Dictionary = {}
	if not pending.is_empty():
		motion = {"cell":[pending.cell.x, pending.cell.y], "source":pending.source, "start":[pending.start.x, pending.start.y], "heading":pending.heading, "elapsed":pending.elapsed, "duration":pending.duration, "seed":pending.seed}
	return {"control":int(control), "origin":[origin.x, origin.y], "cells":cells, "pending":motion, "milestone":milestone, "neighbor_age":neighbor_age}

func restore(data: Dictionary) -> void:
	reset()
	var saved_origin: Array = data.get("origin", [0, 0])
	origin = Vector2(float(saved_origin[0]), float(saved_origin[1]))
	for entry in data.get("cells", []):
		if entry is Array and entry.size() == 3:
			occupied[Vector2i(int(entry[0]), int(entry[1]))] = int(entry[2])
	control = Phase.EDGE if not occupied.is_empty() else Phase.MOLECULE
	var motion: Dictionary = data.get("pending", {})
	if not motion.is_empty():
		var source := int(motion.get("source", -2))
		if source == -2 or (source >= 0 and source < targets.size() and targets[source].kind == 2):
			var cell := Vector2i(int(motion.cell[0]), int(motion.cell[1]))
			pending = {"cell":cell, "source":source, "start":Vector2(float(motion.start[0]), float(motion.start[1])), "heading":float(motion.get("heading", 0)), "elapsed":float(motion.get("elapsed", 0)), "duration":maxf(0.1, float(motion.get("duration", 1))), "seed":bool(motion.get("seed", false))}
			pending.elapsed = clampf(pending.elapsed, 0, pending.duration-0.001)
			if pending.seed:
				control = Phase.NUCLEATING
			create_moving_visual()
	milestone = bool(data.get("milestone", false)) or occupied.size() >= TARGET_SIZE
	neighbor_age = clampf(float(data.get("neighbor_age", 0)), 0, 5)
	if control != Phase.MOLECULE:
		for index in range(SEED_OFFSETS.size()):
			seed_patches[index].visible = origin.distance_to(SEED_OFFSETS[index]) > 1
	refresh_geometry()
	if milestone:
		update_neighbors()

func restore_legacy(indices: Array, sources: Array[int]) -> void:
	reset()
	if indices.is_empty():
		return
	origin = Vector2(-129, -112)
	for index in range(indices.size()):
		var value := int(indices[index])
		if value < 0 or value >= 16:
			continue
		var row := value / 4
		var column := value % 4
		occupied[Vector2i(column-row/2, row)] = sources[index] if index < sources.size() else -3
	control = Phase.EDGE
	milestone = occupied.size() >= 16
	refresh_geometry()

func _draw() -> void:
	if control == Phase.MOLECULE:
		for offset in SEED_OFFSETS:
			draw_arc(offset, 31, 0, TAU, 32, Color(0.55, 0.83, 0.95, 0.3), 1.5, true)
	else:
		for cell: Vector2i in frontier:
			draw_arc(cell_position(cell), marker_radius, 0, TAU, 16, Color(0.48, 0.78, 0.91, 0.38), marker_width, true)
