extends SceneTree

const Crystal = preload("res://scripts/crystal.gd")

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://matter_headless_validation.json"
	game.save_enabled = false
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.universe.set_process(false)
	game.universe.set_physics_process(false)
	game.volume = 0
	game.crystal.set_process(false)
	game.new_game()
	game.universe.restore_legacy()
	game.sync_evolution()
	var proton_material = load("res://resources/proton_material.tres")
	check(game.targets[0].body.material == proton_material, "Free protons must use the shared parton-cloud material")
	var player = game.player
	player.set_process(false)
	player.set_physics_process(false)
	player.position = Vector2(-4000, -3500)
	player.reset_motion()
	var center: Vector2 = player.get_viewport_rect().size * 0.5
	player.update_steering(center + Vector2(270, 0))
	for frame in range(120):
		player._physics_process(1.0/60.0)
	check(player.velocity.x > 350, "Electron must reach its increased speed")
	game.camera.position += Vector2(800, -600)
	player.update_steering(center + Vector2(270, 0))
	check(player.steering.x > 0.99 and absf(player.steering.y) < 0.001, "Camera movement must not affect steering")
	player.update_steering(center)
	for frame in range(60):
		player._physics_process(1.0/60.0)
	var stopped: Vector2 = player.position
	for frame in range(60):
		player._physics_process(1.0/60.0)
	check(player.position == stopped and player.velocity == Vector2.ZERO, "Particle must stop without drift")
	print("PASS screen-relative steering, increased speed and stable stop")
	player.position = game.targets[0].position - Vector2(80, 0)
	player.reset_motion()
	await process_frame
	for tick in range(4):
		await physics_frame
	player.select_target()
	if not is_instance_valid(player.target):
		quit(1)
		return
	game.interact()
	game._process(1.6)
	check(player.form == 1, "First bond must form hydrogen")
	player.position = game.targets[3].position - Vector2(80, 0)
	player.reset_motion()
	await process_frame
	for tick in range(4):
		await physics_frame
	player.select_target()
	game.interact()
	game._process(1.6)
	check(player.form == 2, "Second bond must form H2")
	check(player.visual.surfaces[0].material == proton_material and player.visual.surfaces[1].material == proton_material, "Both H2 nuclei must use the same proton material")
	print("PASS electron -> H -> H2 and shared proton material")
	for group in range(2):
		await collect_nearest(game)
	check(game.carried.size() >= 6, "Successive collections must retain several H2 groups")
	check(game.orbit_visuals.size() == game.carried.size(), "All collected H2 must have an orbit visual")
	var donor = game.targets[game.carried[0]]
	check(donor.body.get_script() == player.visual.get_script(), "Free H2 and player must share the same visual")
	var first_identity: int = game.carried[0]
	var before: Vector2 = game.orbit_visuals[first_identity].position
	game.clock += 1
	game.update_orbits(1)
	check(before.distance_to(game.orbit_visuals[first_identity].position) > 10, "Collected H2 must orbit")
	var expected_orbit: Array = game.carried.duplicate()
	game.save_enabled = true
	game.save_game()
	var original := FileAccess.get_file_as_string(game.save_path)
	game.carried.clear()
	game.load_game()
	check(game.carried == expected_orbit, "Save must restore the entire orbit")
	var legacy = JSON.parse_string(original)
	legacy.carried = first_identity
	var file := FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	game.load_game()
	check(game.carried.size() == 1 and game.carried[0] == first_identity, "Legacy scalar carried identity must migrate")
	file = FileAccess.open(game.save_path, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	game.load_game()
	print("PASS group collection, orbits, shared H2 visual, save reload and legacy migration")
	var released: Array = game.carried.duplicate()
	var seed: Vector2 = game.crystal.to_global(Crystal.SEED_OFFSETS[1])
	player.position = seed + Vector2(0, -100)
	player.reset_motion()
	game.crystal.update_selection(seed, player.position, 2)
	game.interact()
	check(player.embedded and game.carried.is_empty(), "Nucleation must transfer control and release the orbiting molecules")
	for identity in released:
		check(game.targets[identity].visible, "Every previously collected H2 must remain available at the cold surface")
	game.crystal._process(2.0)
	check(game.crystal.control == Crystal.Phase.EDGE and game.crystal.occupied.size() == 4, "Nucleus must contain the player H2 and the three prior deposits")
	for step in range(6):
		var cell := Vector2i(0, -step-1)
		game.crystal.update_selection(game.crystal.cell_world(cell), player.position, 2)
		game.interact()
		check(not game.crystal.pending.is_empty(), "An edge click must guide a nearby molecule")
		game.crystal._process(2.0)
	check(game.crystal.occupied.size() == 10, "The lattice must retain one complete H2 per chosen position")
	game.save_game()
	game.crystal.reset()
	game.load_game()
	check(player.embedded and game.crystal.occupied.size() == 10, "Reload must restore the lattice and edge control")
	print("PASS player incorporation, preserved orbit reservoir, guided growth and edge-control reload")
	print("HEADLESS_VALIDATION_OK" if failures.is_empty() else "HEADLESS_VALIDATION_FAILED")
	game.sound.stop()
	game.sound.stream = null
	await create_timer(0.15).timeout
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func collect_nearest(game: Node2D) -> void:
	var donor: Area2D = null
	var best := INF
	for target in game.targets:
		if target.kind == 2 and target.visible:
			var distance: float = game.player.position.distance_to(target.position)
			if distance < best:
				best = distance
				donor = target
	check(is_instance_valid(donor), "A persistent H2 donor must remain available")
	game.player.position = donor.position - Vector2(80, 0)
	game.player.reset_motion()
	await process_frame
	for tick in range(4):
		await physics_frame
	game.player.select_target()
	game.interact()
