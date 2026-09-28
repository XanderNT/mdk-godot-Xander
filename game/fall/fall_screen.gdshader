// The fall's palette effects on the whole screen (0x410cc0, 0x410c28): towards white by `whiten`
// (1 = none), the red of death, then darkened by `dark` (1 = none).
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float whiten = 1.0;
uniform float dark = 1.0;
uniform float red = 0.0;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	c.r = min(c.r + red, 1.0);
	c = c * whiten + vec3(1.0 - whiten);
	COLOR = vec4(c * dark, 1.0);
}
