## Bug test: the fall's pickups must show and fall long enough to be taken. They're dropped above
## the camera and used to be removed in the same frame (the original only tests them once their
## chute is open, 0x41275c). Run: godot --headless --audio-driver Dummy --fixed-fps 60 --path . -s tests/fall_pickups_test.gd
extends SceneTree

const LEVEL := 3
## The fall drops its pickups during its first 30 seconds.
const SECONDS := 30.0
const FPS := 60.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var fall: Node = load("res://game/fall/fall.tscn").instantiate()
	root.add_child(fall)
	var most := 0
	for frame in int(SECONDS * FPS):
		await process_frame
		most = maxi(most, fall._pickups.size())
	print("most pickups at once: %d" % most)
	print("PASSED" if most > 0 else "FAILED")
	quit(0 if most > 0 else 1)
