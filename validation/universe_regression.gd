extends SceneTree

const Universe = preload("res://scripts/universe.gd")
const GameScene = preload("res://scenes/main.tscn")
var game: Node2D
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func open_game() -> Node2D:
	var scene = GameScene.instantiate()
	scene.save_path = "user://universe_validation.json"
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	scene.player.set_process(false)
	scene.player.set_physics_process(false)
	scene.universe.set_process(false)
	scene.universe.set_physics_process(false)
	scene.crystal.set_process(false)
	scene.volume = 0
	return scene

func advance(seconds: float) -> void:
	for step in range(int(ceil(seconds*60))):
		game.universe._physics_process(1.0/60.0)
		game._process(1.0/60.0)

func visible_targets() -> int:
	var count := 0
	for target in game.targets:
		if target.visible:
			count += 1
	return count

func available(kind: int) -> int:
	var count := 0
	for target in game.targets:
		if target.kind == kind and target.visible and target.available:
			count += 1
	return count

func run() -> void:
	game = open_game()
	game.new_game()
	check(game.player.intro_locked and not game.player.visual.visible, "Opening must hide and lock the controlled electron")
	check(visible_targets() == 0 and game.universe.electron_state.count(1) == 0, "The first frame must contain no matter")
	for item in game.hud_content:
		check(not item.visible, "The opening must begin without HUD")
	check(not game.crystal.visible, "The cold region must stay hidden during the beginning")
	check(ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color") == Color.BLACK, "The background clear color must remain black")
	advance(0.5)
	check(visible_targets() == 0 and game.universe.electron_state.count(1) == 0, "The initial dark interval must remain empty")
	advance(0.7)
	check(game.universe.electron_state.count(1) == Universe.BURST_COUNT and visible_targets() == 0, "The burst must release many electrons before any proton")
	game.save_enabled = true
	game.save_game()
	var intro_time: float = game.universe.elapsed
	game.save_enabled = false
	game.new_game()
	game.queue_free()
	await process_frame
	game = open_game()
	check(game.player.intro_locked and is_equal_approx(game.universe.elapsed, intro_time), "Reopening must resume the Big Bang at its saved time")
	advance(1.8)
	check(not game.player.intro_locked and game.player.form == 0 and game.player.visual.visible, "Control must transfer to exactly one electron after the opening")
	check(visible_targets() == 0, "Protons must remain absent for the first seconds of control")
	var moving_electron: Vector2 = game.universe.electron_position[10]
	advance(0.5)
	check(game.universe.electron_position[10].distance_to(moving_electron) > 1, "Ambient electrons must keep moving while the player stays still")
	advance(2.5)
	check(visible_targets() == 0, "Proton birth must occur after the electron-only interval")
	advance(1.5)
	check(game.targets[0].visible and game.targets[0].available, "The first proton must appear and become a valid capture target")
	var moving_proton: Vector2 = game.targets[0].position
	advance(0.5)
	check(game.targets[0].position.distance_to(moving_proton) > 0.1, "Protons must move rather than remain fixed")
	var state: Dictionary = game.universe.serialize()
	game.save_enabled = true
	game.save_game()
	game.universe.reset()
	game.load_game()
	check(is_equal_approx(game.universe.elapsed, state.elapsed), "Save must restore the environmental clock")
	check(game.universe.electron_position[10].distance_to(Vector2(state.electrons[10][0], state.electrons[10][1])) < 0.01, "Save must restore moving electron positions")
	game.player.position = game.targets[0].position-Vector2(80, 0)
	game.player.reset_motion()
	for tick in range(4):
		await physics_frame
	game.player.select_target()
	game.interact()
	advance(1.6)
	check(game.player.form == 1, "The player must form H through the normal capture after the opening")
	advance(4.0)
	var partner: Area2D = null
	for target in game.targets:
		if target.kind == 1 and target.available:
			partner = target
			break
	check(is_instance_valid(partner), "Environmental formation must supply a hydrogen partner")
	game.player.position = partner.position-Vector2(80, 0)
	game.player.reset_motion()
	for tick in range(4):
		await physics_frame
	game.player.select_target()
	game.interact()
	advance(1.6)
	check(game.player.form == 2, "The player must form H2 alongside automatic environmental reactions")
	advance(6.0)
	check(available(1) >= 6, "Ambient captures must produce hydrogen atoms")
	check(available(2) >= 9, "Ambient atoms must combine into complete H2 molecules")
	check(game.universe.electron_state.count(2) >= 12, "Bound electrons must be incorporated into generated matter")
	for index in range(1, 3):
		check(game.targets[index].available, "Early capture protons must remain available for a late player")
	var source := -1
	for target in game.targets:
		if target.kind == 2 and target.available:
			source = target.identity
			break
	check(source >= 0, "Generated H2 must remain available to collect")
	game.player.set_form(2)
	game.carried.append(source)
	game.sync_orbit_visuals()
	game.sync_evolution()
	advance(0.5)
	check(not game.targets[source].visible and not game.targets[source].available, "The world simulation must never respawn collected H2")
	game.save_game()
	game.carried.clear()
	game.load_game()
	check(source in game.carried and not game.targets[source].visible, "Save must preserve the collected reservoir during environmental evolution")
	game.release_carried_molecules()
	game.sync_evolution()
	var released: Vector2 = game.targets[source].position
	advance(0.5)
	check(game.targets[source].visible and game.targets[source].position.distance_to(released) < 10, "Released H2 must drift near its new location rather than jump to its old spawn")
	game.universe.set_physics_process(true)
	game.toggle_pause()
	var paused_time: float = game.universe.elapsed
	await create_timer(0.05, true).timeout
	check(is_equal_approx(paused_time, game.universe.elapsed), "Pause must freeze cosmic evolution")
	game.toggle_pause()
	game.universe.set_physics_process(false)
	print("PASS empty black beginning, electron burst, delayed protons and automatic atom/H2 formation")
	print("PASS moving matter, opening/world save restoration, reserved sources and paused evolution")
	print("COUNTS atoms=", available(1), " H2=", available(2), " bound_electrons=", game.universe.electron_state.count(2))
	print("UNIVERSE_REGRESSION_OK" if failures.is_empty() else "UNIVERSE_REGRESSION_FAILED count=%d" % failures.size())
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
