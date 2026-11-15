extends SceneTree

func _initialize() -> void:
	root.hide()
	render_preview.call_deferred()

func render_preview() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 640)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(640, 640)
	background.color = Color("060c13")
	viewport.add_child(background)
	var material := preload("res://resources/proton_material.tres")
	for sample in [[Vector2(320, 260), 190.0], [Vector2(220, 550), 15.0], [Vector2(320, 550), 22.0], [Vector2(420, 550), 31.0]]:
		var sprite := Sprite2D.new()
		sprite.texture = preload("res://resources/white.tres")
		sprite.material = material
		sprite.position = sample[0]
		sprite.scale = Vector2.ONE * sample[1]
		viewport.add_child(sprite)
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image().save_png("res://validation/proton_preview.png")
	print("PROTON_PREVIEW_OK" if result == OK else "PROTON_PREVIEW_FAILED")
	quit(0 if result == OK else 1)
