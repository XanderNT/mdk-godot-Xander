## The stream after a level (game state 5: init 0x433b50, each frame 0x4352ac, cleanup 0x435210).
## See docs/gameplay.md, "The stream".
##
## Kurt flies down a translucent tube (`StreamTube`) generated as he goes. The walls hurt. After
## about 30 seconds (or at 1 health) Bones picks him up with a crane (`BONESANIM`); after LEVEL8
## (the Gunter variant) Kurt follows Gunter carrying Bones towards a planet and can die. Then the
## statistics, or LEVEL5 directly after LEVEL8.
##
## Test options (after `--`): `--stream=N` in the main menu starts the stream after LEVELn;
## `--wait=seconds` and `--screenshot=path.png`; `--health=N`.
class_name MDKStream
extends Control

enum Playback { ONCE, LOOP }

const VIEW_HEIGHT := 360.0
const FOCAL := 250.0
const TICKS_PER_SECOND := 30.0
## The last level index with statistics after the stream; the next ones load LEVEL5 directly.
const LAST_STATS_INDEX := 3
## Kurt's speed (segments/s), its recovery (segments/s²), its loss per hit and its minimum.
const SPEED := 6.0
const SPEED_RECOVERY := 1.0
const SPEED_LOSS := 0.9
const SPEED_MIN := 4.5
## Kurt starts this far into the tube, and the tube moves on when he's this far past its tail + 1.
const KURT_START := 0.75
## Steering (°/s, ° around the neutral yaw 90 and pitch 0), and the sideways speed at full turn.
const TURN_RATE := 180.0
const TURN_LIMIT := 45.0
const NEUTRAL_YAW := 90.0
const SIDE_SPEED := 25.0
## Kurt steers until Bones comes or he dies.
func _controlled() -> bool:
	return _bones == null and _health > 0


## On bends Kurt keeps going straight (a lagging direction) and drifts outwards at this rate.
const DRIFT := 100.0
const DIRECTION_LAG := 0.75
## Without control he drifts back to the axis (units/s).
const AXIS_RETURN := 6.25
const WALL_MARGIN := 1.5
## Health lost per wall hit: a base and a random extra (0 or 1 times the step) per difficulty.
const HIT_DAMAGE := [2, 2, 4]
const HIT_EXTRA := [0, 1, 2]
## Bones comes after this segment (normal variant); the rescue ends past this animation frame.
const RESCUE_SEGMENT := 177
const RESCUE_END_FRAME := 80
## The health bonus: where it starts, its speed, its reach and the health it gives.
const SWH150_START := 16.0
const SWH150_SPEED := 5.48
const SWH150_REACH := 5.0
const SWH150_HEALTH := 150
const GUNTA_START := 5.0
## The camera: from the axis behind Kurt and a point past him, looking two segments ahead.
const CAMERA_BACK := 0.75
const CAMERA_AHEAD := 2.0
const CAMERA_BLEND := 0.4
const CAMERA_PAST := 1.375
## Sprites are drawn a quarter of their size (lights), the planet half.
const LIGHT_SCALE := 0.25
const PLANET_SCALE := 0.5
const HURT_SOUNDS := ["HURT1", "HURT2", "HURT3", "HURT4", "HURT5", "HURT6", "HURT7"]
const PLAYERS := 8


class Thing:
	var node: Node3D
	## Position along the tube (segments), across it (x, z) and speed (segments/s).
	var t := 0.0
	var x := 0.0
	var z := 0.0
	var speed := 0.0
	var yaw := 0.0
	var frame := 0.0


var _index := 0
var _difficulty := 1
var _health := 100
var _kind := StreamTube.Kind.NORMAL
var _tube: StreamTube

var _bni: MDKBni
var _palette: MDKPalette
var _resolver: MDKMeshBuilder.MaterialResolver
var _models := {}
var _animations := {}
var _baked := {}
var _meshes := {}
var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _hitside := AudioStreamPlayer.new()
var _wind := AudioStreamPlayer.new()
var _health_box := HealthBox.new()
var _messages := HUDMessages.new()

# Nodes.
var _back := Control.new()
var _view := SubViewport.new()
var _view_rect := TextureRect.new()
var _hud := Control.new()
var _screen := ColorRect.new()
var _screen_material := ShaderMaterial.new()
var _world := Node3D.new()
var _camera := Camera3D.new()
var _tube_node := MeshInstance3D.new()
var _tube_mesh := ImmediateMesh.new()
var _tube_material := StandardMaterial3D.new()
var _background: Texture2D
var _light_material := StandardMaterial3D.new()
var _planet_material := StandardMaterial3D.new()

# Kurt, the others and the camera.
var _kurt := Thing.new()
var _kurt_animation := "KURTANIM"
var _direction := Vector3(0, 1, 0)
var _pitch := 0.0
var _kurt_position := Vector3()
var _bones: Thing
var _pickup: Thing
var _gunta: Thing
var _sprites: Array[Thing] = []
var _screen_up := Vector3(0, 0, 1)
var _view_rows: Array[Vector3] = []
var _background_offset := Vector2()
var _camera_eye := Vector3()

var _fade := 0.0
var _ending := false
var _ended := false
var _blink := 0
var _tick_fraction := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_index = clampi(GameState.index_of(GameState.level), 0, LAST_STATS_INDEX + 1)
	_kind = StreamTube.Kind.GUNTER if _index > LAST_STATS_INDEX else StreamTube.Kind.NORMAL
	_difficulty = Settings.difficulty
	if not GameState.carry.is_empty():
		_health = GameState.carry.health

	var args := Args.get_all()
	if args.has("health"):
		_health = int(args.health)

	_load()
	_build_nodes()
	_start()

	if args.has("screenshot"):
		await get_tree().create_timer(float(args.get("wait", "3"))).timeout
		Args.screenshot_and_quit(get_tree(), args.screenshot, 2)


func _load() -> void:
	_bni = MDKBni.load_file(MDKData.path("STREAM/STREAM.BNI"))
	var fti := MDKFti.load_file(MDKData.path("MISC/MDKFONT.FTI"))

	# Colours 0–63 are the system palette, 64–255 the stream's `PAL`.
	var system_size := MDKPalette.ARENA_FIRST_INDEX * 3
	var rgb := fti.get_bytes("SYS_PAL").slice(0, system_size)
	var entry: Array = _bni.entries["PAL"]
	rgb.append_array(_bni.bytes.slice(entry[0] + system_size, entry[0] + 768))
	_palette = MDKPalette.from_rgb(rgb)

	var archives: Array[MDKTextureArchive] = [MDKTextureArchive.load_file(MDKData.path("STREAM/STREAM.MTI"))]
	_resolver = MDKMeshBuilder.MaterialResolver.new(_palette, archives)
	_resolver.double_sided = true
	var others := "GUNTANIM" if _kind == StreamTube.Kind.GUNTER else "SWHANM"
	for animation_name in ["KURTANIM", "BONESANIM", others]:
		_animations[animation_name] = MDKModelAnimation.parse(animation_name, _bni.bytes, _bni.entries[animation_name][0])

	_messages.setup(fti, _palette)
	_health_box.setup(_bni, _palette)
	var background := _bni.get_image("BG")
	_background = ImageTexture.create_from_image(_palette.make_image(background.width, background.height, background.indices))

	for i in PLAYERS:
		var player := AudioStreamPlayer.new()
		_players.push_back(player)
	for player: AudioStreamPlayer in _players + [_hitside, _wind]:
		player.bus = &"Effects"
		add_child(player)
	_hitside.stream = _sound("HITSIDE", Playback.ONCE)
	_wind.stream = _sound("WIND", Playback.LOOP)


func _sound(sound_name: String, playback: Playback) -> AudioStreamWAV:
	var key := "%s|%d" % [sound_name, playback]
	if _sounds.has(key):
		return _sounds[key]
	var entry: Array = _bni.entries.get(sound_name, [])
	if entry.is_empty():
		_sounds[key] = null
		return null
	_sounds[key] = MDKSound.load_wav(_bni.bytes.slice(entry[0], entry[0] + entry[1]), playback == Playback.LOOP)
	return _sounds[key]


func _play(sound_name: String) -> void:
	for player in _players:
		if player.playing:
			continue
		player.stream = _sound(sound_name, Playback.ONCE)
		player.play()
		return


func _build_nodes() -> void:
	# Layers: the background, the 3D view, the HUD, then the fades over everything.
	_screen_material.shader = preload("res://game/fall/fall_screen.gdshader")
	_screen.material = _screen_material
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for control: Control in [_back, _view_rect, _hud, _screen]:
		control.set_anchors_preset(Control.PRESET_FULL_RECT)
		control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(control)
	_back.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_back.draw.connect(_draw_back)
	_hud.draw.connect(_draw_hud)

	# The 3D view, its colours already multiplied by their alpha.
	_view.transparent_bg = true
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_view_rect.texture = _view.get_texture()
	_view_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var premultiplied := CanvasItemMaterial.new()
	premultiplied.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_view_rect.material = premultiplied
	_view.add_child(_world)
	_world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.fov = rad_to_deg(2.0 * atan(VIEW_HEIGHT * 0.5 / FOCAL))
	_camera.near = 0.05
	_camera.far = 1000.0
	_world.add_child(_camera)

	# The tube: translucent vertex colours drawn far to near, before the sprites.
	_tube_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tube_material.vertex_color_use_as_albedo = true
	_tube_material.vertex_color_is_srgb = true
	_tube_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tube_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tube_material.render_priority = -1
	_tube_node.mesh = _tube_mesh
	_tube_node.extra_cull_margin = 16384.0
	_world.add_child(_tube_node)

	# Sprites; the lights glow, added to what's behind (❓ the original's blend isn't known).
	_setup_sprite(_light_material, "LIGHT")
	_light_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_setup_sprite(_planet_material, "PLANET")


func _setup_sprite(material: StandardMaterial3D, image_name: String) -> void:
	var image := _bni.get_image(image_name)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = ImageTexture.create_from_image(_palette.make_image(image.width, image.height, image.indices, true))


func _start() -> void:
	_tube = StreamTube.new(_index, _difficulty, _kind)
	_add_spawns()

	_kurt.t = KURT_START
	_kurt.yaw = NEUTRAL_YAW
	_kurt.speed = SPEED
	_kurt.node = _make_node("KURT")
	if _kind == StreamTube.Kind.GUNTER:
		_gunta = _make_thing("GUNTA", GUNTA_START, SPEED)
		_gunta.yaw = NEUTRAL_YAW
	else:
		_pickup = _make_thing("SWH150", SWH150_START, SWH150_SPEED)

	_wind.play()
	_update_camera()


# --- Objects ---

func _get_model(model_name: String) -> MDKModel:
	if not _models.has(model_name):
		_models[model_name] = MDKModel.parse(model_name, _bni.bytes, _bni.entries[model_name][0], false, true)
	return _models[model_name]


func _get_mesh(model_name: String, animation_name := "", frame := 0) -> Mesh:
	var key := "%s|%s|%d" % [model_name, animation_name, frame]
	if _meshes.has(key):
		return _meshes[key]

	var model := _get_model(model_name)
	var pose: Array = model.get_rest_pose()
	if animation_name != "":
		var bake_key := model_name + "|" + animation_name
		if not _baked.has(bake_key):
			_baked[bake_key] = (_animations[animation_name] as MDKModelAnimation).bake(model)
		pose = _baked[bake_key][mini(frame, _baked[bake_key].size() - 1)]
	_meshes[key] = MDKMeshBuilder.build_model_mesh(model, pose, _resolver)
	return _meshes[key]


func _make_node(model_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _get_mesh(model_name)
	_world.add_child(node)
	return node


func _make_thing(model_name: String, t: float, speed: float) -> Thing:
	var thing := Thing.new()
	thing.node = _make_node(model_name)
	thing.t = t
	thing.speed = speed
	return thing


## The lights and the planet the tube made: billboards flying along it.
func _add_spawns() -> void:
	for spawn in _tube.take_spawns():
		var light := spawn.kind == StreamTube.SpawnKind.LIGHT
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * spawn.size * (LIGHT_SCALE if light else PLANET_SCALE)
		quad.material = _light_material if light else _planet_material
		var node := MeshInstance3D.new()
		node.mesh = quad
		_world.add_child(node)

		var thing := Thing.new()
		thing.node = node
		thing.t = spawn.t
		thing.x = spawn.x
		thing.z = spawn.z
		thing.speed = spawn.speed
		_sprites.push_back(thing)


## Moves an object along the tube (0x436440); it's freed once it leaves the rings still alive.
func _move(thing: Thing, dt: float) -> bool:
	thing.t += thing.speed * dt
	thing.frame += dt * TICKS_PER_SECOND
	if _tube.contains(thing.t):
		return true
	thing.node.queue_free()
	return false


## Places a model on the axis, turned to its yaw in the tube's frame, in its animation's frame.
func _place(thing: Thing, animation_name: String, model_name: String) -> void:
	thing.node.position = MDKMeshBuilder.to_godot(_tube.place(thing.t, thing.x, thing.z))
	thing.node.basis = _to_godot_basis(_tube.frame(thing.t, _screen_up)) * Basis(Vector3.UP, deg_to_rad(thing.yaw))
	var animation: MDKModelAnimation = _animations[animation_name]
	(thing.node as MeshInstance3D).mesh = _get_mesh(model_name, animation_name, int(thing.frame) % animation.frame_count)


## An MDK basis (columns in MDK space) as a Godot basis acting on converted model vertices.
static func _to_godot_basis(basis: Basis) -> Basis:
	return Basis(MDKMeshBuilder.to_godot(basis.x), MDKMeshBuilder.to_godot(basis.z), -MDKMeshBuilder.to_godot(basis.y))


# --- Each frame (0x4352ac) ---

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not _ending:
		_ending = true


func _process(delta: float) -> void:
	if _ended:
		return
	var dt := minf(delta, 0.1)
	_tick_fraction += dt * TICKS_PER_SECOND
	var ticks := int(_tick_fraction)
	_tick_fraction -= ticks
	_blink = (_blink + ticks) & 31
	if Vector2i(size) != _view.size:
		_view.size = Vector2i(size)

	_check_end()
	if not _update_fade(dt):
		return

	_update_kurt(dt)
	_update_others(dt)
	_update_camera()
	_tube.build_mesh(_tube_mesh, _tube_material, _camera_eye)
	_messages.update(dt)
	_back.queue_redraw()
	_hud.queue_redraw()


## The rescue after segment 177 or at 1 health, or the end of the Gunter tube.
func _check_end() -> void:
	if _health <= 0 or (_tube.tail <= RESCUE_SEGMENT and _health != 1):
		return
	if _kind == StreamTube.Kind.GUNTER:
		_ending = _ending or _tube.head >= StreamTube.LAST_SEGMENT
		return
	if not _bones:
		_start_rescue()
	if _bones.frame > RESCUE_END_FRAME:
		_ending = true


## The fade (`0x520860`): in from white (black after LEVEL8) over 1 s, out the same way once the
## stream ends; on death in the Gunter tube a red flash, then black. Returns false once over.
func _update_fade(dt: float) -> bool:
	if _ending:
		_fade -= dt
		if _fade < 0.0:
			_finish()
			return false
	elif _fade < 1.0:
		_fade = minf(_fade + dt, 1.0)

	var f := clampf(_fade, 0.0, 2.0)
	if _health <= 0 and f > 1.0:
		_set_screen(1.0, 1.0, 2.0 - f)
	elif _health <= 0:
		_set_screen(1.0, f, 1.0)
	elif _kind == StreamTube.Kind.GUNTER:
		_set_screen(1.0, minf(f, 1.0), 0.0)
	else:
		_set_screen(minf(f, 1.0), 1.0, 0.0)
	return true


func _set_screen(whiten: float, dark: float, red: float) -> void:
	_screen_material.set_shader_parameter(&"whiten", whiten)
	_screen_material.set_shader_parameter(&"dark", dark)
	_screen_material.set_shader_parameter(&"red", red)


## The lights and the planet, the health bonus, Gunter and Bones.
func _update_others(dt: float) -> void:
	for thing: Thing in _sprites.duplicate():
		if not _move(thing, dt):
			_sprites.erase(thing)
			continue
		thing.node.position = MDKMeshBuilder.to_godot(_tube.place(thing.t, thing.x, thing.z))

	if _pickup:
		_update_pickup(dt)

	if _gunta and not _move(_gunta, dt):
		_gunta = null
	if _gunta:
		_place(_gunta, "GUNTANIM", "GUNTA")

	if _bones:
		# Bones plays the rescue on Kurt's transform.
		_bones.frame += dt * TICKS_PER_SECOND * (_animations["BONESANIM"] as MDKModelAnimation).speed
		_bones.node.transform = _kurt.node.transform
		(_bones.node as MeshInstance3D).mesh = _get_mesh("BONES", "BONESANIM", int(_bones.frame))


# --- Kurt (0x435c4c) ---

func _update_kurt(dt: float) -> void:
	_kurt.speed = minf(_kurt.speed + SPEED_RECOVERY * dt, SPEED)
	_kurt.t += _kurt.speed * dt

	# A new segment each time Kurt passes one.
	if _kurt.t - KURT_START > _tube.tail + 1:
		_tube.advance()
		_add_spawns()

	var animation: MDKModelAnimation = _animations[_kurt_animation]
	_kurt.frame += dt * TICKS_PER_SECOND * animation.speed
	var looping := _kurt_animation == "KURTANIM"
	if looping:
		_kurt.frame = fmod(_kurt.frame, animation.frame_count)

	var frame := _tube.frame(_kurt.t, _screen_up)
	_drift(frame, dt)
	_steer(dt)

	var centre := _tube.centre(_kurt.t)
	_kurt_position = centre + frame.x * _kurt.x + frame.z * _kurt.z
	if _controlled():
		_collide(centre, frame)

	_kurt.node.position = MDKMeshBuilder.to_godot(_kurt_position)
	_kurt.node.basis = _to_godot_basis(frame) * Basis(Vector3.UP, deg_to_rad(_kurt.yaw)) * Basis(Vector3.BACK, deg_to_rad(_pitch))
	var shown := int(_kurt.frame) if looping else mini(int(_kurt.frame), animation.frame_count - 1)
	(_kurt.node as MeshInstance3D).mesh = _get_mesh("KURT", _kurt_animation, shown)


## On bends Kurt keeps going straight and drifts to the outer wall; without control he goes back
## to the axis.
func _drift(frame: Basis, dt: float) -> void:
	if not _controlled():
		_kurt.x = move_toward(_kurt.x, 0.0, AXIS_RETURN * dt)
		_kurt.z = move_toward(_kurt.z, 0.0, AXIS_RETURN * dt)
		return
	_direction = (DIRECTION_LAG * _direction + (1.0 - DIRECTION_LAG) * frame.y).normalized()
	_kurt.x += DRIFT * dt * _direction.dot(frame.x)
	_kurt.z += DRIFT * dt * _direction.dot(frame.z)


## Steering turns Kurt up to 45° either way and moves him sideways; he turns back when the keys
## are released. Left and up turn him left and up.
func _steer(dt: float) -> void:
	var right := 0.0
	var up := 0.0
	if _controlled():
		right = signf(Input.get_action_strength(&"turn_right") + Input.get_action_strength(&"strafe_right")
				- Input.get_action_strength(&"turn_left") - Input.get_action_strength(&"strafe_left"))
		up = signf(Input.get_action_strength(&"move_forward") - Input.get_action_strength(&"move_back"))

	if right != 0.0:
		_kurt.yaw = clampf(_kurt.yaw - right * TURN_RATE * dt, NEUTRAL_YAW - TURN_LIMIT, NEUTRAL_YAW + TURN_LIMIT)
	else:
		_kurt.yaw = move_toward(_kurt.yaw, NEUTRAL_YAW, TURN_RATE * dt)
	if up != 0.0:
		_pitch = clampf(_pitch + up * TURN_RATE * dt, -TURN_LIMIT, TURN_LIMIT)
	else:
		_pitch = move_toward(_pitch, 0.0, TURN_RATE * dt)

	_kurt.x += cos(deg_to_rad(_kurt.yaw)) * SIDE_SPEED * dt
	_kurt.z += sin(deg_to_rad(_pitch)) * SIDE_SPEED * dt


## A wall hit pushes Kurt back towards the axis, turns him inwards, hurts him and slows him down.
func _collide(centre: Vector3, frame: Basis) -> void:
	var k := _tube.wall_hit(_kurt_position, _kurt.t, WALL_MARGIN)
	if k < 0.0:
		return

	# Facing the axis at full turn, e.g. at the right wall (x > 0) he turns left (yaw 135).
	var r := Vector2(_kurt.x, _kurt.z).length()
	if r > 0.0:
		_kurt.yaw = NEUTRAL_YAW + TURN_LIMIT * _kurt.x / r
		_pitch = -TURN_LIMIT * _kurt.z / r
	_kurt.x *= 1.0 - k
	_kurt.z *= 1.0 - k
	_kurt_position = centre + frame.x * _kurt.x + frame.z * _kurt.z
	_kurt.speed = maxf(_kurt.speed * SPEED_LOSS, SPEED_MIN)

	if not _hitside.playing:
		_hitside.play()
	_play(HURT_SOUNDS[randi() % HURT_SOUNDS.size()])
	_hurt()


## Wall damage by difficulty. At 0 health Kurt dies in the Gunter tube, else Bones comes for him.
func _hurt() -> void:
	if _health <= 0:
		return
	_health -= HIT_DAMAGE[_difficulty] + HIT_EXTRA[_difficulty] * (randi() & 1)
	if _health >= 1:
		return
	if _kind == StreamTube.Kind.NORMAL:
		_health = 1
		return
	_health = 0
	_ending = true
	_fade = 2.0


## The walking health bonus (0x435b18): caught within 5 units, it gives 150 health.
func _update_pickup(dt: float) -> void:
	if not _move(_pickup, dt):
		_pickup = null
		return
	_place(_pickup, "SWHANM", "SWH150")
	if MDKMeshBuilder.to_godot(_kurt_position).distance_to(_pickup.node.position) >= SWH150_REACH:
		return
	_health = SWH150_HEALTH
	_play("APPLE")
	_pickup.node.queue_free()
	_pickup = null


## Bones picks Kurt up: both play `BONESANIM` (the crane, the rope, Bones and Kurt) once.
func _start_rescue() -> void:
	_bones = Thing.new()
	_bones.node = _make_node("BONES")
	_bones.node.transform = _kurt.node.transform
	_play("RESCUE")
	_kurt_animation = "BONESANIM"
	_kurt.frame = 0.0


# --- Camera and drawing ---

## The camera (0x4352ac, 0x436828): behind Kurt and to his side, looking at the axis two segments
## ahead, its roll carried over from frame to frame.
func _update_camera() -> void:
	var target := _tube.centre(_kurt.t + CAMERA_AHEAD)
	var past := target + CAMERA_PAST * (_kurt_position - target)
	var eye := CAMERA_BLEND * _tube.centre(_kurt.t - CAMERA_BACK) + (1.0 - CAMERA_BLEND) * past
	var forward := (target - eye).normalized()
	var right := forward.cross(_screen_up).normalized()
	_screen_up = right.cross(forward)
	_camera.position = MDKMeshBuilder.to_godot(eye)
	_camera.basis = Basis(MDKMeshBuilder.to_godot(right), MDKMeshBuilder.to_godot(_screen_up), -MDKMeshBuilder.to_godot(forward))
	_camera_eye = eye

	# The background scrolls with the view's turns (0x438bfc).
	var down := -_screen_up
	if not _view_rows.is_empty():
		var r0 := _view_rows[0]
		var u0 := _view_rows[1]
		var f0 := _view_rows[2]
		_background_offset.y = fposmod(_background_offset.y + 180.0 * (down.z * f0.z - forward.z * u0.z), VIEW_HEIGHT)
		_background_offset.x = fposmod(_background_offset.x + 300.0 * (right.x * u0.x - down.x * r0.x), 600.0)
	_view_rows = [right, down, forward]


func _draw_back() -> void:
	var width := _back.size.x / _back.size.y * VIEW_HEIGHT
	_back.draw_texture_rect_region(_background, Rect2(Vector2.ZERO, _back.size), Rect2(_background_offset, Vector2(width, VIEW_HEIGHT)))


func _draw_hud() -> void:
	var s := _hud.size.y / VIEW_HEIGHT
	var width := _hud.size.x / s
	_hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	_messages.draw(_hud, width)
	_health_box.draw(_hud, width, _health, _blink)


# --- The end (0x401cb8, state 5) ---

## Game over at 0 health; else the statistics, or LEVEL5 directly after LEVEL8 (with the health).
func _finish() -> void:
	_ended = true
	_wind.stop()
	if _health < 1:
		get_tree().change_scene_to_file("res://game/menu/main_menu.tscn")
		return

	if GameState.carry.is_empty():
		GameState.carry = {inventory = KurtInventory.new()}
	GameState.carry.health = _health
	if _index <= LAST_STATS_INDEX:
		StatsScreen.briefing_only = false
		get_tree().change_scene_to_file("res://game/menu/stats_screen.tscn")
		return
	GameState.level = GameState.ORDER[_index + 1]
	get_tree().change_scene_to_file("res://game/main.tscn")
