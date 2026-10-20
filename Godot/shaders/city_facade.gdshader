shader_type spatial;
render_mode unshaded;

uniform vec4 accent : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform vec4 secondary : source_color = vec4(1.0, 0.05, 0.5, 1.0);
uniform float animation_time = 0.0;
uniform float motion_strength = 1.0;
uniform float pulse_strength = 1.0;
uniform float variation = 0.0;

float cell_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7)) + variation * 19.3) * 43758.5453);
}

void fragment() {
	vec2 grid = UV * vec2(8.0, 24.0);
	vec2 cell = floor(grid);
	vec2 tile = fract(grid);
	float windows = step(0.18, tile.x) * step(tile.x, 0.78)
		* step(0.18, tile.y) * step(tile.y, 0.68) * step(0.25, cell_hash(cell));
	float stripe = step(0.92, fract(UV.x * 4.0 + variation));
	float sweep = 1.0 - smoothstep(0.015, 0.07,
		abs(fract(UV.y - animation_time * 0.035 * motion_strength + variation) - 0.5));
	float pulse = 1.0 + sin(animation_time * 0.7 + variation * 6.0) * 0.12 * pulse_strength;
	vec3 window_color = mix(accent.rgb, secondary.rgb, step(0.65, cell_hash(cell + 7.0)));
	vec3 light = window_color * windows * 2.1 * pulse
		+ secondary.rgb * stripe * 1.8 + accent.rgb * sweep * 0.6;
	ALBEDO = vec3(0.012, 0.018, 0.045) + light;
	EMISSION = light;
}
