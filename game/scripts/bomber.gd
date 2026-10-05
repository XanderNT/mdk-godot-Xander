## The `XE` bomber ride of level 7's `DANT_5` (0x46bf40): Kurt sits in the flyer while its script
## flies it along a path; the view looks straight down from it and a cursor aims `XBN_BOMB`s at the
## ground. See docs/gameplay.md, "The `XE` bomber".
##
##   mount ──▶ camera sinks 50 → 0 u above Kurt in 2 s (then the XE is hidden)
##         ──▶ script unlocks (flag 0x4000000 cleared) ──▶ cursor, bombs, HUD
##         ──▶ script clears the rideable flag ──▶ Kurt drops from the XE (`MDKRides`)
class_name MDKBomber
extends RefCounted

## The view (0x4183f0): 50 units above Kurt at the mount, sinking 25 units/s.
const CAMERA_HEIGHT := 50.0
const CAMERA_DESCENT := 25.0
## The cursor, in pixels of the 600×360 view (0x573b0c): starts at the centre, kept in a box; keys
## accelerate it by 1/3 px/tick² up to 10 px/tick, it brakes by 2/3 px/tick²; the mouse moves it by
## 1/3 of its motion.
const CURSOR_CENTRE := Vector2(300.0, 180.0)
const CURSOR_MIN := Vector2(128.0, 64.0)
const CURSOR_MAX := Vector2(472.0, 296.0)
const CURSOR_ACCEL := 1.0 / 3.0
const CURSOR_SPEED := 10.0
const CURSOR_BRAKE := 2.0 / 3.0
const MOUSE_SCALE := 1.0 / 3.0
## Bombs (0x573c64): 10, one back per second.
const BOMBS := 10
const REFILL_TIME := 1.0
## The aim: a ray from Kurt through the cursor with the view's focal length (600 / zoom 2.4), as
## long as 1000 times that direction; the bomb starts 5 below Kurt and falls by 32 u/s² (the `XE`'s
## gravity) onto the hit point, or for 2.5 s when nothing is hit.
const FOCAL := 250.0
const RAY_LENGTH := 1000.0
const DROP_BELOW := 5.0
const GRAVITY := 32.0
const MISS_TIME := 2.5
## The bomb: a thrown item of kind 0x81 (0x43deac) living 900 ticks.
const BOMB := "XBN_BOMB"
const BOMB_TICKS := 900
## The `XE`'s health is kept at 10000; what it loses goes to Kurt (0x46a77c).
const HEALTH := 10000

## Height of the view above Kurt.
var camera_height := CAMERA_HEIGHT
var cursor := CURSOR_CENTRE
var bombs := BOMBS

var _runtime: MDKScriptRuntime
var _xe: MDKObject
var _speed := Vector2.ZERO
var _refill := REFILL_TIME


func _init(runtime: MDKScriptRuntime, xe: MDKObject) -> void:
	_runtime = runtime
	_xe = xe


## Whether the script still holds the controls (and the HUD is off).
func is_locked() -> bool:
	return _xe.flags & MDKRides.FLAG_LOCKED != 0


## Whether the view is inside the `XE`, which then isn't drawn.
func hides_xe() -> bool:
	return camera_height == 0.0


## Each tick (Kurt's ride): Kurt goes with the `XE`, the view sinks, the cursor moves and drops bombs.
func update(delta: float) -> void:
	var kurt := _runtime.kurt
	kurt.global_position = MDKMeshBuilder.to_godot(_xe.mdk_position)
	kurt.yaw = deg_to_rad(_xe.yaw - 90.0)
	kurt.velocity = Vector3.ZERO
	camera_height = maxf(camera_height - CAMERA_DESCENT * delta, 0.0)
	if hides_xe():
		_xe.flags |= MDKObject.FLAG_NOT_SOLID

	if is_locked():
		_speed.y = 0.0
	else:
		_move_cursor(delta)
		if Input.is_action_just_pressed(&"fire") and bombs > 0:
			_drop()
		_refill_bombs(delta)
	_pass_damage()


func _move_cursor(delta: float) -> void:
	var ticks := delta * Kurt.TICKS
	var turn := Input.get_axis(&"turn_left", &"turn_right")
	var strafe := Input.get_axis(&"strafe_left", &"strafe_right")
	var axis := Vector2(turn if absf(turn) >= absf(strafe) else strafe, Input.get_axis(&"move_forward", &"move_back"))
	for i in 2:
		if axis[i] != 0.0:
			_speed[i] = _accelerate(_speed[i], axis[i] * CURSOR_ACCEL * ticks, absf(axis[i]) * CURSOR_SPEED)
		else:
			_speed[i] = move_toward(_speed[i], 0.0, CURSOR_BRAKE * ticks)

	# The mouse moves it only while no key does.
	var mouse := Input.get_last_mouse_screen_velocity() * delta * MOUSE_SCALE * Settings.mouse_sensitivity
	if axis == Vector2.ZERO and mouse != Vector2.ZERO and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cursor += mouse
		_speed = Vector2.ZERO
	cursor = (cursor + _speed * ticks).clamp(CURSOR_MIN, CURSOR_MAX)


## `vel_accel_dt` (0x4688d0): adds the step while going the same way, else starts over from it.
static func _accelerate(speed: float, step: float, limit: float) -> float:
	var result := speed + step if speed == 0.0 or signf(speed) == signf(step) else step
	return clampf(result, -limit, limit)


func _refill_bombs(delta: float) -> void:
	if bombs >= BOMBS:
		_refill = REFILL_TIME
		return
	_refill -= delta
	if _refill <= 0.0:
		bombs += 1
		_refill = REFILL_TIME


## A bomb from under the `XE`, thrown so it falls onto the point under the cursor.
##
##        Kurt ●───────▶ (vx, vy, 0)
##             ╎  ╲ falls by gravity for t = √(2h / g)
##             ╎     ╲
##   ──────────┴───────✕ hit point (ray through the cursor)
func _drop() -> void:
	bombs -= 1
	var kurt_position := _runtime.kurt_position
	var start := kurt_position - Vector3(0.0, 0.0, DROP_BELOW)
	var offset := cursor - CURSOR_CENTRE
	var yaw := deg_to_rad(_xe.yaw)
	var s := sin(yaw)
	var c := cos(yaw)
	# Right is (s, −c), the top of the view is the heading (c, s).
	var direction := Vector3(s * offset.x - c * offset.y, -c * offset.x - s * offset.y, -FOCAL)
	var end := kurt_position + direction * RAY_LENGTH
	# Objects first (0x46428c flag 1), then the arena up to them (flag 2).
	var target := end
	var object_hit: Variant = _first_object(kurt_position, end)
	if object_hit != null:
		target = object_hit
	var hit := _runtime.raycast(kurt_position, target)
	var time := MISS_TIME
	if not hit.is_empty():
		target = MDKScriptRuntime.to_mdk(hit.position)
	if not hit.is_empty() or object_hit != null:
		time = sqrt(maxf(start.z - target.z, 0.0) * 2.0 / GRAVITY)
	if time <= 0.0:
		time = MISS_TIME

	var controller := _runtime.get_arena_state(_runtime.current_arena).controller
	var bomb := _runtime.spawn(controller, BOMB, start, _xe.yaw, -1, 0, false)
	if not bomb:
		return
	bomb.flags |= MDKItems.THROWN_FLAGS
	bomb.thrown_kind = MDKItems.KIND_BOMB
	bomb.item_ticks = BOMB_TICKS
	bomb.friction = 0.0
	bomb.velocity = Vector3((target.x - start.x) / time, (target.y - start.y) / time, 0.0)
	bomb.loop_sound = _runtime.mixer.play_on("DROP", bomb)


## Where the segment first meets a part of an object of Kurt's arena (alive, not flagged 0x30: the
## hidden `XE` doesn't count), or null.
func _first_object(start: Vector3, end: Vector3) -> Variant:
	var nearest: Variant = null
	for obj in _runtime.objects:
		if obj.dead or obj.health == 0 or obj.arena != _runtime.current_arena or not obj.model 				or obj.flags & (MDKObject.FLAG_NOT_SOLID | MDKObject.FLAG_NOT_TARGET):
			continue
		if _runtime.get_world_bounds(obj).intersects_segment(start, end) == null:
			continue
		var parts := obj.get_part_bounds()
		for i in parts.size():
			if obj.hidden_parts & (1 << i):
				continue
			var point: Variant = _runtime.get_world_bounds(obj, parts[i]).intersects_segment(start, end)
			if point != null and (nearest == null or start.distance_to(point) < start.distance_to(nearest)):
				nearest = point
	return nearest


## Hits on Kurt went to the `XE` (`MDKRides.takes_hits`); Kurt takes them, and if he dies the `XE`
## does too (its death script drops him).
func _pass_damage() -> void:
	if _xe.health == HEALTH:
		return
	var kurt := _runtime.kurt
	kurt.hurt(HEALTH - _xe.health)
	_xe.health = HEALTH
	if kurt.health < 1:
		_xe.health = 0
		_runtime.kill(_xe)
