## The `INTRO1A` splash (0x426edc) before the main menu: at start, after Kurt dies and after the end
## movies. A 600×360 still (`MISC/OPTIONS.BNI`: two 768-byte palettes, then run-length rows, 0x426e04)
## whose palette fades; any key skips it. See docs/gameplay.md, "Videos".
##
##   black ──1 s──▶ palette 1 ──3 s──▶ ──2 s──▶ palette 2 ──3 s──▶ ──1 s──▶ black
class_name IntroSplash
extends Control

signal finished

const ARCHIVE := "MISC/OPTIONS.BNI"
const ENTRY := "INTRO1A"
const WIDTH := 600
const HEIGHT := 360
const PALETTE_SIZE := 768
## Each step: [seconds, palette at its start, palette at its end] (palettes: 0 black, 1, 2).
const STEPS := [[1.0, 0, 1], [3.0, 1, 1], [2.0, 1, 2], [3.0, 2, 2], [1.0, 2, 0]]

var _video := MDKVideo.new()
var _palettes: Array[PackedByteArray] = []
var _indices := PackedByteArray()
var _step := 0
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_video)
	if not _load():
		_finish.call_deferred()
		return
	_show()


func _process(delta: float) -> void:
	if _step >= STEPS.size():
		return
	_time += delta
	if _time >= STEPS[_step][0]:
		_time = 0.0
		_step += 1
		if _step >= STEPS.size():
			_finish()
			return
	_show()


## Any key or click skips it.
func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo():
		get_viewport().set_input_as_handled()
		_finish()


## The palette between the step's two, `t` of the way (0x417040, 0x4170ec).
func _show() -> void:
	var step: Array = STEPS[_step]
	var t := clampf(_time / step[0], 0.0, 1.0)
	var from: PackedByteArray = _palettes[step[1]]
	var to: PackedByteArray = _palettes[step[2]]
	var palette := PackedByteArray()
	palette.resize(PALETTE_SIZE)
	var weight := roundi(t * 256.0)
	for i in PALETTE_SIZE:
		palette[i] = (from[i] * (256 - weight) + to[i] * weight) >> 8
	_video.show_still(WIDTH, HEIGHT, _indices, palette)


func _load() -> bool:
	var archive := MDKBni.load_file(MDKData.path(ARCHIVE))
	if not archive or not archive.has(ENTRY):
		return false
	var entry: Array = archive.entries[ENTRY]
	var bytes := archive.bytes.slice(entry[0], entry[0] + entry[1])
	var black := PackedByteArray()
	black.resize(PALETTE_SIZE)
	_palettes = [black, bytes.slice(0, PALETTE_SIZE), bytes.slice(PALETTE_SIZE, PALETTE_SIZE * 2)]
	_indices = _unpack(bytes, PALETTE_SIZE * 2)
	return true


## Runs: a negative count copies that many bytes, a positive one repeats the next byte, 0 ends.
static func _unpack(bytes: PackedByteArray, p: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(WIDTH * HEIGHT)
	var n := 0
	while p < bytes.size() and n < out.size():
		var count := bytes[p]
		p += 1
		if count == 0:
			break
		if count > 127:
			for k in 256 - count:
				out[n + k] = bytes[p + k]
			p += 256 - count
			n += 256 - count
			continue
		for k in count:
			out[n + k] = bytes[p]
		p += 1
		n += count
	return out


func _finish() -> void:
	if _step > STEPS.size():
		return
	_step = STEPS.size() + 1
	finished.emit()
