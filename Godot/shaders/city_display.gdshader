shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 accent : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform vec4 secondary : source_color = vec4(1.0, 0.05, 0.5, 1.0);
uniform float animation_time = 0.0;
uniform float motion_strength = 1.0;
uniform float pulse_strength = 1.0;
uniform float variation = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float border = step(0.86, max(abs(p.x), abs(p.y)));
	float scan = pow(0.5 + 0.5 * sin(UV.y * 95.0
		- animation_time * 2.0 * motion_strength), 4.0);
	float ring = 1.0 - smoothstep(0.025, 0.065, abs(length(p * vec2(1.0, 0.65)) - 0.5));
	float bars = step(0.66, fract(UV.x * 9.0 + floor(UV.y * 6.0) * 0.27
		+ animation_time * 0.08 * motion_strength + variation));
	float pulse = 1.0 + 0.1 * sin(animation_time * 0.6 + variation) * pulse_strength;
	vec3 light = accent.rgb * (border + ring * 0.65 + bars * 0.24)
		+ secondary.rgb * scan * 0.2;
	ALBEDO = vec3(0.015, 0.008, 0.04) + light * pulse;
	EMISSION = light * 2.4 * pulse;
}
