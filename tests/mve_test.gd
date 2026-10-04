## Test of `MDKMve`: frames and sound match what ffmpeg decodes (MD5 of the palette indices, and of
## the first samples as 16-bit stereo, first 8 hex digits). Run: godot --headless --path . -s
## tests/mve_test.gd
extends SceneTree

const MOVIE := "C:/Games/MDK/MISC/FLIC/MDKBZK.MVE"
## Frame index (from 0) → MD5 of its indices.
const FRAMES := {0: "b15de029", 150: "944265b0", 200: "88e648dd", 201: "8e8da703", 300: "b9322847", 400: "520d06c1",
		1000: "9762c44f", 1500: "a53eb2b2", 2000: "28b1cf1e"}
const LAST_FRAME := 2000
## A frame's colours (RGB through the palette).
const COLOUR_FRAME := 300
const COLOURS := "3fe8c38c"
## Number of 16-bit samples (both channels) → MD5.
const SOUND := {1000: "cf40a1de", 100000: "921e58e2"}

var _failures := 0


func _initialize() -> void:
	var mve := MDKMve.load_file(MOVIE)
	if not mve:
		_fail("not loaded")
		_finish()
		return
	var samples := PackedByteArray()
	var start := Time.get_ticks_msec()
	for i in LAST_FRAME + 1:
		if not mve.next_frame():
			_fail("ended at frame %d" % i)
			break
		for frame in mve.audio:
			if samples.size() < 400000:
				samples.append_array(_s16(frame.x))
				samples.append_array(_s16(frame.y))
		if i == COLOUR_FRAME and _md5(_rgb(mve)) != COLOURS:
			_fail("frame %d colours: %s" % [i, _md5(_rgb(mve))])
		if FRAMES.has(i) and _md5(mve.get_indices()) != FRAMES[i]:
			_fail("frame %d: %s, expected %s" % [i, _md5(mve.get_indices()), FRAMES[i]])
	print("%dx%d, %d µs a frame, %d Hz × %d; %d frames in %d ms" % [mve.width, mve.height, mve.frame_time,
			mve.sample_rate, mve.channels, LAST_FRAME + 1, Time.get_ticks_msec() - start])
	for count: int in SOUND:
		var got := _md5(samples.slice(0, count * 2))
		if got != SOUND[count]:
			_fail("first %d samples: %s, expected %s" % [count, got, SOUND[count]])
	_finish()


func _finish() -> void:
	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


static func _rgb(mve: MDKMve) -> PackedByteArray:
	var indices := mve.get_indices()
	var rgb := PackedByteArray()
	rgb.resize(indices.size() * 3)
	for i in indices.size():
		for k in 3:
			rgb[i * 3 + k] = mve.palette[indices[i] * 3 + k]
	return rgb


static func _s16(value: float) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(2)
	bytes.encode_s16(0, roundi(value * 32768.0))
	return bytes


static func _md5(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	context.update(bytes)
	return context.finish().hex_encode().left(8)


func _fail(what: String) -> void:
	_failures += 1
	print("FAIL: ", what)
