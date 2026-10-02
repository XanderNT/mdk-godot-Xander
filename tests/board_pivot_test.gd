## Test of the camera pivot during a board jump (`K_SURFJ`, 0x46ac4c): 4.5 − 0.2 × frame below
## frame 5, then back up by 1 unit/s to 4.5. Run: godot --headless --path . -s tests/board_pivot_test.gd
extends SceneTree

## Loaded at run time: the board uses autoloads, which a `-s` script can't name when it compiles.
const SNOWBOARD := "res://game/scripts/snowboard.gd"

var _failures := 0
var _board: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_board = load(SNOWBOARD)
	_check(is_equal_approx(_board.jump_pivot(0.0, 4.5, 0.1), 4.5), "frame 0")
	_check(is_equal_approx(_board.jump_pivot(4.0, 4.5, 0.1), 3.7), "frame 4 dips to 3.7")
	_check(is_equal_approx(_board.jump_pivot(5.0, 3.7, 0.1), 3.8), "frame 5 rises by dt")
	_check(is_equal_approx(_board.jump_pivot(5.0, 4.45, 0.1), 4.5), "rises to 4.5 at most")
	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)
