## Plays an FLC (`MDKFlc`) on the 600×360 view, scaled to the window: one frame per game frame
## of the original (34 ms; the file's own speed is ignored), the palette per frame, through
## `flc.gdshader`. The last frame stays; still images (`show_still`) use the same view. See
## docs/gameplay.md, "Videos".
class_name MDKVideo
extends Control

## Whether a key or a click ends the video.
enum Skip { NO, YES }

signal frame_shown(frame: int)
signal finished

const VIEW := Vector2(600.0, 360.0)
## The original's game frame is at least 34 ms (≈ 29.4 fps).
const FRAME_MS := 34.0
const SHADER := preload("res://mdk/shaders/flc.gdshader")

var _flc: MDKFlc
var _skip := Skip.NO
var _time := 0.0
## Seconds the video stays on its frame.
var _hold := 0.0
var _rect := ColorRect.new()
var _indices: ImageTexture
var _palette: ImageTexture


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.material = ShaderMaterial.new()
	_rect.material.shader = SHADER
	add_child(_rect)
	resized.connect(_layout)


## Starts `path` (relative to the game's data). Returns false when it can't be read.
func play(path: String, skip := Skip.NO) -> bool:
	_flc = MDKFlc.load_file(MDKData.path(path))
	if not _flc:
		return false
	_skip = skip
	_time = 0.0
	_show_next()
	return true


## Stays on the current frame for `seconds`.
func hold(seconds: float) -> void:
	_hold = seconds


## Raises every colour by `amount` (0–1).
func set_brighten(amount: float) -> void:
	(_rect.material as ShaderMaterial).set_shader_parameter(&"brighten", amount)


## Whether a video is running.
func is_playing() -> bool:
	return _flc != null


## The image on the view: its indices (R8) and its palette (256 × 1 RGB).
func get_still() -> Array[Image]:
	return [_indices.get_image(), _palette.get_image()]


## Shows a still image of `width` × `height` palette indices with its palette (256 × RGB).
func show_still(width: int, height: int, indices: PackedByteArray, palette: PackedByteArray) -> void:
	var index_image := Image.create_from_data(width, height, false, Image.FORMAT_R8, indices)
	var palette_image := Image.create_from_data(256, 1, false, Image.FORMAT_RGB8, palette)
	if _indices and _indices.get_size() == Vector2(width, height):
		_indices.update(index_image)
		_palette.update(palette_image)
	else:
		_indices = ImageTexture.create_from_image(index_image)
		_palette = ImageTexture.create_from_image(palette_image)
		var material := _rect.material as ShaderMaterial
		material.set_shader_parameter(&"index_texture", _indices)
		material.set_shader_parameter(&"palette", _palette)
	_layout()


func _process(delta: float) -> void:
	if not _flc:
		return
	if _hold > 0.0:
		_hold -= delta
		return
	_time += delta * 1000.0
	while _flc and _hold <= 0.0 and _time >= FRAME_MS:
		_time -= FRAME_MS
		_show_next()
	_layout()


func _show_next() -> void:
	if not _flc.next_frame():
		_finish()
		return
	show_still(_flc.width, _flc.height, _flc.indices, _flc.palette)
	frame_shown.emit(_flc.frame)


## The view keeps its 600:360 shape, centred in the window on black.
func _layout() -> void:
	var scale := minf(size.x / VIEW.x, size.y / VIEW.y)
	_rect.size = VIEW * scale
	_rect.position = (size - _rect.size) / 2.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)


func _unhandled_input(event: InputEvent) -> void:
	if _skip == Skip.NO or not _flc:
		return
	var pressed := (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo()
	if pressed:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	_flc = null
	finished.emit()
