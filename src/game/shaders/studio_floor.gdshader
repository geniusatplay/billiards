shader_type spatial;
// The floor of the Studio room. FLOOR_STYLE picks the surface, SCENE_STYLE the surroundings it mirrors.
// Stage makes one copy of this shader per scene and changes the two numbers below, so only that
// scene's code is compiled. Style 0 is the plank floor of the three original scenes.
#define FLOOR_STYLE 0
#define SCENE_STYLE 0
#include "res://src/game/shaders/backdrop.gdshaderinc"

uniform vec3 tint = vec3(1.0);
uniform vec3 ground = vec3(0.02, 0.03, 0.05);   // the colour the floor fades into far away
uniform float mirror_k = 1.0;                   // 0 switches the mirrored surroundings off (slow phones)
varying vec3 lpos;   // position on the floor, in the room's own space (the room moves and shrinks with an AR table)
varying vec3 lcam;   // the camera, in the same space

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// A line of half-width w around dist = 0 that stays smooth however far away it is.
float aline(float dist, float w) {
	float fw = fwidth(dist) * 1.2;
	return (1.0 - sstep(w - fw, w + fw, abs(dist))) * clamp(w / max(fw, 0.0001) * 1.5, 0.0, 1.0);
}

void vertex() {
	lpos = VERTEX;
	lcam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	vec2 p = lpos.xz;
	float r = length(p);
	vec3 view = normalize(lpos - lcam);
	vec3 alb = vec3(0.1);
	vec3 emi = vec3(0.0);
	float rough = 0.6;
	float metal = 0.0;
	float mirror = 0.0;       // how much of the surroundings the floor reflects
	vec2 wobble = vec2(0.0);  // bends the reflection (ripples, uneven ice)
	float far_a = 9.0;        // the fade into the distance starts here ...
	float far_b = 30.0;       // ... and is complete here

#if FLOOR_STYLE == 0
	float plank = floor(p.x / 0.22);
	float off = hash(vec2(plank, 3.1)) * 2.0;
	float seam = sstep(0.004, 0.0, abs(fract(p.x / 0.22) - 0.0) * 0.22) + sstep(0.004, 0.0, abs(fract((p.y + off) / 1.6)) * 1.6);
	float grain = sin((p.y + off) * 38.0 + sin(p.x * 9.0) * 2.0) * 0.5 + 0.5;
	vec3 wood = mix(vec3(0.075, 0.050, 0.037), vec3(0.12, 0.08, 0.055), grain * 0.6 + hash(vec2(plank, 1.0)) * 0.4);
	wood *= 1.0 - seam * 0.5;
	float vig = sstep(7.5, 1.5, r);
	alb = mix(vec3(0.02, 0.03, 0.05), wood * tint, vig);
	rough = mix(0.95, 0.38, vig);
	far_a = 1000.0;
	far_b = 2000.0;

#elif FLOOR_STYLE == 1
	// Orbit Station: a round deck of dark panels with lit seams; space carries on underneath
	if (r > 3.7) {
		discard;
	}
	vec2 hp = p * 1.6;
	vec2 hq = vec2(hp.x + hp.y * 0.57735, hp.y * 1.1547);
	vec2 hi = floor(hq);
	vec2 hf = fract(hq);
	float tri = step(hf.x + hf.y, 1.0);
	float edge = min(min(hf.x, hf.y), abs(hf.x + hf.y - 1.0) * 0.7071);
	float pan = hash(hi + tri * 7.0);
	alb = vec3(0.09, 0.1, 0.13) * (0.7 + 0.6 * pan);
	float seam = aline(edge, 0.012);
	alb *= 1.0 - seam * 0.6;
	emi += vec3(0.1, 0.75, 1.0) * seam * 0.5 * step(0.6, pan);
	float rim = sstep(3.52, 3.56, r) * sstep(3.7, 3.66, r);
	float ring2 = aline(r - 2.75, 0.012);
	emi += vec3(0.15, 0.85, 1.0) * (rim * 2.2 + ring2 * 1.2 * (0.7 + 0.3 * sin(atan(p.y, p.x) * 24.0 + TIME * 0.8)));
	alb = mix(alb, vec3(0.02), rim);
	rough = 0.28;
	metal = 0.6;
	mirror = 0.3;
	far_a = 1000.0;
	far_b = 2000.0;

#elif FLOOR_STYLE == 2
	// Aurora Lake: black ice that mirrors the sky, with drifts of snow
	float drift = sfbm(p * 0.45 + 3.0);
	float snow = sstep(0.62, 0.72, drift + 0.06 * sfbm(p * 5.0)) * sstep(1.6, 3.0, r);
	vec3 cr = scells(p * 0.9);
	float crack = aline(cr.y, 0.006) * 0.6 + aline(scells(p * 2.7 + 9.0).y, 0.004) * 0.25;
	alb = mix(vec3(0.02, 0.045, 0.07) + vec3(0.25, 0.4, 0.45) * crack, vec3(0.3, 0.38, 0.44) * (0.85 + 0.3 * svn(p * 14.0)), snow);
	rough = mix(0.06, 0.9, snow);
	mirror = mix(0.6, 0.0, snow);
	wobble = (vec2(svn(p * 3.0), svn(p * 3.0 + 40.0)) - 0.5) * 0.03;

#elif FLOOR_STYLE == 3
	// Neon Skyline: a wet rooftop with a lit parapet; the city carries on below
	float sq = max(abs(p.x), abs(p.y));
	if (sq > 6.6) {
		discard;
	}
	vec2 tp = p / 1.2;
	float tl = max(abs(fract(tp.x) - 0.5), abs(fract(tp.y) - 0.5));
	float tile = aline(tl - 0.5, 0.008);
	float wet = sstep(0.42, 0.62, sfbm(p * 0.7 + 11.0));
	alb = vec3(0.16, 0.15, 0.2) * (0.8 + 0.4 * hash(floor(tp))) * (1.0 - tile * 0.6);
	alb = mix(alb, vec3(0.012, 0.012, 0.02), wet * 0.7);
	rough = mix(0.75, 0.05, wet);
	mirror = mix(0.08, 0.6, wet);
	wobble = (vec2(svn(p * 5.0 + TIME * 0.1), svn(p * 5.0 + 20.0)) - 0.5) * 0.02 * wet;
	float par = sstep(6.3, 6.34, sq);
	float strip = sstep(6.36, 6.4, sq) * sstep(6.52, 6.48, sq);
	alb = mix(alb, vec3(0.02, 0.02, 0.03), par);
	vec3 neon = mix(vec3(1.0, 0.1, 0.7), vec3(0.1, 0.9, 1.0), step(abs(p.x), abs(p.y)));
	emi += neon * strip * 2.6;
	emi += neon * exp(-(6.36 - sq) * 1.6) * 0.1 * (1.0 - par);
	float ring = aline(r - 3.4, 0.03);
	emi += vec3(1.0, 0.8, 0.2) * ring * 0.35;
	far_a = 1000.0;
	far_b = 2000.0;

#elif FLOOR_STYLE == 4
	// Coral Deep: rippled sand with light dancing on it
	float rip = sin(p.x * 16.0 + sfbm(p * 0.8) * 9.0) * 0.5 + 0.5;
	alb = mix(vec3(0.2, 0.25, 0.2), vec3(0.3, 0.36, 0.27), rip) * (0.8 + 0.3 * svn(p * 22.0));
	float c1 = sfbm(p * 1.6 + vec2(TIME * 0.12, TIME * 0.07));
	float c2 = sfbm(p * 1.6 * 1.7 - vec2(TIME * 0.1, TIME * 0.13) + 5.0);
	float caus = pow(1.0 - abs(c1 - c2), 10.0);
	emi += vec3(0.35, 0.8, 0.7) * caus * 0.55;
	rough = 0.9;
	far_a = 4.0;
	far_b = 16.0;

#elif FLOOR_STYLE == 5
	// Magma Forge: plates of basalt with lava glowing in the cracks
	vec3 cr = scells(p * 0.75);
	float open = sstep(0.35, 0.6, sfbm(p * 0.3 + 7.0)) * sstep(1.3, 2.6, r);   // cool rock near the table
	float w = 0.02 + 0.07 * open;
	float crack = 1.0 - sstep(w * 0.5, w, cr.y);
	float heat = 0.65 + 0.35 * sin(TIME * 0.9 + cr.z * 30.0 + sfbm(p * 2.0) * 6.0);
	alb = vec3(0.04, 0.032, 0.03) * (0.6 + 0.7 * svn(p * 9.0)) * (0.7 + 0.5 * cr.z);
	alb = mix(alb, vec3(0.01), crack);
	emi += vec3(2.6, 0.62, 0.07) * crack * heat * (0.35 + 0.65 * open);
	emi += vec3(0.9, 0.16, 0.02) * exp(-cr.y * 14.0) * 0.4 * heat * (0.3 + 0.7 * open);
	rough = 0.7;

#elif FLOOR_STYLE == 6
	// Desert Dusk: wind-combed sand
	float dune = sfbm(p * 0.22 + 2.0);
	float rip = sin((p.x * 0.8 + p.y * 0.6) * 34.0 + sfbm(p * 1.2) * 10.0) * 0.5 + 0.5;
	alb = mix(vec3(0.25, 0.14, 0.09), vec3(0.42, 0.27, 0.16), dune * 0.7 + rip * 0.3) * (0.85 + 0.25 * svn(p * 30.0));
	rough = 0.95;

#elif FLOOR_STYLE == 7
	// Firefly Grove: old flagstones with moss between them and a few glowing mushrooms
	vec3 cr = scells(p * 1.3);
	float moss = (1.0 - sstep(0.03, 0.12, cr.y)) + sstep(0.55, 0.75, sfbm(p * 0.8 + 4.0)) * 0.7;
	moss = clamp(moss, 0.0, 1.0);
	vec3 stone = vec3(0.17, 0.18, 0.16) * (0.6 + 0.7 * cr.z) * (0.8 + 0.4 * svn(p * 18.0));
	alb = mix(stone, vec3(0.05, 0.16, 0.06) * (0.7 + 0.6 * svn(p * 40.0)), moss);
	vec2 mc = floor(p * 0.9);
	vec2 mo = vec2(hash(mc), hash(mc + 9.0)) * 0.7 + 0.15;
	float md = length(fract(p * 0.9) - mo);
	float mush = step(0.72, hash(mc + 3.0)) * sstep(2.0, 2.6, r);
	emi += vec3(0.2, 1.0, 0.65) * mush * (sstep(0.045, 0.025, md) * 1.8 + exp(-md * 7.0) * 0.3) * (0.75 + 0.25 * sin(TIME * 1.3 + hash(mc) * 20.0));
	rough = mix(0.75, 0.95, moss);

#elif FLOOR_STYLE == 8
	// Crystal Cavern: clear ice over glowing veins
	vec3 cr = scells(p * 0.8 + 2.0);
	float vein = pow(1.0 - abs(sfbm(p * 0.7 + 5.0) - 0.5) * 2.0, 10.0);
	alb = vec3(0.03, 0.06, 0.1) + vec3(0.2, 0.35, 0.45) * aline(cr.y, 0.005) * 0.6;
	emi += mix(vec3(0.1, 0.8, 1.0), vec3(0.7, 0.3, 1.0), svn(p * 0.4)) * vein * 0.28 * (0.8 + 0.2 * sin(TIME * 0.7 + r));
	rough = 0.08;
	mirror = 0.7;
	wobble = (vec2(svn(p * 2.0), svn(p * 2.0 + 30.0)) - 0.5) * 0.04;
	far_a = 6.0;
	far_b = 22.0;

#elif FLOOR_STYLE == 9
	// Sky Temple: a round marble terrace with gold inlay, above the clouds
	if (r > 3.9) {
		discard;
	}
	float ang = atan(p.y, p.x);
	float vein = pow(1.0 - abs(sfbm(p * 1.1 + sfbm(p * 0.5) * 2.5) - 0.5) * 2.0, 6.0);
	alb = mix(vec3(0.5, 0.49, 0.46), vec3(0.22, 0.22, 0.25), vein * 0.75);
	float chk = step(0.5, fract(ang / S_TAU * 12.0));
	float band = step(3.05, r) * step(r, 3.6);
	alb = mix(alb, mix(vec3(0.07, 0.1, 0.19), vec3(0.5, 0.49, 0.46), chk) * (0.9 + 0.2 * vein), band);
	float gold = max(max(aline(r - 3.05, 0.02), aline(r - 3.6, 0.02)), aline(r - 3.84, 0.03));
	gold = max(gold, aline((fract(ang / S_TAU * 12.0) - 0.5) * r * 0.5236, 0.012) * band);
	alb = mix(alb, vec3(0.95, 0.68, 0.25), gold);
	metal = gold;
	rough = mix(0.22, 0.3, gold);
	mirror = 0.22;
	far_a = 1000.0;
	far_b = 2000.0;

#elif FLOOR_STYLE == 10
	// Synth Horizon: a black mirror with a neon grid
	float g1 = max(abs(fract(p.x) - 0.5), abs(fract(p.y) - 0.5));
	float line = aline(g1 - 0.5, 0.014);
	float g4 = max(abs(fract(p.x * 0.25) - 0.5), abs(fract(p.y * 0.25) - 0.5)) * 4.0;
	float line4 = aline(g4 - 2.0, 0.035);
	float wave = 0.65 + 0.35 * sin(r * 1.6 - TIME * 1.8);
	vec3 nc = mix(vec3(1.0, 0.1, 0.75), vec3(0.1, 0.85, 1.0), sstep(2.0, 14.0, r));
	alb = vec3(0.012, 0.0, 0.03);
	emi += nc * (line * 1.5 * wave + line4 * 1.4);
	rough = 0.12;
	mirror = 0.55;
	far_a = 14.0;
	far_b = 40.0;
#endif

#if SCENE_STYLE != 0
	if (mirror * mirror_k > 0.001) {
		vec3 rd = normalize(reflect(view, normalize(vec3(wobble.x, 1.0, wobble.y))));
		rd.y = abs(rd.y);
		float fres = 0.3 + 0.7 * pow(1.0 - clamp(-view.y, 0.0, 1.0), 3.0);
		emi += scene_backdrop(rd, TIME) * mirror * fres;
	}
	float far = sstep(far_a, far_b, r);
	alb = mix(alb, vec3(0.0), far);
	emi = mix(emi, ground, far * (1.0 - step(0.5, mirror)));   // a mirror keeps mirroring all the way out
	rough = mix(rough, 1.0, far);
	SPECULAR = mix(0.4, 0.12, step(0.3, mirror)) * (1.0 - far);   // a mirror floor already shows the lamp's surroundings
#else
	SPECULAR = 0.4;
#endif
	ALBEDO = alb;
	EMISSION = emi;
	ROUGHNESS = rough;
	METALLIC = metal;
}
