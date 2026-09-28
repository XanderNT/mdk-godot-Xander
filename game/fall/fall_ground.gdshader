// The fall's ground (0x41357c): the texture `LEVELn` mapped affinely onto the view, the
// minecrawler's track (`PODn`) under and behind it, and the haze (`ZOOMnnnn`) blending the ground
// towards white. See docs/gameplay.md, "Ground".
shader_type canvas_item;

uniform sampler2D ground : filter_nearest;
uniform sampler2D track : filter_nearest;
uniform sampler2D palette : filter_nearest;
uniform sampler2D haze : filter_nearest;
// The view in original pixels (360 high, as wide as the window's aspect).
uniform vec2 view_size = vec2(600.0, 360.0);
// Camera position (MDK units).
uniform vec3 camera = vec3(0.0, 0.0, 5280.0);
// The texel row at the view centre (A = 824 − 624 t / 33).
uniform float centre_row = 824.0;
// The first row of the track (R).
uniform int track_row = 1024;
// The wind level (`0x5209b8 >> 8`, 0–12) and the blend of each table (0x490d1c, / 256).
uniform int wind = 12;
uniform float blend[24];

void fragment() {
	vec2 p = UV * view_size;
	float s = camera.z / 5280.0;
	vec2 texel = vec2(512.0 + 0.36 * camera.x + s * (p.x - view_size.x * 0.5),
			centre_row - 0.36 * camera.y + s * (p.y - 180.0));
	ivec2 t = ivec2(floor(texel));
	int index = 0;
	if (t.x >= 0 && t.y >= 0 && t.x < 1024 && t.y < 1024) {
		index = int(round(texelFetch(ground, t, 0).r * 255.0));
		if (t.y >= track_row) {
			int j = t.y - track_row;
			int w = j < 24 ? int(round(16.0 + 2.0 * float(j) / 3.0)) : 32;
			if (t.x >= 512 - w && t.x < 512 + w) {
				index = int(round(texelFetch(track, ivec2(t.x - 480, t.y), 0).r * 255.0));
			}
		}
	}
	vec3 rgb = texelFetch(palette, ivec2(index, 0), 0).rgb;
	int b = int(round(texture(haze, UV).r * 255.0));
	if (b > 0) {
		int k = clamp(wind + b, 1, 24);
		rgb = mix(rgb, vec3(1.0), blend[k - 1]);
	}
	COLOR = vec4(rgb, 1.0);
}
