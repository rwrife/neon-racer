shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.1, 0.9, 1.0, 1.0);
uniform float strength = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.18;
varying float height;
void vertex() {
	height = VERTEX.y + 0.5;
}
void fragment() {
	vec3 color = mix(tint.rgb, vec3(0.8, 1.0, 1.0), pow(1.0 - height, 2.0) * 0.65);
	ALBEDO = color;
	EMISSION = color * strength;
	ALPHA = opacity * (1.0 - smoothstep(0.45, 1.0, height));
}
