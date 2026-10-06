## Bug test: LEVEL7's runner pickup SW_H150 stays where it was placed while it plays its idle
## animation. Godot's overlap recovery nudged it as the pose grew, within 20 units of Kurt at the
## start, so it ran off (the original's sweep never pushes out of overlaps).
## Run: godot --headless --audio-driver Dummy --path . -s tests/runner_pickup_test.gd
extends SceneTree

const LEVEL := 7
const PICKUP := "SW_H150"
const IDLE := "H150_I"
const SECONDS := 10.0
const FPS := 60.0
const TOLERANCE := 0.1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	# Untyped: the game's classes use autoloads, not there yet when this script compiles.
	var scripts: Node = main.get_node("Scripts")
	while scripts.tick_count() == 0:
		await physics_frame
	var pickup: Node = scripts.find_object_named(PICKUP)
	var idle: Variant = scripts.items.get_animation(IDLE)

	# The idle animation over and over (the game plays it now and then).
	for frame in int(SECONDS * FPS):
		if pickup.animation != idle or pickup.is_animation_done():
			pickup.restart_animation(idle, false)
		await physics_frame

	var moved: Vector3 = pickup.mdk_position - pickup.spawn_position
	print("%s moved by %s" % [PICKUP, moved])
	var ok := Vector2(moved.x, moved.y).length() < TOLERANCE
	print("PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
