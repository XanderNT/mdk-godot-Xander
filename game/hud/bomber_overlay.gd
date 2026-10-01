## The `XE` bomber's HUD (0x46be98), on the 600×360 view while the controls are unlocked:
## `BOMBTARG` at the view's centre, `CROSS` at the cursor and the bombs left right-aligned at x 472
## on the baseline y 56, in the big font. See docs/gameplay.md, "The `XE` bomber".
class_name BomberOverlay
extends RefCounted

const VIEW_CENTRE := Vector2(300.0, 180.0)
const COUNT_RIGHT := 472.0
const COUNT_BASELINE := 56.0

var _target: Texture2D
var _target_hotspot := Vector2.ZERO
var _cross: Texture2D
var _cross_hotspot := Vector2.ZERO


func setup(sprites: MDKBni, palette: MDKPalette) -> void:
	var target := sprites.get_animation("BOMBTARG")
	_target = HUD._make_texture(target.get_frame(0), palette)
	_target_hotspot = target.get_hotspot(0)
	var cross := sprites.get_animation("CROSS")
	_cross = HUD._make_texture(cross.get_frame(0), palette)
	_cross_hotspot = cross.get_hotspot(0)


## Draws on the view, `origin` being where its 600×360 area starts.
func draw(canvas: CanvasItem, bomber: MDKBomber, font: MDKFont, origin: Vector2) -> void:
	if bomber.is_locked():
		return
	canvas.draw_texture(_target, origin + VIEW_CENTRE - _target_hotspot)
	canvas.draw_texture(_cross, origin + bomber.cursor.round() - _cross_hotspot)
	var text := str(bomber.bombs).to_ascii_buffer()
	font.draw(canvas, text, origin.x + COUNT_RIGHT - font.get_width(text), origin.y + COUNT_BASELINE)
