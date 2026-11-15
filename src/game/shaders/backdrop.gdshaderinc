// The surroundings of the Studio scenes. One function gives the colour seen in a direction.
// The dome around the room draws it (backdrop.gdshader) and glossy floors mirror it (studio_floor.gdshader),
// so an icy lake really shows the aurora above it.
// What a player sees most is the band from a little below the horizon to about 25 degrees above it
// (the aim view looks along the table), so every scene puts its showpieces low on the horizon.
#include "noise.gdshaderinc"

const float S_TAU = 6.2831853;

float sh21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float svn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(sh21(i), sh21(i + vec2(1.0, 0.0)), u.x), mix(sh21(i + vec2(0.0, 1.0)), sh21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float sfbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * svn(p);
		p = p * 2.02 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return s / 0.9375;
}

// 2D cells: x = distance to the nearest point, y = distance to the border, z = a random number per cell.
vec3 scells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(sh21(i + g), sh21(i + g + 17.3));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = sh21(i + g + 5.1);
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d1, d2 - d1, id);
}

// Twinkling points on the sphere.
float sstars(vec3 d, float scale, float dens, float t) {
	vec3 p = d * scale;
	vec3 i = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = h13(i);
	vec3 o = (h33(i) - 0.5) * 0.7;
	float s = sstep(0.075, 0.0, length(f - o)) * step(1.0 - dens, h);
	return s * (0.55 + 0.45 * sin(t * (0.8 + h * 2.5) + h * 50.0));
}

// A skyline height that joins up all the way round (no seam): 0..1.
float sridge(vec2 c, float freq, float seed) {
	return sfbm(c * freq + seed);
}

float sang(vec3 d, vec3 c) {
	return acos(clamp(dot(d, c), -1.0, 1.0));
}

#if SCENE_STYLE == 1
// ---------------------------------------------------------------- 1. Orbit Station
vec3 sc_space(vec3 d, float t) {
	vec3 col = vec3(0.004, 0.006, 0.016);
	float n = fbm3(d * 2.1 + vec3(0.0, t * 0.004, 0.0));
	float n2 = fbm3(d * 3.7 + vec3(5.2, 1.3, 8.1));
	col += vec3(0.42, 0.08, 0.55) * pow(n, 3.0) * 1.5;
	col += vec3(0.04, 0.32, 0.6) * pow(n2, 3.5) * 1.5;
	float band = exp(-pow(dot(d, normalize(vec3(0.35, 0.8, 0.45))), 2.0) * 16.0);
	col += vec3(0.55, 0.5, 0.7) * band * (0.25 + 0.5 * n2) * 0.5;
	float st = sstars(d, 38.0, 0.16, t) + sstars(d, 71.0, 0.2, t) * 0.6 + sstars(d, 17.0, 0.05, t) * 1.6;
	col += vec3(0.95, 0.97, 1.0) * st * (1.0 + band * 2.0);
	vec3 sdir = normalize(vec3(0.62, 0.2, -0.75));
	float sa = sang(d, sdir);
	col += vec3(1.0, 0.9, 0.75) * (sstep(0.035, 0.028, sa) * 6.0 + exp(-sa * 9.0) * 0.9 + exp(-sa * 2.2) * 0.12);
	// a ringed giant low on the horizon
	vec3 mc = normalize(vec3(0.94, 0.14, 0.3));
	float ma = sang(d, mc);
	if (ma < 0.3) {
		vec3 mu = normalize(cross(mc, vec3(0.0, 1.0, 0.0)));
		vec3 mv = cross(mu, mc);
		vec2 mp = vec2(dot(d, mu), dot(d, mv)) / sin(0.085);
		vec2 rp = vec2(mp.x * 0.9 + mp.y * 0.436, -mp.x * 0.436 + mp.y * 0.9);
		float rr = length(vec2(rp.x, rp.y / 0.3));
		float ringm = sstep(1.35, 1.42, rr) * sstep(2.4, 2.3, rr) * (0.55 + 0.45 * sin(rr * 36.0)) * (1.0 - 0.8 * sstep(0.05, 0.0, abs(rr - 1.95)));
		bool inside = dot(mp, mp) < 1.0;
		if (inside) {
			float mz = sqrt(max(0.0, 1.0 - dot(mp, mp)));
			vec3 mn = normalize(mp.x * mu + mp.y * mv - mz * mc);
			float ml = clamp(dot(mn, sdir) * 1.2 + 0.25, 0.04, 1.0);
			float bands = 0.5 + 0.5 * sin(rp.y * 14.0 + fbm3(mn * 4.0) * 4.0);
			col = mix(vec3(0.72, 0.46, 0.28), vec3(0.95, 0.8, 0.6), bands) * ml;
		}
		if (!inside || rp.y < 0.0) {
			col = mix(col, vec3(0.9, 0.8, 0.65), ringm * 0.75);
		}
	}
	// the planet below the deck
	vec3 pc = normalize(vec3(-0.5, -0.62, -0.6));
	float R = 0.8;
	float a = sang(d, pc);
	if (a < R) {
		vec3 u = normalize(cross(pc, vec3(0.0, 1.0, 0.0)));
		vec3 v = cross(u, pc);
		vec2 p = vec2(dot(d, u), dot(d, v)) / sin(R);
		float z = sqrt(max(0.0, 1.0 - dot(p, p)));
		vec3 nrm = normalize(p.x * u + p.y * v - z * pc);
		float sp = t * 0.006;
		vec3 q = vec3(nrm.x * cos(sp) - nrm.z * sin(sp), nrm.y, nrm.x * sin(sp) + nrm.z * cos(sp));
		float land = fbm3(q * 2.6 + 3.0);
		float cloud = fbm3(q * 5.0 + vec3(0.0, 0.0, t * 0.004) + 11.0);
		vec3 surf = mix(vec3(0.02, 0.09, 0.28), vec3(0.08, 0.26, 0.12), sstep(0.5, 0.56, land));
		surf = mix(surf, vec3(0.42, 0.33, 0.2), sstep(0.62, 0.7, land));
		surf = mix(surf, vec3(0.95), sstep(0.52, 0.72, cloud) * 0.85);
		float lit = clamp(dot(nrm, sdir) * 1.3 + 0.3, 0.0, 1.0);
		vec3 pl = surf * lit * 1.3;
		float night = sstep(0.2, 0.0, lit);
		pl += vec3(1.0, 0.75, 0.4) * night * step(0.56, land) * step(0.7, vnoise3(q * 60.0)) * 0.7;
		pl += vec3(0.25, 0.55, 1.0) * pow(1.0 - z, 3.0) * (0.35 + lit) * 0.9;
		col = pl;
	} else {
		col += vec3(0.2, 0.5, 1.0) * exp(-(a - R) * 26.0) * 0.55;
	}
	return col;
}
#endif

#if SCENE_STYLE == 2
// ---------------------------------------------------------------- 2. Aurora Lake
vec3 sc_aurora(vec3 d, float t) {
	float el = d.y / max(length(d.xz), 0.0001);
	vec2 c = normalize(d.xz + vec2(0.00001, 0.0));
	float turn = atan(d.z, d.x) / S_TAU + 0.5;
	vec3 col = mix(vec3(0.05, 0.12, 0.2), vec3(0.008, 0.02, 0.06), sstep(0.0, 0.9, d.y));
	col += vec3(0.9, 0.95, 1.0) * (sstars(d, 40.0, 0.14, t) + sstars(d, 80.0, 0.18, t) * 0.5) * sstep(0.02, 0.3, d.y);
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.35);
		float wav = sfbm(vec2(uv.x * 0.8 + t * 0.02, uv.y * 0.8 - t * 0.013));
		float fold = sin(uv.x * 2.4 + wav * 7.0 + t * 0.06) * 0.5 + 0.5;
		float fold2 = sin(uv.y * 1.7 - wav * 6.0 - t * 0.045 + 2.0) * 0.5 + 0.5;
		float rays = svn(vec2((uv.x + uv.y) * 22.0 + wav * 6.0, t * 0.3)) * 0.6 + 0.4;
		float hgt = sstep(0.02, 0.2, d.y) * (1.0 - sstep(0.5, 0.97, d.y));
		float a1 = pow(fold, 5.0) * rays * hgt;
		float a2 = pow(fold2, 7.0) * rays * hgt;
		vec3 g = mix(vec3(0.1, 1.0, 0.45), vec3(0.45, 0.25, 1.0), sstep(0.15, 0.6, d.y));
		col += g * a1 * 1.7 + mix(vec3(0.1, 0.9, 0.8), vec3(0.9, 0.2, 0.7), sstep(0.1, 0.5, d.y)) * a2 * 1.2;
	}
	// a far snowy range, then near hills with pines
	float h1 = 0.04 + 0.26 * sridge(c, 2.2, 3.0) + 0.04 * svn(c * 14.0 + 8.0);
	if (el < h1) {
		float line = h1 - 0.1 - 0.06 * svn(c * 30.0 + 2.0);
		float snow = sstep(line, line + 0.035, el);
		float shade = 0.55 + 0.45 * sfbm(vec2(turn * 900.0, el * 26.0));
		col = mix(vec3(0.03, 0.055, 0.09) * (0.7 + 0.6 * shade), vec3(0.24, 0.44, 0.44) * shade, snow);
	}
	float h2 = 0.012 + 0.06 * sridge(c, 5.0, 21.0);
	float slot = turn * 260.0;
	float pine = (1.0 - abs(fract(slot) - 0.5) * 2.0) * 0.045 * step(0.3, sh21(vec2(floor(slot), 4.0))) * (0.5 + 0.5 * sh21(vec2(floor(slot), 9.0)));
	if (el < h2 + pine) {
		col = vec3(0.012, 0.03, 0.05);
	}
	return col;
}
#endif

#if SCENE_STYLE == 3
// ---------------------------------------------------------------- 3. Neon Skyline
vec3 sc_city(vec3 d, float t) {
	float el = d.y / max(length(d.xz), 0.0001);
	float turn = atan(d.z, d.x) / S_TAU + 0.5;
	vec3 haze = vec3(0.36, 0.09, 0.3);
	vec3 col = mix(haze, vec3(0.015, 0.01, 0.05), sstep(-0.02, 0.5, d.y));
	col += vec3(1.0, 0.45, 0.2) * exp(-max(d.y, 0.0) * 9.0) * 0.2;
	col += vec3(0.9, 0.9, 1.0) * sstars(d, 45.0, 0.1, t) * sstep(0.2, 0.6, d.y) * 0.7;
	float ma = sang(d, normalize(vec3(0.9, 0.3, -0.35)));
	col += vec3(1.0, 0.95, 0.85) * (sstep(0.05, 0.045, ma) * 1.6 + exp(-ma * 7.0) * 0.25);
	// three rows of towers, far to near; the roof we stand on is high up, so the near ones start far below
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float n = 150.0 - fk * 50.0;
		float x = turn * n;
		float id = floor(x);
		float fx = fract(x);
		float r = sh21(vec2(id, fk * 7.3 + 1.0));
		float h = (0.02 + 0.02 * fk) + (0.07 + 0.045 * fk) * r * r + 0.11 * step(0.94, r);
		float w = 0.62 + 0.36 * sh21(vec2(id, fk + 9.0));
		float foot = -0.06 - 0.22 * fk;
		if (abs(fx - 0.5) < w * 0.5 && el < h && el > foot) {
			vec3 body = mix(vec3(0.15, 0.06, 0.17), vec3(0.016, 0.016, 0.04), fk * 0.5);
			float cols = 4.0 + floor(sh21(vec2(id, 3.0)) * 5.0);
			float wx = (fx - 0.5) / w + 0.5;
			float rowh = 0.0042 + 0.0022 * fk;
			vec2 wc = vec2(floor(wx * cols), floor(el / rowh));
			vec2 wf = vec2(fract(wx * cols), fract(el / rowh));
			float lit = step(0.56, sh21(wc + id * 13.7 + fk * 31.0 + floor(t * 0.04 + sh21(wc + id) * 9.0)));
			float mask = step(0.22, wf.x) * step(wf.x, 0.78) * step(0.3, wf.y) * step(wf.y, 0.75);
			float hue = sh21(vec2(id, 5.0 + fk));
			vec3 wcol = hue < 0.55 ? vec3(1.0, 0.72, 0.38) : (hue < 0.8 ? vec3(0.3, 0.85, 1.0) : vec3(1.0, 0.35, 0.8));
			body += wcol * lit * mask * (0.45 + 0.2 * fk);
			float roof = sstep(0.004, 0.0, h - el) * step(0.5, sh21(vec2(id, 11.0 + fk)));
			body += (hue < 0.5 ? vec3(1.0, 0.1, 0.7) : vec3(0.1, 0.9, 1.0)) * roof * 2.2;
			// a red light blinking on the tallest masts
			float mast = step(0.94, r) * sstep(0.012, 0.0, length(vec2((fx - 0.5) * 0.25, el - h - 0.006)));
			body += vec3(2.5, 0.1, 0.1) * mast * step(0.5, fract(t * 0.5 + r * 7.0));
			col = mix(body, haze * 0.8, (1.0 - fk * 0.5) * 0.35);
		}
	}
	// the streets far below the roof
	if (d.y < -0.2) {
		vec2 g = d.xz / (-d.y);
		float dist = length(g);
		vec2 gp = g * 5.0;
		vec3 low = vec3(0.02, 0.014, 0.05);
		vec2 cell = floor(gp * 3.0);
		float dot_ = sstep(0.32, 0.08, length(fract(gp * 3.0) - 0.5)) * step(0.55, sh21(cell));
		float hue = sh21(cell + 3.0);
		vec3 lc = hue < 0.6 ? vec3(1.0, 0.75, 0.4) : (hue < 0.82 ? vec3(0.3, 0.85, 1.0) : vec3(1.0, 0.3, 0.75));
		low += lc * dot_ * 1.1;
		float av = sstep(0.07, 0.0, 0.5 - max(abs(fract(gp.x) - 0.5), abs(fract(gp.y) - 0.5)));
		low += vec3(1.0, 0.55, 0.2) * av * 0.6;
		col = mix(col, low, sstep(-0.2, -0.32, d.y));
	}
	return col;
}
#endif

#if SCENE_STYLE == 4
// ---------------------------------------------------------------- 4. Coral Deep
vec3 sc_reef(vec3 d, float t) {
	float el = d.y / max(length(d.xz), 0.0001);
	vec2 c = normalize(d.xz + vec2(0.00001, 0.0));
	float turn = atan(d.z, d.x) / S_TAU + 0.5;
	vec3 col = mix(vec3(0.03, 0.25, 0.32), vec3(0.06, 0.5, 0.62), sstep(0.0, 0.9, d.y));
	col = mix(col, vec3(0.0, 0.05, 0.1), sstep(0.0, -0.6, d.y));
	if (d.y > 0.05) {
		vec2 uv = d.xz / d.y;
		float rip = sfbm(uv * 1.3 + vec2(t * 0.08, t * 0.05));
		float rip2 = sfbm(uv * 2.9 - vec2(t * 0.06, t * 0.09));
		col += vec3(0.5, 0.9, 0.9) * pow(1.0 - abs(rip - rip2), 8.0) * sstep(0.1, 0.8, d.y) * 0.8;
	}
	float sh = svn(c * 3.0 + vec2(t * 0.03, d.y * 1.5)) * svn(c * 8.0 - vec2(d.y * 2.0, t * 0.05));
	col += vec3(0.25, 0.6, 0.55) * pow(sh, 1.3) * sstep(-0.12, 0.5, d.y) * 1.3;
	// rocks and coral heads on the sea floor
	float h1 = 0.02 + 0.2 * pow(sridge(c, 3.0, 5.0), 1.4) + 0.03 * svn(c * 20.0);
	if (el < h1) {
		float top = sstep(h1 - 0.05, h1, el);
		vec3 rock = mix(vec3(0.012, 0.11, 0.15), vec3(0.06, 0.32, 0.33), top * 0.8);
		float coral = step(0.6, svn(c * 9.0 + 2.0)) * top;
		rock = mix(rock, mix(vec3(0.5, 0.12, 0.22), vec3(0.55, 0.3, 0.08), svn(c * 30.0)), coral * 0.6);
		col = rock;
	}
	// kelp swaying
	float slot = turn * 120.0;
	float id = floor(slot);
	float hk = 0.12 + 0.4 * sh21(vec2(id, 2.0));
	float sway = sin(t * 0.8 + el * 9.0 + id) * 0.22 * clamp(el / hk, 0.0, 1.0);
	if (sh21(vec2(id, 6.0)) > 0.6 && el < hk && abs(fract(slot) - 0.5 - sway) < 0.16 * (1.0 - el / hk) + 0.03) {
		col = mix(vec3(0.01, 0.1, 0.07), vec3(0.04, 0.22, 0.12), sh21(vec2(id, 8.0)));
	}
	// a school of fish drifting past
	vec2 fp = vec2(turn * 46.0 + t * 0.1, el * 10.0);
	vec2 fi = floor(fp);
	vec2 ff = fract(fp) - 0.5;
	ff.y += 0.15 * sin(t * 0.6 + fi.x);
	if (sh21(fi + 40.0) > 0.86 && el > 0.05 && el < 0.7) {
		float body = sstep(0.5, 0.3, length(ff * vec2(1.5, 5.0)));
		float tail = sstep(0.26, 0.2, abs(ff.y) * 2.2 + (ff.x + 0.36) * 1.3) * step(ff.x, -0.2) * step(-0.42, ff.x);
		col = mix(col, vec3(0.0, 0.07, 0.11), max(body, tail) * 0.85);
	}
	return col;
}
#endif

#if SCENE_STYLE == 5
// ---------------------------------------------------------------- 5. Magma Forge
vec3 sc_volcano(vec3 d, float t) {
	float el = d.y / max(length(d.xz), 0.0001);
	float az = atan(d.z, d.x);
	vec2 c = vec2(cos(az), sin(az));
	float glow = exp(-max(el, 0.0) * 2.6);
	float ash = sfbm(c * 2.5 + vec2(el * 3.0, -t * 0.015));
	float ash2 = sfbm(c * 6.0 + vec2(el * 6.0 + 4.0, t * 0.02));
	vec3 col = mix(vec3(0.02, 0.01, 0.012), vec3(0.85, 0.2, 0.035), glow * (0.4 + 0.6 * ash));
	col *= 0.6 + 0.7 * ash2;
	float da = mod(az - 0.32 + 3.14159265, S_TAU) - 3.14159265;
	float cone = min(0.52 - abs(da) * 0.62, 0.4 + 0.015 * svn(vec2(da * 40.0, 1.0)));
	cone += 0.025 * (svn(vec2(da * 25.0, 7.0)) - 0.5);
	// smoke plume and the glow over the crater
	float cd = length(vec2(da, el - 0.43));
	float pl = sfbm(vec2(da * 6.0 + sin(el * 3.0) * 0.3, el * 4.0 - t * 0.07));
	float plume = sstep(0.38, 0.7, pl) * sstep(0.38, 0.5, el) * exp(-abs(da) * max(1.2, 5.0 - el * 3.0));
	col = mix(col, vec3(0.08, 0.045, 0.045) + vec3(0.9, 0.22, 0.04) * exp(-max(el - 0.4, 0.0) * 5.0), plume);
	col += vec3(1.0, 0.35, 0.05) * exp(-cd * 7.0) * 1.8;
	if (el < cone && abs(da) < 0.9) {
		vec3 rock = vec3(0.035, 0.02, 0.02) * (0.6 + 0.8 * svn(vec2(da * 30.0, el * 30.0)));
		float stream = svn(vec2(da * 22.0 + svn(vec2(el * 12.0, 2.0)) * 1.5, 5.0));
		float lava = sstep(0.6, 0.68, stream) * sstep(0.0, 0.18, el) * sstep(0.02, 0.1, cone - el + 0.05);
		float flow = 0.6 + 0.4 * sin(el * 60.0 + t * 1.5 + stream * 20.0);
		rock += vec3(2.4, 0.6, 0.07) * lava * flow;
		rock += vec3(0.9, 0.2, 0.03) * sstep(0.28, 0.42, el) * 0.5;
		col = rock;
	}
	float h2 = 0.008 + 0.07 * pow(sridge(c, 4.0, 2.0), 1.6) + 0.025 * svn(c * 26.0 + 4.0);
	if (el < h2) {
		float ember = step(0.78, svn(c * 60.0 + vec2(0.0, el * 90.0)));
		col = vec3(0.04, 0.022, 0.02) * (0.6 + 0.8 * svn(c * 40.0 + el * 30.0)) + vec3(0.7, 0.17, 0.03) * sstep(h2 - 0.012, h2, el) + vec3(1.6, 0.4, 0.05) * ember * 0.5 * sstep(0.0, 0.02, el);
	}
	return col;
}
#endif

#if SCENE_STYLE == 6
// ---------------------------------------------------------------- 6. Desert Dusk
vec3 sc_desert(vec3 d, float t) {
	float el = d.y / max(length(d.xz), 0.0001);
	float az = atan(d.z, d.x);
	vec2 c = vec2(cos(az), sin(az));
	vec3 col = mix(vec3(1.0, 0.48, 0.16), vec3(0.72, 0.22, 0.36), sstep(0.0, 0.22, el));
	col = mix(col, vec3(0.16, 0.1, 0.36), sstep(0.15, 0.6, el));
	col = mix(col, vec3(0.03, 0.03, 0.14), sstep(0.5, 1.6, el));
	col += vec3(1.0) * (sstars(d, 42.0, 0.13, t) + sstars(d, 80.0, 0.15, t) * 0.5) * sstep(0.35, 1.0, el);
	vec3 sdir = normalize(vec3(0.94, 0.085, -0.33));
	float a = sang(d, sdir);
	col += vec3(1.0, 0.72, 0.38) * (sstep(0.088, 0.08, a) * 3.0 + exp(-a * 5.0) * 0.7);
	float cl = sfbm(c * 3.0 + vec2(0.0, el * 18.0) + 3.0);
	col = mix(col, vec3(1.0, 0.5, 0.42), sstep(0.55, 0.8, cl) * sstep(0.07, 0.16, el) * (1.0 - sstep(0.3, 0.6, el)) * 0.6);
	float sun_side = max(dot(c, normalize(sdir.xz)), 0.0);
	// far dunes
	float h0 = 0.035 + 0.06 * svn(c * 1.6 + 2.0);
	if (el < h0) {
		col = vec3(0.6, 0.27, 0.2) + vec3(0.5, 0.22, 0.05) * sstep(h0 - 0.012, h0, el) * sun_side;
	}
	// three pyramids
	float dp = mod(az - 0.45 + 3.14159265, S_TAU) - 3.14159265;
	for (int k = 0; k < 3; k++) {
		float off = dp - (float(k) - 1.0) * 0.21;
		float hp = (k == 1 ? 0.2 : 0.14) * (1.0 - abs(off) / (k == 1 ? 0.17 : 0.12));
		if (el < hp) {
			col = off < hp * 0.25 - 0.02 ? vec3(0.8, 0.38, 0.2) : vec3(0.3, 0.11, 0.13);
		}
	}
	float h1 = 0.02 + 0.055 * svn(c * 2.6 + 7.0);
	if (el < h1) {
		col = vec3(0.5, 0.21, 0.15) + vec3(0.45, 0.2, 0.05) * sstep(h1 - 0.01, h1, el) * sun_side;
	}
	float h2 = 0.004 + 0.04 * svn(c * 4.0 + 12.0);
	if (el < h2) {
		col = vec3(0.42, 0.18, 0.12) + vec3(0.35, 0.16, 0.04) * sstep(h2 - 0.008, h2, el) * sun_side;
	}
	return col;
}
#endif

#if SCENE_STYLE == 7
// ---------------------------------------------------------------- 7. Firefly Grove
vec3 sc_jungle(vec3 d, float t) {
	float el = d.y / max(length(d.xz), 0.0001);
	vec2 c = normalize(d.xz + vec2(0.00001, 0.0));
	float turn = atan(d.z, d.x) / S_TAU + 0.5;
	vec3 mist = vec3(0.09, 0.3, 0.27);
	vec3 col = mix(mist, vec3(0.02, 0.09, 0.15), sstep(0.0, 0.7, d.y));
	col += vec3(0.8, 1.0, 0.9) * sstars(d, 40.0, 0.12, t) * sstep(0.15, 0.5, d.y) * 0.9;
	vec3 mdir = normalize(vec3(0.92, 0.3, 0.25));
	float ma = sang(d, mdir);
	col += vec3(0.85, 1.0, 0.82) * (sstep(0.1, 0.092, ma) * 2.2 + exp(-ma * 4.0) * 0.5 + exp(-ma * 1.5) * 0.15);
	// far trees, pale in the mist
	float n0 = sfbm(c * 7.0 + 1.0);
	float h0 = 0.16 + 0.24 * n0 + 0.03 * svn(c * 50.0);
	if (el < h0) {
		col = mix(vec3(0.05, 0.19, 0.17), mist, 0.45 * sstep(h0, 0.0, el));
	}
	// middle trees: crowns, and trunks rising to the canopy overhead
	float n1 = sfbm(c * 9.0 + 14.0);
	float h1 = 0.04 + 0.12 * n1 + 0.025 * svn(c * 64.0 + 3.0);
	float slot = turn * 54.0;
	float id = floor(slot);
	float tw = 0.06 + 0.09 * sh21(vec2(id, 3.0));
	float lean = (sh21(vec2(id, 5.0)) - 0.5) * 0.25 * el;
	bool trunk = sh21(vec2(id, 1.0)) > 0.55 && abs(fract(slot) - 0.5 - lean) < tw;
	float roofline = 0.62 - 0.3 * sfbm(c * 6.0 + 30.0) - 0.04 * svn(c * 44.0);
	if (el < h1 || trunk || el > roofline) {
		col = vec3(0.02, 0.085, 0.078);
		// moonlight catching one side of each trunk
		col += vec3(0.1, 0.22, 0.18) * float(trunk) * sstep(0.0, tw, fract(slot) - 0.5 - lean) * step(h1, el) * step(el, roofline);
	}
	col += mist * exp(-abs(el - 0.02) * 11.0) * (0.35 + 0.5 * sfbm(c * 3.0 + t * 0.01));
	// ferns in front
	float h2 = 0.01 + 0.045 * sfbm(c * 12.0 + 50.0) + 0.02 * abs(sin(turn * 900.0));
	if (el < h2) {
		col = vec3(0.008, 0.035, 0.03);
		// flowers that glow in the dark
		vec2 fc = vec2(turn * 420.0, el * 160.0);
		vec2 fi = floor(fc);
		float fr = sh21(fi + 2.0);
		float fd = length(fract(fc) - 0.5 - (vec2(sh21(fi + 7.0), sh21(fi + 11.0)) - 0.5) * 0.5);
		vec3 fcol = fr > 0.94 ? vec3(1.0, 0.3, 0.8) : vec3(0.2, 0.9, 1.0);
		col += fcol * step(0.86, fr) * sstep(0.3, 0.05, fd) * (0.8 + 0.4 * sin(t * 1.2 + fr * 60.0)) * 1.3;
	}
	// moonbeams slanting through the trees
	float beam = svn(vec2((turn - el * 0.35) * 46.0, 3.0)) * svn(vec2((turn - el * 0.35) * 17.0 + 5.0, t * 0.05));
	col += vec3(0.5, 0.9, 0.75) * pow(beam, 2.0) * sstep(0.0, 0.12, el) * sstep(0.75, 0.2, el) * exp(-ma * 1.1) * 0.9;
	float ff = sstars(vec3(d.x, d.y * 2.4, d.z), 21.0, 0.12, t * 2.2) * sstep(-0.08, 0.0, el) * sstep(0.5, 0.2, el);
	col += vec3(0.8, 1.0, 0.3) * ff * 2.2;
	return col;
}
#endif

#if SCENE_STYLE == 8
// ---------------------------------------------------------------- 8. Crystal Cavern
vec3 sc_cavern(vec3 d, float t) {
	float el = d.y / max(length(d.xz), 0.0001);
	float turn = atan(d.z, d.x) / S_TAU + 0.5;
	// the cave wall: facets of rock, some of them crystal
	vec3 cl = cells3(d * 11.0);
	float rock = fbm3(d * 9.0);
	vec3 col = vec3(0.05, 0.07, 0.13) * (0.45 + 0.9 * rock) * (0.55 + 0.9 * sstep(0.0, 0.3, cl.y));
	float is = step(0.8, cl.z);
	float pulse = 0.75 + 0.25 * sin(t * 0.6 + cl.z * 40.0);
	vec3 cc = mix(vec3(0.1, 0.9, 1.0), vec3(0.75, 0.25, 1.0), fract(cl.z * 7.0));
	cc = mix(cc, vec3(1.0, 0.3, 0.65), step(0.95, cl.z));
	float core = pow(max(0.0, 1.0 - cl.x * 1.4), 2.0);
	col += cc * is * (core * 1.5 + sstep(0.05, 0.0, cl.y) * 0.7 + 0.1) * pulse;
	// the opening far overhead
	float up = acos(clamp(d.y, -1.0, 1.0));
	float hole = sstep(0.42, 0.34, up + 0.07 * svn(d.xz * 5.0));
	col = mix(col, vec3(0.05, 0.12, 0.25) + vec3(1.0) * sstars(d, 40.0, 0.2, t), hole);
	col += vec3(0.25, 0.45, 0.7) * exp(-up * 2.2) * 0.2;
	// tall crystal shards standing round the cave floor, two rows
	for (int k = 0; k < 2; k++) {
		float fk = float(k);
		float slot = turn * (34.0 + fk * 23.0) + fk * 0.37;
		float id = floor(slot);
		float r = sh21(vec2(id, 3.0 + fk * 5.0));
		if (r > 0.42) {
			float hgt = (0.1 + 0.34 * sh21(vec2(id, 8.0 + fk))) * (1.0 - 0.45 * fk);
			float wid = 0.16 + 0.2 * sh21(vec2(id, 12.0 + fk));
			float lean = (sh21(vec2(id, 17.0 + fk)) - 0.5) * 0.9;
			float y = clamp(el / hgt, 0.0, 1.0);
			float xo = fract(slot) - 0.5 - lean * y * 0.4;
			float half = wid * (1.0 - y);                 // a tall thin triangle
			if (el < hgt && el > -0.05 && abs(xo) < half) {
				vec3 sc = mix(vec3(0.1, 0.85, 1.0), vec3(0.7, 0.3, 1.0), step(0.5, fract(r * 9.0)));
				sc = mix(sc, vec3(1.0, 0.35, 0.7), step(0.9, fract(r * 23.0)));
				float facet = step(0.0, xo) * 0.45 + 0.4;   // one face catches more light
				float edge = sstep(half * 0.8, half, abs(xo)) + sstep(0.03, 0.0, abs(xo));
				float glow = 0.35 + 0.65 * y;
				col = sc * (facet * glow * 0.75 + edge * 0.7) * (0.8 + 0.2 * sin(t * 0.8 + r * 30.0)) * (1.0 - 0.3 * fk);
			}
		}
	}
	return col;
}
#endif

#if SCENE_STYLE == 9
// ---------------------------------------------------------------- 9. Sky Temple
vec3 sc_clouds(vec3 d, float t) {
	float el = d.y / max(length(d.xz), 0.0001);
	float az = atan(d.z, d.x);
	vec2 c = vec2(cos(az), sin(az));
	vec3 sdir = normalize(vec3(0.85, 0.15, -0.5));
	float a = sang(d, sdir);
	vec3 haze = vec3(1.0, 0.72, 0.45);
	vec3 col = mix(haze, vec3(0.55, 0.6, 0.85), sstep(0.0, 0.3, d.y));
	col = mix(col, vec3(0.13, 0.28, 0.62), sstep(0.2, 0.9, d.y));
	col += vec3(1.0, 0.85, 0.6) * (sstep(0.06, 0.052, a) * 4.0 + exp(-a * 6.0) * 0.8 + exp(-a * 1.8) * 0.25);
	if (d.y > 0.02) {
		vec2 uv = d.xz / (d.y + 0.15);
		float ci = sfbm(uv * vec2(0.6, 2.2) + vec2(t * 0.01, 0.0));
		col = mix(col, vec3(1.0, 0.88, 0.8), sstep(0.5, 0.85, ci) * 0.45 * sstep(0.02, 0.2, d.y));
	}
	// peaks standing out of the cloud sea
	float hp = (sridge(c, 3.0, 12.0) - 0.47) * 0.75 + 0.025 * svn(c * 30.0);
	if (el < hp && el > -0.06) {
		float lit = max(dot(c, normalize(sdir.xz)), 0.0);
		float snowcap = sstep(hp - 0.05, hp - 0.01, el);
		col = mix(vec3(0.24, 0.25, 0.45), vec3(0.85, 0.52, 0.42), lit * 0.8);
		col = mix(col, vec3(1.0, 0.9, 0.85), snowcap * 0.6);
		col = mix(col, haze, 0.3);
	}
	if (d.y < 0.03) {
		float dep = max(-d.y + 0.03, 0.002);
		vec2 uv = d.xz / dep;
		float dist = length(uv);
		float dens = sfbm(uv * 0.5 + vec2(t * 0.012, t * 0.006)) * 0.65 + sfbm(uv * 1.7 + vec2(-t * 0.02, 7.0)) * 0.35;
		vec3 sea = mix(vec3(0.62, 0.42, 0.42), vec3(1.0, 0.9, 0.78), sstep(0.36, 0.62, dens));
		sea = mix(sea, vec3(0.42, 0.3, 0.42), sstep(0.4, 0.25, dens) * 0.8);   // gaps between the cloud tops
		sea *= 0.85 + 0.4 * max(dot(c, normalize(sdir.xz)), 0.0);
		col = mix(sea, haze, sstep(5.0, 36.0, dist));
	}
	return col;
}
#endif

#if SCENE_STYLE == 10
// ---------------------------------------------------------------- 10. Synth Horizon
vec3 sc_synth(vec3 d, float t) {
	float el = d.y / max(length(d.xz), 0.0001);
	float az = atan(d.z, d.x);
	float turn = az / S_TAU + 0.5;
	vec3 col = mix(vec3(0.78, 0.1, 0.55), vec3(0.16, 0.02, 0.3), sstep(0.0, 0.25, el));
	col = mix(col, vec3(0.02, 0.0, 0.07), sstep(0.15, 0.9, el));
	col += vec3(1.0, 0.9, 1.0) * (sstars(d, 40.0, 0.14, t) + sstars(d, 75.0, 0.14, t) * 0.5) * sstep(0.2, 0.7, el);
	vec3 sdir = normalize(vec3(1.0, 0.19, 0.0));
	float a = sang(d, sdir);
	float R = 0.27;
	col += vec3(1.0, 0.3, 0.6) * exp(-a * 3.2) * 0.4;
	if (a < R) {
		float yy = (d.y - sdir.y) / sin(R);
		vec3 sc = mix(vec3(1.0, 0.12, 0.55), vec3(1.0, 0.86, 0.2), sstep(-0.9, 0.8, yy));
		float cut = step(yy, 0.2) * step(fract(yy * 6.0 - t * 0.04), 0.18 + 0.45 * (0.2 - yy));
		col = mix(sc * 1.7, col, cut);
	}
	// wireframe mountains, lower in front of the sun
	float N = 44.0;
	float x = turn * N;
	float i = floor(x);
	float f = fract(x);
	float i2 = mod(i + 1.0, N);
	float gap0 = sstep(0.05, 0.16, abs(i / N - 0.5));
	float gap1 = sstep(0.05, 0.16, abs(i2 / N - 0.5));
	float ha = 0.015 + (0.03 + 0.2 * sh21(vec2(i, 2.0))) * gap0;
	float hb = 0.015 + (0.03 + 0.2 * sh21(vec2(i2, 2.0))) * gap1;
	float h = mix(ha, hb, f);
	if (el < h) {
		float edge = sstep(0.006, 0.0, h - el);
		float vert = sstep(0.03, 0.0, min(f, 1.0 - f));
		float lvl = el / max(h, 0.001);
		float inner = sstep(0.44, 0.49, abs(fract(lvl * 4.0) - 0.5)) * 0.45;
		float slant = sstep(0.45, 0.49, abs(fract(f * 3.0 + lvl * 1.5) - 0.5)) * 0.3;
		col = vec3(0.03, 0.0, 0.08) + vec3(0.1, 0.9, 1.0) * (edge * 2.2 + vert * 0.5 + inner + slant) * sstep(-0.02, 0.02, el);
	}
	return col;
}
#endif

// Only the scene in use is compiled: the shader that includes this file sets SCENE_STYLE first.
vec3 scene_backdrop(vec3 d, float t) {
#if SCENE_STYLE == 1
	return sc_space(d, t);
#elif SCENE_STYLE == 2
	return sc_aurora(d, t);
#elif SCENE_STYLE == 3
	return sc_city(d, t);
#elif SCENE_STYLE == 4
	return sc_reef(d, t);
#elif SCENE_STYLE == 5
	return sc_volcano(d, t);
#elif SCENE_STYLE == 6
	return sc_desert(d, t);
#elif SCENE_STYLE == 7
	return sc_jungle(d, t);
#elif SCENE_STYLE == 8
	return sc_cavern(d, t);
#elif SCENE_STYLE == 9
	return sc_clouds(d, t);
#elif SCENE_STYLE == 10
	return sc_synth(d, t);
#else
	return vec3(0.02, 0.03, 0.05);
#endif
}
