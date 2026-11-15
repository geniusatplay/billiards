shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;
// The drifting particles of a Studio scene (snow, fireflies, embers, bubbles ...), drawn as ONE mesh.
// Every quad carries its own random numbers in its vertex colour and this shader moves it, so nothing is
// computed on the phone's processor.
// It glows by EMISSION with a black surface instead of being "unshaded": the Compatibility renderer draws
// everything near a second shadow-casting light once more, and an unshaded see-through quad comes out of
// that extra pass as a plain bright square. A black surface adds nothing there.
uniform vec3 box = vec3(5.0, 1.0, 5.0);   // half-size of the volume the particles live in
uniform vec3 drift = vec3(0.0);           // steady movement, metres per second
uniform float wander = 0.1;               // random movement, metres per second
uniform float size_min = 0.02;
uniform float size_max = 0.04;
uniform vec4 tint = vec4(1.0);            // may be brighter than 1 so it glows
uniform float life = 6.0;                 // seconds for one fade in and out
uniform float blink = 0.0;                // 1 = fades in and out, 0 = steady
uniform float ring = 0.0;                 // 1 = a bubble's outline instead of a soft dot
uniform vec2 keep_out = vec2(0.0);        // half-size of the table's footprint: nothing drifts over the cloth
varying float fade;

// smoothstep that is also defined for a falling ramp (first edge larger); the built-in is not.
float sstep(float a, float b, float x) {
	float k = clamp((x - a) / (b - a), 0.0, 1.0);
	return k * k * (3.0 - 2.0 * k);
}

void vertex() {
	vec3 seed = COLOR.rgb;
	float s2 = COLOR.a;
	vec3 vel = drift + (vec3(fract(seed.x * 7.13), fract(seed.y * 5.71), fract(seed.z * 3.37)) - 0.5) * 2.0 * wander;
	vec3 p = (seed * 2.0 - 1.0) * box + vel * TIME;
	p.x += sin(TIME * (0.3 + s2) + seed.y * 40.0) * wander * 0.6;
	p.z += cos(TIME * (0.25 + s2 * 0.7) + seed.x * 40.0) * wander * 0.6;
	p = mod(p + box, box * 2.0) - box;
	float ph = fract(TIME / life * (0.6 + 0.8 * s2) + seed.z * 9.0);
	fade = mix(1.0, sstep(0.0, 0.3, ph) * sstep(1.0, 0.7, ph), blink);
	vec3 e = 1.0 - abs(p) / box;
	fade *= sstep(0.0, 0.12, min(e.x, min(e.y, e.z)));   // no popping where the volume wraps round
	fade *= sstep(0.0, 0.3, max(abs(p.x) - keep_out.x, abs(p.z) - keep_out.y));
	float sz = mix(size_min, size_max, fract(s2 * 13.7));
	// face the camera: its right and up, brought into the room's own space (the room turns with an AR table)
	mat4 to_room = inverse(MODEL_MATRIX);
	vec3 cam_r = normalize((to_room * vec4(INV_VIEW_MATRIX[0].xyz, 0.0)).xyz);
	vec3 cam_u = normalize((to_room * vec4(INV_VIEW_MATRIX[1].xyz, 0.0)).xyz);
	VERTEX = p + (cam_r * (UV.x - 0.5) + cam_u * (UV.y - 0.5)) * sz;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float dot_a = pow(clamp(1.0 - d, 0.0, 1.0), 1.6);
	float ring_a = sstep(1.0, 0.86, d) * (0.1 + 0.9 * sstep(0.6, 0.84, d));
	ALBEDO = vec3(0.0);
	// The strength goes into the colour and ALPHA stays 1: adding "colour x strength" is what an additive
	// particle is, and on this mesh the renderer does not apply a varying ALPHA (the quads came out square).
	EMISSION = tint.rgb * (mix(dot_a, ring_a, ring) * tint.a * fade);
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	ALPHA = 1.0;
}
