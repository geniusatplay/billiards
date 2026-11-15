// Shared procedural building blocks for the cosmetic shaders (balls, cues, tables).

// smoothstep that is also defined when the first edge is the larger one (a falling ramp). GLSL leaves that
// case undefined for the built-in, and phone graphics drivers are entitled to return anything.
float sstep(float a, float b, float x) {
	float k = clamp((x - a) / (b - a), 0.0, 1.0);
	return k * k * (3.0 - 2.0 * k);
}
float h13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec3 h33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(h13(i), h13(i + vec3(1.0, 0.0, 0.0)), u.x), mix(h13(i + vec3(0.0, 1.0, 0.0)), h13(i + vec3(1.0, 1.0, 0.0)), u.x), u.y);
	float b = mix(mix(h13(i + vec3(0.0, 0.0, 1.0)), h13(i + vec3(1.0, 0.0, 1.0)), u.x), mix(h13(i + vec3(0.0, 1.0, 1.0)), h13(i + vec3(1.0, 1.0, 1.0)), u.x), u.y);
	return mix(a, b, u.z);
}

float fbm3(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise3(p);
		p = p * 2.03 + vec3(17.1, 3.7, 9.2);
		a *= 0.5;
	}
	return s / 0.9375;
}

// Cellular noise: x = distance to the nearest cell point, y = distance to the border, z = a random number per cell.
vec3 cells3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = h33(i + g);
				float d = length(g + o - f);
				if (d < d1) {
					d2 = d1;
					d1 = d;
					id = h13(i + g + 7.0);
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec3(d1, d2 - d1, id);
}

// What a polished ball or cue mirrors: the lamp over the table, a dim room, the cloth underneath. The renderer
// gives metals nothing to reflect, so without this chrome and gold come out black.
vec3 room_mirror(vec3 r) {
	float up = r.y;
	vec3 c = mix(vec3(0.04, 0.3, 0.19), vec3(0.15, 0.17, 0.23), sstep(-0.18, 0.04, up));
	c = mix(c, vec3(0.46, 0.5, 0.58), sstep(0.04, 0.62, up));
	float az = atan(r.z, r.x);
	c += vec3(0.5, 0.55, 0.65) * sstep(0.8, 0.97, sin(az * 3.0 + 0.6)) * sstep(0.04, 0.16, up) * (1.0 - sstep(0.3, 0.45, up));
	c += vec3(1.5, 1.4, 1.2) * sstep(0.9, 0.975, up);
	return c;
}
