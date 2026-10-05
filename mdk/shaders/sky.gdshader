// MDK sky. The original blits a panorama as a 2D backdrop: it scrolls horizontally with the yaw
// (`wrap_width` pixels for 360°) and vertically with the pitch, with `horizon_row` at eye level.
// The screen above and below the panorama is filled with `top_color` and `bottom_color`. The
// enhanced look (`filtered`) blends the 4 nearest pixels, each through the palette.
shader_type sky;

uniform sampler2D sky_index : filter_nearest, repeat_disable;
uniform sampler2D palette : source_color, filter_nearest;
uniform float texture_width = 1804.0;
uniform float wrap_width = 1800.0;
uniform float horizon_row = 240.0;
uniform float offset = 300.0;
uniform int top_color = 0;
uniform int bottom_color = 0;
uniform bool filtered = false;

vec3 pixel(int column, int row, int height) {
	int index;
	if (row < 0) {
		index = top_color;
	} else if (row >= height) {
		index = bottom_color;
	} else {
		int wrapped = (column % int(wrap_width) + int(wrap_width)) % int(wrap_width);
		index = int(round(texelFetch(sky_index, ivec2(wrapped, row), 0).r * 255.0));
	}
	return texelFetch(palette, ivec2(index, 0), 0).rgb;
}

void sky() {
	float pixels_per_radian = wrap_width / TAU;
	float azimuth = atan(EYEDIR.x, -EYEDIR.z);
	float elevation = asin(clamp(EYEDIR.y, -1.0, 1.0));
	float column = mod(azimuth * pixels_per_radian + offset, wrap_width);
	float row = horizon_row - elevation * pixels_per_radian;
	int height = textureSize(sky_index, 0).y;
	if (filtered) {
		vec2 position = vec2(column, row) - 0.5;
		ivec2 base = ivec2(floor(position));
		vec2 f = fract(position);
		COLOR = mix(mix(pixel(base.x, base.y, height), pixel(base.x + 1, base.y, height), f.x),
				mix(pixel(base.x, base.y + 1, height), pixel(base.x + 1, base.y + 1, height), f.x), f.y);
	} else {
		COLOR = pixel(int(column), int(floor(row)), height);
	}
}
