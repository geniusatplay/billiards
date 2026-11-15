shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
// Soft ambient-occlusion blob that grounds the table on the camera image.
void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float d = length(c);
	ALBEDO = vec3(0.0);
	ALPHA = smoothstep(1.0, 0.35, d) * 0.45;
}
