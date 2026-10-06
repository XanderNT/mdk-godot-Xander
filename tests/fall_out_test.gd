## Bug test: Kurt dies 50 units below his arena's lowest point (`damp_gravity` 0x469efc). He used
## to fall forever with full health.
## Run: godot --headless --audio-driver Dummy --path . -s tests/fall_out_test.gd
extends SceneTree

const LEVEL := 3
## Teleported this far below his arena's lowest point, he must die within the wait.
const BELOW := 60.0
const FRAMES := 30

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
	var at: Vector3 = scripts.kurt_position
	at.z = scripts.get_arena_floor(scripts.current_arena) - BELOW
	scripts.teleport_kurt("", at, scripts.kurt_yaw)
	for i in FRAMES:
		await physics_frame

	print("health %d state %s" % [kurt.health, kurt.State.keys()[kurt.state]])
	_expect(kurt.health == 0, "alive")
	_expect(kurt.state == kurt.State.DEAD, "not dying")

	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("FAILED: " + message)
