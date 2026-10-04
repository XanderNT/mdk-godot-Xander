## An Interplay MVE movie (`MISC/FLIC/MDKBZK.MVE`, the end of the game): chunks of opcodes that set
## up the screen and the sound, then per frame a decoding map (4 bits per 8×8 block), the blocks'
## data (video format 0x11, 8 bits) and DPCM sound. `next_frame` decodes up to the next shown
## frame. See docs/formats.md, "Videos and images".
##
##   signature (26 bytes) ─▶ chunk [u16 size, u16 type] ─▶ opcode [u16 size, u8 type, u8 version, data]
##
## Frames are decoded into the back buffer, which still holds the frame before the last one
## (double buffering): blocks stay as they are, copy from the frame shown last or from the back
## buffer itself, or are drawn from 1 to 64 colours.
class_name MDKMve
extends RefCounted

const SIGNATURE := "Interplay MVE File\u001a"
const SIGNATURE_SIZE := 26
const CHUNK_HEADER := 4
const OPCODE_HEADER := 4
## Opcodes.
const END_OF_STREAM := 0x00
const END_OF_CHUNK := 0x01
const CREATE_TIMER := 0x02
const INIT_AUDIO := 0x03
const INIT_VIDEO := 0x05
const SEND_BUFFER := 0x07
const AUDIO_FRAME := 0x08
const SILENCE_FRAME := 0x09
const SET_PALETTE := 0x0C
const DECODING_MAP := 0x0F
const VIDEO_DATA := 0x11
## Audio flags: stereo, 16 bits, compressed (DPCM, from version 1).
const AUDIO_STEREO := 1
const AUDIO_16_BIT := 2
const AUDIO_COMPRESSED := 4
## The sound of stream 0 only.
const STREAM_MASK := 1
## The video data starts with a 14-byte header.
const VIDEO_HEADER := 14
const BLOCK := 8
## Interplay DPCM: each byte is an index into this table of steps.
const DELTAS: Array[int] = [
	0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
	16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
	32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 47, 51, 56, 61,
	66, 72, 79, 86, 94, 102, 112, 122, 133, 145, 158, 173, 189, 206, 225, 245,
	267, 292, 318, 348, 379, 414, 452, 493, 538, 587, 640, 699, 763, 832, 908, 991,
	1081, 1180, 1288, 1405, 1534, 1673, 1826, 1993, 2175, 2373, 2590, 2826, 3084, 3365, 3672, 4008,
	4373, 4772, 5208, 5683, 6202, 6767, 7385, 8059, 8794, 9597, 10472, 11428, 12471, 13609, 14851, 16206,
	17685, 19298, 21060, 22981, 25078, 27367, 29864, 32589, -29973, -26728, -23186, -19322, -15105, -10503, -5481, -1,
	1, 1, 5481, 10503, 15105, 19322, 23186, 26728, 29973, -32589, -29864, -27367, -25078, -22981, -21060, -19298,
	-17685, -16206, -14851, -13609, -12471, -11428, -10472, -9597, -8794, -8059, -7385, -6767, -6202, -5683, -5208, -4772,
	-4373, -4008, -3672, -3365, -3084, -2826, -2590, -2373, -2175, -1993, -1826, -1673, -1534, -1405, -1288, -1180,
	-1081, -991, -908, -832, -763, -699, -640, -587, -538, -493, -452, -414, -379, -348, -318, -292,
	-267, -245, -225, -206, -189, -173, -158, -145, -133, -122, -112, -102, -94, -86, -79, -72,
	-66, -61, -56, -51, -47, -43, -42, -41, -40, -39, -38, -37, -36, -35, -34, -33,
	-32, -31, -30, -29, -28, -27, -26, -25, -24, -23, -22, -21, -20, -19, -18, -17,
	-16, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1,
]

var width := 0
var height := 0
## Microseconds per frame.
var frame_time := 0
var sample_rate := 0
var channels := 1
## The palette (256 × RGB, 0–255).
var palette := PackedByteArray()
## Sound decoded since the last call, as stereo frames (−1–1).
var audio := PackedVector2Array()
## Frames shown so far.
var frame := 0

var _bytes: PackedByteArray
var _pos := 0
var _audio_flags := 0
## The back buffer (being decoded) and the frame shown last.
var _current := PackedByteArray()
var _last := PackedByteArray()
var _map := PackedByteArray()
var _predictors := PackedInt32Array([0, 0])
var _shown := false
var _ended := false


static func load_file(path: String) -> MDKMve:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < SIGNATURE_SIZE or bytes.slice(0, SIGNATURE.length()).get_string_from_ascii() != SIGNATURE:
		return null
	var mve := MDKMve.new()
	mve._bytes = bytes
	mve._pos = SIGNATURE_SIZE
	mve.palette.resize(768)
	return mve


## The frame shown last (width × height palette indices).
func get_indices() -> PackedByteArray:
	return _last


## Runs opcodes up to the next shown frame. Returns false at the end of the movie.
func next_frame() -> bool:
	audio.clear()
	_shown = false
	while not _ended and not _shown and _pos + CHUNK_HEADER <= _bytes.size():
		var size := _bytes.decode_u16(_pos)
		var end := _pos + CHUNK_HEADER + size
		_pos += CHUNK_HEADER
		while _pos + OPCODE_HEADER <= end:
			var length := _bytes.decode_u16(_pos)
			var type := _bytes[_pos + 2]
			var version := _bytes[_pos + 3]
			_run(type, version, _pos + OPCODE_HEADER, length)
			_pos += OPCODE_HEADER + length
			if type == END_OF_STREAM:
				_ended = true
		_pos = end
	if _shown:
		frame += 1
	return _shown


func _run(type: int, version: int, p: int, length: int) -> void:
	match type:
		CREATE_TIMER:
			frame_time = _bytes.decode_u32(p) * _bytes.decode_u16(p + 4)
		INIT_AUDIO:
			_audio_flags = _bytes.decode_u16(p + 2)
			if version == 0:
				_audio_flags &= ~AUDIO_COMPRESSED
			sample_rate = _bytes.decode_u16(p + 4)
			channels = 2 if _audio_flags & AUDIO_STEREO else 1
		INIT_VIDEO:
			_init_video(_bytes.decode_u16(p) * BLOCK, _bytes.decode_u16(p + 2) * BLOCK)
		SET_PALETTE:
			_set_palette(p)
		DECODING_MAP:
			_map = _bytes.slice(p, p + length)
		VIDEO_DATA:
			_decode_video(p + VIDEO_HEADER, p + length)
		SEND_BUFFER:
			_show()
		AUDIO_FRAME:
			if _bytes.decode_u16(p + 2) & STREAM_MASK:
				_decode_audio(p + 6, p + length, _bytes.decode_u16(p + 4))
		SILENCE_FRAME:
			if _bytes.decode_u16(p + 2) & STREAM_MASK:
				_silence(_bytes.decode_u16(p + 4))


func _init_video(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	for buffer in [_current, _last]:
		buffer.resize(width * height)
		buffer.fill(0)


## 6-bit levels scaled to 8 bits as ffmpeg does (`v × 4 + v / 16`).
func _set_palette(p: int) -> void:
	var start := _bytes.decode_u16(p)
	var count := _bytes.decode_u16(p + 2)
	p += 4
	for i in count * 3:
		var index := start * 3 + i
		if index >= palette.size():
			break
		var v := _bytes[p + i] & 0x3F
		palette[index] = (v << 2) | (v >> 4)


## The buffers swap: the decoded frame is shown.
func _show() -> void:
	var back := _last
	_last = _current
	_current = back
	_shown = true


# Sound.

func _decode_audio(p: int, end: int, size: int) -> void:
	if not _audio_flags & AUDIO_COMPRESSED:
		_decode_pcm(p, end)
		return
	var samples := PackedInt32Array()
	samples.resize(size / 2)
	var count := 0
	for ch in channels:
		_predictors[ch] = _bytes.decode_s16(p)
		samples[count] = _predictors[ch]
		count += 1
		p += 2
	var ch := 0
	while count < samples.size() and p < end:
		_predictors[ch] = clampi(_predictors[ch] + DELTAS[_bytes[p]], -32768, 32767)
		samples[count] = _predictors[ch]
		count += 1
		p += 1
		ch ^= channels - 1
	_push_samples(samples, count)


func _decode_pcm(p: int, end: int) -> void:
	var samples := PackedInt32Array()
	var step := 2 if _audio_flags & AUDIO_16_BIT else 1
	while p + step <= end:
		samples.push_back(_bytes.decode_s16(p) if step == 2 else (_bytes[p] - 128) << 8)
		p += step
	_push_samples(samples, samples.size())


func _silence(size: int) -> void:
	var frames := size / (2 * channels)
	for i in frames:
		audio.push_back(Vector2.ZERO)


func _push_samples(samples: PackedInt32Array, count: int) -> void:
	var scale := 1.0 / 32768.0
	if channels == 1:
		for i in count:
			audio.push_back(Vector2.ONE * samples[i] * scale)
		return
	for i in range(0, count - 1, 2):
		audio.push_back(Vector2(samples[i], samples[i + 1]) * scale)


# Video: one opcode (4 bits of the map, low nibble first) per 8×8 block.

func _decode_video(p: int, end: int) -> void:
	var block := 0
	for by in range(0, height, BLOCK):
		for bx in range(0, width, BLOCK):
			var code := _map[block >> 1] >> 4 if block & 1 else _map[block >> 1] & 0x0F
			block += 1
			p = _decode_block(code, bx, by, p)
			if p > end:
				return


## Decodes one block at (`x`, `y`) from the data at `p`; returns where the next block's data starts.
func _decode_block(code: int, x: int, y: int, p: int) -> int:
	var o := y * width + x
	match code:
		0x0:
			_copy(_last, o, 0, 0)
		0x1:
			pass
		0x2:
			var b := _bytes[p]
			if b < 56:
				_copy(_current, o, 8 + b % 7, b / 7)
			else:
				_copy(_current, o, -14 + (b - 56) % 29, 8 + (b - 56) / 29)
			return p + 1
		0x3:
			var b := _bytes[p]
			if b < 56:
				_copy(_current, o, -(8 + b % 7), -(b / 7))
			else:
				_copy(_current, o, -(-14 + (b - 56) % 29), -(8 + (b - 56) / 29))
			return p + 1
		0x4:
			var b := _bytes[p]
			_copy(_last, o, -8 + (b & 0x0F), -8 + (b >> 4))
			return p + 1
		0x5:
			_copy(_last, o, _signed(_bytes[p]), _signed(_bytes[p + 1]))
			return p + 2
		0x7:
			return _two_colours(o, p)
		0x8:
			return _two_colours_quadrants(o, p)
		0x9:
			return _four_colours(o, p)
		0xA:
			return _four_colours_quadrants(o, p)
		0xB:
			for row in BLOCK:
				for col in BLOCK:
					_current[o + row * width + col] = _bytes[p + row * BLOCK + col]
			return p + 64
		0xC:
			for i in 16:
				_fill(o + (i >> 2) * 2 * width + (i & 3) * 2, 2, 2, _bytes[p + i])
			return p + 16
		0xD:
			for i in 4:
				_fill(o + (i >> 1) * 4 * width + (i & 1) * 4, 4, 4, _bytes[p + i])
			return p + 4
		0xE:
			_fill(o, BLOCK, BLOCK, _bytes[p])
			return p + 1
		0xF:
			for row in BLOCK:
				for col in BLOCK:
					_current[o + row * width + col] = _bytes[p + ((row + col) & 1)]
			return p + 2
	return p


## Copies the 8×8 block from `source` at the block's place moved by (`dx`, `dy`).
func _copy(source: PackedByteArray, o: int, dx: int, dy: int) -> void:
	var from := o + dy * width + dx
	if from < 0 or from + 7 * width + BLOCK > source.size():
		return
	for row in BLOCK:
		var a := o + row * width
		var b := from + row * width
		for col in BLOCK:
			_current[a + col] = source[b + col]


func _fill(o: int, w: int, h: int, value: int) -> void:
	for row in h:
		for col in w:
			_current[o + row * width + col] = value


## Two colours: P0 ≤ P1, a bit per pixel (8 bytes, a row each, low bit first); else a bit per
## 2×2 (16 bits).
func _two_colours(o: int, p: int) -> int:
	var p0 := _bytes[p]
	var p1 := _bytes[p + 1]
	p += 2
	if p0 <= p1:
		for row in BLOCK:
			var flags := _bytes[p + row]
			for col in BLOCK:
				_current[o + row * width + col] = p1 if flags >> col & 1 else p0
		return p + 8
	var bits := _bytes.decode_u16(p)
	for i in 16:
		_fill(o + (i >> 2) * 2 * width + (i & 3) * 2, 2, 2, p1 if bits >> i & 1 else p0)
	return p + 2


## Two colours per 4×4 quadrant (P0 ≤ P1: quadrants top-left, bottom-left, top-right,
## bottom-right, each with its colours and 16 bits), or per half (P2 ≤ P3: left and right, else top
## and bottom; 32 bits each).
func _two_colours_quadrants(o: int, p: int) -> int:
	var colours := [_bytes[p], _bytes[p + 1]]
	if colours[0] <= colours[1]:
		for q in 4:
			if q > 0:
				colours = [_bytes[p], _bytes[p + 1]]
			var bits := _bytes.decode_u16(p + 2)
			p += 4
			var qo := o + (q & 1) * 4 * width + (q >> 1) * 4
			for i in 16:
				_current[qo + (i >> 2) * width + (i & 3)] = colours[bits >> i & 1]
		return p
	var bits := _bytes.decode_u32(p + 2)
	var other := [_bytes[p + 6], _bytes[p + 7]]
	p += 8
	if other[0] <= other[1]:
		# Left half, then right.
		for half in 2:
			if half == 1:
				colours = other
				bits = _bytes.decode_u32(p)
				p += 4
			for i in 32:
				_current[o + (i >> 2) * width + half * 4 + (i & 3)] = colours[bits >> i & 1]
		return p
	for half in 2:
		if half == 1:
			colours = other
			bits = _bytes.decode_u32(p)
			p += 4
		for i in 32:
			_current[o + (half * 4 + (i >> 3)) * width + (i & 7)] = colours[bits >> i & 1]
	return p


## Four colours: P0 ≤ P1 and P2 ≤ P3: 2 bits per pixel (16 bytes); P0 ≤ P1: per 2×2 (4 bytes);
## else 64 bits per 2×1 (P2 ≤ P3) or 1×2 pairs.
func _four_colours(o: int, p: int) -> int:
	var colours := [_bytes[p], _bytes[p + 1], _bytes[p + 2], _bytes[p + 3]]
	p += 4
	if colours[0] <= colours[1]:
		if colours[2] <= colours[3]:
			for row in BLOCK:
				var flags := _bytes.decode_u16(p + row * 2)
				for col in BLOCK:
					_current[o + row * width + col] = colours[flags >> (col * 2) & 3]
			return p + 16
		var bits := _bytes.decode_u32(p)
		for i in 16:
			_fill(o + (i >> 2) * 2 * width + (i & 3) * 2, 2, 2, colours[bits >> (i * 2) & 3])
		return p + 4
	var low := _bytes.decode_u32(p)
	var high := _bytes.decode_u32(p + 4)
	for i in 32:
		var c: int = colours[(low >> (i * 2) & 3) if i < 16 else (high >> ((i - 16) * 2) & 3)]
		if colours[2] <= colours[3]:
			_fill(o + (i >> 2) * width + (i & 3) * 2, 2, 1, c)
		else:
			_fill(o + (i >> 3) * 2 * width + (i & 7), 1, 2, c)
	return p + 8


## Four colours per 4×4 quadrant (P0 ≤ P1: each with its colours and 32 bits, in the order of
## `_two_colours_quadrants`), or per half (P4 ≤ P5 of the second half: left and right, else top and
## bottom; 64 bits each).
func _four_colours_quadrants(o: int, p: int) -> int:
	var colours := [_bytes[p], _bytes[p + 1], _bytes[p + 2], _bytes[p + 3]]
	if colours[0] <= colours[1]:
		for q in 4:
			if q > 0:
				colours = [_bytes[p], _bytes[p + 1], _bytes[p + 2], _bytes[p + 3]]
			var bits := _bytes.decode_u32(p + 4)
			p += 8
			var qo := o + (q & 1) * 4 * width + (q >> 1) * 4
			for i in 16:
				_current[qo + (i >> 2) * width + (i & 3)] = colours[bits >> (i * 2) & 3]
		return p
	var low := _bytes.decode_u32(p + 4)
	var high := _bytes.decode_u32(p + 8)
	var other := [_bytes[p + 12], _bytes[p + 13], _bytes[p + 14], _bytes[p + 15]]
	p += 16
	var vertical: bool = other[0] <= other[1]
	for half in 2:
		if half == 1:
			colours = other
			low = _bytes.decode_u32(p)
			high = _bytes.decode_u32(p + 4)
			p += 8
		for i in 32:
			var c: int = colours[(low >> (i * 2) & 3) if i < 16 else (high >> ((i - 16) * 2) & 3)]
			if vertical:
				_current[o + (i >> 2) * width + half * 4 + (i & 3)] = c
			else:
				_current[o + (half * 4 + (i >> 3)) * width + (i & 7)] = c
	return p


static func _signed(value: int) -> int:
	return value - 256 if value > 127 else value
