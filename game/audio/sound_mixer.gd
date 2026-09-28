## The game's sound effects, mixed like the original (`0x402b40`–`0x403c70`, the listener update
## 0x403348). See docs/sound.md.
##
## - Volume is linear in decibels over 25 dB: `dB = −25 + 25 × volume / 0x7FFF` (never silent).
## - 3D voices: full volume up to 20 units from the camera, falling linearly to 0 at 250 units, with a
##   Doppler pitch (speed of sound 1100 u/s, 0.25–3). In sniper mode the scope listens: sounds near
##   the crosshair are loud, those behind are at the floor.
## - At most 64 voices: a new sound is dropped when all are busy.
## - Looping comes from the sound itself (the SNI flag, see `MDKSni.get_sound()`).
##
##   play("LAND")                      2D, the sound's default volume
##   play_at("EXPLODE", point)         3D, fixed at a point (MDK coordinates)
##   play_on("DUMMY", node)            3D, following a node
class_name SoundMixer
extends Node

## Whether a new voice starts even if the sound is playing (`NEW`), stops the sound's voices first
## (`RESTART`), or is only started if the sound isn't playing (`ONCE`).
enum Start { NEW, RESTART, ONCE }

const MAX_VOICES := 64
const FULL_VOLUME := 0x7FFF
const FLOOR_DB := -25.0
## The distance law (0x40347c).
const NEAR := 20.0
const FAR := 250.0
## Doppler (0x40347c).
const SPEED_OF_SOUND := 1100.0
const PITCH_MIN := 0.25
const PITCH_MAX := 3.0
## Scope listening (0x403750): the scope is 384 × 280 pixels, its focal length 384 / zoom.
const SCOPE_AXIS := 2.0
const SCOPE_RATIO := 384.0 / 280.0
const SCOPE_DEPTH := 300.0
const SCOPE_EDGE := 1.3


class Voice:
	var player: Node
	var stream: AudioStreamWAV
	var sound_name := ""
	var volume := FULL_VOLUME
	var positional := false
	var distance := -1.0

	## Whether the voice is still playing.
	func is_playing() -> bool:
		return is_instance_valid(player) and player.playing

	## The frequency as a multiple of the sound's own (`BUTSLIDE`).
	func set_pitch(pitch: float) -> void:
		if is_instance_valid(player):
			player.pitch_scale = pitch


## Returns a sound by name (an `AudioStreamWAV`, see `Level.get_sound()`), or `null`.
var get_sound: Callable
## The sniper scope's zoom (1 to 0.25) while Kurt snipes, else 0.
var scope_zoom := 0.0

var _voices: Array[Voice] = []


## Plays a sound without position; with an `owner` it stops when the owner goes.
func play(sound_name: String, start := Start.NEW, owner: Node = null) -> Voice:
	var voice := _start(sound_name, start)
	if not voice:
		return null
	voice.player = AudioStreamPlayer.new()
	_launch(voice, owner if owner else self)
	return voice


## Plays a sound at a fixed point (MDK coordinates).
func play_at(sound_name: String, point: Vector3, start := Start.NEW) -> Voice:
	var voice := _start(sound_name, start)
	if not voice:
		return null
	var player := _make_3d()
	player.position = MDKMeshBuilder.to_godot(point)
	voice.player = player
	_launch(voice, self)
	return voice


## Plays a sound following a node (at an offset in its frame, MDK coordinates); it stops when the
## node goes.
func play_on(sound_name: String, node: Node3D, start := Start.NEW, offset := Vector3.ZERO) -> Voice:
	var voice := _start(sound_name, start)
	if not voice:
		return null
	var player := _make_3d()
	player.position = MDKMeshBuilder.to_godot(offset)
	voice.player = player
	_launch(voice, node)
	return voice


## Stops every voice of a sound.
func stop(sound_name: String) -> void:
	for voice in _voices.duplicate():
		if voice.sound_name == sound_name:
			_free(voice)


func stop_voice(voice: Voice) -> void:
	if voice:
		_free(voice)


func is_playing(sound_name: String) -> bool:
	return _voices.any(func(voice: Voice) -> bool: return voice.sound_name == sound_name and voice.is_playing())


## Decibels of a volume (0–0x7FFF): linear over 25 dB, never silent.
static func to_db(volume: float) -> float:
	return FLOOR_DB * (1.0 - clampf(volume, 0.0, FULL_VOLUME) / FULL_VOLUME)


## A new voice for a sound, or null when it can't or needn't play.
func _start(sound_name: String, start: Start) -> Voice:
	var stream: AudioStreamWAV = get_sound.call(sound_name) if get_sound.is_valid() else null
	if not stream:
		return null
	if start == Start.ONCE and is_playing(sound_name):
		return null
	if start == Start.RESTART:
		stop(sound_name)
	if _voices.size() >= MAX_VOICES:
		return null

	var voice := Voice.new()
	voice.sound_name = sound_name
	voice.volume = stream.get_meta(&"volume", FULL_VOLUME)
	voice.stream = stream
	return voice


func _make_3d() -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	# The volume is computed here; Godot only pans.
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	return player


func _launch(voice: Voice, parent: Node) -> void:
	var player := voice.player
	voice.positional = player is AudioStreamPlayer3D
	player.stream = voice.stream
	player.bus = &"Effects"
	player.volume_db = to_db(voice.volume)
	player.set_meta(&"sound", voice.sound_name.to_upper())
	player.add_to_group(&"mdk_sounds")
	player.finished.connect(_free.bind(voice))
	player.tree_exiting.connect(_voices.erase.bind(voice))
	parent.add_child(player)
	player.play()
	_voices.push_back(voice)
	if voice.positional:
		_update(voice, get_viewport().get_camera_3d(), 0.0)


func _free(voice: Voice) -> void:
	_voices.erase(voice)
	if is_instance_valid(voice.player):
		voice.player.queue_free()


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	for voice in _voices:
		if voice.positional and is_instance_valid(voice.player):
			_update(voice, camera, delta)


## The volume and pitch of a 3D voice from its place relative to the camera.
func _update(voice: Voice, camera: Camera3D, delta: float) -> void:
	if not camera:
		return
	var q := camera.global_transform.affine_inverse() * (voice.player as Node3D).global_position
	var d := maxf(q.length(), 1.0)

	# Doppler: coming closer raises the pitch.
	if voice.distance >= 0.0 and delta > 0.0:
		voice.player.pitch_scale = clampf(1.0 + (voice.distance - d) / (delta * SPEED_OF_SOUND), PITCH_MIN, PITCH_MAX)
	voice.distance = d

	var gain := _scope_gain(q) if scope_zoom > 0.0 else clampf((FAR - d) / (FAR - NEAR), 0.0, 1.0)
	voice.player.volume_db = to_db(voice.volume * gain)


## Sniper mode (0x403750): the gain of a sound through the scope, from its offset from the line of
## sight (in scope half-widths) and its depth; behind the camera it's 0.
func _scope_gain(q: Vector3) -> float:
	# Godot cameras look along −z: in front of the camera q.z < 0.
	if q.z >= 0.0:
		return 0.0
	var offset := Vector2(q.x, q.y)
	var r := offset.length()
	var screen := Vector2.ZERO
	if r > SCOPE_AXIS:
		offset -= offset * SCOPE_AXIS / r
		screen = Vector2(offset.x * 2.0 / scope_zoom, offset.y * 2.0 * SCOPE_RATIO / scope_zoom)
	var depth := -q.z
	var gain := minf(1.0, SCOPE_DEPTH / (scope_zoom * depth))
	return clampf(gain * (SCOPE_EDGE - screen.length() / depth), 0.0, 1.0)
