## Plays the music of the arena Kurt is in (0x419158, fades 0x418ffc). See docs/sound.md, "Music".
##
## A new track fades in from −25 dB to full in about 8.7 s while the previous one fades out to
## −25 dB in about 4.35 s and stops. Corridors (arenas without music) play the level's `CORRIDOR`;
## `NONE` is silence. Going back to the fading track brings it back where it was.
class_name LevelAudio
extends Node

## Volume steps per frame at the original's ~29.4 frames per second (0x7FFF is full).
const FRAMES_PER_SECOND := 1000.0 / 34.0
const FADE_IN := 0x80 * FRAMES_PER_SECOND
const FADE_OUT := 0x100 * FRAMES_PER_SECOND
const CORRIDOR := "CORRIDOR"

@export var level: Level
@export var target: Node3D
## Kurt's arena comes from the scripts when they run (crossing connections), else from his position.
var scripts: MDKScriptRuntime

var arena := ""
## The playing track and the one fading out, with their volumes (0–0x7FFF).
var _current := AudioStreamPlayer.new()
var _fading := AudioStreamPlayer.new()
var _current_volume := 0.0
var _fading_volume := 0.0
## The arena's ambient loop, which the 1996 demo plays under the music (`MDKCmi.arena_ambience`).
var _ambience := AudioStreamPlayer.new()


func _ready() -> void:
	for player: AudioStreamPlayer in [_current, _fading]:
		player.bus = &"Music"
		add_child(player)
	_ambience.bus = &"Effects"
	add_child(_ambience)


func _process(delta: float) -> void:
	if not level.cmi or not target:
		return
	var current_arena := scripts.current_arena if scripts else level.get_arena_at(target.global_position)
	if not current_arena.is_empty() and current_arena != arena:
		arena = current_arena
		_switch(_music_of(arena))
		if level.cmi.beta:
			_play_ambience(level.get_sound(level.cmi.arena_ambience.get(arena, "")))
	_fade(delta)


## The track of an arena: its own, or `CORRIDOR` when it has none (null for `NONE`).
func _music_of(arena_name: String) -> AudioStream:
	var music_name: String = level.cmi.arena_music.get(arena_name, "")
	return level.get_sound(CORRIDOR if music_name.is_empty() else music_name)


func _switch(music: AudioStream) -> void:
	if music == _current.stream:
		return

	# Back to the fading track: they swap.
	if music and music == _fading.stream:
		var player := _current
		_current = _fading
		_fading = player
		var volume := _current_volume
		_current_volume = _fading_volume
		_fading_volume = volume
		return

	# The current track fades out, the new one fades in.
	_fading.stop()
	var player := _fading
	_fading = _current
	_fading_volume = _current_volume
	_current = player
	_current.stream = music
	_current_volume = 0.0
	if music:
		_current.play()


func _play_ambience(sound: AudioStreamWAV) -> void:
	if sound == _ambience.stream:
		return
	_ambience.stream = sound
	if sound:
		_ambience.volume_db = SoundMixer.to_db(sound.get_meta(&"volume", SoundMixer.FULL_VOLUME))
		_ambience.play()
	else:
		_ambience.stop()


func _fade(delta: float) -> void:
	_current_volume = minf(_current_volume + FADE_IN * delta, SoundMixer.FULL_VOLUME)
	_fading_volume -= FADE_OUT * delta
	if _fading_volume < 0.0:
		_fading.stop()
	_current.volume_db = SoundMixer.to_db(_current_volume)
	_fading.volume_db = SoundMixer.to_db(_fading_volume)
