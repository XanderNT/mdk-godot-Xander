## Bug test: Kurt teleported onto LEVEL6's doorway OLYM_7 → COLYM_6 (connection 1011, the plane
## y = 3230, closed by a door) stays there. The camera's clearance cut the view at the door part
## his head was in and shoved him 9 units into the corridor (0x45f588 skips a part the head is in).
## Run: godot --headless --audio-driver Dummy --path . -s tests/doorway_teleport_test.gd
extends SceneTree

const LEVEL := 6
const ROOM := "OLYM_7"
## MDK coordinates in the middle of the doorway, and its floor.
const SPOT := Vector3(-2197.0, 3230.0, -2858.0)
const FLOOR := -2862.0
const TOLERANCE := 1.0
const FRAMES := 120

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	# Untyped: the game's classes use autoloads, not there yet when this script compiles.
	var scripts: Node = main.get_node("Scripts")
	var kurt: Node = main.get_node("Kurt")
	while scripts.tick_count() == 0:
		await physics_frame
	scripts.teleport_kurt(ROOM, SPOT, 90.0)
	for i in FRAMES:
		await physics_frame

	var at: Vector3 = scripts.kurt_position
	print("arena %s at %s health %d" % [scripts.current_arena, at, kurt.health])
	_expect(scripts.current_arena == ROOM, "arena: %s" % scripts.current_arena)
	_expect(absf(at.y - SPOT.y) < TOLERANCE, "shoved to y %.1f" % at.y)
	_expect(absf(at.z - FLOOR) < TOLERANCE, "not on the floor: z %.1f" % at.z)

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)
