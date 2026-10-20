shader_type spatial;
uniform vec4 paint : source_color = vec4(1.0, 0.03, 0.3, 1.0);
void fragment() {
	float shade = clamp(pow(dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)), 0.65) * 1.6, 0.025, 1.0);
	ALBEDO = paint.rgb * shade;
	METALLIC = 0.45;
	ROUGHNESS = 0.28;
}
