## An 8-bit paletted texture: `u16 width, u16 height`, then `width × height` palette indices.
## Animated textures store `frame_count` frames of `width × height` one after another.
class_name MDKTexture
extends RefCounted

## Animated texture kinds: frames as changes to the first one (0x20000).
const DELTAS := 0x20000
const DELTA_UNIT := 4

var name := ""
var width := 0
## Height of one frame.
var height := 0
var frame_count := 1
## Palette indices, row by row (all frames).
var indices := PackedByteArray()

var _index_texture: ImageTexture


static func parse(p_name: String, bytes: PackedByteArray, offset: int) -> MDKTexture:
	var texture := MDKTexture.new()
	texture.name = p_name
	texture.width = bytes.decode_u16(offset)
	texture.height = bytes.decode_u16(offset + 2)
	texture.indices = bytes.slice(offset + 4, offset + 4 + texture.width * texture.height)
	return texture


## Parses an animated texture: `u32 frame count, u16 width, u16 height`, then the frames back to
## back, or with `DELTAS` (kind 0x20000, `M_COMM`, 0x422c00) the first frame and the changes that
## make each next one (`_apply_deltas`).
static func parse_animated(p_name: String, bytes: PackedByteArray, offset: int, kind := 0) -> MDKTexture:
	var texture := MDKTexture.new()
	texture.name = p_name
	texture.frame_count = bytes.decode_u32(offset)
	texture.width = bytes.decode_u16(offset + 4)
	texture.height = bytes.decode_u16(offset + 6)
	var size := texture.width * texture.height
	if kind & DELTAS:
		texture.indices = _apply_deltas(bytes, offset + 8, size, texture.frame_count)
	else:
		texture.indices = bytes.slice(offset + 8, offset + 8 + size * texture.frame_count)
	return texture


## The frames of a delta texture: after the first frame, `f32` (the current frame at run time)
## and `u32` offsets (from after it) to `2n` blocks: n controls, then n data. A control is
## `u16 start, u16 runs`, then per run `u8 copy, u8 skip`, in units of 4 pixels: from `start × 4`,
## each run copies `copy × 4` bytes of its data block, then moves on by `(copy + skip) × 4`. Change
## k turns frame k into frame k + 1 (the last one leads back to the first).
static func _apply_deltas(bytes: PackedByteArray, p: int, size: int, count: int) -> PackedByteArray:
	var frame := bytes.slice(p, p + size)
	var frames := frame.duplicate()
	var table := p + size + 4
	for k in count - 1:
		var control := table + bytes.decode_u32(table + k * 4)
		var data := table + bytes.decode_u32(table + (count + k) * 4)
		var destination := bytes.decode_u16(control) * DELTA_UNIT
		var runs := bytes.decode_u16(control + 2)
		for run in runs:
			var copy := bytes[control + 4 + run * 2] * DELTA_UNIT
			var skip := bytes[control + 5 + run * 2] * DELTA_UNIT
			for i in copy:
				if destination + i < size:
					frame[destination + i] = bytes[data + i]
			data += copy
			destination += copy + skip
		frames.append_array(frame)
	return frames


## Returns the palette indices as a single-channel texture, for use with `palette.gdshader`.
## Frames of animated textures are stacked vertically.
func get_index_texture() -> ImageTexture:
	if not _index_texture:
		var image := Image.create_from_data(width, height * frame_count, false, Image.FORMAT_R8, indices)
		_index_texture = ImageTexture.create_from_image(image)
	return _index_texture
