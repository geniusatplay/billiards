shader_type spatial;
// One shader for every special ball set. The ball's colour, number and stripe come in as parameters and
// BALL_STYLE picks the look, so a new set costs no textures. Solids and stripes stay easy to tell apart in
// every style: the pattern covers a solid ball and only the band of a striped one. The cue ball always has
// a light body, so it can never be mistaken for the 8.
// BallView makes one copy of this shader per style and changes the number on the next line, so a phone
// only compiles the look that is on the table.
#define BALL_STYLE 0
#include "res://src/game/shaders/noise.gdshaderinc"

uniform int number = 1;            // 0 = cue ball
uniform bool striped = false;
uniform vec3 col : source_color = vec3(0.95, 0.75, 0.1);    // this ball's colour (cue ball: the set's accent)
uniform vec3 base : source_color = vec3(0.96, 0.95, 0.92);  // the "white" of the set
uniform vec3 col2 : source_color = vec3(0.0, 0.0, 0.0);     // second colour of the set (veins, glow, gold...)
uniform vec3 disc : source_color = vec3(0.97, 0.96, 0.94);  // number plate
uniform vec3 ink : source_color = vec3(0.07, 0.07, 0.09);   // number
uniform float rough = 0.1;
uniform float metal = 0.0;
uniform float glow = 0.0;          // strength of the style's light
uniform float ink_glow = 0.0;      // > 0: the number itself glows
uniform sampler2D glyphs : filter_linear_mipmap, repeat_disable;

varying vec3 dpos;
varying vec3 opos;     // (the see-through styles: where this point is, and the camera, in the ball's own space)
varying vec3 ocam;

#if BALL_STYLE == 24
// football: the twelve pentagon centres, then the twenty hexagon centres
const vec3 FOOTBALL[32] = {
	vec3(0.00000, -0.52573, -0.85065), vec3(-0.52573, -0.85065, 0.00000), vec3(-0.85065, 0.00000, -0.52573),
	vec3(0.00000, -0.52573, 0.85065), vec3(-0.52573, 0.85065, 0.00000), vec3(0.85065, 0.00000, -0.52573),
	vec3(0.00000, 0.52573, -0.85065), vec3(0.52573, -0.85065, 0.00000), vec3(-0.85065, 0.00000, 0.52573),
	vec3(0.00000, 0.52573, 0.85065), vec3(0.52573, 0.85065, 0.00000), vec3(0.85065, 0.00000, 0.52573),
	vec3(-0.57735, -0.57735, -0.57735), vec3(0.00000, -0.93417, -0.35682), vec3(-0.35682, 0.00000, -0.93417),
	vec3(0.35682, 0.00000, -0.93417), vec3(0.57735, -0.57735, -0.57735), vec3(-0.93417, -0.35682, 0.00000),
	vec3(0.00000, -0.93417, 0.35682), vec3(-0.57735, -0.57735, 0.57735), vec3(-0.57735, 0.57735, -0.57735),
	vec3(-0.93417, 0.35682, 0.00000), vec3(0.57735, -0.57735, 0.57735), vec3(-0.35682, 0.00000, 0.93417),
	vec3(0.35682, 0.00000, 0.93417), vec3(0.00000, 0.93417, -0.35682), vec3(-0.57735, 0.57735, 0.57735),
	vec3(0.00000, 0.93417, 0.35682), vec3(0.57735, 0.57735, -0.57735), vec3(0.93417, -0.35682, 0.00000),
	vec3(0.93417, 0.35682, 0.00000), vec3(0.57735, 0.57735, 0.57735)
};
#endif

void vertex() {
	dpos = normalize(VERTEX);
#if BALL_STYLE == 19 || BALL_STYLE == 22
	opos = VERTEX;
	ocam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
#endif
}

float line(float x, float w) {
	float f = abs(fract(x) - 0.5);
	return 1.0 - sstep(w, w + 0.02, f);
}

void fragment() {
	vec3 d = normalize(dpos);
	float lat = asin(clamp(d.y, -1.0, 1.0));
	float lon = atan(d.z, d.x);
	float band = clamp((radians(33.0) - abs(lat)) / 0.02 + 0.5, 0.0, 1.0);
	// k = how much of this spot belongs to the ball's colour (1 = coloured, 0 = the set's white)
	float k = striped ? band : 1.0;
	bool cue = number == 0;
	if (cue) {
		k = 0.0;
	}
	vec3 a = mix(base, col, k);
	vec3 e = vec3(0.0);
	float m = metal;
	float r = rough;
	float spec = 0.6;
	float rim = 0.12;
	float mirror = 0.0;      // how strongly the ball mirrors the room (metals)
	float t = TIME;

#if BALL_STYLE == 2
	{            // marble: dark veins in the white, pale veins in the colour
		float n = fbm3(d * 3.0);
		float v = pow(1.0 - abs(sin((d.x + d.y * 0.6 + d.z * 0.3) * 5.0 + n * 7.0)), 6.0);
		float v2 = pow(1.0 - abs(sin((d.z - d.x * 0.5 + d.y * 0.8) * 9.0 + n * 11.0)), 10.0) * 0.5;
		vec3 vein = mix(vec3(0.2, 0.19, 0.22), mix(col2, col, 0.25), k);
		a = mix(a, vein, clamp(v * 0.8 + v2, 0.0, 0.85));
		a *= 0.88 + 0.24 * n;
	}
#elif BALL_STYLE == 3
	{     // turned wood
		float n = fbm3(d * vec3(2.0, 9.0, 2.0));
		float ring = 0.5 + 0.5 * sin((d.y * 14.0 + n * 3.0) * 3.14159);
		vec3 wood = mix(base * 0.72, base, ring);
		a = mix(wood, col * (0.7 + 0.3 * ring), k * 0.88);
		r = 0.28;
	}
#elif BALL_STYLE == 4
	{     // carbon fibre (the cue ball is woven in silver)
		vec2 uv = vec2(lon * 9.0, lat * 18.0);
		float w = step(0.5, fract(uv.x + floor(uv.y) * 0.5));
		float sheen = 0.5 + 0.5 * sin(fract(uv.y) * 6.2832);
		float weave = mix(sheen, 1.0 - sheen, w);
		vec3 fibre = base * (0.45 + 0.75 * weave) + vec3(0.02);
		a = mix(fibre, col * (0.5 + 0.5 * weave), k);
		r = 0.22;
		m = 0.35;
		mirror = 0.35;
	}
#elif BALL_STYLE == 5
	{     // chrome: a coloured mirror
		m = 1.0;
		r = 0.1 + 0.04 * vnoise3(d * 40.0);
		a = mix(a, vec3(1.0), 0.12);
		mirror = 1.0;
		rim = 0.0;
	}
#elif BALL_STYLE == 6
	{     // candy swirl
		float s = sin(lon * 5.0 + d.y * 7.0);
		float c = sstep(-0.08, 0.08, s);
		a = mix(base, mix(col * 0.92, base, c * 0.9), k);
		r = 0.06;
	}
#elif BALL_STYLE == 7
	{     // gas giant
		float warp = fbm3(d * 2.2) * 1.6;
		float b = sstep(0.22, 0.78, fbm3(vec3(d.x * 1.2, d.y * 9.0 + warp, d.z * 1.2)));
		float storm = sstep(0.7, 0.8, fbm3(d * 5.0 + 4.0));
		vec3 planet = mix(col * 0.3, mix(col, col2, 0.3), b);
		planet = mix(planet, col2, storm * 0.7);
		float crater = sstep(0.62, 0.7, fbm3(d * 6.0 + 9.0));
		a = mix(base * (0.72 + 0.28 * b) * (1.0 - 0.3 * crater), planet, k);
		r = 0.5;
		spec = 0.3;
	}
#elif BALL_STYLE == 8
	{     // neon grid (cue ball: white with the set's colour as its grid)
		float g = max(line(lon * 12.0 / 6.2832 * 2.0, 0.035), line(lat * 12.0 / 3.14159, 0.05));
		float pulse = 0.85 + 0.15 * sin(t * 2.0 + lat * 6.0);
		if (cue) {
			a = mix(base * 0.8, col, g);
			e = col * g * glow * 0.45 * pulse;
		} else {
			vec3 lc = mix(base * 0.22, col, k);
			a = vec3(0.012, 0.014, 0.022) + lc * g * 0.5;
			e = lc * g * glow * pulse;
		}
		r = 0.18;
	}
#elif BALL_STYLE == 9
	{     // galaxy (cue ball: a pale moon-white with a violet haze)
		float n = fbm3(d * 2.4 + 3.0);
		float n2 = fbm3(d * 4.5 - 2.0);
		float stars = pow(vnoise3(d * 70.0), 22.0) * 40.0;
		if (cue) {
			a = mix(vec3(0.8, 0.84, 0.95), col * 0.85, sstep(0.45, 0.8, n) * 0.8);
			e = (col * sstep(0.55, 0.9, n2) * 0.25 + vec3(stars) * 0.12) * glow;
		} else {
			vec3 neb = col * sstep(0.35, 0.8, n) + col2 * sstep(0.5, 0.9, n2) * 0.8;
			a = vec3(0.01, 0.012, 0.03) + neb * 0.25 * k;
			e = (neb * k + vec3(stars) * (0.4 + 0.6 * k)) * glow;
		}
		r = 0.08;
	}
#elif BALL_STYLE == 10
	{    // cut gemstone
		vec3 c = cells3(d * 3.2);
		float facet = 0.55 + 0.45 * c.z;
		float edge = 1.0 - sstep(0.0, 0.04, c.y);
		vec3 gem = col * facet + vec3(1.0) * edge * 0.35;
		a = mix(base * (0.75 + 0.25 * c.z), gem, k);
		e = col * k * (0.12 + 0.5 * pow(c.z, 6.0)) * glow;
		r = 0.03;
		m = 0.15;
		mirror = 0.25;
	}
#elif BALL_STYLE == 11
	{    // dragon scales
		vec2 uv = vec2(lon * 7.0 / 3.14159, lat * 9.0 / 3.14159 * 2.0);
		uv.x += 0.5 * mod(floor(uv.y), 2.0);
		vec2 f = fract(uv) - vec2(0.5, 0.0);
		float sc = sstep(0.62, 0.48, length(f * vec2(1.0, 0.85)));
		float rimline = sstep(0.38, 0.5, length(f * vec2(1.0, 0.85))) * sc;
		vec3 scale_c = mix(col * 0.25, col, sc) + col2 * rimline * 0.6;
		a = mix(base * (0.6 + 0.4 * sc), scale_c, k);
		m = 0.75;
		r = 0.28;
		mirror = 0.45;
	}
#elif BALL_STYLE == 12
	{    // molten: dark rock, cracks glowing in the ball's colour (cue ball: pale ash, orange cracks)
		vec3 c = cells3(d * 2.6 + fbm3(d * 3.0) * 0.5);
		float crack = 1.0 - sstep(0.0, 0.13, c.y);
		float core = 1.0 - sstep(0.0, 0.035, c.y);
		float heat = 0.75 + 0.25 * sin(t * 1.6 + c.z * 12.0);
		vec3 rock = vec3(0.03, 0.026, 0.026) * (0.5 + 0.9 * c.z);
		vec3 ash = vec3(0.5, 0.47, 0.43) * (0.55 + 0.6 * c.z);
		a = cue ? ash * 1.35 : mix(ash, rock, k);
		float lit = cue ? 0.7 : k;
		e = (col * pow(crack, 1.6) + mix(col, col2, 0.6) * core * 0.7) * heat * glow * lit;
		r = 0.85;
		spec = 0.12;
		rim = 0.0;
	}
#elif BALL_STYLE == 13
	{    // gold and enamel
		vec3 gold = col2;
		float lattice = max(line(lon * 8.0 / 3.14159 + lat * 3.0, 0.03), line(lon * 8.0 / 3.14159 - lat * 3.0, 0.03));
		float edge = 1.0 - sstep(0.0, 0.03, abs(abs(lat) - radians(33.0)));
		float is_gold = striped ? max(1.0 - band, edge) : lattice;
		if (cue) {
			is_gold = lattice;
			a = mix(base, gold, lattice);
		} else {
			a = mix(col, gold, is_gold);
		}
		m = mix(0.1, 1.0, is_gold);
		r = mix(0.05, 0.2, is_gold);
		mirror = is_gold;
	}
#elif BALL_STYLE == 14
	{    // storm (cue ball: a white cloud)
		float cl = fbm3(d * 2.5 + vec3(0.0, t * 0.05, 0.0));
		float bolt_n = fbm3(d * 3.5 + 11.0);
		float bolt = pow(1.0 - min(1.0, abs(bolt_n - 0.5) * 9.0), 6.0);
		float flick = step(0.35, fract(sin(floor(t * 9.0) * 12.9898 + float(number)) * 43758.5453));
		vec3 cloud = mix(vec3(0.03, 0.035, 0.06), vec3(0.22, 0.25, 0.34), cl);
		if (cue) {
			a = mix(vec3(0.5, 0.55, 0.66), vec3(0.92, 0.95, 1.0), cl);
			e = col * bolt * (0.45 + 0.55 * flick) * glow * 0.5;
		} else {
			a = mix(cloud, mix(cloud, col, 0.55), k);
			vec3 lc = mix(vec3(0.5, 0.6, 1.0) * 0.25, col, k);
			e = lc * bolt * (0.45 + 0.55 * flick) * glow;
		}
		r = 0.35;
	}
#elif BALL_STYLE == 15
	{    // vortex (cue ball: white with emerald arms)
		float pole = acos(clamp(abs(d.y), 0.0, 1.0));
		float s = sin(lon * 5.0 + pole * 9.0 - t * 1.4);
		float arm = sstep(0.1, 0.9, s);
		if (cue) {
			a = mix(vec3(0.86, 0.93, 0.9), col2, arm * 0.9);
			e = col * pow(arm, 3.0) * glow * 0.3;
		} else {
			a = mix(base * 0.08, mix(col2 * 0.12, col * 0.6, arm), k);
			e = col * pow(arm, 3.0) * glow * k;
		}
		r = 0.1;
	}

#elif BALL_STYLE == 16
	{	// watchers: every ball is an eye; the iris is the ball's colour (the number plates sit on its sides)
		float ang = acos(clamp(d.z, -1.0, 1.0));
		float iris_r = radians(34.0);
		float pupil_r = radians(11.0) * (1.0 + 0.16 * sin(t * 1.3 + float(number) * 1.7));
		float around = atan(d.y, d.x);
		float fib = 0.7 + 0.3 * sin(around * 38.0 + fbm3(d * 9.0) * 5.0);
		float iris = sstep(iris_r + 0.02, iris_r - 0.02, ang);
		float limbal = sstep(iris_r - 0.1, iris_r, ang) * iris;
		float pupil = sstep(pupil_r + 0.015, pupil_r - 0.015, ang);
		vec3 iris_c = col * fib * (1.0 - 0.65 * limbal) + col2 * pow(max(1.0 - ang / iris_r, 0.0), 3.0) * 0.45;
		float vn = fbm3(d * 5.0);
		float veins = pow(1.0 - abs(sin(around * 7.0 + vn * 9.0)), 30.0) * sstep(iris_r, radians(70.0), ang) * sstep(radians(115.0), radians(80.0), ang);
		vec3 sclera = mix(base, vec3(0.72, 0.1, 0.1), veins * 0.6);
		// solids: the whole eye in the ball's colour; stripes: white with a coloured band (clear of the iris)
		float near_iris = sstep(iris_r + 0.16, iris_r + 0.05, ang);
		float tint = striped ? band * (1.0 - near_iris) : (number == 8 ? 0.95 : 0.9);
		vec3 skin = cue ? sclera : mix(sclera, col * 0.85 + base * (number == 8 ? 0.0 : 0.15), tint);
		a = mix(skin, iris_c, iris);
		a = mix(a, vec3(0.008), pupil);
		e = iris_c * iris * (1.0 - pupil) * glow * 0.12;
		r = 0.07;
		spec = 0.75;
	}
#elif BALL_STYLE == 17
	{	// cathedral glass: leaded panes lit from inside
		vec3 c = cells3(d * 3.4);
		float lead = 1.0 - sstep(0.025, 0.065, c.y);
		float h = c.z;
		vec3 pane = mix(col * (0.55 + 0.6 * h), col2, sstep(0.78, 0.96, h) * 0.55);
		vec3 frost = base * (0.72 + 0.28 * h);
		vec3 glass = mix(frost, pane, k);
		a = mix(glass * 0.62, vec3(0.045, 0.045, 0.055), lead);
		e = glass * (1.0 - lead) * glow * (0.45 + 0.4 * fbm3(d * 2.0 + vec3(t * 0.15)));
		r = 0.1;
		spec = 0.65;
	}
#elif BALL_STYLE == 18
	{	// disco: little mirror tiles, each catching the light at its own moment
		vec2 uv = vec2(lon / 6.2832 * 26.0, lat / 3.14159 * 13.0);
		vec2 cell = floor(uv);
		vec2 f = fract(uv);
		float tile = sstep(0.05, 0.11, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		float h = h13(vec3(cell, float(number) + 3.0));
		vec3 tint = mix(base, col, k) * (0.82 + 0.3 * h);
		a = mix(vec3(0.05), tint, tile);
		m = tile;
		r = 0.05 + 0.08 * h;
		mirror = tile;
		float glint = step(0.965, fract(h * 7.3 + t * 0.45));
		e = mix(vec3(1.0), tint, 0.4) * glint * tile * glow;
		rim = 0.0;
	}
#elif BALL_STYLE == 19
	{	// lava lamp: warm wax drifting inside a glass ball (solids: coloured liquid; stripes: clear with a coloured band)
		float R = length(opos);
		vec3 p0 = opos / max(R, 1e-5);
		vec3 rd = normalize(opos - ocam);
		float chord = max(-2.0 * dot(p0, rd), 0.0);
		vec3 acc = vec3(0.0);
		float trans = 1.0;
		// the liquid is the ball's colour; the wax is a warm, lighter blob (stripes: clear liquid, coloured wax)
		vec3 wax_c = cue ? mix(col, vec3(1.0), 0.55) : min(col * 1.12 + vec3(0.06, 0.04, 0.0), vec3(1.0));
		vec3 liq_c = cue ? base : (striped ? mix(base, col * 0.5, band) : col * 0.42);
		for (int i = 0; i < 8; i++) {
			float s = (float(i) + 0.5) / 8.0 * chord;
			vec3 q = p0 + rd * s;
			vec3 flow = vec3(0.0, -t * 0.22, 0.0) + vec3(float(number) * 3.1);
			float n = vnoise3(q * vec3(1.5, 1.1, 1.5) + flow) * 0.7 + vnoise3(q * 3.0 + flow * 1.7) * 0.3;
			float blob = sstep(0.52, 0.62, n);
			acc += trans * blob * wax_c * (0.75 + 0.5 * n) * 0.45;
			trans *= 1.0 - blob * 0.5;
		}
		float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		a = liq_c * 0.22;
		e = (acc + liq_c * trans * 0.32) * glow + vec3(0.6) * pow(fres, 4.0) * 0.3;
		r = 0.03;
		spec = 0.85;
	}
#elif BALL_STYLE == 20
	{	// circuit board: copper traces, light pulses running along them
		vec2 uv = vec2(lon / 6.2832 * 16.0, lat / 3.14159 * 8.0);
		vec2 cell = floor(uv);
		vec2 f = fract(uv);
		float hc = h13(vec3(cell, 5.0));
		float trace_h = (1.0 - sstep(0.07, 0.11, abs(f.y - 0.5))) * step(0.35, hc);
		float trace_v = (1.0 - sstep(0.07, 0.11, abs(f.x - 0.5))) * step(hc, 0.65);
		float pad = (1.0 - sstep(0.13, 0.19, length(f - 0.5))) * step(0.78, hc);
		float tr = max(max(trace_h, trace_v), pad);
		float pulse = pow(fract(uv.x * 0.25 - t * 0.8 + hc), 10.0) * trace_h + pow(fract(uv.y * 0.25 - t * 0.6 + hc), 10.0) * trace_v;
		vec3 board = mix(base * 0.92, col * 0.5, k);
		a = mix(board, vec3(0.85, 0.58, 0.24), tr);
		m = tr * 0.9;
		r = mix(0.45, 0.2, tr);
		mirror = tr * 0.6;
		e = mix(col2, col, 0.4) * pulse * glow * (cue ? 0.5 : 1.0);
	}
#elif BALL_STYLE == 21
	{	// opal: flashes of colour that move as you look round the ball
		float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		vec3 c = cells3(d * 6.0);
		float hue = fract(c.z * 3.0 + fres * 1.5 + dot(d, vec3(0.3, 0.5, 0.2)));
		vec3 rainbow = 0.5 + 0.5 * cos(6.2832 * (hue + vec3(0.0, 0.33, 0.67)));
		float flash = sstep(0.3, 0.9, sin(c.z * 40.0 + fres * 9.0) * 0.5 + 0.5);
		vec3 body = mix(base * 0.85, col * 0.32, k);
		a = body + rainbow * flash * 0.3;
		e = rainbow * flash * glow * 0.35 * (0.5 + 0.5 * k);
		r = 0.07;
		spec = 0.75;
	}
#elif BALL_STYLE == 22
	{	// snow globe: a glass ball, a coloured core inside, snow drifting round it
		float R = length(opos);
		vec3 p0 = opos / max(R, 1e-5);
		vec3 rd = normalize(opos - ocam);
		float b = dot(p0, rd);
		float rc = 0.64;
		float disc_ = b * b - (1.0 - rc * rc);
		vec3 inner = base * 0.28;
		vec3 core_c = cue ? base : (striped ? base * 0.92 : col);
		if (disc_ > 0.0) {
			vec3 q = p0 + rd * (-b - sqrt(disc_));
			vec3 nq = normalize(q);
			float lit = 0.45 + 0.55 * max(dot(nq, normalize(vec3(0.3, 0.9, 0.3))), 0.0);
			float facets = 0.85 + 0.15 * cells3(nq * 4.0).z;
			inner = core_c * lit * facets;
		}
		float snow = 0.0;
		float chord = max(-2.0 * b, 0.0);
		for (int i = 0; i < 6; i++) {
			float s = (float(i) + 0.5) / 6.0 * chord;
			vec3 q = p0 + rd * s;
			snow += pow(vnoise3(q * 11.0 + vec3(0.0, t * 0.35, 0.0) + float(i) * 1.3), 30.0) * 1.6;
		}
		float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		a = base * 0.1 + col * band * 0.5 * (striped ? 1.0 : 0.0);
		e = (inner * 1.15 + vec3(snow)) * glow + vec3(0.7, 0.8, 0.95) * pow(fres, 3.0) * 0.4;
		r = 0.03;
		spec = 0.85;
	}
#elif BALL_STYLE == 23
	{	// kintsugi: glazed porcelain, broken and mended with gold
		vec3 w = d + (vec3(fbm3(d * 2.0), fbm3(d * 2.0 + 5.0), fbm3(d * 2.0 + 9.0)) - 0.5) * 0.35;
		vec3 c = cells3(w * 2.4);
		float crack = 1.0 - sstep(0.012, 0.032, c.y);
		vec3 glaze = mix(base, col, k) * (0.93 + 0.07 * fbm3(d * 8.0));
		glaze *= 1.0 - 0.12 * (1.0 - sstep(0.0, 0.03, cells3(d * 9.0).y));
		a = mix(glaze, col2, crack);
		m = crack;
		r = mix(0.08, 0.24, crack);
		mirror = crack;
	}
#elif BALL_STYLE == 24
	{	// football: twelve pentagons, twenty hexagons, stitched seams
		float best = 9.0;
		float second = 9.0;
		bool penta = false;
		for (int i = 0; i < 32; i++) {
			// the pentagons' edges lie closer to their centres (16.5 against 20.9 degrees)
			float sc = acos(clamp(dot(d, FOOTBALL[i]), -1.0, 1.0)) * (i < 12 ? 1.266 : 1.0);
			if (sc < best) {
				second = best;
				best = sc;
				penta = i < 12;
			} else if (sc < second) {
				second = sc;
			}
		}
		float seam = 1.0 - sstep(0.012, 0.03, second - best);
		vec3 panel;
		if (cue) {
			panel = penta ? mix(base, col, 0.6) : base;
		} else if (striped) {
			panel = penta ? col : mix(base, col, band * 0.85);
		} else {
			panel = penta ? col * 0.38 : col;
		}
		a = mix(panel, panel * 0.45, seam);
		r = 0.32;
		spec = 0.45;
	}
#elif BALL_STYLE == 25
	{	// wild: leopard rosettes on the solids, tiger stripes on the stripes, a snow leopard for the cue ball
		float fur = 0.9 + 0.12 * vnoise3(d * 140.0);
		if (striped) {
			float n = fbm3(d * vec3(3.0, 1.2, 3.0));
			float s = sin(lon * 7.0 + n * 7.0 + d.y * 2.0);
			float tiger = sstep(0.55, 0.78, s);
			a = mix(base, col, band) * fur;
			a = mix(a, col2, tiger * 0.9);
		} else {
			vec3 c = cells3(d * 5.5);
			float ring = sstep(0.24, 0.3, c.x) * sstep(0.47, 0.4, c.x);
			float inner = sstep(0.28, 0.2, c.x) * 0.25;
			vec3 coat = cue ? base : col;
			vec3 spot = cue ? vec3(0.35, 0.36, 0.4) : col2;
			a = mix(coat * fur, spot, ring * 0.92);
			a = mix(a, coat * 0.7, inner);
		}
		r = 0.72;
		spec = 0.22;
	}
#elif BALL_STYLE == 26
	{	// ink bloom: clouds of ink curling through milky water
		float n = fbm3(d * 2.0 + vec3(t * 0.05, 0.0, -t * 0.04));
		float n2 = fbm3(d * 4.0 + vec3(n * 2.0) + 7.0);
		float plume = sstep(0.42, 0.7, n2);
		vec3 dye = mix(col, col * 0.28, sstep(0.62, 0.92, n2));
		// solids: water dyed the ball's colour, darker ink curling through; stripes: the same in the band, clear caps
		float body_k = cue ? 0.0 : (striped ? band : 1.0);
		vec3 water = mix(base * 0.96, mix(base, col, number == 8 ? 0.95 : 0.8), body_k);
		a = mix(water, dye * mix(1.0, 0.55, body_k), plume * (cue ? 0.18 : mix(0.16, 1.0, body_k)));
		r = 0.08;
		spec = 0.65;
	}
#elif BALL_STYLE == 27
	{	// abyss: a deep-sea creature, veins of light pulsing through dark flesh
		vec3 c = cells3(d * 3.0 + fbm3(d * 2.0) * 0.6);
		float vein = 1.0 - sstep(0.0, 0.06, c.y);
		float pulse = 0.55 + 0.45 * sin(t * 2.0 - length(d.xz) * 6.0 + c.z * 6.28);
		vec3 flesh = cue ? base * 0.86 : mix(base * 0.5, col * 0.26, k);
		a = flesh + col * vein * 0.2;
		e = mix(col2, col, cue ? 0.6 : k) * vein * pulse * glow + col * 0.05 * k * glow;
		r = 0.24;
		spec = 0.6;
		rim = 0.5;
	}
#elif BALL_STYLE == 28
	{	// hologram: projected light, scanlines rolling, a flicker now and then
		float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float scan = 0.8 + 0.2 * sin(d.y * 70.0 - t * 6.0);
		float flick = 0.82 + 0.18 * step(0.92, fract(sin(floor(t * 12.0) * 78.233 + float(number)) * 43758.5453));
		vec3 lc = mix(base * 0.75, col, k);
		a = cue ? base * 0.6 : lc * 0.22;
		e = lc * (0.32 + 1.3 * pow(fres, 2.0)) * scan * flick * glow;
		r = 0.2;
		spec = 0.3;
	}
#elif BALL_STYLE == 29
	{	// origami: folded paper, flat facets catching the light, crisp creases
		vec3 c = cells3(d * 2.3);
		vec3 j = vec3(fract(c.z * 13.17), fract(c.z * 71.71), fract(c.z * 37.37)) - 0.5;
		vec3 fn = normalize(d + j * 0.55);
		NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(fn, 0.0))).xyz);
		float crease = 1.0 - sstep(0.0, 0.025, c.y);
		float paper = 0.94 + 0.06 * vnoise3(d * 90.0);
		a = mix(base, col, k) * paper;
		a = mix(a, a * 1.12 + 0.05, crease * 0.6);
		r = 0.85;
		spec = 0.25;
	}
#elif BALL_STYLE == 30
	{	// 8-bit: the ball drawn in chunky pixels
		vec2 uv = vec2(lon / 6.2832 * 20.0, lat / 3.14159 * 10.0);
		vec2 cell = floor(uv);
		vec2 f = fract(uv);
		float latc = (cell.y + 0.5) / 10.0 * 3.14159;
		float kk = cue ? 0.0 : (striped ? (abs(latc) < radians(33.0) ? 1.0 : 0.0) : 1.0);
		float shade = floor((0.55 + 0.45 * h13(vec3(cell, 3.0))) * 4.0) / 4.0;
		vec3 pc = mix(base, col, kk) * (0.72 + 0.34 * shade);
		float edge = 1.0 - sstep(0.06, 0.12, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		a = mix(pc, pc * 0.62, edge);
		r = 0.5;
		spec = 0.3;
	}
#elif BALL_STYLE == 31
	{	// fireworks: a night sky, bursts blooming and fading in the ball's colour
		vec3 sky = mix(vec3(0.015, 0.02, 0.05), col * 0.34, 0.75);     // a night sky in the ball's colour
		vec3 burst = vec3(0.0);
		float stars = pow(vnoise3(d * 60.0), 18.0) * 3.0;
		for (int i = 0; i < 4; i++) {
			float ph = t * 0.42 + float(i) * 0.25 + float(number) * 0.17;
			float cyc = floor(ph);
			float age = fract(ph);
			vec3 cdir = normalize(h33(vec3(cyc, float(i), float(number))) - 0.5);
			float ad = acos(clamp(dot(d, cdir), -1.0, 1.0));
			vec3 tang = normalize(d - cdir * dot(d, cdir) + vec3(1e-4));
			vec3 ref = normalize(cross(cdir, vec3(0.3, 1.0, 0.2)));
			float around = atan(dot(tang, cross(cdir, ref)), dot(tang, ref));
			float rays = pow(max(cos(around * 9.0), 0.0), 24.0);
			float shell = sstep(0.16, 0.0, abs(ad - age * 1.1)) * sstep(0.0, 0.08, ad);
			float sparks = shell * (0.45 + rays * 1.4) * (1.0 - age * 0.85);
			burst += mix(mix(col, vec3(1.0), 0.45), col2, float(i % 2) * 0.35) * sparks;
		}
		if (cue) {
			a = base * 0.9;
			e = burst * glow * 0.35;
		} else {
			a = mix(base * 0.92, sky, k);
			e = (burst + vec3(stars) * k) * glow * (0.25 + 0.75 * k) + col * 0.08 * k * glow;
		}
		r = 0.15;
	}
#elif BALL_STYLE == 32
	{	// digital rain: columns of falling digits in the ball's colour
		vec2 uv = vec2(lon / 6.2832 * 22.0, lat / 3.14159 * 13.0);
		float colx = floor(uv.x);
		float speed = 0.6 + 0.8 * h13(vec3(colx, 1.0, float(number)));
		float yy = uv.y + t * speed * 2.0;
		float celly = floor(yy);
		float trail = pow(fract(-celly * 0.07 + h13(vec3(colx, 2.0, 0.0)) + t * speed * 0.15), 3.0);
		float gid = floor(h13(vec3(colx, celly, floor(t * 3.0 + colx))) * 15.99);
		vec2 gcell = vec2(mod(gid, 4.0), floor(gid / 4.0));
		vec2 guv = clamp(vec2(fract(uv.x), 1.0 - fract(yy)), 0.05, 0.95);
		float gly = texture(glyphs, (gcell + guv) / 4.0).r;
		float lit = gly * trail;
		vec3 lc = mix(col, vec3(1.0), 0.4);
		if (cue) {
			a = base * 0.92;
			e = col * lit * glow * 0.3;
		} else {
			a = mix(base * 0.92, col * 0.3, k);     // a screen in the ball's colour, the digits brighter
			e = (lc * lit * 1.2 + col * 0.12) * glow * k + col * lit * glow * 0.25 * (1.0 - k);
		}
		r = 0.2;
	}
#elif BALL_STYLE == 33
	{	// damascus: folded steel in wavy layers, blued in the ball's colour
		float n = fbm3(d * 2.5);
		float layers = 0.5 + 0.5 * sin((d.y * 14.0 + n * 9.0 + sin(lon * 3.0) * 0.8) * 3.14159);
		vec3 steel_c = mix(vec3(0.2, 0.21, 0.24), vec3(0.78, 0.8, 0.83), layers);
		a = mix(steel_c, steel_c * col * 1.7, k * 0.85);
		m = 1.0;
		r = 0.2 + 0.1 * layers;
		mirror = 1.0;
		rim = 0.0;
	}
#elif BALL_STYLE == 34
	{	// tie-dye: a spiral of dye from the pole, white where the cloth was folded
		float pole = acos(clamp(d.y, -1.0, 1.0));
		float sp = sin(pole * 10.0 + lon * 2.0 + fbm3(d * 3.0) * 4.0);
		vec3 ty = mix(col, col * 0.5 + col2 * 0.12, sstep(-0.4, 0.4, sp));     // the ball's own colour, light and dark
		ty = mix(ty, base, sstep(0.82, 0.98, sp) * 0.45);
		a = mix(base * (0.92 + 0.08 * sp), ty, k);
		r = 0.32;
	}
#elif BALL_STYLE == 35
	{	// topographic: a map of hills, contour lines, the ball's colour as the land
		float hgt = fbm3(d * 2.2 + float(number) * 1.3);
		float f = fract(hgt * 14.0);
		float ln = 1.0 - sstep(0.05, 0.12, min(f, 1.0 - f));
		float major = step(4.5, mod(floor(hgt * 14.0), 5.0));
		vec3 land = mix(col * 0.62, col * 1.05, sstep(0.3, 0.8, hgt));
		a = mix(base, land, k);
		a = mix(a, mix(vec3(0.12, 0.1, 0.08), col * 0.35, k), ln * (0.55 + 0.4 * major));
		r = 0.55;
		spec = 0.3;
	}
#elif BALL_STYLE == 1
	{     // matte
		r = 0.62;
		spec = 0.35;
	}
#endif

	// cue ball: six small dots so its spin is readable (the patterned sets show spin by their pattern)
	if (cue && BALL_STYLE < 8) {
		vec3 ad = abs(d);
		float mx = max(ad.x, max(ad.y, ad.z));
		float dot_m = 1.0 - sstep(0.110, 0.125, acos(clamp(mx, -1.0, 1.0)));
		a = mix(a, col, dot_m);
	}

	// number plates on two opposite sides
	if (number > 0) {
		float sgn = d.x >= 0.0 ? 1.0 : -1.0;
		vec3 c = vec3(sgn, 0.0, 0.0);
		float dc = dot(d, c);
		float ang = acos(clamp(dc, -1.0, 1.0));
		float plate = clamp((radians(19.0) - ang) / 0.012 + 0.5, 0.0, 1.0);
		if (plate > 0.0) {
			vec3 east = vec3(0.0, 0.0, -sgn);
			float tr = tan(radians(19.0) * 0.8);
			vec2 g = vec2(dot(d, east), d.y) / max(dc, 0.001) / tr;
			vec2 guv = clamp(vec2(g.x, -g.y) * 0.5 + 0.5, 0.02, 0.98);
			vec2 cell = vec2(float(number % 4), float(number / 4));
			float s = texture(glyphs, (cell + guv) / 4.0).r;
			s *= step(abs(g.x), 1.0) * step(abs(g.y), 1.0);
			vec3 pc = mix(disc, ink, s);
			a = mix(a, pc, plate);
			e = mix(e, ink * s * ink_glow, plate);
			m = mix(m, 0.0, plate);
			r = mix(r, 0.12, plate);
			mirror *= 1.0 - plate;
		}
	}

	if (mirror > 0.0) {
		vec3 rv = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
		e += a * room_mirror(rv) * mirror;
	}

	ALBEDO = a;
	EMISSION = e;
	METALLIC = m;
	ROUGHNESS = r;
	SPECULAR = spec;
	RIM = rim;
	RIM_TINT = 0.8;
}
