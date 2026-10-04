## A still GIF (`MISC/MDKS_00n.GIF`, the menu's slideshow): the first image's palette indices and
## its palette (256 × RGB). See docs/formats.md, "GIF".
##
##   header ─▶ global palette ─▶ extensions (skipped) ─▶ image descriptor ─▶ LZW data
class_name MDKGif
extends RefCounted

const SIGNATURE := "GIF"
const HEADER_SIZE := 13
const IMAGE := 0x2C
const EXTENSION := 0x21
const TRAILER := 0x3B
## Packed fields: a colour table follows (its size is 2 << the low 3 bits); interlaced rows.
const HAS_TABLE := 0x80
const TABLE_SIZE := 0x07
const INTERLACED := 0x40
const MAX_CODE_SIZE := 12
## Interlaced rows come in four passes: start row and step.
const PASSES := [[0, 8], [4, 8], [2, 4], [1, 2]]

var width := 0
var height := 0
var indices := PackedByteArray()
var palette := PackedByteArray()

var _bytes: PackedByteArray


static func load_file(path: String) -> MDKGif:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < HEADER_SIZE or bytes.slice(0, 3).get_string_from_ascii() != SIGNATURE:
		return null
	var gif := MDKGif.new()
	gif._bytes = bytes
	return gif if gif._parse() else null


func _parse() -> bool:
	width = _bytes.decode_u16(6)
	height = _bytes.decode_u16(8)
	palette.resize(768)
	var p := HEADER_SIZE
	var fields := _bytes[10]
	if fields & HAS_TABLE:
		p = _read_palette(p, fields)
	while p < _bytes.size():
		var block := _bytes[p]
		p += 1
		if block == EXTENSION:
			p = _skip_sub_blocks(p + 1)
		elif block == IMAGE:
			return _read_image(p)
		else:
			return false
	return false


func _read_palette(p: int, fields: int) -> int:
	var count := 2 << (fields & TABLE_SIZE)
	for i in count * 3:
		palette[i] = _bytes[p + i]
	return p + count * 3


func _skip_sub_blocks(p: int) -> int:
	while p < _bytes.size() and _bytes[p] != 0:
		p += _bytes[p] + 1
	return p + 1


func _read_image(p: int) -> bool:
	var left := _bytes.decode_u16(p)
	var top := _bytes.decode_u16(p + 2)
	var image_width := _bytes.decode_u16(p + 4)
	var image_height := _bytes.decode_u16(p + 6)
	var fields := _bytes[p + 8]
	p += 9
	if fields & HAS_TABLE:
		p = _read_palette(p, fields)
	var code_size := _bytes[p]
	var data := PackedByteArray()
	p += 1
	while p < _bytes.size() and _bytes[p] != 0:
		data.append_array(_bytes.slice(p + 1, p + 1 + _bytes[p]))
		p += _bytes[p] + 1
	var pixels := _lzw(data, code_size, image_width * image_height)

	indices.resize(width * height)
	var rows := _row_order(image_height, fields & INTERLACED != 0)
	for i in image_height:
		var y: int = rows[i] + top
		if y >= height:
			continue
		for x in mini(image_width, width - left):
			indices[y * width + left + x] = pixels[i * image_width + x]
	return true


## The image's rows in the order they're stored.
static func _row_order(rows: int, interlaced: bool) -> PackedInt32Array:
	var order := PackedInt32Array()
	if not interlaced:
		order.resize(rows)
		for i in rows:
			order[i] = i
		return order
	for pass_rows: Array in PASSES:
		for y in range(pass_rows[0], rows, pass_rows[1]):
			order.push_back(y)
	return order


## Variable-width LZW: codes grow from `min_size + 1` bits up to 12; a clear code starts over.
static func _lzw(data: PackedByteArray, min_size: int, count: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(count)
	var clear := 1 << min_size
	var end := clear + 1
	# Each code is a prefix code and its last byte; strings are rebuilt backwards.
	var prefixes := PackedInt32Array()
	var suffixes := PackedByteArray()
	var firsts := PackedByteArray()
	prefixes.resize(1 << MAX_CODE_SIZE)
	suffixes.resize(1 << MAX_CODE_SIZE)
	firsts.resize(1 << MAX_CODE_SIZE)
	for i in clear:
		prefixes[i] = -1
		suffixes[i] = i
		firsts[i] = i
	var stack := PackedByteArray()
	stack.resize(1 << MAX_CODE_SIZE)

	var size := min_size + 1
	var next := end + 1
	var previous := -1
	var bits := 0
	var bit_count := 0
	var written := 0
	var p := 0
	while written < count:
		while bit_count < size and p < data.size():
			bits |= data[p] << bit_count
			bit_count += 8
			p += 1
		if bit_count < size:
			break
		var code := bits & ((1 << size) - 1)
		bits >>= size
		bit_count -= size
		if code == clear:
			size = min_size + 1
			next = end + 1
			previous = -1
			continue
		if code == end:
			break

		# A code not defined yet is the previous string plus its own first byte.
		var current := code
		var depth := 0
		if code >= next and previous >= 0:
			stack[0] = firsts[previous]
			depth = 1
			current = previous
		while current >= 0:
			stack[depth] = suffixes[current]
			depth += 1
			current = prefixes[current]
		for k in range(depth - 1, -1, -1):
			if written < count:
				out[written] = stack[k]
				written += 1

		if previous >= 0 and next < (1 << MAX_CODE_SIZE):
			prefixes[next] = previous
			suffixes[next] = stack[depth - 1]
			firsts[next] = firsts[previous]
			next += 1
			if next == (1 << size) and size < MAX_CODE_SIZE:
				size += 1
		previous = code
	return out
