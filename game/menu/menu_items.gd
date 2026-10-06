## A list of menu items drawn like the original's menus (`MenuEntry`: `FONTBIG` through `SYS_PAL`,
## the selected item growing), a click on focus and press, and the options screen shared by the
## main menu and the pause menu. Laid out on the 600×360 view, scaled to the window: rows of 36
## from y 5 (baselines at 31 + 36 × row, 0x4265c0); longer pages get lower rows, and below 24 the
## small font. See docs/gameplay.md, "Menus".
##
##   main menu: a column at the view's left edge, items centred on half its width
##   other pages: centred on x 300
class_name MenuItems
extends Control

## Where the column of items stands on the view.
enum Align { LEFT, CENTRE }

const VIEW := Vector2(600.0, 360.0)
const TOP := 5.0
const ROW := 36.0
## The baseline is 26 below the row's top (y 31 in the first row of 36).
const BASELINE := 26.0 / 36.0
const SMALL_FONT_ROW := 24.0
const SPACE_BIG := 6
const SPACE_SMALL := 4
## The mouse cursor (0x42c010): `ARROW`, a one-frame sprite in `MDKFONT.FTI` (after its size).
const CURSOR := "ARROW"
const CURSOR_OFFSET := 4
const SENSITIVITIES := [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0]
## The options screen's sounds (0x42bb6c): the `OPTSONG` loop on the music bus, so the music volume
## can be heard, and `OPTBUTT` on each change.
const OPTION_SOUNDS := "MISC/MDKSOUND.SNI"
const OPTION_SONG := "OPTSONG"
const OPTION_CHANGE := "OPTBUTT"

var click: AudioStreamPlayer
var align := Align.CENTRE
## The row the first item stands in.
var first_row := 0
var _big: MDKFont
var _small: MDKFont
## The controls screen waits for a key or a mouse button for this action.
var _waiting := &""
var _waiting_button: Button
var _song := AudioStreamPlayer.new()
var _change := AudioStreamPlayer.new()


func _ready() -> void:
	var sounds := MDKSni.load_file(MDKData.path(OPTION_SOUNDS))
	if sounds:
		_song.stream = sounds.get_sound(OPTION_SONG)
		_change.stream = sounds.get_sound(OPTION_CHANGE)
	_song.bus = &"Music"
	add_child(_song, false, INTERNAL_MODE_FRONT)
	add_child(_change, false, INTERNAL_MODE_FRONT)


## The fonts, from `MDKFONT.FTI` through its `SYS_PAL` (the menu images share those colours).
func setup(fti: MDKFti) -> void:
	var palette := MDKPalette.from_rgb(fti.get_bytes("SYS_PAL").slice(0, 768))
	_big = MDKFont.load_font(fti, "FONTBIG", palette, SPACE_BIG)
	_small = MDKFont.load_font(fti, "FONTSML", palette, SPACE_SMALL)
	_set_cursor(fti, palette)
	texture_filter = Settings.canvas_filter()


## The original's arrow as the mouse cursor, at the view's scale in the window.
func _set_cursor(fti: MDKFti, palette: MDKPalette) -> void:
	var sprite := MDKSpriteAnimation.parse(CURSOR, fti.get_bytes(CURSOR), CURSOR_OFFSET)
	if sprite.frame_count < 1:
		return
	var frame := sprite.get_frame(0)
	var image := palette.make_image(frame.width, frame.height, frame.indices, true)
	var window := get_viewport_rect().size if is_inside_tree() else Vector2(DisplayServer.window_get_size())
	var s := maxi(floori(minf(window.x / VIEW.x, window.y / VIEW.y)), 1)
	image.resize(frame.width * s, frame.height * s, Image.INTERPOLATE_NEAREST)
	Input.set_custom_mouse_cursor(image, Input.CURSOR_ARROW, Vector2(sprite.get_hotspot(0) * s))

func _process(_delta: float) -> void:
	_layout()


## Rows on the view, the view fitted to the window and centred.
func _layout() -> void:
	var entries := get_children()
	if entries.is_empty() or not _big:
		return
	var row := minf(ROW, (VIEW.y - TOP * 2.0) / entries.size())
	var font := _big if row >= SMALL_FONT_ROW else _small
	var width := 0.0
	for entry: MenuEntry in entries:
		width = maxf(width, font.get_width(entry.text.to_ascii_buffer()))
	var x := 0.0 if align == Align.LEFT else (VIEW.x - width) / 2.0
	for i in entries.size():
		var entry: MenuEntry = entries[i]
		entry.font = font
		entry.baseline = roundf(row * BASELINE)
		entry.position = Vector2(x, TOP + row * (i + first_row))
		entry.size = Vector2(width, row)
	# The view fits the window as `MDKVideo` places it, so the items stand on its images.
	var window := get_viewport_rect().size
	var s := minf(window.x / VIEW.x, window.y / VIEW.y)
	scale = Vector2(s, s)
	position = (window - VIEW * s) / 2.0


func clear() -> void:
	_song.stop()
	align = Align.CENTRE
	first_row = 0
	for child in get_children():
		remove_child(child)
		child.queue_free()


func add_item(text: String, callback: Callable) -> Button:
	var button := MenuEntry.new()
	button.text = text
	if callback.is_valid():
		button.pressed.connect(func() -> void:
			_click()
			callback.call())
	button.focus_entered.connect(_click)
	add_child(button)
	_layout()
	return button


## A line at full size that can't be selected ("Really Quit?", list titles).
func add_title(text: String) -> Button:
	var title := add_item(text, Callable())
	title.disabled = true
	title.focus_mode = Control.FOCUS_NONE
	(title as MenuEntry).kind = MenuEntry.Kind.TITLE
	return title


## An item that changes a setting by a step on a click or the right arrow (back with a right click
## or the left arrow); `text` gives its label.
func add_option(text: Callable, change: Callable) -> Button:
	var button := add_item(text.call(), Callable())
	var apply := func(step: int) -> void:
		change.call(step)
		Settings.apply()
		button.text = text.call()
		_change.play()
	button.pressed.connect(apply.bind(1))
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			apply.call(-1)
		elif event.is_action_pressed(&"ui_right"):
			apply.call(1)
			button.accept_event()
		elif event.is_action_pressed(&"ui_left"):
			apply.call(-1)
			button.accept_event())
	return button


## The options (see `Settings`); saved when leaving with "Back".
func show_options(on_back: Callable) -> void:
	clear()
	add_option(func() -> String: return "Master volume: %d" % Settings.master_volume,
			func(step: int) -> void: Settings.master_volume = _volume_step(Settings.master_volume, step))
	add_option(func() -> String: return "Music volume: %d" % Settings.music_volume,
			func(step: int) -> void: Settings.music_volume = _volume_step(Settings.music_volume, step))
	add_option(func() -> String: return "Effects volume: %d" % Settings.effects_volume,
			func(step: int) -> void: Settings.effects_volume = _volume_step(Settings.effects_volume, step))
	add_option(func() -> String: return "Music filter: %s" % _on_off(Settings.music_filter),
			func(_step: int) -> void: Settings.music_filter = not Settings.music_filter)
	add_option(func() -> String: return "Mouse sensitivity: %.2f" % Settings.mouse_sensitivity,
			func(step: int) -> void: Settings.mouse_sensitivity = _sensitivity_step(Settings.mouse_sensitivity, step))
	add_option(func() -> String: return "Invert mouse: %s" % _on_off(Settings.invert_mouse),
			func(_step: int) -> void: Settings.invert_mouse = not Settings.invert_mouse)
	add_option(func() -> String: return "Fullscreen: %s" % _on_off(Settings.fullscreen),
			func(_step: int) -> void: Settings.fullscreen = not Settings.fullscreen)
	add_option(func() -> String: return "Anti-aliasing: %s" % Settings.ANTIALIASING_NAMES[Settings.antialiasing],
			func(step: int) -> void: Settings.antialiasing = wrapi(Settings.antialiasing + step, 0, Settings.ANTIALIASING_NAMES.size()))
	add_option(func() -> String: return "Difficulty: %s" % ["Easy", "Normal", "Hard"][Settings.difficulty],
			func(step: int) -> void: Settings.difficulty = wrapi(Settings.difficulty + step, 0, 3))
	add_option(func() -> String: return "Graphics: %s" % ("Enhanced" if Settings.enhanced_graphics else "Original"),
			func(_step: int) -> void: Settings.enhanced_graphics = not Settings.enhanced_graphics)
	add_option(func() -> String: return "Gore: %s" % _on_off(Settings.gore),
			func(_step: int) -> void: Settings.gore = not Settings.gore)
	add_item("Controls", func() -> void: show_controls(show_options.bind(on_back)))
	add_item("Back", func() -> void:
		Settings.save()
		on_back.call())
	get_child(0).grab_focus()
	_song.play()


## The key bindings: pressing an item waits for a key or a mouse button (Esc cancels).
func show_controls(on_back: Callable) -> void:
	clear()
	for action: StringName in Settings.ACTIONS:
		var button := add_item("", Callable())
		button.text = _binding_text(action)
		button.pressed.connect(func() -> void:
			_click()
			_waiting = action
			_waiting_button = button
			button.text = "%s: press a key..." % Settings.ACTIONS[action])
	add_item("Default keys", func() -> void:
		Settings.reset_bindings()
		show_controls(on_back))
	add_item("Back", func() -> void:
		Settings.save()
		on_back.call())
	get_child(0).grab_focus()


func _binding_text(action: StringName) -> String:
	return "%s: %s" % [Settings.ACTIONS[action], Settings.describe(action)]


func _input(event: InputEvent) -> void:
	if _waiting.is_empty() or not event.is_pressed() or event.is_echo():
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	get_viewport().set_input_as_handled()
	if not (event is InputEventKey and event.keycode == KEY_ESCAPE):
		Settings.bind(_waiting, event)
	_waiting_button.text = _binding_text(_waiting)
	_waiting = &""


func _click() -> void:
	if click:
		click.play()


static func _volume_step(value: int, step: int) -> int:
	return wrapi(value + step * 10, 0, 110)


static func _sensitivity_step(value: float, step: int) -> float:
	var index := SENSITIVITIES.find(value)
	return SENSITIVITIES[wrapi((index if index >= 0 else 3) + step, 0, SENSITIVITIES.size())]


static func _on_off(value: bool) -> String:
	return "On" if value else "Off"
