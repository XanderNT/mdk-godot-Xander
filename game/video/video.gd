## Plays an FLC (`MDKFlc`) on the 600×360 view, scaled to the window: one frame per game frame
## of the original (34 ms; the file's own speed is ignored), the palette per frame, through
## `flc.gdshader`. The last frame stays; still images (`show_still`) use the same view. An MVE
## (`MDKMve`, `play_movie`) plays at its own rate with its sound, centred on the 640×480 screen.
## See docs/gameplay.md, "Videos".
class_name MDKVideo
extends Control

## Whether a key or a click ends the video.
enum Skip { NO, YES }

signal frame_shown(frame: int)
signal finished

const VIEW := Vector2(600.0, 360.0)
## MVEs are centred on the whole screen.
const SCREEN := Vector2(640.0, 480.0)
## Seconds of sound the generator holds (the movie starts with about 1 s of it).
const SOUND_BUFFER := 2.0
## The movie's sound is a bit shorter than its frames (1462 samples against 66.7 ms): with less
## than this much queued, the next frame comes at once, so the sound leads.
const SOUND_LOW := 0.25
## The original's game frame is at least 34 ms (≈ 29.4 fps).
const FRAME_MS := 34.0
const SHADER := preload("res://mdk/shaders/flc.gdshader")

var _flc: MDKFlc
var _mve: MDKMve
var _sound: AudioStreamGeneratorPlayback
## The area the image is fitted in, and the image's size in it.
var _view := VIEW
var _image_size := VIEW
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


## Starts the MVE `path` (relative to the game's data). Returns false when it can't be read.
func play_movie(path: String, skip := Skip.NO) -> bool:
	_mve = MDKMve.load_file(MDKData.path(path))
	if not _mve:
		return false
	_skip = skip
	_time = 0.0
	_view = SCREEN
	if not _next_movie_frame():
		return false
	var player := AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = _mve.sample_rate
	stream.buffer_length = SOUND_BUFFER
	player.stream = stream
	player.bus = &"Effects"
	add_child(player)
	player.play()
	_sound = player.get_stream_playback()
	_push_sound()
	return true


## Stays on the current frame for `seconds`.
func hold(seconds: float) -> void:
	_hold = seconds


## Raises every colour by `amount` (0–1).
func set_brighten(amount: float) -> void:
	(_rect.material as ShaderMaterial).set_shader_parameter(&"brighten", amount)


## Whether a video is running.
func is_playing() -> bool:
	return _flc != null or _mve != null


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
	_image_size = Vector2(width, height)
	_layout()


func _process(delta: float) -> void:
	if _mve:
		_update_movie(delta)
		return
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


## A frame every `frame_time` µs, or sooner when the sound runs low; its sound goes to the
## generator.
func _update_movie(delta: float) -> void:
	_time += delta * 1000000.0
	while _mve and (_time >= _mve.frame_time or _sound_queued() < SOUND_LOW):
		_time = maxf(_time - _mve.frame_time, 0.0)
		if not _next_movie_frame():
			_finish()
			return
		_push_sound()


## Seconds of sound waiting in the generator.
func _sound_queued() -> float:
	if not _sound:
		return INF
	var capacity := roundi(_mve.sample_rate * SOUND_BUFFER)
	return float(capacity - _sound.get_frames_available()) / _mve.sample_rate


func _next_movie_frame() -> bool:
	if not _mve.next_frame():
		return false
	show_still(_mve.width, _mve.height, _mve.get_indices(), _mve.palette)
	frame_shown.emit(_mve.frame)
	return true


func _push_sound() -> void:
	if _sound and not _mve.audio.is_empty():
		_sound.push_buffer(_mve.audio)


## The view keeps its shape, centred in the window on black; the image is centred in it.
func _layout() -> void:
	var scale := minf(size.x / _view.x, size.y / _view.y)
	_rect.size = _image_size * scale
	_rect.position = (size - _rect.size) / 2.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)


func _unhandled_input(event: InputEvent) -> void:
	if _skip == Skip.NO or not is_playing():
		return
	var pressed := (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo()
	if pressed:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	_flc = null
	_mve = null
	finished.emit()
