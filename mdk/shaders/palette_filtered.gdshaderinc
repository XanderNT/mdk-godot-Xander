// The enhanced look of palette textures (palette_lit*.gdshader): lit, and filtered bilinearly by
// hand (each of the 4 texels goes through the palette first, so the indices aren't blended).
// Index 0 stays transparent. Animated textures keep to their frame.
uniform sampler2D index_texture : filter_nearest, repeat_enable;
uniform sampler2D palette : source_color, filter_nearest;
uniform int frame_count = 1;
uniform float frames_per_second = 15.0;
instance uniform int frame_index = -1;

vec4 texel(ivec2 cell, ivec2 frame_size, int frame) {
	ivec2 wrapped = ivec2((cell.x % frame_size.x + frame_size.x) % frame_size.x,
			(cell.y % frame_size.y + frame_size.y) % frame_size.y + frame * frame_size.y);
	int index = int(round(texelFetch(index_texture, wrapped, 0).r * 255.0));
	return index == 0 ? vec4(0.0) : vec4(texelFetch(palette, ivec2(index, 0), 0).rgb, 1.0);
}

void fragment() {
	ivec2 size = textureSize(index_texture, 0);
	ivec2 frame_size = ivec2(size.x, size.y / max(frame_count, 1));
	int frame = 0;
	if (frame_count > 1) {
		frame = frame_index >= 0 ? min(frame_index, frame_count - 1) : int(mod(floor(TIME * frames_per_second), float(frame_count)));
	}
	vec2 position = UV * vec2(frame_size) - 0.5;
	ivec2 base = ivec2(floor(position));
	vec2 f = fract(position);
	vec4 colour = mix(mix(texel(base, frame_size, frame), texel(base + ivec2(1, 0), frame_size, frame), f.x),
			mix(texel(base + ivec2(0, 1), frame_size, frame), texel(base + ivec2(1, 1), frame_size, frame), f.x), f.y);
	if (colour.a < 0.5) {
		discard;
	}
	ALBEDO = colour.rgb / colour.a * COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
