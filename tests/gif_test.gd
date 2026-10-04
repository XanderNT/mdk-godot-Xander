## Test of `MDKGif`: the menu's slideshow images match what Pillow decodes (MD5 of the indices and
## the palette, first 8 hex digits). Run: godot --headless --path . -s tests/gif_test.gd
extends SceneTree

const DATA := "C:/Games/MDK/MISC/"
const EXPECTED := {
	"MDKS_001.GIF": ["68fb1299", "d4f91aaf"],
	"MDKS_002.GIF": ["3a4a37ff", "10a4fba9"],
	"MDKS_003.GIF": ["c8df58e7", "32506f63"],
	"MDKS_004.GIF": ["6ab1e680", "19796123"],
	"MDKS_005.GIF": ["4896b509", "0f9f8868"],
	"MDKS_006.GIF": ["2221b43e", "ce9f7ea6"],
	"MDKS_007.GIF": ["16d3c1da", "3f668c4e"],
	"MDKS_008.GIF": ["efc7e9ad", "0f9f8868"],
}

var _failures := 0


func _initialize() -> void:
	for file_name: String in EXPECTED:
		var start := Time.get_ticks_msec()
		var gif := MDKGif.load_file(DATA + file_name)
		if not gif:
			_fail("%s: not loaded" % file_name)
			continue
		var got := [_md5(gif.indices), _md5(gif.palette)]
		if got != EXPECTED[file_name]:
			_fail("%s: %s, expected %s" % [file_name, got, EXPECTED[file_name]])
		print("%s %dx%d in %d ms" % [file_name, gif.width, gif.height, Time.get_ticks_msec() - start])
	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


static func _md5(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	context.update(bytes)
	return context.finish().hex_encode().left(8)


func _fail(what: String) -> void:
	_failures += 1
	print("FAIL: ", what)
