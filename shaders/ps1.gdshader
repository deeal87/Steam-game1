shader_type spatial;
render_mode vertex_lighting, diffuse_lambert, specular_disabled, cull_back;

// Late-90s console rendering, reproduced honestly rather than faked in post.
//
// Two artefacts define the look:
//
//  1. Vertex snapping. The original hardware had no floating point in its
//     geometry unit, so screen positions landed on a coarse integer grid and
//     polygons visibly jittered as things moved.
//
//  2. Affine texture mapping. It had no perspective divide per pixel either,
//     so textures interpolated linearly in screen space and swam across large
//     surfaces like a floor or a wall.

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 emission_tint : source_color = vec4(0.0);
uniform float emission_strength = 0.0;
uniform float snap_strength : hint_range(0.0, 1.0) = 1.0;
uniform float snap_grid = 110.0;
uniform float affine_strength : hint_range(0.0, 1.0) = 1.0;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.0;
uniform float uv_scale = 1.0;

// Scaled by the settings menu, so a player who finds the jitter or the texture
// swim uncomfortable can dial either back to nothing.
global uniform float ps1_snap;
global uniform float ps1_affine;

varying vec2 v_uv_w;   // UV premultiplied by clip w
varying float v_w;     // clip w, interpolated the same way

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);

	// Quantise the on-screen position. Done in normalised device coordinates
	// so the jitter stays constant in screen pixels regardless of distance,
	// which is what makes distant geometry wobble the most.
	vec2 snapped = round(clip.xy / clip.w * snap_grid) / snap_grid * clip.w;
	clip.xy = mix(clip.xy, snapped, snap_strength * ps1_snap);
	POSITION = clip;

	// Hardware interpolates varyings with a perspective divide. Feeding it
	// UV*w and w separately and dividing them back in the fragment stage
	// cancels that divide out exactly, leaving screen-linear interpolation.
	v_w = clip.w;
	v_uv_w = UV * uv_scale * clip.w;
}

void fragment() {
	vec2 affine_uv = v_uv_w / v_w;
	vec2 correct_uv = UV * uv_scale;
	vec2 uv = mix(correct_uv, affine_uv, affine_strength * ps1_affine);

	vec4 c = texture(albedo_tex, uv) * tint;

	if (alpha_scissor > 0.0 && c.a < alpha_scissor) {
		discard;
	}

	ALBEDO = c.rgb;
	ALPHA = c.a;
	EMISSION = emission_tint.rgb * emission_strength;
	// The console had no specular pass at all; anything shiny was painted in.
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
