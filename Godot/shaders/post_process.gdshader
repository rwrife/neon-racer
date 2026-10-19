shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform bool soften_effects = false;

float neon_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 center = uv - 0.5;
	float edge = smoothstep(0.18, 0.78, length(center));
	float split = soften_effects ? 0.0 : 0.0008 + edge * 0.0018;
	vec4 base = textureLod(screen, uv, 0.0);
	vec3 color = vec3(
		textureLod(screen, uv + vec2(split, 0.0), 0.0).r,
		base.g,
		textureLod(screen, uv - vec2(split, 0.0), 0.0).b);
	float scan = sin(uv.y * 980.0);
	float scan_mask = 1.0 - (scan * 0.5 + 0.5) * 0.045;
	float grain = soften_effects ? 0.0 : (neon_hash(uv * vec2(850.0, 480.0)) - 0.5) * 0.018;
	float horizon = exp(-abs(uv.y - 0.49) * 15.0)
		* smoothstep(0.08, 0.85, 1.0 - abs(uv.x - 0.5) * 2.0) * 0.11;
	float vignette = 1.0 - smoothstep(0.28, 0.94, dot(center, center) * 1.35);
	color *= scan_mask * max(vignette, 0.55);
	color += vec3(0.04, 0.0, 0.08) * edge;
	color += vec3(1.0, 0.18, 0.45) * horizon;
	color += vec3(grain);
	if (!soften_effects) {
		vec3 bloom = max(textureLod(screen, uv, 2.0).rgb - vec3(0.35), vec3(0.0)) * 0.22
			+ max(textureLod(screen, uv, 4.0).rgb - vec3(0.3), vec3(0.0)) * 0.18;
		color += bloom;
	}
	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), 1.0);
}
