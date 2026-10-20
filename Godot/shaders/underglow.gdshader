shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.1, 0.9, 1.0, 1.0);
uniform float strength = 1.1;
void fragment() {
	float radius = length((UV - 0.5) * 2.0);
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb;
	ALPHA = exp(-radius * radius * 3.0) * (1.0 - smoothstep(0.7, 1.0, radius)) * 0.55 * strength;
}
