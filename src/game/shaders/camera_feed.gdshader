shader_type canvas_item;
// Phone camera passthrough. Handles RGB feeds and split Y + CbCr feeds.
// The feed's own transform (sensor orientation) is applied, then optional debug
// quarter-turns / mirror, with "cover" fitting so the video always fills the screen.
uniform sampler2D tex_a : filter_linear;   // RGB or Y plane
uniform sampler2D tex_b : filter_linear;   // CbCr plane (when ycbcr)
uniform bool ycbcr = false;
uniform vec2 xf_x = vec2(1.0, 0.0);        // CameraFeed.feed_transform basis columns (normalised)
uniform vec2 xf_y = vec2(0.0, 1.0);
uniform int quarter_turns = 0;
uniform bool mirror = false;
uniform vec2 screen_size = vec2(1920.0, 1080.0);
uniform vec2 image_size = vec2(1280.0, 720.0);
uniform float exposure = 1.0;
uniform bool affine = false;               // ARCore: exact view -> image mapping (rotation + crop)
uniform vec2 uv_o = vec2(0.0);
uniform vec2 uv_x = vec2(1.0, 0.0);
uniform vec2 uv_y = vec2(0.0, 1.0);

vec2 rot_uv(vec2 uv, int q) {
	if (q == 1) return vec2(uv.y, 1.0 - uv.x);
	if (q == 2) return vec2(1.0 - uv.x, 1.0 - uv.y);
	if (q == 3) return vec2(1.0 - uv.y, uv.x);
	return uv;
}

void fragment() {
	if (affine) {
		vec2 a = uv_o + uv_x * UV.x + uv_y * UV.y;
		float yy = texture(tex_a, a).r;
		vec2 cc = texture(tex_b, a).rg - vec2(0.5);
		COLOR = vec4(vec3(yy + 1.402 * cc.y, yy - 0.344136 * cc.x - 0.714136 * cc.y, yy + 1.772 * cc.x) * exposure, 1.0);
	} else {
	bool swapped = abs(xf_x.y) > abs(xf_x.x);
	if (quarter_turns % 2 == 1) swapped = !swapped;
	vec2 img = swapped ? image_size.yx : image_size;
	float sa = screen_size.x / max(screen_size.y, 1.0);
	float ia = img.x / max(img.y, 1.0);
	vec2 uv = UV;
	if (ia > sa) { uv.x = 0.5 + (uv.x - 0.5) * (sa / ia); }
	else { uv.y = 0.5 + (uv.y - 0.5) * (ia / sa); }
	if (mirror) uv.x = 1.0 - uv.x;
	uv = rot_uv(uv, quarter_turns);
	// feed_transform rotates the image for display (Godot's Android feed: a pure rotation from sensor
	// orientation + display rotation). We map screen -> image, so apply its inverse (= transpose) about
	// the image centre; the translation part isn't meaningful for UVs.
	vec2 c = uv - vec2(0.5);
	vec2 iuv = vec2(0.5) + vec2(dot(xf_x, c), dot(xf_y, c));
	vec3 rgb;
	if (ycbcr) {
		float y = texture(tex_a, iuv).r;
		vec2 cbcr = texture(tex_b, iuv).rg - vec2(0.5);
		rgb = vec3(y + 1.402 * cbcr.y, y - 0.344136 * cbcr.x - 0.714136 * cbcr.y, y + 1.772 * cbcr.x);
	} else {
		rgb = texture(tex_a, iuv).rgb;
	}
	COLOR = vec4(rgb * exposure, 1.0);
}
}
