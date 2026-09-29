## Tests of `FallMissile`. Run: godot --headless --path . -s tests/fall_missile_test.gd
extends SceneTree

const DT := 1.0 / 30.0
const KURT_SPEED := 2000.0 / 30.0
## Kurt's collision box (x ± 4, y ± 4, z ± 5).
const KURT_BOX := Vector3(4.0, 4.0, 5.0)

var _failures := 0


func _initialize() -> void:
	_test_homes_on_kurt()
	_test_passed_missile_flies_on()
	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


## A missile below Kurt, past its free flight, comes at him.
func _test_homes_on_kurt() -> void:
	var missile := FallMissile.new(0.0)
	var kurt := Vector3(0, 0, 5000)
	missile.position = kurt + Vector3(40, 0, -300)
	missile.velocity = Vector3(0, 0, FallMissile.SPEED)
	_skip_free_flight(missile, kurt)
	var start := missile.position.distance_to(kurt)
	for i in 30:
		kurt.z -= KURT_SPEED * DT
		missile.update(DT, 1, kurt)
	_check(missile.position.distance_to(kurt) < start, "homes on Kurt")


## A missile that went past Kurt (5 units above him) doesn't turn back to hit him.
func _test_passed_missile_flies_on() -> void:
	var missile := FallMissile.new(0.0)
	var kurt := Vector3(0, 0, 5000)
	missile.position = kurt + Vector3(6, 0, -20)
	missile.velocity = Vector3(0, 0, FallMissile.SPEED)
	_skip_free_flight(missile, kurt)
	var hit := false
	for i in 90:
		kurt.z -= KURT_SPEED * DT
		var previous := missile.position
		if missile.update(DT, 1, kurt) == FallMissile.Event.GONE:
			break
		var box := AABB(kurt - KURT_BOX, KURT_BOX * 2.0)
		if missile.position.z > kurt.z and (box.has_point(missile.position) or box.intersects_segment(previous, missile.position) != null):
			hit = true
	_check(not hit, "a missile that passed Kurt doesn't hit him from above")


## Runs a missile's 60 ticks of free flight without moving it.
func _skip_free_flight(missile: FallMissile, kurt: Vector3) -> void:
	var position := missile.position
	var velocity := missile.velocity
	missile.update(0.0, FallMissile.FREE_TICKS + 1, kurt)
	missile.position = position
	missile.velocity = velocity
	missile.trail.clear()


func _check(condition: bool, what: String) -> void:
	if condition:
		print("ok   %s" % what)
		return
	print("FAIL %s" % what)
	_failures += 1
