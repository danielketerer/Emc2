extends SceneTree

const Crystal = preload("res://scripts/crystal.gd")

func _initialize() -> void:
	root.hide()
	run.call_deferred()

func run() -> void:
	var cases := ["seed", "incorporation", "wide", "narrow"]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--preview="):
			cases = [argument.get_slice("=", 1)]
	for route in cases:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1440, 900)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var game = load("res://scenes/main.tscn").instantiate()
		game.save_path = "user://crystal_%s_1_validation.json" % route
		game.save_enabled = false
		viewport.add_child(game)
		game.set_process(false)
		game.universe.set_process(false)
		game.universe.set_physics_process(false)
		game.player.set_process(false)
		game.player.set_physics_process(false)
		game.crystal.set_process(false)
		game.volume = 0
		game.message_time = 0
		if route in ["seed", "incorporation"]:
			game.new_game()
			game.universe.restore_legacy()
			game.sync_evolution()
			game.player.set_form(2)
			var seed: Vector2 = game.crystal.to_global(Crystal.SEED_OFFSETS[1])
			game.player.position = seed + Vector2(-120, -100)
			game.player.reset_motion()
			game.camera.position = game.player.render_position
			game.camera.zoom = Vector2.ONE * 0.72
			game.camera.force_update_scroll()
			game._process(0.01)
			game.crystal.update_selection(seed, game.player.position, 2)
			if route == "incorporation":
				game.interact()
				game.crystal._process(0.4)
				game._process(0.2)
			game.update_ui()
		else:
			game.crystal._process(5)
			game.camera.position = game.crystal.focus_position()
			game.camera.zoom = Vector2.ONE * game.crystal.desired_zoom(Vector2(1440, 900))
			game.camera.force_update_scroll()
			game._process(0.01)
		game.universe.update_presentation()
		game.message.modulate.a = 0
		for frame in range(6):
			await process_frame
		await RenderingServer.frame_post_draw
		var result := viewport.get_texture().get_image().save_png("res://validation/crystal_%s.png" % route)
		if result != OK:
			push_error("Crystal preview failed")
			quit(1)
			return
		print("CRYSTAL_PREVIEW_OK ", route)
		game.sound.stop()
		game.sound.stream = null
		viewport.queue_free()
		await process_frame
	quit()
