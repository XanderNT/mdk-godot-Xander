## Bug test: Kurt and the muzzle flash are flat sprites turned to the camera; in the enhanced look
## the sun must not throw their quads' shadows on the floor. Run: godot --headless --path . -s
## tests/sprite_shadow_test.gd
extends SceneTree

## Loaded at run time: Kurt uses autoloads, which a `-s` script can't name when it compiles.
const KURT := "res://game/kurt/kurt.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var kurt: Node = load(KURT).instantiate()
	var failures := 0
	for node_name in ["Sprite", "Muzzle"]:
		var sprite := kurt.get_node(node_name) as GeometryInstance3D
		if sprite.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			failures += 1
			print("FAIL: %s casts a shadow" % node_name)
	kurt.free()
	print("FAILED %d" % failures if failures else "PASSED")
	quit(1 if failures else 0)
