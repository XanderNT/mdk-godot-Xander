## An Autodesk FLC animation (`MISC/FLIC/*.FLC`): 8-bit frames with a palette, decoded one frame at a
## time into `indices` and `palette`. See docs/formats.md, "FLC".
##
##   header (128 bytes) ─▶ frame 1 (palette + BYTE_RUN) ─▶ frames 2…n (DELTA_FLC) ─▶ ring frame
##                          (back to frame 1, for looping)
class_name MDKFlc
extends RefCounted

const MAGIC := 0xAF12
const HEADER_SIZE := 128
const FRAME_HEADER_SIZE := 16
const SUB_CHUNK_HEADER_SIZE := 6
## Chunk types: frames, and the prefix chunk (skipped); in a frame the palette (256 levels or 64),
## deltas (word-oriented FLC, byte-oriented FLI), all black, a full run-length frame, raw pixels and
## the postage stamp (skipped).
const FRAME := 0xF1FA
const COLOR_256 := 4
const DELTA_FLC := 7
const COLOR_64 := 11
const DELTA_FLI := 12
const BLACK := 13
const BYTE_RUN := 15
const COPY := 16
## DELTA_FLC line words: the top two bits tell a packet count (00), a line skip (11) or the last
## pixel of an odd-width line (10).
const OPCODE_MASK := 0xC000
const OPCODE_SKIP := 0xC000
const OPCODE_LAST_BYTE := 0x8000

var width := 0
var height := 0
## Frames to show (the file has one more, the ring frame that leads back to the first).
var frame_count := 0
## Milliseconds per frame.
var speed := 0
## The current frame's palette indices (width × height) and palette (256 × RGB, 0–255).
var indices := PackedByteArray()
var palette := PackedByteArray()
## Frames decoded since the start (1 after the first).
var frame := 0

var _bytes: PackedByteArray
var _first_frame := 0
var _pos := 0


static func load_file(path: String) -> MDKFlc:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < HEADER_SIZE or bytes.decode_u16(4) != MAGIC:
		return null
	var flc := MDKFlc.new()
	flc._bytes = bytes
	flc.frame_count = bytes.decode_u16(6)
	flc.width = bytes.decode_u16(8)
	flc.height = bytes.decode_u16(10)
	flc.speed = bytes.decode_u32(16)
	flc._first_frame = bytes.decode_u32(80)
	if flc._first_frame == 0:
		flc._first_frame = HEADER_SIZE
	flc.indices.resize(flc.width * flc.height)
	flc.palette.resize(768)
	flc.rewind()
	return flc


## Back to before the first frame.
func rewind() -> void:
	_pos = _first_frame
	frame = 0
	indices.fill(0)


## Decodes the next frame. Returns false at the end (after `frame_count` frames).
func next_frame() -> bool:
	if frame >= frame_count:
		return false
	while _pos + SUB_CHUNK_HEADER_SIZE <= _bytes.size():
		var size := _bytes.decode_u32(_pos)
		var type := _bytes.decode_u16(_pos + 4)
		var start := _pos
		_pos += maxi(size, SUB_CHUNK_HEADER_SIZE)
		if type != FRAME:
			continue
		var chunks := _bytes.decode_u16(start + 6)
		var p := start + FRAME_HEADER_SIZE
		for i in chunks:
			var chunk_size := _bytes.decode_u32(p)
			_decode_chunk(_bytes.decode_u16(p + 4), p + SUB_CHUNK_HEADER_SIZE)
			p += maxi(chunk_size, SUB_CHUNK_HEADER_SIZE)
		frame += 1
		return true
	return false


func _decode_chunk(type: int, p: int) -> void:
	match type:
		COLOR_256:
			_decode_palette(p, 1)
		COLOR_64:
			_decode_palette(p, 4)
		BYTE_RUN:
			_decode_byte_run(p)
		DELTA_FLC:
			_decode_delta_flc(p)
		DELTA_FLI:
			_decode_delta_fli(p)
		BLACK:
			indices.fill(0)
		COPY:
			for i in indices.size():
				indices[i] = _bytes[p + i]


## Packets of (colours to skip, colours to set (0 = 256), RGB…); 64-level palettes are scaled.
func _decode_palette(p: int, scale: int) -> void:
	var packets := _bytes.decode_u16(p)
	p += 2
	var colour := 0
	for i in packets:
		colour += _bytes[p]
		var count := _bytes[p + 1]
		if count == 0:
			count = 256
		p += 2
		for k in count * 3:
			if colour * 3 + k < palette.size():
				palette[colour * 3 + k] = mini(_bytes[p + k] * scale, 255)
		p += count * 3
		colour += count


## Each line: a packet count (ignored), then runs until the line is full: a negative count copies
## that many bytes, a positive one repeats the next byte.
func _decode_byte_run(p: int) -> void:
	for y in height:
		p += 1
		var x := 0
		var row := y * width
		while x < width:
			var count := _signed(_bytes[p])
			p += 1
			if count < 0:
				for k in -count:
					indices[row + x + k] = _bytes[p + k]
				p += -count
				x += -count
			else:
				var value := _bytes[p]
				p += 1
				for k in count:
					indices[row + x + k] = value
				x += count


## Lines of word packets: line words first (skips, the last byte of odd lines, then the packet
## count), then packets of (columns to skip, count): a positive count copies that many words, a
## negative one repeats one word.
func _decode_delta_flc(p: int) -> void:
	var lines := _bytes.decode_u16(p)
	p += 2
	var y := 0
	for line in lines:
		var packets := 0
		while true:
			var word := _bytes.decode_u16(p)
			p += 2
			if word & OPCODE_MASK == OPCODE_SKIP:
				y += 0x10000 - word
			elif word & OPCODE_MASK == OPCODE_LAST_BYTE:
				indices[y * width + width - 1] = word & 0xFF
			else:
				packets = word
				break
		var x := 0
		var row := y * width
		for i in packets:
			x += _bytes[p]
			var count := _signed(_bytes[p + 1])
			p += 2
			if count > 0:
				for k in count * 2:
					indices[row + x + k] = _bytes[p + k]
				p += count * 2
				x += count * 2
			else:
				var a := _bytes[p]
				var b := _bytes[p + 1]
				p += 2
				for k in -count:
					indices[row + x] = a
					indices[row + x + 1] = b
					x += 2
		y += 1


## The older byte delta: the first line and the line count, then per line packets of (columns to
## skip, count): positive copies bytes, negative repeats one.
func _decode_delta_fli(p: int) -> void:
	var y := _bytes.decode_u16(p)
	var lines := _bytes.decode_u16(p + 2)
	p += 4
	for line in lines:
		var packets := _bytes[p]
		p += 1
		var x := 0
		var row := y * width
		for i in packets:
			x += _bytes[p]
			var count := _signed(_bytes[p + 1])
			p += 2
			if count > 0:
				for k in count:
					indices[row + x + k] = _bytes[p + k]
				p += count
				x += count
			else:
				var value := _bytes[p]
				p += 1
				for k in -count:
					indices[row + x + k] = value
				x += -count
		y += 1


static func _signed(value: int) -> int:
	return value - 256 if value > 127 else value
