extends Node2D

@export var visual_test: bool = false
const PlayerScript = preload("res://scripts/player.gd")
const TargetScript = preload("res://scripts/target.gd")
const BackgroundScript = preload("res://scripts/background.gd")
const CrystalScript = preload("res://scripts/crystal.gd")
const UniverseScript = preload("res://scripts/universe.gd")
var save_path: String = "user://matter_save.json"
const SETTINGS_PATH = "user://settings.cfg"
const COLD = Vector2(2700,-1500)
var player: Node2D
var camera: Camera2D
var targets: Array[Area2D] = []
var crystal: Node2D
var universe: Node2D
var hud_content: Array[CanvasItem] = []
var spawn_positions: Array[Vector2] = []
var consumed: Array[int] = []
var carried: Array[int] = []
var orbit_visuals: Dictionary = {}
var orbit_offsets: Dictionary = {}
var cold_seen: bool = false
var clock: float = 0.0
var pulse: float = 0.0
var pulse_position := Vector2.ZERO
var transform_time: float = 0.0
var auto_save_clock: float = 0.0
var pending_form: int = -1
var reduced_effects: bool = false
var volume: float = 0.55
var hud: CanvasLayer
var form_label: Label
var objective: Label
var action_label: Label
var location_label: Label
var message: Label
var message_time: float = 0.0
var pause_panel: PanelContainer
var reset_dialog: ConfirmationDialog
var sound: AudioStreamPlayer
var motes: CPUParticles2D
var save_enabled: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 10
	install_inputs()
	load_settings()
	player = Node2D.new()
	player.set_script(PlayerScript)
	player.position = Vector2(-2400,900)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	camera = Camera2D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position_smoothing_enabled = false
	add_child(camera)
	var background := Node2D.new()
	background.set_script(BackgroundScript)
	background.camera = camera
	background.process_priority = 20
	background.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	background.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(background)
	sound = AudioStreamPlayer.new()
	add_child(sound)
	build_world()
	build_ui()
	make_motes()
	crystal = Node2D.new()
	crystal.set_script(CrystalScript)
	crystal.position = COLD
	crystal.targets = targets
	crystal.incorporated.connect(on_molecule_incorporated)
	crystal.milestone_reached.connect(on_crystal_milestone)
	add_child(crystal)
	universe = Node2D.new()
	universe.set_script(UniverseScript)
	universe.world = self
	universe.intro_ended.connect(on_intro_ended)
	universe.first_protons.connect(on_first_protons)
	add_child(universe)
	if visual_test:
		universe.restore_legacy()
		save_enabled = false
		player.position = Vector2(-2300,900)
		show_message("Estudo visual · aproxime-se do próton e clique",6)
	else:
		load_game()
	sync_evolution()
	player.reset_motion()
	camera.position = crystal.focus_position() if crystal.control != CrystalScript.Phase.MOLECULE else player.position
	camera.force_update_scroll()
	if "--capture" in OS.get_cmdline_user_args():
		capture_visual.call_deferred()

func install_inputs() -> void:
	var keys := {"pause": KEY_ESCAPE, "restart": KEY_R, "fullscreen": KEY_F11}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = keys[action]
			InputMap.action_add_event(action,event)
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("interact",click)

func add_target(kind: int, pos: Vector2, radius: float = 22.0) -> Area2D:
	var target := Area2D.new()
	target.set_script(TargetScript)
	target.kind = kind
	target.identity = targets.size()
	target.radius = radius
	target.tint = [Color("efa563"),Color("c6cddc"),Color("8acfe8")][kind]
	target.position = pos
	target.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(target)
	targets.append(target)
	spawn_positions.append(pos)
	return target

func build_world() -> void:
	add_target(0,Vector2(-2110,920),27)
	add_target(0,Vector2(-2800,490),20)
	add_target(0,Vector2(-1800,1450),31)
	if visual_test:
		add_target(1,Vector2(-1840,650),34)
		return
	populate_regions()

func populate_regions() -> void:
	# The western branch reaches partners early. The eastern branch previews the cold shelf.
	for pos in [Vector2(-3350,450),Vector2(-3400,-450),Vector2(-2900,-1100),Vector2(-2400,-1800),Vector2(-1850,-1600),Vector2(-900,-200),Vector2(300,-750),Vector2(1750,-950)]:
		add_target(1,pos,27)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4189
	for i in range(28):
		add_target(0,Vector2(rng.randf_range(-4300,4700),rng.randf_range(-3300,3000)),rng.randf_range(14,29))
	for i in range(20):
		var angle := float(i)/20.0*TAU
		var radius := 1650.0+float(i%4)*320
		add_target(2,COLD+Vector2.from_angle(angle)*radius,24)
	# Append clusters after the original targets so existing save identities stay valid.
	for i in range(20):
		var angle := float(i) / 20.0 * TAU
		var center := COLD + Vector2.from_angle(angle) * (1650.0 + float(i % 4) * 320)
		add_target(2, center + Vector2(105, 75), 24)
		add_target(2, center + Vector2(-100, 80), 24)
	# Surface bands support broad growth. Repeated pockets support a narrow advancing tip.
	for column in range(-18, 19):
		var dispersion := Vector2(sin(column*2.4)*18, cos(column*1.7)*30)
		add_target(2, COLD + Vector2(column*140+35, -45+sin(column*2.4)*25) + dispersion, 24)
		add_target(2, COLD + Vector2(column*140, 130 + (posmod(column, 2))*25) + dispersion, 24)
		add_target(2, COLD + Vector2(column*140+65, 270) + dispersion, 24)
	for seed in CrystalScript.SEED_OFFSETS:
		for pocket in range(1, 13):
			var row := -pocket * 3
			var center: Vector2 = COLD + seed + Vector2(row*0.5, row*sqrt(3.0)*0.5)*CrystalScript.SPACING
			for offset in [Vector2(40, -80), Vector2(-65, -70), Vector2(100, 55)]:
				add_target(2, center + offset, 24)
	# Local reactions make the first atoms and molecules visible beside the player.
	for point in [Vector2(-3100,650), Vector2(-2700,200), Vector2(-1700,1000), Vector2(-2350,1450), Vector2(-3200,1500), Vector2(-1800,200)]:
		add_target(1, point, 27)
	for pocket in [Vector2(-2900,900), Vector2(-2100,1450), Vector2(-1800,450)]:
		for offset in [Vector2.ZERO, Vector2(110,-50), Vector2(-90,90)]:
			add_target(2, pocket+offset, 24)

func make_motes() -> void:
	motes = CPUParticles2D.new()
	motes.amount = 80
	motes.lifetime = 1.3
	motes.one_shot = true
	motes.explosiveness = 1.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 145.0
	motes.direction = Vector2.ZERO
	motes.spread = 180
	motes.initial_velocity_min = 0
	motes.initial_velocity_max = 12
	motes.radial_accel_min = -210
	motes.radial_accel_max = -150
	motes.gravity = Vector2.ZERO
	motes.scale_amount_min = 1.5
	motes.scale_amount_max = 3.5
	motes.color = Color("bcEaff")
	motes.emitting = false
	motes.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(motes)

func label(text: String, size: int, color: Color = Color("d9e8f0")) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size",size)
	result.add_theme_color_override("font_shadow_color",Color(0,0,0,0.9))
	result.add_theme_constant_override("shadow_outline_size",3)
	result.add_theme_color_override("font_color",color)
	return result

func build_ui() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",36)
	margin.add_theme_constant_override("margin_top",28)
	margin.add_theme_constant_override("margin_right",36)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var title := label("DA MATÉRIA",15,Color("6d8b9d"))
	column.add_child(title)
	form_label = label("Elétron livre",27)
	column.add_child(form_label)
	objective = label("Encontre um próton. Observe a curva do seu rastro.",17,Color("a6b8c7"))
	column.add_child(objective)
	location_label = label("",14,Color("7996aa"))
	location_label.position = Vector2(36,142)
	hud.add_child(location_label)
	action_label = label("Mouse para mover · Esc para pausar",17)
	action_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	action_label.offset_left = 36
	action_label.offset_top = -62
	hud.add_child(action_label)
	message = label("",22,Color("d6ebf7"))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	message.offset_left = -500
	message.offset_right = 500
	message.offset_top = 175
	hud.add_child(message)
	pause_panel = PanelContainer.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_panel.offset_left = -225
	pause_panel.offset_right = 225
	pause_panel.offset_top = -230
	pause_panel.offset_bottom = 230
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035,0.055,0.09,0.98)
	style.border_color = Color("385263")
	style.set_border_width_all(1)
	style.set_content_margin_all(28)
	pause_panel.add_theme_stylebox_override("panel",style)
	hud.add_child(pause_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",18)
	pause_panel.add_child(box)
	box.add_child(label("Um instante na matéria",25))
	var resume := Button.new()
	resume.text = "Continuar"
	resume.pressed.connect(toggle_pause)
	box.add_child(resume)
	box.add_child(label("Volume",16))
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.01
	slider.value = volume
	slider.value_changed.connect(func(value: float): volume = value; save_settings())
	box.add_child(slider)
	var reduced := CheckButton.new()
	reduced.text = "Reduzir flashes e tremor"
	reduced.button_pressed = reduced_effects
	reduced.toggled.connect(func(value: bool): reduced_effects = value; save_settings())
	box.add_child(reduced)
	var fullscreen := Button.new()
	fullscreen.text = "Janela / tela cheia · F11"
	fullscreen.pressed.connect(toggle_fullscreen)
	box.add_child(fullscreen)
	var restart := Button.new()
	restart.text = "Novo jogo · R"
	restart.pressed.connect(func(): reset_dialog.popup_centered())
	box.add_child(restart)
	var quit := Button.new()
	quit.text = "Salvar e sair"
	quit.pressed.connect(func(): save_game(); get_tree().quit())
	box.add_child(quit)
	pause_panel.hide()
	reset_dialog = ConfirmationDialog.new()
	reset_dialog.dialog_text = "Recomeçar como elétron? O progresso atual será substituído."
	reset_dialog.title = "Novo jogo"
	reset_dialog.confirmed.connect(new_game)
	hud.add_child(reset_dialog)
	hud_content.assign([margin, location_label, action_label, message])

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
	elif event.is_action_pressed("fullscreen"):
		toggle_fullscreen()
	elif event.is_action_pressed("restart"):
		if not get_tree().paused:
			toggle_pause()
		reset_dialog.popup_centered()
	elif event.is_action_pressed("interact") and not get_tree().paused:
		interact()

func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused
	player.velocity = Vector2.ZERO

func toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	clock += delta
	auto_save_clock += delta
	if auto_save_clock > 15.0 and not player.locked:
		auto_save_clock = 0
		save_game()
	pulse = maxf(0,pulse-delta*0.7)
	if transform_time > 0:
		transform_time -= delta
		if transform_time <= 0:
			player.set_form(pending_form)
			pending_form = -1
			player.locked = false
			save_game()
			show_message("Um núcleo, uma órbita. Você é hidrogênio." if player.form == 1 else "Dois átomos, um movimento. Você é H₂.",5)
	sync_evolution()
	var embedded: bool = crystal.control != CrystalScript.Phase.MOLECULE
	player.speed_scale = 1.0
	if player.form == 2 and not embedded:
		player.speed_scale = lerpf(0.34, 1.0, smoothstep(200.0, 900.0, crystal.seed_distance(player.position)))
	var target_zoom: float = PlayerScript.PROFILES[player.form].zoom
	if embedded:
		target_zoom = crystal.desired_zoom(get_viewport_rect().size)
		camera.position = camera.position.lerp(crystal.focus_position(), 1.0-exp(-delta*2.0))
	else:
		camera.position = player.render_position
	camera.zoom = camera.zoom.lerp(Vector2.ONE*target_zoom, 1.0-exp(-delta*0.7))
	camera.offset = Vector2.ZERO
	camera.force_update_scroll()
	crystal.effect_strength = 0.35 if reduced_effects else 1.0
	crystal.set_view_scale(camera.zoom.x)
	update_orbits(delta)
	if not cold_seen and not embedded and player.position.distance_to(COLD)<1100:
		cold_seen = true
		show_message("A superfície fria guarda lugares para H₂." if player.form < 2 else "Algumas moléculas já repousam aqui. Escolha onde formar o núcleo.", 6)
	crystal.update_selection(get_global_mouse_position(), player.position, player.form)
	update_ui()
	message_time = maxf(0,message_time-delta)
	message.modulate.a = minf(1,message_time)
	queue_redraw()

func update_ui() -> void:
	var embedded: bool = crystal.control != CrystalScript.Phase.MOLECULE
	form_label.text = "Cristal de hidrogênio" if embedded else PlayerScript.PROFILES[player.form].title
	if player.form == 0:
		objective.text = "Encontre um próton. Observe a curva do seu rastro." if universe.elapsed >= UniverseScript.PROTON_START else "Você controla o elétron no centro. A matéria está se formando."
	elif player.form == 1:
		objective.text = "Encontre outro H. O meio também está formando moléculas."
	elif embedded:
		objective.text = "%d moléculas · continue escolhendo a forma" % crystal.occupied.size() if crystal.milestone else "Faça a rede crescer · %d / %d moléculas" % [crystal.occupied.size(), CrystalScript.TARGET_SIZE]
	else:
		objective.text = "Visite a superfície fria e escolha um núcleo para o cristal."
	var region := "Mar de cargas" if player.position.x < -800 else "Arquipélago de núcleos"
	if player.position.distance_to(COLD) < 1500 or embedded:
		region = "Margem fria"
	location_label.text = region
	if player.form == 2 and not embedded:
		var direction := COLD-player.position
		if direction.length() > 500:
			location_label.text += "   ·   Superfície fria %s  %d" % [compass(direction), int(direction.length())]
	if transform_time > 0:
		action_label.text = "Ligação em formação…"
	elif not crystal.pending.is_empty():
		action_label.text = "H₂ se acomodando na rede…"
	elif embedded:
		if crystal.has_selection and crystal.selected_source >= 0:
			var distance: float = targets[crystal.selected_source].position.distance_to(crystal.cell_world(crystal.selected_cell))
			action_label.text = "Clique para guiar H₂ até esta posição · distância %d" % int(distance)
		elif crystal.has_selection:
			action_label.text = "Escolha outra borda para alcançar o próximo bolsão de H₂"
		else:
			action_label.text = "Selecione uma posição livre da borda · clique quando quiser crescer"
	elif crystal.selected_seed >= 0:
		action_label.text = "Clique para incorporar seu H₂ e formar o núcleo do cristal"
	elif is_instance_valid(player.target):
		action_label.text = ["Clique para capturar o próton", "Clique para formar H₂", "Clique para atrair os H₂ próximos para sua órbita"][player.form]
	elif not carried.is_empty():
		action_label.text = "%d H₂ em órbita · leve as moléculas até a superfície fria" % carried.size()
	else:
		action_label.text = "Mouse para mover · Esc para pausar"

func compass(direction: Vector2) -> String:
	var arrows := ["→","↘","↓","↙","←","↖","↑","↗"]
	return arrows[posmod(int(round(direction.angle()/(PI/4))),8)]

func interact() -> void:
	if universe.intro_active():
		return
	if crystal.control == CrystalScript.Phase.EDGE:
		if crystal.has_selection:
			if crystal.request_growth(crystal.selected_cell):
				save_game()
		return
	if player.locked:
		return
	if player.form == 2 and crystal.selected_seed >= 0:
		if crystal.begin_seed(player.render_position, player.heading):
			release_carried_molecules()
			player.set_embedded(true)
			save_game()
		return
	if not is_instance_valid(player.target):
		return
	var target: Area2D = player.target
	if player.position.distance_to(target.position) > PlayerScript.PROFILES[player.form].bond_range*1.15:
		return
	if player.form < 2:
		consumed.append(target.identity)
		target.selected = false
		target.hide()
		sync_evolution()
		player.target = null
		pending_form = player.form+1
		transform_time = 1.5
		player.locked = true
		player.velocity = Vector2.ZERO
		emit_pulse(player.position, true)
		play_tone(pending_form)
	else:
		collect_molecules()

func emit_pulse(pos: Vector2, intense: bool) -> void:
	pulse_position = pos
	pulse = (1.0 if intense else 0.25) * (0.35 if reduced_effects else 1.0)
	motes.position = pos
	motes.amount = 30 if reduced_effects else (100 if intense else 28)
	motes.restart()

func play_tone(kind: int) -> void:
	if volume <= 0.0:
		return
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var bytes := PackedByteArray()
	var duration := 1.4 if kind>0 else 0.35
	bytes.resize(int(22050*duration)*2)
	var frequency: float = [330.0,220.0,293.66,440.0][kind]
	for i in range(bytes.size()/2):
		var t := float(i)/22050.0
		var envelope := sin(minf(1,t*12)*PI/2)*exp(-t*3.5)
		var wave := sin(TAU*frequency*t)+sin(TAU*frequency*1.5*t)*0.35+sin(TAU*frequency*2.0*t)*0.2
		bytes.encode_s16(i*2,int(wave*envelope*10000))
	stream.data = bytes
	sound.stream = stream
	sound.volume_db = linear_to_db(maxf(volume,0.00001))
	sound.play()

func show_message(text: String, duration: float) -> void:
	message.text = text
	message_time = duration

func save_game() -> void:
	if not save_enabled:
		return
	sync_evolution()
	var molecule_positions: Array = []
	for target in targets:
		if target.kind == 2:
			molecule_positions.append([target.identity, target.position.x, target.position.y])
	var data := {"version":3, "form":pending_form if pending_form >= 0 else int(player.form), "position":[player.position.x, player.position.y], "consumed":consumed, "carried":carried, "cold_seen":cold_seen, "crystal":crystal.serialize(), "molecule_positions":molecule_positions, "universe":universe.serialize()}
	var file := FileAccess.open(save_path+".tmp", FileAccess.WRITE)
	if file == null:
		show_message("Não foi possível salvar o progresso.", 5)
		return
	file.store_string(JSON.stringify(data))
	file.close()
	if DirAccess.rename_absolute(save_path+".tmp", save_path) != OK:
		show_message("Falha ao concluir o salvamento.", 5)

func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary or int(data.get("version", 0)) not in [1, 2, 3]:
		return
	var pos = data.get("position", [-2400, 900])
	if not pos is Array or pos.size() != 2:
		return
	player.set_embedded(false)
	player.set_form(clampi(int(data.get("form", 0)), 0, 2))
	player.position = Vector2(float(pos[0]), float(pos[1])).clamp(Vector2(-5000, -4300), Vector2(6000, 4300))
	player.reset_motion()
	transform_time = 0
	pending_form = -1
	consumed.clear()
	for value in data.get("consumed", []):
		if int(value) >= 0 and int(value) < targets.size() and int(value) not in consumed:
			consumed.append(int(value))
	for target in targets:
		target.set_simulation_position(spawn_positions[target.identity], true)
	for entry in data.get("molecule_positions", []):
		if entry is Array and entry.size() == 3:
			var identity := int(entry[0])
			if identity >= 0 and identity < targets.size() and targets[identity].kind == 2:
				targets[identity].set_simulation_position(Vector2(float(entry[1]), float(entry[2])), true)
	if int(data.version) >= 2:
		crystal.restore(data.get("crystal", {}))
	else:
		var source_identities: Array[int] = []
		for identity in consumed:
			if targets[identity].kind == 2:
				source_identities.append(identity)
		crystal.restore_legacy(data.get("filled", []), source_identities)
	if int(data.version) == 3:
		universe.restore(data.get("universe", {}))
	else:
		universe.restore_legacy()
	var reserved: Array[int] = crystal.reserved_sources()
	for identity in reserved:
		if identity not in consumed and (crystal.pending.is_empty() or identity != int(crystal.pending.source)):
			consumed.append(identity)
	var saved_carried = data.get("carried", [])
	if saved_carried is int or saved_carried is float:
		saved_carried = [int(saved_carried)] if int(saved_carried) >= 0 else []
	carried.clear()
	if saved_carried is Array and player.form == 2:
		for value in saved_carried:
			var identity := int(value)
			if identity >= 0 and identity < targets.size() and targets[identity].kind == 2 and identity not in consumed and identity not in reserved and identity not in carried:
				carried.append(identity)
	for target in targets:
		target.selected = false
	player.target = null
	if crystal.control != CrystalScript.Phase.MOLECULE:
		release_carried_molecules()
		player.set_embedded(true)
		camera.zoom = Vector2.ONE * crystal.desired_zoom(get_viewport_rect().size)
	else:
		sync_orbit_visuals(false)
	cold_seen = bool(data.get("cold_seen", false))
	sync_evolution()
	camera.position = crystal.focus_position() if player.embedded else player.position
	camera.force_update_scroll()
	show_message("A matéria guardou seu lugar.", 4)

func new_game() -> void:
	get_tree().paused = false
	pause_panel.hide()
	crystal.reset()
	player.set_embedded(false)
	player.set_form(0)
	player.position = Vector2(-2400, 900)
	player.target = null
	player.speed_scale = 1.0
	player.reset_motion()
	consumed.clear()
	carried.clear()
	sync_orbit_visuals()
	cold_seen = false
	transform_time = 0
	pending_form = -1
	pulse = 0
	message_time = 0
	auto_save_clock = 0
	sound.stop()
	motes.emitting = false
	for target in targets:
		target.show()
		target.selected = false
		target.set_simulation_position(spawn_positions[target.identity], true)
	camera.zoom = Vector2.ONE
	camera.position = player.position
	camera.force_update_scroll()
	universe.reset()
	sync_evolution()
	save_game()

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio","volume",volume)
	config.set_value("accessibility","reduced_effects",reduced_effects)
	config.save(SETTINGS_PATH)

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		volume = clampf(float(config.get_value("audio","volume",0.55)),0,1)
		reduced_effects = bool(config.get_value("accessibility","reduced_effects",false))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(player):
		save_game()

func _draw() -> void:
	if pulse > 0:
		for i in range(4):
			draw_arc(pulse_position, (1-pulse)*220+i*9, 0, TAU, 80, Color(0.7,0.88,1,pulse*0.2), 2, true)

func capture_visual() -> void:
	save_enabled = false
	new_game()
	universe.restore_legacy()
	sync_evolution()
	get_viewport().warp_mouse(Vector2(980,470))
	await get_tree().create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://validation/visual_test.png" if visual_test else "res://validation/opening.png")
	player.velocity = Vector2.ZERO
	player.target = targets[0]
	player.position = targets[0].position-Vector2(90,0)
	interact()
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://validation/visual_bond.png")
	get_tree().quit()

func collect_molecules() -> void:
	var count := 0
	var range_limit: float = PlayerScript.PROFILES[2].field_range
	for target in player.candidates:
		if not player.valid_candidate(target) or target.identity in carried:
			continue
		if player.position.distance_to(target.position) > range_limit:
			continue
		carried.append(target.identity)
		target.selected = false
		target.hide()
		count += 1
	if count == 0:
		return
	player.target = null
	sync_orbit_visuals()
	show_message("%d H₂ atraídos · %d moléculas em órbita" % [count, carried.size()], 3)
	play_tone(0)
	save_game()

func orbit_offset(index: int) -> Vector2:
	var ring := index / 8
	var radius := 125.0 + ring * 100.0
	var ring_count := mini(8, carried.size() - ring * 8)
	var angle := clock * (0.5 / (1.0 + ring * 0.15)) + float(index % 8) * TAU / float(ring_count)
	return Vector2.from_angle(angle) * radius

func sync_orbit_visuals(animate_new: bool = true) -> void:
	for identity in orbit_visuals.keys():
		if identity not in carried:
			orbit_visuals[identity].queue_free()
			orbit_visuals.erase(identity)
			orbit_offsets.erase(identity)
	for i in range(carried.size()):
		var identity := carried[i]
		if orbit_visuals.has(identity):
			continue
		var visual := Node2D.new()
		visual.set_script(preload("res://scripts/matter_visual.gd"))
		visual.form = 2
		visual.top_level = true
		var offset: Vector2 = targets[identity].position - player.position if animate_new else orbit_offset(i)
		orbit_offsets[identity] = offset
		visual.position = player.render_position + offset
		player.add_child(visual)
		orbit_visuals[identity] = visual

func update_orbits(delta: float) -> void:
	var blend := 1.0 - exp(-delta * 6.0)
	for i in range(carried.size()):
		var visual: Node2D = orbit_visuals[carried[i]]
		var destination := orbit_offset(i)
		orbit_offsets[carried[i]] = (orbit_offsets[carried[i]] as Vector2).lerp(destination, blend)
		visual.position = player.render_position + orbit_offsets[carried[i]]
		visual.rotation = lerp_angle(visual.rotation, destination.angle() + PI/2, blend)

func release_carried_molecules() -> void:
	for index in range(carried.size()):
		var target: Area2D = targets[carried[index]]
		var angle := float(index) * 2.399963
		target.position = crystal.cell_world(Vector2i.ZERO) + Vector2.from_angle(angle)*(260.0 + floorf(index/8.0)*70.0)
		universe.reanchor(target.identity, target.position)
		target.show()
	carried.clear()
	sync_orbit_visuals()

func on_molecule_incorporated(source_identity: int) -> void:
	if source_identity >= 0 and source_identity not in consumed:
		consumed.append(source_identity)
	player.set_embedded(true)
	play_tone(0)
	save_game()

func on_crystal_milestone() -> void:
	emit_pulse(crystal.focus_position(), true)
	play_tone(3)
	show_message("O primeiro cristal nasceu. Outros núcleos aparecem ao redor. Continue expandindo sua rede.", 8)

func sync_evolution() -> void:
	var reserved: Array[int] = consumed.duplicate()
	reserved.append_array(carried)
	reserved.append_array(crystal.reserved_sources())
	universe.set_blocked(reserved)
	universe.reduced_effects = reduced_effects
	var opening: bool = universe.intro_active()
	motes.visible = not opening
	player.set_intro_locked(opening)
	for item in hud_content:
		item.visible = not opening
	crystal.visible = not opening and player.form >= 2

func on_intro_ended() -> void:
	sync_evolution()
	show_message("Você é um destes elétrons. Siga o movimento da matéria.", 4)

func on_first_protons() -> void:
	show_message("Os primeiros prótons aparecem. Observe a atração.", 4)