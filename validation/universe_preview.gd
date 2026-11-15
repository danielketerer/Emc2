extends SceneTree

func _initialize() -> void:
	root.hide()
	run.call_deferred()

func run() -> void:
	var stage := "electrons"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--preview="):
			stage = argument.get_slice("=", 1)
	var seconds: float = {"empty":0.3, "bang":1.2, "electrons":3.8, "protons":7.8, "atoms":12.5, "molecules":19.0}.get(stage, 3.8)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://universe_preview_unused.json"
	game.save_enabled = false
	viewport.add_child(game)
	game.set_process(false)
	game.player.set_process(false)
	game.player.set_physics_process(false)
	game.universe.set_process(false)
	game.universe.set_physics_process(false)
	game.crystal.set_process(false)
	game.volume = 0
	game.new_game()
	if stage in ["atoms", "molecules"]:
		game.player.set_form(1 if stage == "atoms" else 2)
	for step in range(int(ceil(seconds*60))):
		game.universe._physics_process(1.0/60.0)
		game._process(1.0/60.0)
	game.player.reset_motion()
	game.camera.position = game.player.position
	game.camera.force_update_scroll()
	game.universe.update_presentation()
	game.message_time = 0
	game.message.modulate.a = 0
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if stage == "empty":
		var bytes := image.get_data()
		var channels := 4 if image.get_format() == Image.FORMAT_RGBA8 else 3
		for offset in range(0, bytes.size(), channels):
			if bytes[offset] != 0 or bytes[offset+1] != 0 or bytes[offset+2] != 0:
				push_error("Initial frame must be entirely black")
				quit(1)
				return
	var result := image.save_png("res://validation/universe_%s.png" % stage)
	print("UNIVERSE_PREVIEW_OK ", stage, " size=", image.get_size())
	game.queue_free()
	await process_frame
	quit(0 if result == OK else 1)
