shader_type spatial;
// Soft glow under a floating AR table: a rounded-rectangle halo that gently breathes.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.17, 0.9, 0.65, 1.0);
uniform float strength = 0.45;
uniform vec2 half_extent = vec2(0.62, 0.45);   // footprint in UV half-units

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	vec2 q = abs(p) - half_extent;
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
	float a = clamp(1.0 - max(d, 0.0) / 0.32, 0.0, 1.0);
	a = a * a * (0.85 + 0.15 * sin(TIME * 1.7));
	if (d < -0.05) a *= 0.55;   // softer under the middle of the table
	ALBEDO = color.rgb * a * strength;
}
