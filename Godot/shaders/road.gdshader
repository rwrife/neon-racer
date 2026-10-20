shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 primary : source_color = vec4(0.0, 0.95, 1.0, 1.0);
uniform vec4 secondary : source_color = vec4(1.0, 0.02, 0.75, 1.0);
uniform vec4 warning : source_color = vec4(1.0, 0.55, 0.05, 1.0);
uniform vec4 asphalt_color : source_color = vec4(0.10, 0.02, 0.16, 1.0);
uniform vec4 shoulder_color : source_color = vec4(0.08, 0.0, 0.12, 1.0);
uniform vec4 lattice_color : source_color = vec4(0.0, 0.30, 0.42, 1.0);

float stripe(float position, float period, float thickness) {
	float distance = abs(mod(position + period * 0.5, period) - period * 0.5);
	float aa = max(fwidth(position), 0.0001);
	return 1.0 - smoothstep(thickness * 0.5, thickness * 0.5 + aa, distance);
}

vec3 lane_marking(float count, vec2 uv) {
	float lane = stripe(uv.x * count, 1.0, 0.009 * count);
	lane *= step(0.04, uv.x) * step(uv.x, 0.96) * (1.0 - step(8.0, mod(uv.y, 22.0)));
	float center = (1.0 - step(0.01, mod(count, 2.0))) * (1.0 - step(0.04, abs(uv.x - 0.5)));
	return mix(primary.rgb, warning.rgb, center) * lane;
}

void fragment() {
	float asphalt = step(0.0, UV.x) * step(UV.x, 1.0);
	vec3 color = mix(shoulder_color.rgb, asphalt_color.rgb, asphalt);
	float split = step(0.5, abs(UV2.y));
	float cross_line = stripe(UV.y, 24.0, 0.35) * (1.0 - split);
	float lattice = max(stripe(UV.y, 6.0, 0.12) * (1.0 - cross_line),
		stripe(UV.x - 0.125, 0.25, 0.005)) * asphalt * (1.0 - split);
	color = mix(color, lattice_color.rgb, lattice);
	color = mix(color, primary.rgb, cross_line);
	float count = max(UV2.x, 1.0);
	vec3 lanes = mix(lane_marking(floor(count), UV), lane_marking(ceil(count), UV), fract(count));
	color = mix(color, lanes, clamp(max(max(lanes.r, lanes.g), lanes.b), 0.0, 1.0));
	float edge = max(stripe(UV.x, 100.0, 0.025), stripe(UV.x - 1.0, 100.0, 0.025));
	color = mix(color, mix(secondary.rgb, warning.rgb, step(0.5, UV2.y)), edge);
	ALBEDO = color;
	EMISSION = color * 0.45;
}
