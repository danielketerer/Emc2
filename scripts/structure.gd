extends Node2D
var radius: float = 180.0
var tint := Color("58769c")
var ring: bool = false
var age: float = 0.0

func _ready() -> void:
	var visibility_notifier := VisibleOnScreenNotifier2D.new()
	var extent := radius * 2.0
	visibility_notifier.rect = Rect2(Vector2.ONE * -extent, Vector2.ONE * extent * 2.0)
	visibility_notifier.screen_entered.connect(set_process.bind(true))
	visibility_notifier.screen_exited.connect(set_process.bind(false))
	add_child(visibility_notifier)
	set_process(false)
	var sprite := Sprite2D.new()
	var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.scale = Vector2.ONE*radius
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://art/matter.gdshader")
	mat.set_shader_parameter("tint",tint)
	mat.set_shader_parameter("seed",position.x*0.002)
	sprite.material = mat
	add_child(sprite)

func _process(delta: float) -> void:
	age += delta
	queue_redraw()

func _draw() -> void:
	for i in range(16,0,-1):
		draw_circle(Vector2.ZERO,radius+i*5,Color(tint,0.007))
	if ring:
		var points := PackedVector2Array()
		for i in range(121):
			var a := float(i)/120*TAU
			points.append(Vector2(cos(a)*radius*1.6,sin(a)*radius*0.4).rotated(-0.35))
		draw_polyline(points,Color(tint.lightened(0.4),0.3),6,true)
	for i in range(26):
		var a := i*2.39996+age*0.015
		var pos := Vector2.from_angle(a)*(radius+30+i*6)
		draw_circle(pos,1+i%3,Color(tint.lightened(0.3),0.35))
