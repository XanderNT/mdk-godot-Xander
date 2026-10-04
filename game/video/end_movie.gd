## The end of the game (game state 8, 0x47727c): `MISC/FLIC/MDKEND.FLC` with its sounds from
## `MISC/FINISH.BNI` and a white flash (0x477604), then `MISC/FLIC/MDKBZK.MVE` (0x477870) and the
## main menu, after the `INTRO1A` splash. See docs/gameplay.md, "Videos".
##
##   frame 1 DOGSHIP (loop) … 129 DROP, 133 FLYBY, 186 EXPLODE1, 188 DOGSHIP stops, 194 ENDEXP,
##   196 EXPLODE1, 210–232 whiter, 233 white for 1 s, 233–260 back
class_name EndMovie
extends Control

const VIDEO := "MISC/FLIC/MDKEND.FLC"
const MOVIE := "MISC/FLIC/MDKBZK.MVE"
const SOUNDS := "MISC/FINISH.BNI"
const MENU := "res://game/menu/main_menu.tscn"
## Sounds by frame (the frame counter before decoding a frame, from 0).
const FRAME_SOUNDS := {1: "DOGSHIP", 129: "DROP", 133: "FLYBY", 186: "EXPLODE1", 194: "ENDEXP", 196: "EXPLODE1"}
const LOOPED := "DOGSHIP"
const LOOP_END := 188
## The flash: up over 23 frames from 210, white at 233 (where the video holds 1 s), down over 28
## frames to 260.
const FLASH_START := 210
const FLASH_PEAK := 233
const FLASH_END := 260
const FLASH_HOLD := 1.0

## The end has been shown (the menu doesn't play it again for `--end`).
static var played := false

var _video := MDKVideo.new()
var _sounds: MDKBni
var _players := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_video)
	_sounds = MDKBni.load_file(MDKData.path(SOUNDS))
	_video.frame_shown.connect(_on_frame)
	_video.finished.connect(_play_movie, CONNECT_ONE_SHOT)
	if not _video.play(VIDEO):
		_play_movie.call_deferred()
	var args := Args.get_all()
	if args.has("screenshot"):
		# Tests: `--wait=seconds` into the video.
		await get_tree().create_timer(float(args.get("wait", "0"))).timeout
		Args.screenshot_and_quit(get_tree(), args.screenshot)


## Esc gives up (the original asks first during the FLC, and "quit" also skips the MVE; the MVE
## can't be stopped).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_to_menu()


## `frame` frames are shown: the extras of the next one (0x477604).
func _on_frame(frame: int) -> void:
	if FRAME_SOUNDS.has(frame):
		_play(FRAME_SOUNDS[frame])
	if frame == LOOP_END and _players.has(LOOPED):
		_players[LOOPED].stop()
	_video.set_brighten(_flash(frame))
	if frame == FLASH_PEAK:
		_video.hold(FLASH_HOLD)


## How much whiter the frame is (0–1).
static func _flash(frame: int) -> float:
	if frame < FLASH_START or frame > FLASH_END:
		return 0.0
	if frame < FLASH_PEAK:
		return roundf(255.0 * (frame - FLASH_START) / (FLASH_PEAK - FLASH_START)) / 255.0
	return roundf(255.0 * (FLASH_END - frame) / (FLASH_END - FLASH_PEAK)) / 255.0


## After the FLC: the MVE, then the menu.
func _play_movie() -> void:
	for player: AudioStreamPlayer in _players.values():
		player.stop()
	_video.set_brighten(0.0)
	_video.finished.connect(_to_menu, CONNECT_ONE_SHOT)
	if not _video.play_movie(MOVIE):
		_to_menu()


func _play(sound_name: String) -> void:
	if not _sounds or not _sounds.has(sound_name):
		return
	var entry: Array = _sounds.entries[sound_name]
	var player := AudioStreamPlayer.new()
	player.bus = &"Effects"
	player.stream = MDKSound.load_wav(_sounds.bytes.slice(entry[0], entry[0] + entry[1]), sound_name == LOOPED)
	add_child(player)
	player.play()
	_players[sound_name] = player


func _to_menu() -> void:
	played = true
	GameState.splash = true
	get_tree().change_scene_to_file(MENU)
