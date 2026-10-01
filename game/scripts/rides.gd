## The objects Kurt rides (`0x573c30`, `damp_control` 0x466368): the snowboard of level 4
## (`XSNOWB`, `MDKSnowboard`) and the `XD2` of level 7's `DANT_9` (0x46a840). See
## docs/gameplay.md, "Rides".
##
## A script makes an object rideable (flag 0x2000000); Kurt gets on when he stands on it (or, for
## the `XD2`, touches it) without firing, and off when the script clears the flag.
##
##   rideable + Kurt on it ──▶ riding ──(flag cleared)──▶ off (the XD2: a jump; the board: thrown)
class_name MDKRides
extends RefCounted

## Object flags: rideable, controls locked (the board), ridden, the rider fires (the `XD2`).
const FLAG_RIDEABLE := 0x2000000
const FLAG_LOCKED := 0x4000000
const FLAG_RIDDEN := 0x80000
const FLAG_FIRING := 0x1
## On the board: Kurt passes through it (+0x800) and it's no platform any more (−0x800100).
const BOARD_FLAGS_SET := 0x80800
const BOARD_FLAGS_CLEAR := 0x800100
const BOARD := "XSNOWB"
const WALKERS := ["XD", "XD2"]
## The `XD2`: `DUMMY` at volume 0x2000 while moving, `ALERT` and the alarm while firing; Kurt
## takes 50 damage if it goes while he rides it.
const WALKER_SOUND_VOLUME := 0x2000
const ALARM_TICKS := 10
const LOST_DAMAGE := 50

## The object Kurt rides, if any.
var ridden: MDKObject

var _runtime: MDKScriptRuntime
var _board: MDKSnowboard
var _walker_sound: SoundMixer.Voice


func _init(runtime: MDKScriptRuntime) -> void:
	_runtime = runtime


## Each tick, after Kurt moved: getting on, riding the `XD2`, getting off.
func update() -> void:
	if not ridden:
		_try_mount()
		return
	var off := not ridden.flags & FLAG_RIDEABLE or ridden.dead or (_board and _runtime.kurt.health == 0)
	if off:
		_dismount()
		return
	if not _board:
		_update_walker()


## Whether Kurt rides the snowboard.
func on_board() -> bool:
	return _board != null


## Whether hits on Kurt go to the object he rides (the `XD2`).
func takes_hits() -> bool:
	return ridden != null and _board == null


## The ridden object went (0x43d734): Kurt is off, and on the `XD2` he takes 50 damage.
func lost(obj: MDKObject) -> void:
	if obj != ridden:
		return
	var walker := _board == null
	_dismount()
	if walker:
		_runtime.kurt.hurt(LOST_DAMAGE)


func _try_mount() -> void:
	var kurt := _runtime.kurt
	if kurt.firing:
		return
	for obj in _touched():
		if not obj.flags & FLAG_RIDEABLE:
			continue
		var type := obj.type_name.to_upper()
		if type == BOARD:
			_mount_board(obj)
			return
		if type in WALKERS and kurt.is_on_floor():
			_mount_walker(obj)
			return


## The objects Kurt stands on or touches this tick.
func _touched() -> Array[MDKObject]:
	var kurt := _runtime.kurt
	var found: Array[MDKObject] = []
	for i in kurt.get_slide_collision_count():
		var body := kurt.get_slide_collision(i).get_collider() as Node
		var obj := body.get_parent() as MDKObject if body else null
		if obj and not obj.dead and obj not in found:
			found.push_back(obj)
	return found


func _mount_board(obj: MDKObject) -> void:
	ridden = obj
	obj.flags = (obj.flags | BOARD_FLAGS_SET) & ~BOARD_FLAGS_CLEAR
	_runtime.kurt.leave_sniper()
	_board = MDKSnowboard.new(_runtime, obj)
	_runtime.kurt.ride = _board.update


## The `XD2`: Kurt goes where it is, facing its way, and walks it (without strafing or jumping).
func _mount_walker(obj: MDKObject) -> void:
	var kurt := _runtime.kurt
	ridden = obj
	obj.flags |= FLAG_RIDDEN
	kurt.stop_firing()
	kurt.global_position = MDKMeshBuilder.to_godot(obj.mdk_position)
	kurt.yaw = deg_to_rad(obj.yaw - 90.0)
	kurt.forward_speed = 0.0
	kurt.strafe_speed = 0.0
	kurt.walk_mode = Kurt.Walk.RIDING
	kurt.sprite.visible = false


## The `XD2` goes with Kurt, animating while it moves; its sound while the keys are held; firing
## sounds the alarm.
func _update_walker() -> void:
	var kurt := _runtime.kurt
	ridden.mdk_position = _runtime.kurt_position
	ridden.yaw = fposmod(rad_to_deg(kurt.yaw) + 90.0, 360.0)
	var moving := not is_zero_approx(kurt.forward_speed) or not is_zero_approx(kurt.turn_speed)
	ridden.animation_fps = 30.0 if moving else 0.0
	ridden.update_transform()

	var input := Input.get_axis(&"move_back", &"move_forward") != 0.0 or Input.get_axis(&"turn_left", &"turn_right") != 0.0
	if input and not (_walker_sound and _walker_sound.is_playing()):
		_walker_sound = _runtime.mixer.play("DUMMY", SoundMixer.Start.NEW)
		_runtime.mixer.set_volume(_walker_sound, WALKER_SOUND_VOLUME)
	elif not input:
		_runtime.mixer.stop_voice(_walker_sound)
		_walker_sound = null

	if Input.is_action_pressed(&"fire"):
		ridden.flags |= FLAG_FIRING
		_runtime.mixer.play("ALERT", SoundMixer.Start.ONCE)
		_runtime.alarm_ticks = ALARM_TICKS
	elif ridden.flags & FLAG_FIRING:
		ridden.flags &= ~FLAG_FIRING
		_runtime.alarm_ticks = 0


func _dismount() -> void:
	var kurt := _runtime.kurt
	if _board:
		_board.get_off()
		_board = null
	elif ridden:
		_runtime.mixer.stop_voice(_walker_sound)
		_walker_sound = null
		kurt.jump_off()
	ridden = null
