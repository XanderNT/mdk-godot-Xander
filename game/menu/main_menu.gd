## The main menu: original background, texts and music. The original font isn't decoded yet.
## `MDK12.FLC` plays behind it each time it opens (0x4260e4), its last frame stays, then the
## slideshow (`MenuSlideshow`); `MDKOPT` is the background when the video is missing. At start,
## after Kurt died and after the end movies the `INTRO1A` splash comes first (`IntroSplash`;
## `--menu` skips it unless `--splash` is given too).
##
## Game command line options (`--level`, `--viewer`, `--screenshot`, …) skip the menu,
## unless `--menu` is given; `--options` and `--controls` open those screens; `--stats=N` shows the
## screens after LEVELn (`--phase=1…4` starts at a page, `--counts=shots,hits,sniper,sniper hits,
## kills,enemies,heads`, `--towns=bits`), `--beta-levels` the page of the 1996 demo's levels, `--briefing=N` its briefing and `--fall=N` the fall before it,
## `--stream=N` the stream after it, `--end` the end movie.
extends Control

const MENU_VIDEO := "MISC/FLIC/MDK12.FLC"
## "Really Quit?" (0x403cf8): its title in row 3 (y 139), Yes and No below; Y, J, O, S or T say
## yes in the game's languages, N no.
const QUIT_ROW := 3
const YES_KEYS := [KEY_Y, KEY_J, KEY_O, KEY_S, KEY_T]
const NO_KEY := KEY_N

## `SEETHEWHOLEGAME`'s keys: LEVEL3–8, the fall of level index 4, the stream after index 0, and
## random counts below 100 for the statistics ❓ (the original's range wasn't read).
const DEBUG_FIRST_LEVEL := KEY_3
const DEBUG_LAST_LEVEL := KEY_8
const DEBUG_FALL_INDEX := 4
const DEBUG_STREAM_INDEX := 0
const DEBUG_STATS_MAX := 100

## The page of the 1996 demo's levels (`_show_beta_levels`): its title and the levels' names.
const BETA_TITLE := "Beta Levels"
const BETA_LEVEL_NAMES := {1: "96 Level 1: City", 3: "96 Level 3: Wheel Boss", 6: "96 Level 6: Olympus"}

## The page shown, for Esc.
enum Page { MAIN, QUIT, OTHER }

## The command line skipped the menu (`--level`, …) once: when that game comes back to it (the
## level is over, Kurt died), it stays instead of reloading the level.
static var _skipped := false

var fti: MDKFti
var level_index := 0
var _video := MDKVideo.new()
var _slideshow: MenuSlideshow
var _page := Page.MAIN

@onready var background: TextureRect = $Background
@onready var items: MenuItems = $Items
@onready var music: AudioStreamPlayer = $Music
@onready var click: AudioStreamPlayer = $Click


func _ready() -> void:
	var args := Args.get_all()
	if args.has("stats") or args.has("briefing"):
		# Tests: the screens after LEVELn (`--stats=N`) or its briefing (`--briefing=N`).
		GameState.level = int(args.get("stats", args.get("briefing", "7")))
		StatsScreen.briefing_only = args.has("briefing")
		get_tree().change_scene_to_file.call_deferred("res://game/menu/stats_screen.tscn")
		return
	if args.has("stream"):
		# Test: the stream after LEVELn (`--stream=N`).
		GameState.level = int(args.stream)
		get_tree().change_scene_to_file.call_deferred("res://game/stream/stream.tscn")
		return
	if args.has("end") and not EndMovie.played:
		# Test: the end movie (`--end`).
		get_tree().change_scene_to_file.call_deferred("res://game/video/end_movie.tscn")
		return
	if args.has("fall"):
		# Test: the fall before LEVELn (`--fall=N`).
		GameState.level = int(args.fall)
		get_tree().change_scene_to_file.call_deferred("res://game/fall/fall.tscn")
		return
	var skip: bool = args.has("level") or args.has("load") or args.has("viewer") or args.has("models") or (args.has("screenshot") and not args.has("menu"))
	if skip and not _skipped:
		_skipped = true
		get_tree().change_scene_to_file.call_deferred("res://game/main.tscn")
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	fti = MDKFti.load_file(MDKData.path("MISC/MDKFONT.FTI"))
	var options := MDKBni.load_file(MDKData.path("MISC/OPTIONS.BNI"))

	# `MDKOPT`: a 768-byte palette, then a 600×360 image.
	var entry: Array = options.entries["MDKOPT"]
	var palette := MDKPalette.from_rgb(options.bytes.slice(entry[0], entry[0] + 768))
	var image := MDKTexture.parse("MDKOPT", options.bytes, entry[0] + 768)
	background.texture = ImageTexture.create_from_image(palette.make_image(image.width, image.height, image.indices))
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_sibling(_video)
	_slideshow = MenuSlideshow.new(_video, items)
	var splash := GameState.splash and (not args.has("menu") or args.has("splash"))
	GameState.splash = false
	if splash:
		_show_splash()
	else:
		_start_video()

	var song: Array = options.entries["MAINSONG"]
	music.bus = &"Music"
	music.stream = MDKSound.load_wav(options.bytes.slice(song[0], song[0] + song[1]), true)
	music.play()
	click.stream = MDKSound.load_wav(fti.get_bytes("SND_PUSH"))
	items.click = click
	items.setup(fti)

	level_index = maxi(GameState.index_of(GameState.level), 0)
	_show_main()
	if args.has("options"):
		_show_options()
	if args.has("beta-levels") and MDKBeta.is_available():
		_show_beta_levels()
	if args.has("controls"):
		items.show_controls(_show_options)

	if args.has("screenshot"):
		# `--wait=seconds` first (the menu video, the slideshow).
		if args.has("wait"):
			await get_tree().create_timer(float(args.wait)).timeout
		Args.screenshot_and_quit(get_tree(), args.screenshot)


## The splash covers the menu, then the menu's video starts.
func _show_splash() -> void:
	items.visible = false
	var splash := IntroSplash.new()
	add_child(splash)
	await splash.finished
	splash.queue_free()
	items.visible = true
	items.get_child(0).grab_focus()
	_start_video()


func _start_video() -> void:
	if _video.play(MENU_VIDEO):
		background.visible = false
		_video.finished.connect(_slideshow.start)
	else:
		_video.queue_free()


func _process(delta: float) -> void:
	if _slideshow:
		_slideshow.update(delta)


## Any key or click starts the slideshow's wait again (the menu still gets it).
func _input(event: InputEvent) -> void:
	if _slideshow and (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_slideshow.reset()


## Esc on the main page asks "Really Quit?", and there means no.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not items.visible:
		return
	if _page == Page.MAIN and GameState.debug_keys and _debug_key(event.keycode):
		get_viewport().set_input_as_handled()
		return
	if _page == Page.MAIN and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_show_quit()
	elif _page == Page.QUIT and event.keycode in YES_KEYS:
		get_tree().quit()
	elif _page == Page.QUIT and event.keycode in [NO_KEY, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		_show_main()


## The debug keys of `SEETHEWHOLEGAME` (0x426574, 0x410018, 0x433b50, 0x431b00). Returns whether
## the key was one of them.
func _debug_key(keycode: Key) -> bool:
	if keycode >= DEBUG_FIRST_LEVEL and keycode <= DEBUG_LAST_LEVEL:
		GameState.level = keycode - KEY_0
		get_tree().change_scene_to_file("res://game/main.tscn")
		return true
	match keycode:
		KEY_F:
			GameState.level = GameState.ORDER[DEBUG_FALL_INDEX]
			get_tree().change_scene_to_file("res://game/fall/fall.tscn")
		KEY_S:
			GameState.level = GameState.ORDER[DEBUG_STREAM_INDEX]
			get_tree().change_scene_to_file("res://game/stream/stream.tscn")
		KEY_D:
			for key: String in GameState.stats:
				GameState.stats[key] = randi() % DEBUG_STATS_MAX
			StatsScreen.briefing_only = false
			get_tree().change_scene_to_file("res://game/menu/stats_screen.tscn")
		_:
			return false
	return true


func _show_quit() -> void:
	items.clear()
	_page = Page.QUIT
	items.first_row = QUIT_ROW
	items.add_title(fti.get_text("ABORT1", "Really Quit?"))
	items.add_item(fti.get_text("ABORT2", "Yes"), get_tree().quit)
	items.add_item(fti.get_text("ABORT3", "No"), _show_main)
	items.get_child(1).grab_focus()


func _show_main() -> void:
	items.clear()
	_page = Page.MAIN
	# "Continue" plays the level Kurt last died in (`LASTGAME`).
	if GameState.has_last_game():
		items.add_item(fti.get_text("OPT0", "Continue"), _load.bind(GameState.LAST_GAME))
	items.add_item(fti.get_text("OPT1", "New Game"), _on_new_game)
	items.add_item("", _on_level).name = "Level"
	items.add_item(fti.get_text("OPT2", "Saved Game"), _show_saves)
	# The 1996 demo's levels, when the demo is found.
	if MDKBeta.is_available():
		items.add_item(BETA_TITLE, _show_beta_levels)
	items.add_item(fti.get_text("OPT3", "Options"), _show_options)
	items.add_item(fti.get_text("OPT4", "Quit"), get_tree().quit)
	# The main page is a column at the view's left edge (0x4265c0).
	items.align = MenuItems.Align.LEFT
	_update_level_text()
	items.get_child(0).grab_focus()


## The saved games (`SVOPT1`, or `SVOPT3` when there are none), with their level.
func _show_saves() -> void:
	items.clear()
	_page = Page.OTHER
	var names := GameState.list_games()
	items.add_title(fti.get_text("SVOPT1" if not names.is_empty() else "SVOPT3", "Saved games").split("
")[0])
	for save_name in names:
		var data := GameState.read_game(save_name)
		var text := "%s  (%s)" % [save_name, "Level %d" % (GameState.index_of(int(data.level)) + 1) if not data.is_empty() else fti.get_text("SVBAD", "Invalid")]
		var button := items.add_item(text, _load.bind(save_name))
		button.disabled = data.is_empty()
	items.add_item("Back", _show_main)
	items.get_child(mini(1, items.get_child_count() - 1)).grab_focus()


func _load(save_name: String) -> void:
	if not GameState.load_game(save_name):
		return

	# A save made before a level shows its briefing and the fall first.
	if int(GameState.read_game(save_name).get("type", GameState.KIND_LEVEL_START)) == GameState.KIND_BEFORE_LEVEL:
		StatsScreen.briefing_only = true
		get_tree().change_scene_to_file("res://game/menu/stats_screen.tscn")
		return
	get_tree().change_scene_to_file("res://game/main.tscn")


## `MAINSONG` stops while the options play `OPTSONG` (0x42bb6c, 0x42bbc0).
func _show_options() -> void:
	_page = Page.OTHER
	music.stop()
	items.show_options(func() -> void:
		music.play()
		_show_main())


## The levels of the 1996 demo (`MDKBeta`, docs/beta96.md), a page of the port's own.
func _show_beta_levels() -> void:
	items.clear()
	_page = Page.OTHER
	items.add_title(BETA_TITLE)
	for beta_level in MDKBeta.LEVELS:
		items.add_item(BETA_LEVEL_NAMES[beta_level], _on_beta_level.bind(beta_level))
	items.add_item("Back", _show_main)
	items.get_child(1).grab_focus()


## The demo's levels start at once: it has no briefing or fall.
func _on_beta_level(beta_level: int) -> void:
	GameState.level = MDKBeta.number_of(beta_level)
	GameState.deaths = 0
	GameState.strike_used = false
	GameState.carry = {}
	get_tree().change_scene_to_file("res://game/main.tscn")


func _update_level_text() -> void:
	items.get_node(^"Level").text = "Level: %d" % (level_index + 1)


func _on_new_game() -> void:
	GameState.level = GameState.ORDER[level_index]
	GameState.deaths = 0
	GameState.strike_used = false
	# The briefing, the fall, then the level.
	StatsScreen.briefing_only = true
	get_tree().change_scene_to_file("res://game/menu/stats_screen.tscn")


func _on_level() -> void:
	level_index = (level_index + 1) % GameState.ORDER.size()
	_update_level_text()
