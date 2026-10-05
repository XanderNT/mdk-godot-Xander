## The game: a level with Kurt and the third person camera.
##
## Command line (after `--`):
##   --level=N                 LEVELn to load (3–8, default: the one chosen in the menu; played in
##                             the order 7, 6, 3, 4, 8, 5).
##   --viewer                  Open the free-camera level viewer instead.
##   --models                  Open the model viewer instead (see `model_viewer.gd`).
##   --at=x,y,z[,yaw]          Start Kurt there instead (MDK coordinates and yaw, for tests).
##   --delay=seconds           Wait this long before walking.
##   --walk=seconds            Hold "move forward" for this long (for automated tests).
##   --fire                    Hold "fire" (for automated tests).
##   --health=N                Start with this much health (for tests).
##   --give=SW_A,SW_B          Start with these pickups (for tests).
##   --use                     Press "use item" after the delay (for tests).
##   --wait=seconds            Wait this long before the screenshot.
##   --screenshot=path.png     Save a screenshot after loading (and walking) and quit.
##   --profile=seconds         Print performance and script statistics after this long, then quit.
##   --no-scripts              Don't run the level scripts (no objects or aliens).
##   --town=seconds            The minecrawler flattens the town after this long (for tests).
##   --spawn-box=TEXTURE       Create a `spawn_box` object showing that texture in front of Kurt.
##   --fx                      Effects test after the delay: slime drops and bubbles in front of
##                             Kurt, a wound and bullet holes on the first grunt (`XG`).
##   --teleport=ARENA,x,y,z    Teleports Kurt there after the delay (`teleport_player`).
##   --cow                     Drops the holy cow of `SW_EWJ` after the delay.
##   --unlock                  Unlocks every door after the delay (tests of doors and the second arena).
##   --strike[=dive]           Bones' full-screen strike after the delay (without him: `dive`).
##   --sparks                  Sparks of every kind in front of Kurt after the delay, and the first
##                             grunt (`XG`) explodes.
##   --shatter=GROUP           Shatter a triangle group of Kurt's arena (`shatter_group` test).
##   --probe=x,y               Print the arena surfaces above and below that point.
##   --sniper[=zoom[,pitch]]   Enter sniper mode after the delay (zoom 1 to 0.25, pitch in degrees,
##                             positive looks down).
##   --pause                   Open the pause menu after the delay.
##   --loading-screen=path.png Save a screenshot of the loading screen and quit.
##   --event=N                 Run `special_event` N after the delay (cutscenes, end of level).
##   --snapshot=NAME           After the delay (and the walk), make a full save as F2 does, print
##                             its hash and quit.
##   --load=NAME               Load a saved game (a full save comes back as it was; its hash is
##                             printed).
##   --bomber[=drop]           LEVEL7: hits the comm device of `DANT_5` after the delay, waits for
##                             the `XE` it calls to be rideable and drops Kurt onto it (`drop`:
##                             then a bomb once the controls are unlocked).
extends Node3D

## `--bomber`: the arena of the `XE` ride and the comm device that calls it.
const BOMBER_ARENA := "DANT_5"
const BOMBER_CALL_GROUP := 16
const BOMBER_CALL_DELAY := 1.0
## The end of the game (game state 8).
const END_MOVIE := "res://game/video/end_movie.tscn"
## F2 makes a full save (0x42b520(0)), offering the level's number as its name.
const SNAPSHOT_KEY := KEY_F2
## The name prompt is drawn over the HUD and the pause menu.
const SNAPSHOT_LAYER := 20
## Cheats typed in a level (0x42c5f0): gore on or off, and the main menu's debug keys.
const GORE_CHEAT := "TOOSCARYFORME"
const DEBUG_CHEAT := "SEETHEWHOLEGAME"

## The last letters typed, for the cheat.
var _typed := ""

@onready var level: Level = $Level
@onready var kurt: Kurt = $Kurt
@onready var scripts: MDKScriptRuntime = $Scripts
@onready var info: Label = $Info
@onready var hud: HUD = $HUDLayer/HUD


func _ready() -> void:
	var args := Args.get_all()
	if args.has("viewer"):
		get_tree().change_scene_to_file.call_deferred("res://game/level_viewer.tscn")
		return
	if args.has("models"):
		get_tree().change_scene_to_file.call_deferred("res://game/model_viewer.tscn")
		return
	if args.has("load"):
		GameState.load_game(args.load)
	# The loading screen shows while the level loads (the game is paused meanwhile).
	var level_number := int(args.get("level", str(GameState.level)))
	var loading := LoadingScreen.new()
	loading.setup(level_number, MDKFti.load_file(MDKData.path("MISC/MDKFONT.FTI")))
	loading.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(loading)
	get_tree().paused = true
	for i in 2:
		await get_tree().process_frame
	if args.has("loading-screen"):
		loading.set_progress(0.4)
		Args.screenshot_and_quit(get_tree(), args["loading-screen"], 3)
		return
	var start := Time.get_ticks_msec()
	level.load_level(level_number)
	print("Level %d loaded in %d ms" % [level.number, Time.get_ticks_msec() - start])
	loading.set_progress(1.0)
	loading.queue_free()
	get_tree().paused = false

	var sprites := MDKBni.load_file(MDKData.path("TRAVERSE/TRAVSPRT.BNI"))
	# Kurt's sliding and surfing frames are in the level's own archive.
	for animation_name in ["K_SLIP", "K_SLIDE", "K_FSLIDE", "K_BSLIDE", "K_SURF", "K_SURFJ"]:
		var animation := level.get_sprite_animation(animation_name)
		if animation:
			sprites.add_animation(animation_name, animation)
	var mixer := SoundMixer.new()
	mixer.name = "SoundMixer"
	mixer.get_sound = level.get_sound
	add_child(mixer)
	kurt.mixer = mixer
	scripts.mixer = mixer
	kurt.setup(sprites, level.get_palette(), level.get_sound)
	# Kurt keeps the health and the pickups of the fall.
	if not GameState.carry.is_empty():
		kurt.health = GameState.carry.health
		kurt.inventory = GameState.carry.inventory
		GameState.carry = {}
	hud.setup(kurt, sprites, level.get_palette(), MDKFti.load_file(MDKData.path("MISC/MDKFONT.FTI")))
	var pause := PauseMenu.new()
	pause.name = "PauseMenu"
	add_child(pause)
	kurt.died.connect(_on_kurt_died)
	kurt.inventory.difficulty = Settings.difficulty
	if args.has("health"):
		kurt.health = int(args.health)
	if args.has("give"):
		for pickup: String in args.give.split(","):
			kurt.inventory.collect(pickup, kurt)
	# The start position is slightly below the landing pad (the original lands Kurt by parachute),
	# so drop him from a bit higher.
	kurt.teleport(level.get_start_position() + Vector3.UP * 3.0, level.get_start_yaw())
	if args.has("at"):
		var at: PackedFloat64Array = args.at.split_floats(",")
		kurt.teleport(MDKMeshBuilder.to_godot(Vector3(at[0], at[1], at[2])), deg_to_rad(at[3] - 90.0) if at.size() > 3 else kurt.yaw)
	if not args.has("no-scripts"):
		scripts.messages = hud.messages
		scripts.setup(level, kurt)
		hud.scripts = scripts
		$FollowCamera.scripts = scripts
		scripts.level_ended.connect(_on_level_ended)
		scripts.game_finished.connect(get_tree().change_scene_to_file.bind(END_MOVIE), CONNECT_DEFERRED)
		# The music goes on during the full-screen strike.
		scripts.strike_scene.connect(func(active: bool) -> void:
			$LevelAudio.process_mode = Node.PROCESS_MODE_ALWAYS if active else Node.PROCESS_MODE_INHERIT)
		if not GameState.snapshot.is_empty():
			_restore_snapshot()
		if args.has("town"):
			scripts.town_ticks = roundi(float(args.town) * 30.0)
		if args.has("shatter"):
			var arena_name := level.get_arena_at(kurt.global_position)
			var centers := level.get_group_centers(arena_name, int(args.shatter))
			if not centers.is_empty():
				level.set_group_state(arena_name, int(args.shatter), 0)
				scripts.debris.shatter(arena_name, int(args.shatter), 3.0, 50.0, 3.0, centers[0], Vector3.ZERO)
				print("shatter group %s at %s" % [args.shatter, centers[0]])
		if args.has("spawn-box"):
			var facing := MDKScriptRuntime.to_mdk(kurt.get_facing())
			var point := MDKScriptRuntime.to_mdk(kurt.global_position) + facing * 20.0 + Vector3(0, 0, 5)
			scripts.spawn_box(scripts.get_arena_state(level.get_arena_at(kurt.global_position)).controller,
					point, Vector3(4, 4, 4), args["spawn-box"], 0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if args.has("fire"):
		Input.action_press(&"fire")
	if args.has("delay"):
		await get_tree().create_timer(float(args.delay)).timeout
	if args.has("fx"):
		var ahead := MDKScriptRuntime.to_mdk(kurt.global_position + kurt.get_facing() * 25.0)
		var arena_name := level.get_arena_at(kurt.global_position)
		for i in 16:
			scripts.effects.spawn_drop(arena_name, ahead + Vector3(0, 0, 5), Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), 1.5), 16.0)
		for i in 3:
			scripts.effects.spawn_bubble(arena_name, ahead + Vector3(i * 4 - 4, 0, 2))
		var alien := scripts.find_object_named("XG")
		if alien:
			scripts.effects.attach(alien, 2, 3)
			# Bullet holes on every part, at the middle of each part's box.
			for part in alien.model.parts.size():
				alien.shot_part = part + 1
				alien.shot_point = scripts.get_world_bounds(alien, alien.get_part_bounds()[part]).get_center()
				for i in 4:
					scripts.stamp_bullet_hole(alien)
	if args.has("sparks"):
		var ahead := MDKScriptRuntime.to_mdk(kurt.global_position + kurt.get_facing() * 15.0) + Vector3(0, 0, 4)
		for kind in MDKScriptRuntime.Spark.size():
			scripts.spark(ahead + Vector3(0, 0, kind * 3), 8, "", kind)
		var grunt := scripts.find_object_named("XG")
		if grunt:
			scripts.explode(grunt, 0.0)
	if args.has("teleport"):
		var parts: PackedStringArray = args.teleport.split(",")
		scripts.teleport_kurt(parts[0], Vector3(float(parts[1]), float(parts[2]), float(parts[3])), 90.0)
	if args.has("cow"):
		scripts._drop_cow()
	if args.has("unlock"):
		for obj in scripts.objects:
			obj.door_state &= ~MDKObjectBehaviors.DOOR_LOCKED
	if args.has("probe"):
		_probe(args.probe.split_floats(","))
	if args.has("sniper"):
		kurt._enter_sniper(true)
		if args.sniper != "":
			var values: PackedFloat64Array = args.sniper.split_floats(",")
			kurt.zoom = values[0]
			if values.size() > 1:
				kurt.sniper_pitch = values[1]
	if args.has("strike"):
		scripts.play_strike_scene(MDKStrikeScene.Kind.BONES, args.strike == "dive")
	if args.has("pause"):
		get_node(^"PauseMenu")._open()
	if args.has("event"):
		scripts.special_event(scripts.get_arena_state(scripts.current_arena).controller, int(args.event))
	if args.has("bomber"):
		await _board_bomber()
		if args.bomber == "drop":
			await _drop_bomb()
	if args.has("use"):
		Input.action_press(&"item_use")
		await get_tree().create_timer(0.1).timeout
		Input.action_release(&"item_use")
	if args.has("walk"):
		Input.action_press(&"move_forward")
		await get_tree().create_timer(float(args.walk)).timeout
		Input.action_release(&"move_forward")
	if args.has("wait"):
		await get_tree().create_timer(float(args.wait)).timeout
	if args.has("snapshot"):
		var state := _capture()
		GameState.save_game(args.snapshot, GameState.KIND_SNAPSHOT, state)
		print("snapshot hash %d, objects %d" % [var_to_str(state).hash(), scripts.objects.size()])
		get_tree().quit()
		return
	if args.has("screenshot"):
		Args.screenshot_and_quit(get_tree(), args.screenshot, 20)
	if args.has("profile"):
		_profile(float(args.profile))


## Test of the `XE` ride: the comm device's hit calls the `XE`; once it waits to be ridden, Kurt
## falls onto it.
func _board_bomber() -> void:
	# The teleport into `DANT_5` settles first.
	await get_tree().create_timer(BOMBER_CALL_DELAY).timeout
	scripts.hit_group(BOMBER_ARENA, BOMBER_CALL_GROUP, 1, MDKScriptRuntime.HIT_CHAIN_GUN, 0)
	var xe: MDKObject
	while not xe:
		await get_tree().physics_frame
		for obj in scripts.objects:
			if obj.type_name == "XE" and obj.flags & MDKRides.FLAG_RIDEABLE:
				xe = obj
	var top := scripts.get_world_bounds(xe).end.z
	kurt.teleport(MDKMeshBuilder.to_godot(Vector3(xe.mdk_position.x, xe.mdk_position.y, top + 1.0)), kurt.yaw)


## Presses fire for a tick once the script unlocks the `XE`'s controls.
func _drop_bomb() -> void:
	while not scripts.rides.bomber or scripts.rides.bomber.is_locked():
		await get_tree().physics_frame
	Input.action_press(&"fire")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(&"fire")


## Prints every arena surface above and below an MDK point x,y (tests of the floors).
func _probe(at: PackedFloat64Array) -> void:
	var space := get_world_3d().direct_space_state
	var from := MDKMeshBuilder.to_godot(Vector3(at[0], at[1], at[2] if at.size() > 2 else 10000.0))
	var exclude: Array[RID] = []
	for i in 20:
		var query := PhysicsRayQueryParameters3D.create(from, MDKMeshBuilder.to_godot(Vector3(at[0], at[1], -10000.0)), MDKScriptRuntime.LEVEL_LAYER)
		query.exclude = exclude
		query.hit_back_faces = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		print("probe z %.1f normal %s %s group %d" % [hit.position.y, MDKScriptRuntime.to_mdk(hit.normal).snapped(Vector3.ONE * 0.01),
				hit.collider.get_meta(&"arena", "?"), hit.collider.get_meta(&"group", 0)])
		from = hit.position + Vector3.DOWN * 0.01
	# The arena triangles over the point, whether solid or not.
	for arena_name: String in level._arenas:
		var arena: MDKArena = level._arenas[arena_name]
		var point := Vector2(at[0], at[1])
		for tri in arena.triangle_flags.size():
			var a := arena.vertices[arena.triangle_indices[tri * 3]]
			var b := arena.vertices[arena.triangle_indices[tri * 3 + 1]]
			var c := arena.vertices[arena.triangle_indices[tri * 3 + 2]]
			if Geometry2D.point_is_inside_triangle(point, Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y)):
				var n := (b - a).cross(c - a)
				var z := a.z - (n.x * (point.x - a.x) + n.y * (point.y - a.y)) / n.z if n.z != 0.0 else a.z
				print("triangle %s %d z %.1f flags %x material %d" % [arena_name, tri, z, arena.triangle_flags[tri], arena.triangle_materials[tri]])


## The level is over: the stream (`MDKStream`, then the statistics and the next briefing, or
## LEVEL5 at once after LEVEL8), or back to the menu after the last one. Kurt's health and pickups
## go with him.
func _on_level_ended(game_over: bool) -> void:
	await get_tree().create_timer(5.0 if game_over else 0.5).timeout
	var index := GameState.index_of(level.number)
	if game_over or index < 0 or index + 1 >= GameState.ORDER.size():
		get_tree().change_scene_to_file("res://game/menu/main_menu.tscn")
		return
	GameState.level = level.number
	GameState.carry = {health = kurt.health, inventory = kurt.inventory}
	get_tree().change_scene_to_file("res://game/stream/stream.tscn")


## Kurt died (`damp_control` ≈ 0x466b40): the death is counted, the level is saved as `LASTGAME`
## and the game goes back to the main menu, whose "Continue" starts the level again.
func _on_kurt_died() -> void:
	GameState.splash = true
	GameState.level = level.number
	GameState.deaths += 1
	GameState.strike_used = scripts.air_strike.used_up if scripts.air_strike else false
	GameState.save_game(GameState.LAST_GAME)
	get_tree().change_scene_to_file("res://game/menu/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == SNAPSHOT_KEY:
		_ask_snapshot()
	if event is InputEventKey and event.pressed and not event.echo:
		_type(event.keycode)


## Letters typed in a level: `TOOSCARYFORME` turns gore on or off (not saved), `SEETHEWHOLEGAME`
## the main menu's debug keys (`0x5742bc`).
func _type(keycode: Key) -> void:
	if keycode < KEY_A or keycode > KEY_Z:
		return
	_typed = (_typed + OS.get_keycode_string(keycode)).right(DEBUG_CHEAT.length())
	if _typed.ends_with(GORE_CHEAT):
		_typed = ""
		Settings.gore = not Settings.gore
		if scripts.vm:
			scripts.option = 1 if Settings.gore else 0
	elif _typed.ends_with(DEBUG_CHEAT):
		_typed = ""
		GameState.debug_keys = not GameState.debug_keys


## The level and Kurt for a full save (the save's header names this level).
func _capture() -> Dictionary:
	GameState.level = level.number
	return {kurt = kurt.snapshot(), level = scripts.snapshot()}


## A full save loaded from the menu: the level and Kurt as they were.
func _restore_snapshot() -> void:
	scripts.restore(GameState.snapshot.level)
	kurt.restore(GameState.snapshot.kurt)
	GameState.snapshot = {}
	print("restored hash %d, objects %d" % [var_to_str(_capture()).hash(), scripts.objects.size()])


## F2: the game stops and the name is asked (on black); Enter saves the level as it was.
func _ask_snapshot() -> void:
	if get_tree().paused or not scripts.vm or not scripts.can_snapshot() or kurt.sniping:
		return
	var state := _capture()
	get_tree().paused = true
	var layer := CanvasLayer.new()
	layer.layer = SNAPSHOT_LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var prompt := SavePrompt.new()
	layer.add_child(prompt)
	prompt.open(MDKFti.load_file(MDKData.path("MISC/MDKFONT.FTI")), GameState.KIND_SNAPSHOT,
			str(GameState.index_of(level.number) + 1), state)
	await prompt.closed
	layer.queue_free()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	# In sniper mode the sounds are heard through the scope.
	$SoundMixer.scope_zoom = kurt.zoom if kurt.sniping else 0.0
	info.text = "Level %d  %s  Kurt: %s  %s  objects: %d  FPS: %d" % [level.number, scripts.current_arena,
			MDKScriptRuntime.to_mdk(kurt.global_position).round(), Kurt.State.keys()[kurt.state],
			scripts.objects.size(), Engine.get_frames_per_second()]


func _profile(seconds: float) -> void:
	var frames := 0
	var start := Time.get_ticks_msec()
	var slowest := 0
	var last := start
	var process_ms := 0.0
	var physics_ms := 0.0
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		var now := Time.get_ticks_msec()
		slowest = maxi(slowest, now - last)
		last = now
		frames += 1
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	print("FPS %.1f (slowest frame %d ms), objects %d, arena %s, second %s%s" % [frames / seconds, slowest, scripts.objects.size(),
			scripts.current_arena, scripts.second_arena, " (active)" if scripts.second_active else ""])
	print("solid for Kurt: %s" % ", ".join(scripts.level.solid_arenas))
	if scripts.rides and scripts.rides.ridden:
		print("riding %s" % scripts.rides.ridden.type_name)
	if scripts.rides and scripts.rides.bomber:
		var bomber := scripts.rides.bomber
		print("bomber view %.1f, locked %s, bombs %d" % [bomber.camera_height, bomber.is_locked(), bomber.bombs])
	print("per frame: process %.1f ms, physics %.1f ms, draw calls %d; script tick %.2f ms" % [
			process_ms / frames, physics_ms / frames,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), scripts.average_tick_ms()])
	if scripts.vm:
		print("unimplemented opcodes (opcode: count): ", scripts.vm.unimplemented)
		print("effects %d, debris pieces %d" % [scripts.effects.get_child_count(), scripts.debris.piece_count()])
		var playing := {}
		for node in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false) + get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
			if node.playing:
				var key := "%s %s %s %.0fdB" % [node.get_class(), node.bus, node.get_meta(&"sound", "?"), node.volume_db]
				playing[key] = playing.get(key, 0) + 1
		print("sounds playing: ", playing)
		for obj in scripts.objects:
			print("  %s_%d %s %s yaw %d move %d path %d anim %s frame %d speed %.1f health %d flags %x%s" % [
					obj.type_name, obj.instance_id, obj.arena, obj.mdk_position.round(), obj.yaw, obj.move_command,
					obj.path, obj.animation.name if obj.animation else "-", obj.animation_frame, obj.speed, obj.health, obj.flags,
					" door %x" % obj.door_state if obj.flags & MDKObject.FLAG_DOOR else ""])
		var items := []
		for slot in kurt.inventory.slots:
			items.push_back("%s×%d" % [KurtInventory.Item.keys()[slot.item], slot.count])
		print("Kurt at %s health %d, items %s (selected %d), ammo %s, super chain gun %d" % [MDKScriptRuntime.to_mdk(kurt.global_position).round(), kurt.health, items,
				kurt.inventory.selected, kurt.inventory.ammo, kurt.inventory.super_chain_gun])
	get_tree().quit()
