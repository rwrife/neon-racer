shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.012, 0.008, 0.035, 1.0);
uniform vec4 grid_color : source_color = vec4(0.0, 0.96, 1.0, 1.0);

void fragment() {
	vec3 aa = max(fwidth(COLOR.rgb), vec3(0.0001));
	vec3 line = smoothstep(vec3(0.0), aa * 1.1, COLOR.rgb);
	float grid = 1.0 - min(min(line.r, line.g), line.b);
	vec3 tint = mix(grid_color.rgb, vec3(1.0, 0.05, 0.78), step(0.75, UV.x));
	ALBEDO = mix(base_color.rgb, tint, grid * 0.8);
	EMISSION = tint * grid * 0.55;
}
