// MDK mirrors (`MIRRLOW`…`MIRRHIGH`, D3D 0x471908): no reflection, the triangle shows the mirror
// panorama where the sky behind it would be, `row_shift` rows lower (MIRRLOW) or higher (MIRRHIGH).
// Rows wrap, as the D3D texture does. Same mapping as sky.gdshader.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D sky_index : filter_nearest, repeat_enable;
uniform sampler2D palette : source_color, filter_nearest;
uniform float texture_width = 1804.0;
uniform float wrap_width = 1800.0;
uniform float horizon_row = 240.0;
uniform float offset = 300.0;
uniform float row_shift = 0.0;

void fragment() {
	vec3 direction = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	float pixels_per_radian = wrap_width / TAU;
	float azimuth = atan(direction.x, -direction.z);
	float elevation = asin(clamp(direction.y, -1.0, 1.0));
	float column = mod(azimuth * pixels_per_radian + offset, wrap_width);
	vec2 size = vec2(textureSize(sky_index, 0));
	float row = mod(horizon_row - elevation * pixels_per_radian + row_shift, size.y);
	int index = int(round(texture(sky_index, vec2((column + 0.5) / texture_width, (row + 0.5) / size.y)).r * 255.0));
	ALBEDO = texelFetch(palette, ivec2(index, 0), 0).rgb;
}
