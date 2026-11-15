extends SceneTree

const GameScene = preload("res://scenes/main.tscn")
const Crystal = preload("res://scripts/crystal.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func open_game(path: String) -> Node2D:
	var game = GameScene.instantiate()
	game.save_path = path
	game.save_enabled = false
	root.add_child(game)
	game.set_process(false)
	game.universe.set_process(false)
	game.universe.set_physics_process(false)
	game.player.set_process(false)
	game.player.set_physics_process(false)
	game.crystal.set_process(false)
	game.volume = 0
	return game

func close_game(game: Node2D) -> void:
	game.sound.stop()
	game.sound.stream = null
	game.queue_free()
	await process_frame

func reopen(game: Node2D, path: String) -> Node2D:
	await close_game(game)
	return open_game(path)

func verify_frontier(crystal: Node2D) -> void:
	for cell: Vector2i in crystal.frontier:
		check(not crystal.occupied.has(cell), "Frontier must contain only free positions")
		var touches := false
		for direction in Crystal.DIRECTIONS:
			if crystal.occupied.has(cell + direction):
				touches = true
		check(touches, "Every available position must touch the lattice")
	for cell: Vector2i in crystal.occupied:
		check(crystal.world_cell(crystal.cell_world(cell)) == cell, "Triangular coordinate conversion must round-trip")

func wide_cell(index: int) -> Vector2i:
	var reach := index / 4 + 1
	return [Vector2i(reach, 0), Vector2i(-reach-1, 0), Vector2i(reach, 1), Vector2i(-reach-1, 1)][index % 4]

func run_route(route: String, seed_index: int) -> void:
	var path := "user://crystal_%s_%d_validation.json" % [route, seed_index]
	var game := open_game(path)
	game.new_game()
	game.universe.restore_legacy()
	game.sync_evolution()
	game.player.set_form(2)
	var seed: Vector2 = game.crystal.to_global(Crystal.SEED_OFFSETS[seed_index])
	game.player.position = seed + Vector2(0, -130)
	game.player.reset_motion()
	game.crystal.update_selection(seed, game.player.position, 2)
	game.interact()
	check(game.player.embedded and game.crystal.control == Crystal.Phase.NUCLEATING, "The player's H2 must enter the nucleus animation")
	check(game.crystal.occupied.size() == 3, "Deposited molecules must precede incorporation")
	game.crystal._process(0.3)
	game.save_enabled = true
	game.save_game()
	game = await reopen(game, path)
	check(game.player.embedded and not game.crystal.pending.is_empty(), "Nucleation animation must resume after reopening")
	game.crystal._process(2.0)
	check(game.crystal.control == Crystal.Phase.EDGE and game.crystal.occupied.get(Vector2i.ZERO) == -2, "The player's whole H2 must become the nucleus and transfer control")
	verify_frontier(game.crystal)
	var midpoint := 14
	for index in range(Crystal.TARGET_SIZE - 4):
		var cell := wide_cell(index) if route == "wide" else Vector2i(0, -index-1)
		check(game.crystal.frontier.has(cell), "%s chosen cell must lie on the border %s" % [route, cell])
		game.crystal.update_selection(game.crystal.cell_world(cell), game.player.position, 2)
		var before: int = game.crystal.occupied.size()
		game.interact()
		if game.crystal.pending.is_empty():
			check(false, "%s seed %d cannot reach H2 at %s after %d molecules" % [route, seed_index, cell, before])
			await close_game(game)
			return
		var source: int = game.crystal.pending.source
		check(not game.targets[source].visible, "An incoming molecule must be reserved")
		game.interact()
		check(game.crystal.occupied.size() == before, "Repeated clicks during animation must not duplicate a placement")
		if index == 6:
			game.crystal._process(0.25)
			var elapsed: float = game.crystal.pending.elapsed
			game.crystal.set_process(true)
			game.toggle_pause()
			await create_timer(0.05, true).timeout
			check(is_equal_approx(game.crystal.pending.elapsed, elapsed), "Pause must freeze an incoming molecule")
			game.toggle_pause()
			game.crystal.set_process(false)
			game.save_enabled = true
			game.save_game()
			game = await reopen(game, path)
			check(not game.crystal.pending.is_empty() and int(game.crystal.pending.source) == source, "Growth animation must retain the same whole molecule after reopening")
			check(is_equal_approx(game.crystal.pending.elapsed, elapsed) and not game.targets[source].visible, "Growth progress and donor reservation must resume")
		game.crystal._process(2.0)
		check(game.crystal.occupied.size() == before+1 and game.crystal.occupied[cell] == source, "Each placement must consume exactly one whole H2")
		verify_frontier(game.crystal)
		if index == midpoint-1:
			var structure: Dictionary = game.crystal.occupied.duplicate()
			var edge: Dictionary = game.crystal.frontier.duplicate()
			game.crystal._process(10.0)
			check(game.crystal.occupied == structure, "Observation time must never trigger automatic growth")
			game.save_enabled = true
			game.save_game()
			game = await reopen(game, path)
			check(game.player.embedded and game.crystal.control == Crystal.Phase.EDGE, "Reload must restore border control")
			check(game.crystal.occupied == structure and game.crystal.frontier == edge, "Mid-route structure and all available positions must survive reopening")
			game.toggle_pause()
			await create_timer(0.05, true).timeout
			check(game.crystal.occupied == structure, "Paused structure must remain assembled")
			game.toggle_pause()
	check(game.crystal.milestone and game.crystal.occupied.size() == Crystal.TARGET_SIZE, "Both routes must reach the first target size")
	if route == "wide":
		check(game.crystal.bounds.size.x > game.crystal.bounds.size.y*3, "Wide choices must create a broad silhouette")
	else:
		check(game.crystal.bounds.size.y > game.crystal.bounds.size.x*1.4, "Narrow choices must create an advancing tip")
	game.crystal._process(5.0)
	check(game.crystal.neighbors[0].cells.size() == 7 and game.crystal.neighbors[2].cells.size() == 7, "Other crystals must grow after the milestone")
	var continued := false
	for cell: Vector2i in game.crystal.frontier:
		if game.crystal.request_growth(cell):
			game.crystal._process(2.0)
			continued = true
			break
	check(continued and game.crystal.occupied.size() == Crystal.TARGET_SIZE+1, "Expansion must continue beyond the milestone")
	game.save_enabled = true
	game.save_game()
	print("PASS ", route, " seed=", seed_index, " cells=", game.crystal.occupied.size(), " silhouette=", game.crystal.bounds.size, " zoom=", game.crystal.desired_zoom(Vector2(1440, 900)))
	await close_game(game)

func run_legacy() -> void:
	var path := "user://crystal_legacy_validation.json"
	var game := open_game(path)
	var legacy := {"version":1, "form":2, "position":[2700, -1500], "filled":[0,1,4,5], "consumed":[0,3,39,40,41,42], "carried":43}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	game.load_game()
	check(game.player.embedded and game.crystal.occupied.size() == 4, "Legacy fixed-grid progress must become an editable lattice")
	check(game.targets[43].visible and game.carried.is_empty(), "A legacy carried H2 must remain available near the crystal")
	verify_frontier(game.crystal)
	game.save_enabled = true
	game.save_game()
	game = await reopen(game, path)
	check(game.crystal.occupied.size() == 4 and game.player.embedded, "Migrated progress must reopen in edge control")
	print("PASS legacy lattice migration")
	await close_game(game)

func run() -> void:
	for route in ["wide", "narrow"]:
		for seed_index in range(Crystal.SEED_OFFSETS.size()):
			await run_route(route, seed_index)
	await run_legacy()
	await create_timer(0.2).timeout
	print("CRYSTAL_ROUTES_OK" if failures.is_empty() else "CRYSTAL_ROUTES_FAILED count=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
