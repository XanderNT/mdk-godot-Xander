## Test of `MDKFlc`: frames match those Pillow decodes (MD5 of the indices and the palette, first 8
## hex digits). Run: godot --headless --path . -s tests/flc_test.gd
extends SceneTree

const DATA := "C:/Games/MDK/MISC/FLIC/"
## File → frame index → [indices MD5, palette MD5].
const EXPECTED := {
	"Mdk12.flc": {0: ["fd4df52e", "fa037e2d"], 1: ["97afa19c", "fa037e2d"], 40: ["6c00fa9c", "fa037e2d"], 81: ["961be24d", "fa037e2d"]},
	"shiny.flc": {0: ["5ac67219", "75d407b8"], 1: ["5e7e6fc5", "75d407b8"], 40: ["667450ba", "75d407b8"], 120: ["bb03d07b", "75d407b8"]},
	"pie.flc": {0: ["8d323d9c", "ae279936"], 1: ["d59e82bb", "ae279936"], 40: ["4a182e80", "ae279936"], 310: ["eb1b76b6", "ae279936"]},
}

var _failures := 0


func _initialize() -> void:
	for file_name: String in EXPECTED:
		_check_file(file_name, EXPECTED[file_name])
	_check_end_movie()
	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _check_file(file_name: String, frames: Dictionary) -> void:
	var flc := MDKFlc.load_file(DATA + file_name)
	if not flc:
		_fail("%s: not loaded" % file_name)
		return
	var start := Time.get_ticks_msec()
	for i in flc.frame_count:
		if not flc.next_frame():
			_fail("%s: ended at frame %d" % [file_name, i])
			return
		if not frames.has(i):
			continue
		var got := [_md5(flc.indices), _md5(flc.palette)]
		if got != frames[i]:
			_fail("%s frame %d: %s, expected %s" % [file_name, i, got, frames[i]])
	if flc.next_frame():
		_fail("%s: more than %d frames" % [file_name, flc.frame_count])
	print("%s: %d frames in %d ms" % [file_name, flc.frame_count, Time.get_ticks_msec() - start])


## The end movie has a prefix chunk Pillow can't read: all its frames decode.
func _check_end_movie() -> void:
	var flc := MDKFlc.load_file(DATA + "MDKEND.FLC")
	var count := 0
	while flc and flc.next_frame():
		count += 1
	if count != 316:
		_fail("MDKEND.FLC: %d frames" % count)


static func _md5(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	context.update(bytes)
	return context.finish().hex_encode().left(8)


func _fail(what: String) -> void:
	_failures += 1
	print("FAIL: ", what)
