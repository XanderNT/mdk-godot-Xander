## The camera's roll (`0x573910`, degrees; positive banks the view to the right), which Kurt's
## movement sets each tick. See docs/gameplay.md, "Horizontal".
##
##   running + turning (keys) ──▶ ±0.25°/tick up to ±10° (`damp_move` 0x467fa4)
##   sliding                  ──▶ 0.9·roll + 0.1·slope angle per tick (0x468db8)
##   snowboard                ──▶ towards the board's bank at 45°/s (0x46ac4c)
##   none of these            ──▶ back to 0 by clamp(0.35·|roll|, 0.05, 2.5)°/tick (`damp_control`)
class_name CameraRoll
extends RefCounted

const TICKS := 30.0
const WALK_RATE := 0.25
const WALK_LIMIT := 10.0
## Turning the other way first jumps 2° back towards level.
const WALK_REVERSE := 2.0
const DECAY_FACTOR := 0.35
const DECAY_MIN := 0.05
const DECAY_MAX := 2.5
const SLIDE_KEEP := 0.9
const BOARD_RATE := 45.0

var roll := 0.0
## Something set the roll this tick, so it doesn't level out (`0x57ff74`).
var _held := false


## Running and turning with the keys: `right` and `forward` are the turn and forward inputs
## (positive: right, forward). Without both it doesn't change.
func walk(right: float, forward: float, delta: float) -> void:
	if forward == 0.0 or right == 0.0:
		return
	_held = true
	var step := WALK_RATE * TICKS * delta
	if right * forward > 0.0:
		roll += step
		if roll < 0.0:
			roll += WALK_REVERSE
		roll = minf(roll, WALK_LIMIT)
	else:
		roll -= step
		if roll > 0.0:
			roll -= WALK_REVERSE
		roll = maxf(roll, -WALK_LIMIT)


## Sliding: eases towards `90° − atan2(n.z, n.x·f.y − n.y·f.x)` with the floor normal `normal` and
## the facing `facing` (MDK coordinates), a tenth per tick.
func slide(normal: Vector3, facing: Vector2, delta: float) -> void:
	_held = true
	var angle := rad_to_deg(atan2(normal.z, normal.x * facing.y - normal.y * facing.x))
	roll = lerpf(90.0 - angle, roll, pow(SLIDE_KEEP, TICKS * delta))


## On the board: towards its bank at 45°/s.
func follow(bank: float, delta: float) -> void:
	_held = true
	roll = move_toward(roll, bank, BOARD_RATE * delta)


## At the end of the tick: levels out unless something set it.
func settle(delta: float) -> void:
	if _held:
		_held = false
		return
	var step := clampf(DECAY_FACTOR * absf(roll), DECAY_MIN, DECAY_MAX) * TICKS * delta
	roll = move_toward(roll, 0.0, step)
