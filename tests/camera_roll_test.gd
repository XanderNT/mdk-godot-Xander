## Tests of `CameraRoll`. Run: godot --headless --path . -s tests/camera_roll_test.gd
extends SceneTree

const DT := 1.0 / 30.0

var _failures := 0


func _initialize() -> void:
	_test_walk_limit()
	_test_reverse_jump()
	_test_decay()
	_test_no_roll_without_forward()
	_test_board()
	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


## Running and turning right banks right by 0.25° a tick, up to 10°.
func _test_walk_limit() -> void:
	var roll := CameraRoll.new()
	for i in 4:
		roll.walk(1.0, 1.0, DT)
		roll.settle(DT)
	_check(is_equal_approx(roll.roll, 1.0), "0.25 per tick (got %f)" % roll.roll)
	for i in 100:
		roll.walk(1.0, 1.0, DT)
		roll.settle(DT)
	_check(is_equal_approx(roll.roll, 10.0), "limit 10 (got %f)" % roll.roll)


## Turning the other way jumps 2° back.
func _test_reverse_jump() -> void:
	var roll := CameraRoll.new()
	roll.roll = 5.0
	roll.walk(-1.0, 1.0, DT)
	_check(is_equal_approx(roll.roll, 2.75), "reverse jump (got %f)" % roll.roll)


## Without input it levels out by 0.35·|roll| a tick (at most 2.5, at least 0.05).
func _test_decay() -> void:
	var roll := CameraRoll.new()
	roll.roll = 10.0
	roll.settle(DT)
	_check(is_equal_approx(roll.roll, 7.5), "decay capped at 2.5 (got %f)" % roll.roll)
	roll.roll = 0.04
	roll.settle(DT)
	_check(roll.roll == 0.0, "decay to 0 (got %f)" % roll.roll)


## Turning on the spot doesn't roll.
func _test_no_roll_without_forward() -> void:
	var roll := CameraRoll.new()
	roll.walk(1.0, 0.0, DT)
	roll.settle(DT)
	_check(roll.roll == 0.0, "no roll standing (got %f)" % roll.roll)


## On the board it follows the bank at 45°/s.
func _test_board() -> void:
	var roll := CameraRoll.new()
	roll.follow(10.0, DT)
	roll.settle(DT)
	_check(is_equal_approx(roll.roll, 1.5), "board 1.5 per tick (got %f)" % roll.roll)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)
