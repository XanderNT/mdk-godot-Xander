## The health box of the screens without the level's HUD (the fall, the stream): `SC_STAT` at the
## bottom right with the number in `SNIP_TXT` digits, blinking at 20 or less (0x420830).
class_name HealthBox
extends RefCounted

var _panel: Texture2D
var _digits: Texture2D
var _digit_height := 0


func setup(bni: MDKBni, palette: MDKPalette) -> void:
	_panel = _make_texture(bni.get_image("SC_STAT"), palette)
	var digit_image := bni.get_image("SNIP_TXT")
	_digits = _make_texture(digit_image, palette)
	_digit_height = digit_image.height


## Draws the box on a 360-high view `width` wide (the canvas transform scales it to the window);
## `blink` counts ticks (0–31).
func draw(canvas: CanvasItem, width: float, health: int, blink: int) -> void:
	var position := Vector2(width - (_panel.get_width() + 16), 360.0 - (_panel.get_height() + 10))
	canvas.draw_texture(_panel, position)
	if health > 20 or blink < 16:
		draw_number(canvas, mini(health, 999), position + Vector2(_panel.get_width() >> 1, (_panel.get_height() - _digit_height) >> 1))


## A number centred on `position.x`, with 8-pixel wide digits (0x420bd0).
func draw_number(canvas: CanvasItem, value: int, position: Vector2) -> void:
	var text := str(value)
	var x := position.x - 4 * text.length()
	for c in text:
		canvas.draw_texture_rect_region(_digits, Rect2(x, position.y, 8, _digit_height), Rect2(int(c) * 8, 0, 8, _digit_height))
		x += 8


## A paletted image with index 0 transparent.
static func _make_texture(image: MDKTexture, palette: MDKPalette) -> ImageTexture:
	return ImageTexture.create_from_image(palette.make_image(image.width, image.height, image.indices, true))
