// An 8-bit paletted sprite drawn like MDK draws Kurt: at a fixed size in screen pixels (one sprite
// pixel is 1/360 of the view height, as on the original 600×360 view), anchored to a 3D point and
// depth-tested at that point's depth. `anchor` is the sprite pixel placed on the node's origin.
// Palette index 0 is transparent. The enhanced look (`filtered`) blends the 4 nearest pixels, each
// through the palette; the edge is where they're half covered (alpha scissor, so the sprite stays
// opaque and keeps its depth order).
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D index_texture : filter_nearest;
uniform sampler2D palette : source_color, filter_nearest;
// Frame size and anchor in pixels.
uniform vec2 frame_size = vec2(64.0);
uniform vec2 anchor = vec2(0.0);
// Height of the original view in pixels.
uniform float view_height = 360.0;
uniform bool flip_h = false;
// Moves the sprite away from the camera (world units), e.g. to draw a muzzle flash behind Kurt.
uniform float depth_bias = 0.0;
uniform bool filtered = false;

void vertex() {
	vec2 pixel = vec2(VERTEX.x + 0.5, 0.5 - VERTEX.y) * frame_size;
	vec2 offset = vec2(pixel.x - anchor.x, anchor.y - pixel.y);
	if (flip_h) {
		offset.x = -offset.x;
	}
	vec4 view_anchor = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	view_anchor.z -= depth_bias;
	// World units per pixel at the anchor's depth: 2·depth·tan(fov/2) / view height.
	// (The projection may flip Y, hence abs().)
	float pixel_size = 2.0 * -view_anchor.z / (abs(PROJECTION_MATRIX[1][1]) * view_height);
	POSITION = PROJECTION_MATRIX * vec4(view_anchor.xy + offset * pixel_size, view_anchor.z, 1.0);
}

vec4 pixel(ivec2 cell) {
	ivec2 size = textureSize(index_texture, 0);
	if (cell.x < 0 || cell.y < 0 || cell.x >= size.x || cell.y >= size.y) {
		return vec4(0.0);
	}
	int index = int(round(texelFetch(index_texture, cell, 0).r * 255.0));
	return index == 0 ? vec4(0.0) : vec4(texelFetch(palette, ivec2(index, 0), 0).rgb, 1.0);
}

void fragment() {
	// Mirroring is done by the vertex positions (around the anchor), so UVs stay as they are.
	if (filtered) {
		vec2 position = UV * vec2(textureSize(index_texture, 0)) - 0.5;
		ivec2 base = ivec2(floor(position));
		vec2 f = fract(position);
		vec4 colour = mix(mix(pixel(base), pixel(base + ivec2(1, 0)), f.x),
				mix(pixel(base + ivec2(0, 1)), pixel(base + ivec2(1, 1)), f.x), f.y);
		ALBEDO = colour.a > 0.0 ? colour.rgb / colour.a : vec3(0.0);
		ALPHA = colour.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	} else {
		int index = int(round(texture(index_texture, UV).r * 255.0));
		if (index == 0) {
			discard;
		}
		ALBEDO = texelFetch(palette, ivec2(index, 0), 0).rgb;
	}
}
