shader_type canvas_item;

// Full-screen pass. Doubles as the CRT treatment for the terminal monitor and
// as the general grade over the whole game, since a kiosk lit by one failing
// strip light and a monitor are visually the same problem.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

uniform float scanline_strength : hint_range(0.0, 1.0) = 0.22;
uniform float scanline_count = 270.0;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.85;
uniform float aberration : hint_range(0.0, 4.0) = 0.6;
uniform float grain : hint_range(0.0, 1.0) = 0.05;
uniform float curvature : hint_range(0.0, 0.4) = 0.0;
uniform float posterize_steps = 32.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.0;
uniform vec4 grade : source_color = vec4(0.86, 0.90, 1.0, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

vec2 curve_uv(vec2 uv) {
	if (curvature <= 0.0) {
		return uv;
	}
	uv = uv * 2.0 - 1.0;
	vec2 offset = abs(uv.yx) / vec2(1.0 / curvature, 1.0 / curvature);
	uv += uv * offset * offset;
	return uv * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = curve_uv(SCREEN_UV);

	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		// Split the channels sideways a little, the way a cheap composite
		// signal smears red and blue apart.
		vec2 shift = vec2(aberration / 480.0, 0.0);
		vec3 col;
		col.r = texture(screen_tex, uv + shift).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - shift).b;

		float line = sin(uv.y * scanline_count * 3.14159);
		col *= 1.0 - scanline_strength * (0.5 + 0.5 * line);

		vec2 d = uv - 0.5;
		col *= 1.0 - vignette_strength * dot(d, d);

		col += (hash(uv * vec2(1024.0, 768.0) + fract(TIME) * 91.7) - 0.5) * grain;

		if (posterize_steps > 0.0) {
			col = floor(col * posterize_steps + 0.5) / posterize_steps;
		}

		col *= grade.rgb;
		col *= 1.0 - flicker * (0.5 + 0.5 * sin(TIME * 47.0)) * hash(vec2(floor(TIME * 12.0), 3.0));

		COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
	}
}
