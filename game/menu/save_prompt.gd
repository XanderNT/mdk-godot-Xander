## The save prompt after a level (0x42b520(1), each frame 0x42b75c): `SV_ASK` "Save Game?" with
## `ABORT2` "Yes" and `ABORT3` "No", then `SV_TITLE` "Name for Saved Game" with the name typed
## below it (up to 8 letters, digits, `_` and `$`), preset to the next level's number. Enter
## saves, Esc gives up. Drawn in `FONTBIG` on the 600×360 view. F2's full save (0x42b520(0))
## asks the name at once.
##
##   Save Game?        y 139
##       Yes           y 175   the selected line grows from 65 % to full size in 5 ticks
##       No            y 211
class_name SavePrompt
extends Control

signal closed

enum Stage { ASK, NAME }

const VIEW := Vector2(600.0, 360.0)
const TICKS_PER_SECOND := 30.0
## The lines: the question's row is −1, the answers 0 (Yes) and 1 (No).
const ROW_Y := 175.0
const ROW_HEIGHT := 36.0
const ANSWERS := ["ABORT2", "ABORT3"]
const YES := 0
## Unselected lines are drawn at 65 %; the selected one grows by 0.35 × 0.2 per tick.
const SMALL := 0.65
const GROW_TICKS := 5.0
## The name: the title's baseline, then one character per 28 pixels from x 202, baseline 200.
const TITLE_Y := 31.0
const NAME_X := 202.0
const NAME_Y := 200.0
const NAME_STEP := 28.0
const NAME_LENGTH := 8
const NAME_EXTRA := "_$"
## The cursor blinks every 8 frames (`0x5742e8 & 8`).
const BLINK_TICKS := 8

var _fti: MDKFti
var _font: MDKFont
var _kind := GameState.KIND_BEFORE_LEVEL
var _stage := Stage.ASK
var _selected := YES
var _grow := 0.0
var _name := ""
var _cursor := 0
var _ticks := 0.0
var _level_state := {}


## Opens the prompt; `kind` is the save's kind (`GameState.KIND_*`), `default_name` the name offered,
## `level_state` a full snapshot's state (see `GameState.save_game`).
func open(fti: MDKFti, kind: int, default_name: String, level_state := {}) -> void:
	_fti = fti
	var system := MDKPalette.from_rgb(fti.get_bytes("SYS_PAL").slice(0, 768))
	_font = MDKFont.load_font(fti, "FONTBIG", system, 6)
	_kind = kind
	_level_state = level_state
	_stage = Stage.NAME if kind == GameState.KIND_SNAPSHOT else Stage.ASK
	_name = default_name.left(NAME_LENGTH)
	_cursor = _name.length()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = Settings.canvas_filter()
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	_ticks += delta * TICKS_PER_SECOND
	_grow = minf(_grow + delta * TICKS_PER_SECOND, GROW_TICKS)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	get_viewport().set_input_as_handled()
	if _stage == Stage.ASK:
		_ask_input(event)
		return
	if event is InputEventKey and event.pressed:
		_name_input(event)


## Yes or No: up and down or the mouse choose, Enter, Space or a click confirms, Esc says no.
func _ask_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var row := floori((event.position.y / _scale() - (ROW_Y - ROW_HEIGHT + 10.0)) / ROW_HEIGHT)
		if row >= 0 and row < ANSWERS.size():
			_select(row)
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_answer()
		return
	if not event is InputEventKey or not event.pressed:
		return

	match event.keycode:
		KEY_UP, KEY_DOWN:
			_select(1 - _selected)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_answer()
		KEY_ESCAPE:
			_close()


func _select(row: int) -> void:
	if row == _selected:
		return
	_selected = row
	_grow = 0.0


func _answer() -> void:
	if _selected != YES:
		_close()
		return
	_stage = Stage.NAME


## Typing the name: characters replace the one at the cursor, Backspace and Delete remove one,
## Left, Right, Home and End move the cursor.
func _name_input(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			_close()
		KEY_ENTER, KEY_KP_ENTER:
			_save()
		KEY_LEFT:
			_cursor = maxi(_cursor - 1, 0)
		KEY_RIGHT:
			_cursor = mini(_cursor + 1, _name.length())
		KEY_HOME:
			_cursor = 0
		KEY_END:
			_cursor = _name.length()
		KEY_BACKSPACE:
			if _cursor > 0:
				_name = _name.erase(_cursor - 1)
				_cursor -= 1
		KEY_DELETE:
			_name = _name.erase(_cursor)
		_:
			_type(char(event.unicode).to_upper())


func _type(c: String) -> void:
	if _cursor >= NAME_LENGTH or c.is_empty():
		return
	if not (c.is_valid_identifier() or c.is_valid_int() or c in NAME_EXTRA):
		return
	_name = _name.left(_cursor) + c + _name.substr(_cursor + 1)
	_cursor += 1


func _save() -> void:
	if _name.is_empty():
		return
	if GameState.save_game(_name, _kind, _level_state):
		_close()


func _close() -> void:
	visible = false
	set_process_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	closed.emit()


func _scale() -> float:
	return size.y / VIEW.y


func _draw() -> void:
	if not _font:
		return
	var s := _scale()
	var width := size.x / s
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	if _stage == Stage.ASK:
		_draw_line("SV_ASK", -1, SMALL, width)
		for row in ANSWERS.size():
			var grow := SMALL + (1.0 - SMALL) * _grow / GROW_TICKS if row == _selected else SMALL
			_draw_line(ANSWERS[row], row, grow, width)
		return

	# The title, the name one character per step, and the blinking cursor.
	var title := _fti.get_text_bytes("SV_TITLE")
	_font.draw(self, title, (width - _font.get_width(title)) * 0.5, TITLE_Y)
	var origin := NAME_X + (width - VIEW.x) * 0.5
	for i in _name.length():
		var glyph := _name[i].to_ascii_buffer()
		_font.draw(self, glyph, origin + NAME_STEP * i - _font.get_width(glyph) * 0.5, NAME_Y)
	if int(_ticks) & BLINK_TICKS:
		var cursor := "_".to_ascii_buffer()
		_font.draw(self, cursor, origin + NAME_STEP * _cursor - _font.get_width(cursor) * 0.5, NAME_Y)


## A line centred at row `row`, scaled about its centre.
func _draw_line(text_name: String, row: int, scale: float, width: float) -> void:
	var text := _fti.get_text_bytes(text_name)
	_font.draw(self, text, (width - _font.get_width(text) * scale) * 0.5, ROW_Y + ROW_HEIGHT * row, scale)
