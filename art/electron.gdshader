shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float radius = length(point);
	float glow = 1.0 - smoothstep(0.05, 1.0, radius);
	COLOR = vec4(COLOR.rgb, COLOR.a * glow);
}
