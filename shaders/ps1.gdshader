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

	// Cutouts are a discard, never an alpha value. See below.
	if (alpha_scissor > 0.0 && c.a < alpha_scissor) {
		discard;
	}

	ALBEDO = c.rgb;
	// ALPHA is deliberately not written here, and this is the single most
	// important line in the file.
	//
	// A spatial shader in Godot 4 becomes a *transparent* material simply by
	// assigning to ALPHA. Nothing warns you. Transparent materials do not write
	// to the depth buffer and are drawn after everything else, sorted by how far
	// each object's origin is from the camera — so two of them draw in whatever
	// order their centres happen to fall in, and that order changes as the
	// camera moves.
	//
	// Every surface in this game goes through this shader, so every surface in
	// this game was transparent. The world is built out of long boxes — a
	// hundred metres of road, a shop wall, a counter — whose origins are metres
	// away while their faces are at arm's length, which is the exact case where
	// sorting by origin gets the answer wrong. That is "objects through the
	// wall", "the stock in the shelf you cannot see", "the table with the
	// scanner disappears at the right angle", and "everything is disappearing
	// and coming back depending how far or from which angle I look". One line.
	//
	// It was writing a constant, too: every texture in the game is RGB8 and
	// nothing has ever set alpha_scissor, so `c.a` was 1.0 everywhere. The whole
	// depth buffer was being given up for a value that never varied.
	//
	// If a cutout texture is ever needed, the discard above is the way to do it
	// and it works in an opaque shader. Reinstating this line is not.
	EMISSION = emission_tint.rgb * emission_strength;
	// The console had no specular pass at all; anything shiny was painted in.
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
