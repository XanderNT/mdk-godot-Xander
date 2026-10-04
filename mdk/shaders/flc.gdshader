// An FLC frame (`MDKVideo`): palette indices looked up in the frame's palette (256 × 1), every
// colour raised by `brighten` (0–1, the end movie's white flash).
shader_type canvas_item;

uniform sampler2D index_texture : filter_nearest;
uniform sampler2D palette : source_color, filter_nearest;
uniform float brighten = 0.0;

void fragment() {
	int index = int(round(texture(index_texture, UV).r * 255.0));
	COLOR = vec4(min(texelFetch(palette, ivec2(index, 0), 0).rgb + brighten, vec3(1.0)), 1.0);
}
