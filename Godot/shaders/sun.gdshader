shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float disc = 1.0 - smoothstep(0.97, 1.0, length(p));
	float stripe = step(0.18, fract(UV.y * 16.0));
	float visible = UV.y < 0.5 ? 1.0 : stripe;
	ALBEDO = mix(vec3(1.0, 0.9, 0.01), vec3(1.0, 0.06, 0.25), UV.y);
	EMISSION = ALBEDO * 1.5;
	ALPHA = disc * visible * opacity;
}
