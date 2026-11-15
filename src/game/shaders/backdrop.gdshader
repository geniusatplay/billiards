shader_type spatial;
render_mode cull_front, shadows_disabled, fog_disabled, depth_draw_never, ambient_light_disabled;
// The dome around the Studio room. It follows the camera, so it behaves like a sky: far mountains,
// skylines and suns never come closer. Stage makes one copy of this shader per scene and changes the
// number on the next line, so only that scene's code is compiled.
// It shines by EMISSION with a black surface rather than being "unshaded": the Compatibility renderer draws
// things near a second shadow-casting light once more, which would add an unshaded dome to itself.
#define SCENE_STYLE 0
#include "res://src/game/shaders/backdrop.gdshaderinc"

uniform vec3 ground = vec3(0.02, 0.03, 0.05);   // what lies below the horizon when the floor goes on for ever
uniform float open_below = 0.0;                 // 1 = the room is a platform: the scene carries on underneath
varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

void fragment() {
	vec3 d = normalize(dir);
	vec3 c = scene_backdrop(d, TIME);
	c = mix(c, ground, smoothstep(0.0, -0.035, d.y) * (1.0 - open_below));
	ALBEDO = vec3(0.0);
	EMISSION = c;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}
