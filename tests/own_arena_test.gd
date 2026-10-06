## Bug test: objects collide only with their own arena (0x45e810). In LEVEL5 the boss's key
## (`SW_KEY`, dropped in MUSE_5 at z −1900) landed on the overlapping CMUSE_4's slope (z ≈ −2009)
## instead of MUSE_5's floor (z −2264).
## Run: godot --headless --audio-driver Dummy --path . -s tests/own_arena_test.gd
extends SceneTree

const LEVEL := 5
const ARENA := "MUSE_5"
const ITEM := "SW_KEY"
## Where MUSE_5's script drops the key, and the floor below it (MDK).
const DROP := Vector3(388.0, 92.0, -1900.0)
const FLOOR := -2264.0
const TOLERANCE := 10.0
## Kurt stands in MUSE_5 (its objects only run with him there), away from the drop.
const KURT_AT := Vector3(440.0, 84.0, -2250.0)
const SPAWN_FLAGGED := true
## The key falls slowly (about 16 units a second).
const SECONDS := 30.0
const FPS := 60.0


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
	scripts.teleport_kurt(ARENA, KURT_AT, 0.0)
	await physics_frame
	await physics_frame
	var parent: Node = null
	for obj: Node in scripts.objects:
		if obj.arena == ARENA:
			parent = obj
			break
	var key: Node = scripts.spawn(parent, ITEM, DROP, 0.0, -1, 0, SPAWN_FLAGGED)
	for frame in int(SECONDS * FPS):
		await physics_frame

	var z: float = key.mdk_position.z
	print("%s at z %.1f" % [ITEM, z])
	var ok := absf(z - FLOOR) < TOLERANCE
	print("PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
