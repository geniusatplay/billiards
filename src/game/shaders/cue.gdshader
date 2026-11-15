shader_type spatial;
// One shader paints every part of every cue. A cue model is split into slots (shaft, grip, blade, scales...)
// and a skin gives each slot two colours, a finish and a pattern. Patterns are worked out from the position
// on the cue itself (metres, Z runs from the tip to the butt), so the models need no texture coordinates.
// Cues.material() makes one copy of this shader per pattern and changes the number on the next line.
// (The reward packages are painted with the same shader: patterns 20-22 are made for them.)
#define CUE_FX 0
#include "res://src/game/shaders/noise.gdshaderinc"

uniform vec3 col : source_color = vec3(0.6, 0.4, 0.2);
uniform vec3 col2 : source_color = vec3(0.0, 0.0, 0.0);
uniform float metal = 0.0;
uniform float rough = 0.3;
uniform float glow = 0.0;      // strength of the pattern's own light
uniform float scale = 1.0;     // pattern size
uniform float za = 0.75;       // where a fade or the inlay points begin and end along the cue
uniform float zb = 1.05;

varying vec3 opos;

void vertex() {
	opos = VERTEX;
}

void fragment() {
	vec3 a = col;
	vec3 e = vec3(0.0);
	float m = metal;
	float r = rough;
	float spec = 0.5;
	float mirror = metal;
	float th = atan(opos.y, opos.x);
	float t = TIME;

#if CUE_FX == 0
	e = col * glow;
#elif CUE_FX == 1
	{	// wood grain
		float g = fbm3(vec3(opos.x * 70.0, opos.y * 70.0, opos.z * 4.0) * scale);
		float streak = 0.5 + 0.5 * sin((g * 6.0 + opos.z * 3.0) * 6.2832);
		a = mix(col, col2, streak * 0.65);
	}
#elif CUE_FX == 2
	{	// bands along the cue
		float b = sstep(0.42, 0.58, abs(fract(opos.z * 25.0 * scale) - 0.5) * 2.0);
		a = mix(col, col2, b);
		e = col2 * b * glow;
	}
#elif CUE_FX == 3
	{	// a stripe winding round the cue
		float s = fract(th / 6.2832 * 2.0 + opos.z * 9.0 * scale);
		float b = sstep(0.42, 0.58, abs(s - 0.5) * 2.0);
		a = mix(col, col2, b);
		e = col2 * b * glow;
	}
#elif CUE_FX == 4
	{	// scales
		vec3 c = cells3(opos * 260.0 * scale);
		float edge = 1.0 - sstep(0.0, 0.14, c.y);
		a = mix(col * (0.5 + 0.5 * c.z), col2, edge * 0.8);
		e = col2 * edge * glow;
	}
#elif CUE_FX == 5
	{	// cooling rock with glowing cracks, hotter towards the butt
		vec3 c = cells3(opos * 85.0 * scale + fbm3(opos * 60.0) * 0.5);
		float crack = 1.0 - sstep(0.0, 0.13, c.y);
		float core = 1.0 - sstep(0.0, 0.035, c.y);
		float heat = 0.75 + 0.25 * sin(t * 1.6 + c.z * 12.0);
		float ramp = 0.3 + 0.7 * sstep(0.1, 1.0, opos.z);
		a = col * (0.5 + 0.9 * c.z);
		e = (col2 * pow(crack, 1.6) + mix(col2, vec3(1.0, 0.95, 0.75), 0.55) * core * 0.6) * heat * glow * ramp;
		r = 0.85;
		spec = 0.15;
	}
#elif CUE_FX == 6
	{	// crawling lightning
		float n = fbm3(opos * 55.0 * scale + vec3(0.0, 0.0, t * 0.5));
		float bolt = pow(1.0 - min(1.0, abs(n - 0.5) * 8.0), 5.0);
		float flick = 0.6 + 0.4 * step(0.4, fract(sin(floor(t * 11.0) * 12.9898) * 43758.5453));
		e = col2 * bolt * flick * glow;
	}
#elif CUE_FX == 7
	{	// carbon fibre
		vec2 uv = vec2(th / 6.2832 * 16.0, opos.z * 230.0) * scale;
		float w = step(0.5, fract(uv.x + floor(uv.y) * 0.5));
		float sheen = 0.5 + 0.5 * sin(fract(uv.y) * 6.2832);
		a = col * (0.45 + 0.75 * mix(sheen, 1.0 - sheen, w)) + vec3(0.015);
	}
#elif CUE_FX == 8
	{	// marble
		float n = fbm3(opos * 40.0 * scale);
		float v = pow(1.0 - abs(sin(opos.z * 30.0 + th + n * 7.0)), 6.0);
		a = mix(col, col2, v * 0.8) * (0.88 + 0.24 * n);
	}
#elif CUE_FX == 9
	{	// crystal: lit from inside, brightest at the edges
		float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		float n = fbm3(opos * 45.0 * scale + vec3(0.0, 0.0, t * 0.04));
		a = col * (0.55 + 0.6 * n);
		e = col2 * (fr * 1.1 + pow(n, 3.0) * 0.9) * glow;
		spec = 0.9;
		mirror = max(mirror, 0.35);
	}
#elif CUE_FX == 10
	{	// galaxy
		float n = fbm3(opos * 28.0 * scale + 3.0);
		float n2 = fbm3(opos * 52.0 * scale - 2.0);
		float stars = pow(vnoise3(opos * 900.0), 22.0) * 40.0;
		vec3 neb = col * sstep(0.35, 0.8, n) + col2 * sstep(0.5, 0.9, n2) * 0.8;
		a = vec3(0.01, 0.012, 0.03) + neb * 0.2;
		e = (neb + vec3(stars)) * glow;
	}
#elif CUE_FX == 11
	{	// holographic foil: the colour depends on the angle you see it from
		float h = fract(dot(NORMAL, VIEW) * 1.2 + opos.z * 2.5 * scale + th * 0.16 + t * 0.04);
		vec3 rainbow = clamp(abs(fract(h + vec3(0.0, 0.667, 0.333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
		a = mix(col, rainbow, 0.75);
		e = rainbow * glow * 0.4;
	}
#elif CUE_FX == 12
	{	// glowing runes
		vec2 uv = vec2(th / 6.2832 * 6.0, opos.z * 60.0 * scale);
		vec2 id = floor(uv);
		vec2 f = fract(uv) - 0.5;
		float h = fract(sin(dot(id, vec2(127.1, 311.7))) * 43758.5453);
		float st = min(abs(f.x), abs(f.y - (h - 0.5) * 0.5));
		st = min(st, abs(f.x + f.y * (h * 2.0 - 1.0)));
		float mark = (1.0 - sstep(0.035, 0.075, st)) * step(max(abs(f.x), abs(f.y)), 0.34) * step(0.3, h);
		a = mix(col, col2 * 0.5, mark);
		e = col2 * mark * glow * (0.7 + 0.3 * sin(t * 2.0 + h * 20.0));
	}
#elif CUE_FX == 13
	{	// checker
		float ch = mod(floor(th / 6.2832 * 8.0) + floor(opos.z * 45.0 * scale), 2.0);
		a = mix(col, col2, ch);
	}
#elif CUE_FX == 14
	{	// fire or plasma: all light
		float n = fbm3(opos * 120.0 * scale - vec3(0.0, 0.0, t * 0.4));
		a = vec3(0.0);
		e = mix(col, col2, n) * glow * (0.82 + 0.18 * sin(t * 9.0 + opos.z * 300.0));
		spec = 0.0;
	}
#elif CUE_FX == 15
	{	// the classic inlay: four points running up the butt
		float u = clamp((zb - opos.z) / (zb - za), 0.0, 1.0);
		float w = abs(fract(th / 6.2832 * 4.0 + 0.5) - 0.5) * 2.0;
		float inside = (1.0 - sstep(0.0, 0.04, w - u * 0.62)) * step(za, opos.z) * step(opos.z, zb);
		float veneer = (1.0 - sstep(0.03, 0.07, abs(w - u * 0.62))) * step(za, opos.z) * step(opos.z, zb);
		a = mix(mix(col, col2, inside), vec3(0.9, 0.86, 0.75), veneer * 0.9);
	}
#elif CUE_FX == 16
	{	// a steady light with a slow pulse
		a = col * 0.25;
		e = col * glow * (0.82 + 0.18 * sin(t * 3.0 + opos.z * 20.0));
	}
#elif CUE_FX == 17
	{	// one colour fading into another along the cue (glow > 0: it glows softly in its own colour)
		a = mix(col, col2, sstep(za, zb, opos.z));
		e = a * glow * 0.6;
	}
#elif CUE_FX == 18
	{	// tiger stripes
		float n = fbm3(vec3(opos.x * 30.0, opos.y * 30.0, opos.z * 6.0));
		float s = sin(opos.z * 160.0 * scale + n * 14.0 + th * 1.5);
		a = mix(col, col2, sstep(0.2, 0.6, s));
	}
#elif CUE_FX == 19
	{	// vortex: glowing arms that keep winding
		float s = sin(th * 3.0 + opos.z * 60.0 * scale - t * 2.2);
		float arm = sstep(0.2, 0.95, s);
		a = mix(col, col2 * 0.3, arm * 0.5);
		e = col2 * pow(arm, 3.0) * glow;
	}
#elif CUE_FX == 20
	{	// sawn planks: long grain running along X (crates)
		float g = fbm3(vec3(opos.x * 2.5, opos.y * 55.0, opos.z * 55.0) * scale);
		float fine = vnoise3(vec3(opos.x * 9.0, opos.y * 260.0, opos.z * 260.0) * scale);
		a = mix(col, col2, clamp(g * 0.75 + fine * 0.3 - 0.1, 0.0, 1.0));
		spec = 0.25;
	}
#elif CUE_FX == 21
	{	// a block cut from a gemstone (packages): every facet its own shade, its edges lit from inside
		vec3 c = cells3(opos * 9.0 * scale);
		float edge = 1.0 - sstep(0.0, 0.035, c.y);
		a = mix(col, col2, 0.15 + 0.55 * pow(c.z, 1.6));
		float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		e = mix(col, col2, edge) * (edge * 1.6 + 0.35 + fr * 0.5) * glow;
		spec = 0.9;
		mirror = max(mirror, 0.3);
	}
#elif CUE_FX == 22
	{	// woven carbon fibre on flat panels (packages): a fine check turned 45 degrees
		vec3 q = vec3(opos.x * 0.7071 - opos.z * 0.7071, opos.y, opos.x * 0.7071 + opos.z * 0.7071) * 60.0 * scale;
		float ch = mod(floor(q.x) + floor(q.y) + floor(q.z), 2.0);
		a = mix(col, col2, ch);
		spec = 0.8;
	}
#endif

	if (mirror > 0.0) {
		vec3 rv = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
		e += a * room_mirror(rv) * mirror * 0.8;
	}
	ALBEDO = a;
	EMISSION = e;
	METALLIC = m;
	ROUGHNESS = r;
	SPECULAR = spec;
}
