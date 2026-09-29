## A missile of the fall (launch 0x412568, each frame 0x411ee8). See docs/gameplay.md, "Missiles".
##
## It flies free for 60 ticks, then homes on Kurt; once it's more than 5 units above him it has
## passed (`M_PASS`): it stops homing, flies on and goes 60 ticks later.
##
##   FREE (60 ticks) ──> HOMING ──(5 units above Kurt)──> PASSED (60 ticks) ──> gone
class_name FallMissile
extends RefCounted

## What happened this frame.
enum Event { NONE, PASSED, GONE }

enum Phase { FREE, HOMING, PASSED }

const SPEED := 250.0
const FREE_TICKS := 60
const PASS_HEIGHT := 5.0
const GONE_TICKS := 60
const TRAIL_POINTS := 32
## Homing: `v = 0.8 v + 0.2 × 250 × unit(aim − position)`.
const HOMING := 0.2
## Below 0.75 × Kurt's height it climbs 3 times as fast.
const BOOST_HEIGHT := 0.75
const BOOST := 3.0
## The aim is below Kurt by `min(depth / 225, 10) × 66.67`.
const AIM_DEPTH := 225.0
const AIM_MAX := 10.0
const AIM_SPEED := 2000.0 / 30.0

var node: MeshInstance3D
var position := Vector3()
var velocity := Vector3()
## The aim's offset from Kurt (x, y).
var offset := Vector3()
## The last points, for the smoke trail.
var trail: Array[Vector3] = []

var _phase := Phase.FREE
## Ticks left free, or since it passed.
var _ticks := float(FREE_TICKS)


## Launched from the origin in a random direction, climbing, with a random aim offset of ±`spread`.
func _init(spread: float) -> void:
	var a := randf() * TAU
	velocity = Vector3(sin(a), cos(a), 1.0) * SPEED
	offset = Vector3(randf_range(-spread, spread), randf_range(-spread, spread), 0.0)


## Moves the missile for a frame, Kurt being at `kurt`.
func update(dt: float, ticks: int, kurt: Vector3) -> Event:
	position += velocity * dt
	if position.z < BOOST_HEIGHT * kurt.z:
		position.z += BOOST * velocity.z * dt
	for i in ticks:
		trail.push_back(position)
	while trail.size() > TRAIL_POINTS:
		trail.pop_front()

	match _phase:
		Phase.FREE:
			_ticks -= ticks
			if _ticks <= 0.0:
				_phase = Phase.HOMING
		Phase.HOMING:
			return _home(kurt)
		Phase.PASSED:
			_ticks += ticks
			if _ticks > GONE_TICKS:
				return Event.GONE
	return Event.NONE


## Steers towards a point below Kurt (deeper the farther below him it is), until it's 5 units
## above him.
func _home(kurt: Vector3) -> Event:
	var dz := kurt.z - position.z
	if dz <= -PASS_HEIGHT:
		_phase = Phase.PASSED
		_ticks = 0.0
		return Event.PASSED
	var aim := kurt + Vector3(offset.x, offset.y, -minf(dz / AIM_DEPTH, AIM_MAX) * AIM_SPEED)
	velocity = (1.0 - HOMING) * velocity + HOMING * SPEED * (aim - position).normalized()
	return Event.NONE
