shader_type canvas_item;
render_mode unshaded;

// Schematic uud valence structure within a diffuse parton cloud.
// RGB encodes color charge symbolically. All instances share this material.
float grain_hash(vec2 cell) {
	vec3 value = fract(vec3(cell.xyx) * 0.1031);
	value += dot(value, value.yzx + 33.33);
	return fract((value.x + value.y) * value.z);
}

void fragment() {
	vec2 position = UV * 2.0 - 1.0;
	float radius_squared = dot(position, position);
	float envelope = 1.0 - smoothstep(0.58, 1.0, radius_squared);

	float drift = sin(TIME * 0.65) * 0.035;
	vec2 red_offset = position - vec2(0.36, -0.16 + drift);
	vec2 green_offset = position - vec2(-0.31, -0.26 - drift);
	vec2 blue_offset = position - vec2(-0.04 + drift, 0.37);
	vec3 density = exp(-vec3(dot(red_offset, red_offset), dot(green_offset, green_offset), dot(blue_offset, blue_offset)) * 9.0);
	float total_density = density.r + density.g + density.b;
	vec3 color = (density.r * vec3(1.0, 0.065, 0.12)
		+ density.g * vec3(0.16, 1.0, 0.12)
		+ density.b * vec3(0.065, 0.42, 1.0)) / max(total_density, 0.001);

	// One stationary dot per cell, softened in screen space to avoid aliasing.
	vec2 grid = UV * 40.0;
	vec2 cell = floor(grid);
	float random_value = grain_hash(cell);
	vec2 point_center = vec2(random_value, grain_hash(cell + vec2(41.0, 17.0))) * 0.64 + 0.18;
	float point_distance = length(fract(grid) - point_center);
	float point_radius = mix(0.13, 0.29, random_value);
	float antialias = max(fwidth(point_distance), 0.045);
	float point = 1.0 - smoothstep(point_radius - antialias, point_radius + antialias, point_distance);
	float occupancy = step(random_value, 0.32 + total_density * 0.47);
	float core = pow(max(max(density.r, density.g), density.b), 3.0);
	float cloud = (0.055 + core * 0.32) * envelope;
	float dots = point * occupancy * envelope * (0.35 + min(total_density, 1.0) * 0.65);
	float alpha = clamp(cloud + dots, 0.0, 1.0);
	vec3 radiance = color * (0.95 + core * 0.55) + vec3(0.7, 0.85, 1.0) * pow(random_value, 10.0) * dots * 0.55;
	COLOR = vec4(radiance, alpha);
}
