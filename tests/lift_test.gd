## Bug test: LEVEL4's corridor CMEAT_6 lifts Kurt 1971 up into MEAT_7 (`teleport_player_keep`,
## opcode 173, 0x454556). The handler tested its list operand for emptiness, so it never ran.
## Run: godot --headless --audio-driver Dummy --path . -s tests/lift_test.gd
extends SceneTree

const LEVEL := 4
const CORRIDOR := "CMEAT_6"
const ROOM := "MEAT_7"
## MDK coordinates inside the script's trigger box, and the lift's offset.
const SPOT := Vector3(-125.0, 13587.0, -1975.0)
const LIFT := Vector3(130.0, 845.0, 1971.0)
const YAW := 30.0
const TOLERANCE := 30.0
## A script tick (30 per second) runs within this many physics frames (60 per second).
const TICK_FRAMES := 6

var _failures := 0


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
	scripts.teleport_kurt(CORRIDOR, SPOT, YAW)
	for i in TICK_FRAMES:
		await physics_frame

	# Lifted into the room, same place plus the offset, same yaw.
	var at: Vector3 = scripts.kurt_position
	print("arena %s at %s yaw %.1f" % [scripts.current_arena, at, scripts.kurt_yaw])
	_expect(scripts.current_arena == ROOM, "arena: %s" % scripts.current_arena)
	_expect(at.distance_to(SPOT + LIFT) < TOLERANCE, "position: %s" % at)
	_expect(absf(scripts.kurt_yaw - YAW) < 1.0, "yaw: %.1f" % scripts.kurt_yaw)

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)
