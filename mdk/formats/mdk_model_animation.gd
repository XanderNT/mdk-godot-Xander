## A vertex animation of a model's parts. See `docs/formats.md` ("Animation").
class_name MDKModelAnimation
extends RefCounted

var name := ""
## 1.0 means 30 frames per second.
var speed := 1.0
var frame_count := 0
## Per frame, the object's movement in model space (MDK coordinates).
var root_motion := PackedVector3Array()
## Per reference point, its place in each frame (model space; `anim_step_frames` 0x43ab70 copies
## them to the model's reference points, at most 8).
var reference_points: Array[PackedVector3Array] = []

var _bytes: PackedByteArray
## The 1996 demo's layout (`parse_beta`).
var _beta := false
## Lowercase track name to the track's offset.
var _tracks := {}


static func parse(p_name: String, bytes: PackedByteArray, offset: int) -> MDKModelAnimation:
	var animation := MDKModelAnimation.new()
	animation.name = p_name
	animation._bytes = bytes
	var r := BinReader.new(bytes, offset)
	animation.speed = r.f32()
	var track_count := r.u32()
	animation.frame_count = r.u32()
	for i in track_count:
		var track_offset := offset + 4 + r.u32()
		var track_name := bytes.slice(track_offset, track_offset + 12).get_string_from_ascii()
		animation._tracks[track_name.to_lower()] = track_offset
	animation.root_motion.resize(animation.frame_count)
	for f in animation.frame_count:
		animation.root_motion[f] = r.vec3()
	for i in r.u32():
		var points := PackedVector3Array()
		points.resize(animation.frame_count)
		for f in animation.frame_count:
			points[f] = r.vec3()
		animation.reference_points.push_back(points)
	return animation


## Parses an animation of the 1996 demo (`MDKBeta`), kept in `LEVELn.CMI`:
##
## ```
## +0   u32 track count T
## +4   u32 frame count F
## +8   u32 track offset[T]         relative to the animation
##      f32 root motion[F][3]
##      f32 bounds[F][6]            the model's box in each frame
##      u32 reference point count R, f32[R][F][3]
## track: char[12] part name, u32 vertex count, f32 scale, f32 base[n][3],
##        then for each of the other F − 1 frames s8 delta[n][3]
## ```
##
## There's no speed, the delta records of every frame follow each other without frame numbers,
## and no track uses matrices.
static func parse_beta(p_name: String, bytes: PackedByteArray, offset: int) -> MDKModelAnimation:
	var animation := MDKModelAnimation.new()
	animation.name = p_name
	animation._bytes = bytes
	animation._beta = true
	var r := BinReader.new(bytes, offset)
	var track_count := r.u32()
	animation.frame_count = r.u32()
	for i in track_count:
		var track_offset := offset + r.u32()
		var track_name := bytes.slice(track_offset, track_offset + 12).get_string_from_ascii()
		animation._tracks[track_name.to_lower()] = track_offset
	animation.root_motion.resize(animation.frame_count)
	for f in animation.frame_count:
		animation.root_motion[f] = r.vec3()
	r.skip(animation.frame_count * 24)
	for i in r.u32():
		var points := PackedVector3Array()
		points.resize(animation.frame_count)
		for f in animation.frame_count:
			points[f] = r.vec3()
		animation.reference_points.push_back(points)
	return animation


## Computes the vertices of every part of `model` for every frame. Returns an Array of frames, each an
## Array[PackedVector3Array] in part order. Parts without a track keep their model vertices.
func bake(model: MDKModel) -> Array:
	var per_part: Array = []
	for part in model.parts:
		var key := part.name.to_lower()
		if _tracks.has(key):
			per_part.push_back(_decode_track(_tracks[key], part.vertices.size()))
		else:
			per_part.push_back(null)
	var frames := []
	for f in frame_count:
		var pose: Array[PackedVector3Array] = []
		for p in model.parts.size():
			pose.push_back(per_part[p][f] if per_part[p] != null else model.parts[p].vertices)
		frames.push_back(pose)
	return frames


## Returns the vertices of a track for every frame (`vertex_count` comes from the model part).
func _decode_track(offset: int, vertex_count: int) -> Array[PackedVector3Array]:
	var frames: Array[PackedVector3Array] = []
	var scale_bits := _bytes.decode_u32(offset + 16)
	if _beta:
		_decode_beta_track(offset, vertex_count, _bytes.decode_float(offset + 16), frames)
	elif scale_bits & 0x7FFFFFFF == 0:
		_decode_matrix_track(offset, vertex_count, frames)
	else:
		_decode_delta_track(offset, vertex_count, _bytes.decode_float(offset + 16), frames)
	return frames


## Delta tracks: base vertices, then records of `s16 frame, s8 delta[n][3]` (ending with frame −1)
## adding `delta × scale` to the previous frame's vertices.
func _decode_delta_track(offset: int, vertex_count: int, scale: float, frames: Array[PackedVector3Array]) -> void:
	var r := BinReader.new(_bytes, offset + 20)
	var vertices := PackedVector3Array()
	vertices.resize(vertex_count)
	for v in vertex_count:
		vertices[v] = r.vec3()
	frames.push_back(vertices.duplicate())
	var next_record := r.s16()
	for f in range(1, frame_count):
		if next_record == f:
			for v in vertex_count:
				var dx := _signed_byte(r.u8())
				var dy := _signed_byte(r.u8())
				var dz := _signed_byte(r.u8())
				vertices[v] += Vector3(dx, dy, dz) * scale
			next_record = r.s16()
		frames.push_back(vertices.duplicate())


## The 1996 demo's tracks: base vertices, then `s8 delta[n][3]` for every following frame.
func _decode_beta_track(offset: int, vertex_count: int, scale: float, frames: Array[PackedVector3Array]) -> void:
	var r := BinReader.new(_bytes, offset + 20)
	var vertices := PackedVector3Array()
	vertices.resize(vertex_count)
	for v in vertex_count:
		vertices[v] = r.vec3()
	frames.push_back(vertices.duplicate())
	for f in range(1, frame_count):
		for v in vertex_count:
			var dx := _signed_byte(r.u8())
			var dy := _signed_byte(r.u8())
			var dz := _signed_byte(r.u8())
			vertices[v] += Vector3(dx, dy, dz) * scale
		frames.push_back(vertices.duplicate())


## Matrix tracks (rigid parts): shifts, base vertices, then a 3×4 `s16` matrix per frame.
func _decode_matrix_track(offset: int, vertex_count: int, frames: Array[PackedVector3Array]) -> void:
	var rotation_scale := 1.0 / float(0x8000 >> _bytes[offset + 20])
	var position_scale := 1.0 / float(0x8000 >> _bytes[offset + 21])
	var r := BinReader.new(_bytes, offset + 22)
	var base := PackedVector3Array()
	base.resize(vertex_count)
	for v in vertex_count:
		base[v] = r.vec3()
	for f in frame_count:
		var m := []
		for i in 12:
			m.push_back(r.s16())
		var basis := Basis(
				Vector3(m[0], m[4], m[8]) * rotation_scale,
				Vector3(m[1], m[5], m[9]) * rotation_scale,
				Vector3(m[2], m[6], m[10]) * rotation_scale)
		var origin := Vector3(m[3], m[7], m[11]) * position_scale
		var vertices := PackedVector3Array()
		vertices.resize(vertex_count)
		for v in vertex_count:
			vertices[v] = basis * base[v] + origin
		frames.push_back(vertices)


static func _signed_byte(value: int) -> int:
	return value - 256 if value >= 128 else value
