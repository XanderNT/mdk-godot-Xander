## A menu item drawn like the original (0x42c374, 0x42c488): its text in an MDK font, centred,
## at 65 % of its size until it's selected; then it grows to full size in 5 ticks, and shrinks back
## the same way when the selection leaves it. A title stays at full size.
class_name MenuEntry
extends Button

## Whether the item is a title (full size, not selectable).
enum Kind { ITEM, TITLE }

const SMALL := 0.65
## 0.35 × 0.2 per tick.
const GROW_RATE := 0.07 * 30.0
const DISABLED := Color(0.5, 0.5, 0.5)

var font: MDKFont
## The baseline's height in the item.
var baseline := 0.0
var kind := Kind.ITEM
var _grow := SMALL


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	# Only `_draw` shows the text.
	for state in [&"font_color", &"font_hover_color", &"font_focus_color", &"font_pressed_color",
			&"font_hover_pressed_color", &"font_disabled_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	for style in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())
	mouse_entered.connect(func() -> void:
		if not disabled:
			grab_focus())


func _process(delta: float) -> void:
	modulate = DISABLED if disabled and kind == Kind.ITEM else Color.WHITE
	var target := 1.0 if has_focus() or kind == Kind.TITLE else SMALL
	if _grow == target:
		return
	_grow = move_toward(_grow, target, GROW_RATE * delta)
	queue_redraw()


func _draw() -> void:
	if not font or text.is_empty():
		return
	var bytes := text.to_ascii_buffer()
	var x := (size.x - font.get_width(bytes) * _grow) / 2.0
	font.draw(self, bytes, roundf(x), baseline, _grow)
