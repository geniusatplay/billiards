shader_type spatial;
// Billiard cloth: fibre noise, soft centre light pool, head string and spots.
// Special tables add a quiet pattern to the cloth (FELT_FX below; TableView makes one shader copy per pattern).
// The patterns stay faint on purpose: the balls must always read clearly against the cloth.
#define FELT_FX 0
uniform vec3 felt_color : source_color = vec3(0.06, 0.42, 0.31);
uniform vec2 half_size = vec2(1.12, 0.56);
uniform float marks = 1.0;
uniform vec3 felt2 : source_color = vec3(0.0, 0.0, 0.0);   // the pattern's colour
varying vec3 lpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() { lpos = VERTEX; }

void fragment() {
	vec2 p = lpos.xz;
	float n = vnoise(p * 260.0) * 0.45 + vnoise(p * 700.0) * 0.35 + vnoise(p * 40.0) * 0.20;
	float nap = vnoise(vec2(p.x * 30.0, p.y * 900.0)) * 0.5;
	vec3 col = felt_color * 0.82 * (0.90 + 0.14 * n + 0.04 * nap);
	vec2 q = p / max(half_size * 1.15, vec2(0.01));
	float d = length(q);
	col *= mix(1.10, 0.80, smoothstep(0.15, 1.25, d));
	if (marks > 0.5 && abs(p.x) <= half_size.x && abs(p.y) <= half_size.y) {
		float hx = -half_size.x * 0.5;
		float hs = 1.0 - smoothstep(0.0009, 0.0018, abs(p.x - hx));
		col = mix(col, col * 1.45 + vec3(0.03), hs * 0.35);
		float sp = 0.0;
		sp = max(sp, 1.0 - smoothstep(0.0045, 0.0062, length(p - vec2(half_size.x * 0.5, 0.0))));
		sp = max(sp, 1.0 - smoothstep(0.0045, 0.0062, length(p - vec2(hx, 0.0))));
		sp = max(sp, 1.0 - smoothstep(0.0030, 0.0042, length(p)));
		col = mix(col, vec3(0.86, 0.9, 0.86), sp * 0.7);
	}
	vec3 glow = vec3(0.0);
#if FELT_FX == 1
	{	// night sky: fine stars and a faint haze
		float st = pow(vnoise(p * 420.0), 18.0) * 30.0;
		float haze = vnoise(p * 3.0 + 7.0) * vnoise(p * 7.0);
		col += felt2 * haze * 0.2;
		glow = vec3(st) * 0.3 + felt2 * haze * 0.07;
	}
#elif FELT_FX == 2
	{	// a grid of light
		vec2 g = abs(fract(p / 0.14) - 0.5);
		float ln = 1.0 - smoothstep(0.006, 0.016, 0.5 - max(g.x, g.y));
		col += felt2 * ln * 0.12;
		glow = felt2 * ln * 0.22;
	}
#elif FELT_FX == 3
	{	// embers: slow glowing veins
		float v = vnoise(p * 9.0) * 0.6 + vnoise(p * 21.0) * 0.4;
		float vein = pow(1.0 - abs(v * 2.0 - 1.0), 9.0);
		glow = felt2 * vein * 0.3 * (0.7 + 0.3 * sin(TIME * 0.9 + v * 20.0));
		col = col * (0.85 + 0.15 * vein) + felt2 * vein * 0.1;
	}
#elif FELT_FX == 4
	{	// light through water
		float c = 1.0 - abs(sin(p.x * 14.0 + vnoise(p * 5.0 + TIME * 0.15) * 6.0) * sin(p.y * 14.0 + vnoise(p * 5.0 - TIME * 0.12 + 3.0) * 6.0));
		c = pow(c, 6.0);
		col += felt2 * c * 0.13;
		glow = felt2 * c * 0.05;
	}
#elif FELT_FX == 5
	{	// diamond weave, tone on tone
		vec2 q2 = p / 0.1;
		float ch = mod(floor(q2.x + q2.y) + floor(q2.x - q2.y), 2.0);
		col *= mix(0.955, 1.045, ch);
	}
#elif FELT_FX == 6
	{	// frost
		float f = pow(vnoise(p * 34.0), 3.0) + pow(vnoise(p * 120.0), 6.0) * 1.5;
		col += felt2 * f * 0.2;
		glow = felt2 * pow(vnoise(p * 300.0), 20.0) * 4.0;
	}
#elif FELT_FX == 7
	{	// a slow vortex from the centre spot
		float rr = length(p);
		float arm = smoothstep(0.5, 1.0, sin(atan(p.y, p.x) * 3.0 + rr * 9.0 - TIME * 0.5));
		col += felt2 * arm * 0.08;
		glow = felt2 * arm * 0.1 * (1.0 - smoothstep(0.0, 1.4, rr));
	}
#endif
	ALBEDO = col;
	EMISSION = glow * marks;
	ROUGHNESS = 0.94;
	SPECULAR = 0.12;
}
