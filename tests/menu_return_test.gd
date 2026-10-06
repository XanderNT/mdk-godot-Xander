## Bug test: after a level started from the command line ends into the main menu (LEVEL5 is the
## last), the menu stays. It skipped itself again for `--level` and reloaded the level in a loop.
## Run: godot --headless --audio-driver Dummy --path . -s tests/menu_return_test.gd -- --level=5 --delay=0.5 --event=1
extends SceneTree

const MENU := "res://game/menu/main_menu.tscn"
## The end of the level (the camera spin, then 0.5 s) is over well within this.
const TIMEOUT := 30.0
## The menu must still be there this long after it opened.
const STAY := 3.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not OS.get_cmdline_user_args().has("--event=1"):
		print("FAILED: run with -- --level=5 --delay=0.5 --event=1")
		quit(1)
		return

	change_scene_to_file(MENU)
	await process_frame
	await process_frame

	# The level first, then the menu after its end.
	var waited := 0.0
	while _on_menu() and waited < TIMEOUT:
		await process_frame
		waited += root.get_process_delta_time()
	while not _on_menu() and waited < TIMEOUT:
		await process_frame
		waited += root.get_process_delta_time()
	var stayed := 0.0
	while _on_menu() and stayed < STAY:
		await process_frame
		stayed += root.get_process_delta_time()

	var ok := _on_menu()
	print("menu after %.1f s, stayed %.1f s" % [waited, stayed])
	print("PASSED" if ok else "FAILED")
	quit(0 if ok else 1)


func _on_menu() -> bool:
	return current_scene != null and current_scene.scene_file_path == MENU
