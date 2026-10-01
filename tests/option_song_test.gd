## Test of the options screen's `OPTSONG` (0x42bb6c). Run: godot --headless --path . -s tests/option_song_test.gd
extends SceneTree

## Loaded at run time: the menu uses autoloads, which a `-s` script can't name when it compiles.
const MENU_ITEMS := "res://game/menu/menu_items.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var items: VBoxContainer = load(MENU_ITEMS).new()
	root.add_child(items)
	items.show_options(Callable())
	var song := items.get_child(0, true) as AudioStreamPlayer
	var ok := song != null and song.stream != null and song.playing
	items.clear()
	ok = ok and not song.playing
	print("PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
