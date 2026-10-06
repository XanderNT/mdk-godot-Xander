## Bug test (found by playtest): Kurt's arena came from the arena boxes, so on LEVEL4's MEAT_7
## floor, just before the doorway to CMEAT_7 (connection 1012, the plane y = 14822), he was already
## in the corridor; the scripts then dropped MEAT_7 from the solid arenas and he fell through its
## floor. The original switches only when his move crosses the doorway (0x41c550).
## Run: godot --headless --audio-driver Dummy --path . -s tests/arena_switch_test.gd
extends SceneTree

const LEVEL := 4
const ROOM := "MEAT_7"
const CORRIDOR := "CMEAT_7"
## MDK coordinates of the doorway's plane and of the floor before it.
const DOORWAY := 14822.0
const FLOOR := 21.0
## A script tick (30 per second) runs within this many physics frames (60 per second).
const TICK_FRAMES := 3

var _failures := 0
var _main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("GameState").level = LEVEL
	_main = load("res://game/main.tscn").instantiate()
	root.add_child(_main)
	# Untyped: the game's classes use autoloads, not there yet when this script compiles.
	var scripts: Node = _main.get_node("Scripts")
	while scripts.tick_count() == 0:
		await physics_frame
	scripts.teleport_kurt(ROOM, Vector3(0.0, DOORWAY - 100.0, FLOOR), 90.0)
	await _ticks()

	# Inside the corridor's box, but not through the doorway yet.
	await _step_to(DOORWAY - 1.0)
	_expect(scripts.current_arena == ROOM, "before the doorway: %s" % scripts.current_arena)

	# Through: the room stays as the active second arena.
	await _step_to(DOORWAY + 3.0)
	_expect(scripts.current_arena == CORRIDOR, "through the doorway: %s" % scripts.current_arena)
	_expect(scripts.second_arena == ROOM and scripts.second_active, "second: %s" % scripts.second_arena)

	# And back.
	await _step_to(DOORWAY - 1.0)
	_expect(scripts.current_arena == ROOM, "back: %s" % scripts.current_arena)
	_expect(scripts.second_arena == CORRIDOR, "second back: %s" % scripts.second_arena)

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


## Puts Kurt at a y on the floor by the doorway and runs a tick.
func _step_to(y: float) -> void:
	var kurt: Node = _main.get_node("Kurt")
	# MDK (x, y, z) is Godot (x, z, −y).
	kurt.teleport(Vector3(0.0, FLOOR, -y), kurt.yaw)
	await _ticks()


func _ticks() -> void:
	for i in TICK_FRAMES:
		await physics_frame


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)
