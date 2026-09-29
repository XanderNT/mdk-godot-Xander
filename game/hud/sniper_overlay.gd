## Sniper mode's screen (HUD 0x41e128, 0x420830; `TRAVERSE/TRAVSPRT.BNI`), drawn over the whole
## 640×480 screen: the `SNIPERS1` frame around the 600×360 view at (20, 60), the `SNIPERS2` mask
## over the view (holes for the scope and the three round cameras at the top: 140×70 views from
## behind each round, 90° wide, then a colour or the `SNIPERGA` animation), the `CROSS` crosshair
## on the scope's centre, the zoom in percent with its `SNIP_RNG` gauge, and the ammo types (`SNIP_WEP`, `SNIP_Wn`, the selected one's
## `SNIP_Ln` and count), the loaded rounds as 3D models (0x41eb10) and the air strike's iris
## (0x41ef90). See `docs/gameplay.md` ("Sniper mode").
class_name SniperOverlay
extends RefCounted

const SCREEN := Vector2(640.0, 480.0)
## Where the 600×360 view sits on the screen.
const VIEW_ORIGIN := Vector2(20.0, 60.0)
## The scope window inside the view; its holes elsewhere are the round cameras.
const SCOPE := Rect2(107.0, 79.0, 384.0, 280.0)
const CROSSHAIR := Vector2(299.0, 219.0)
const ZOOM_DIGITS := Vector2(564.0, 155.0)
const GAUGE := Vector2(552.0, 176.0)
const GAUGE_HEIGHT := 88
## The gauge's shown height follows the zoom by 3 pixels per tick.
const GAUGE_SPEED := 3
const WEAPON := Vector2(112.0, 304.0)
const TYPE_ICONS := [Vector2(0, 256), Vector2(0, 280), Vector2(0, 300), Vector2(4, 320), Vector2(16, 336), Vector2(32, 344)]
const TYPE_LABELS := [Vector2(12, 268), Vector2(12, 288), Vector2(12, 308), Vector2(20, 320), Vector2(24, 328), Vector2(36, 336)]
const COUNT := Vector2(64.0, 315.0)
## The round cameras' windows in the view (0x461d80).
const ROUND_VIEWS := [Rect2(72, 10, 140, 70), Rect2(228, 0, 140, 70), Rect2(384, 10, 140, 70)]
## The air strike's iris (0x41ef90): with a valid target the scope reddens from its edge in 1 s,
## leaving a hole of radius `384 × c²` (c from 1 to 0); once closed, a darker ring contracts every
## second. View rows 80–359, x 108–492, centred on (300, 220).
const STRIKE_TYPE := 5
const IRIS_CENTRE := Vector2(300.0, 220.0)
const IRIS_TOP := 80
const IRIS_BOTTOM := 360
const IRIS_HALF_WIDTH := 192.0
const IRIS_RADIUS := 384.0
const RING_OUTER := 392.0
const RING_INNER := 376.0
const IRIS_COLOUR := Color(200.0 / 255.0, 0.0, 0.0, 0x60 / 255.0)
const RING_COLOUR := Color(200.0 / 255.0, 0.0, 0.0, 0xC4 / 255.0)
## The loaded rounds (0x41eb10): round i at time `clip timer + i` (shown between 0 and 3, not at 0),
## between keys of position, angles (z, y, x: `Rz(a) Ry(−b) Rx(c)`) and scale (0x490e4c), seen with
## a focal length of 250 on the view; they slide into the chamber (key 0) after a shot.
const CLIP_KEYS := [
	[Vector3(-225, -242, 65), Vector3(-30, 180, 90), 4.0],
	[Vector3(-203, -242, 107), Vector3(0, 180, 0), 9.0],
	[Vector3(-176, -242, 145), Vector3(0, 180, 0), 9.0],
	[Vector3(-154, -242, 174), Vector3(0, 180, 0), 9.0],
]
const CLIP_SIZE := 3
const FOCAL := 250.0
const ROUND_MODELS := ["SW_SHOT", "SW_HOME", "SW_SGREN", "SW_HGREN", "SW_LGREN", "SW_BONES"]
## Clip space (x right, y away, z down on the screen) to a camera looking along −z.
const CLIP_TO_CAMERA := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
## Godot model space back to MDK model space.
const GODOT_TO_MDK := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

var _frame: Texture2D
var _mask: Texture2D
var _cross: Texture2D
var _cross_hotspot := Vector2i()
var _gauge: Texture2D
var _weapon: Texture2D
var _icons: Array[Texture2D] = []
var _labels: Array[Texture2D] = []
var _gauge_shown := 0
var _palette: MDKPalette
var _miss: MDKSpriteAnimation
var _miss_frames: Array[Texture2D] = []
var _views: Array[SubViewport] = []
var _cameras: Array[Camera3D] = []
# The iris: its opening (1 open, 0 closed), the pulse, and whether the strike has a target.
var _iris := 1.0
var _pulse := 1.0
var _target := false
# The clip: its view, a node per round, meshes by model name.
var _clip_view := SubViewport.new()
var _clip_nodes: Array[MeshInstance3D] = []
var _clip_meshes := {}


func setup(sprites: MDKBni, palette: MDKPalette, parent: Node) -> void:
	_palette = palette
	_miss = sprites.get_animation("SNIPERGA")
	for i in _miss.frame_count:
		_miss_frames.push_back(HUD._make_texture(_miss.get_frame(i), palette))
	for rect: Rect2 in ROUND_VIEWS:
		var view := SubViewport.new()
		view.size = Vector2i(rect.size)
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var camera := Camera3D.new()
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.fov = 90.0
		camera.near = 0.5
		view.add_child(camera)
		parent.add_child(view)
		_views.push_back(view)
		_cameras.push_back(camera)
	_setup_clip(parent)
	_frame = ImageTexture.create_from_image(_frame_image(sprites, palette))
	_mask = ImageTexture.create_from_image(_mask_image(sprites, palette))
	var cross := sprites.get_animation("CROSS")
	_cross = HUD._make_texture(cross.get_frame(0), palette)
	_cross_hotspot = cross.get_hotspot(0)
	_gauge = HUD._make_texture(sprites.get_image("SNIP_RNG"), palette)
	_weapon = HUD._make_texture(sprites.get_image("SNIP_WEP"), palette)
	for i in range(1, 7):
		_icons.push_back(HUD._make_texture(sprites.get_image("SNIP_W%d" % i), palette))
		_labels.push_back(HUD._make_texture(sprites.get_image("SNIP_L%d" % i), palette))


func _setup_clip(parent: Node) -> void:
	_clip_view.size = Vector2i(600, 360)
	_clip_view.transparent_bg = true
	_clip_view.own_world_3d = true
	_clip_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var camera := Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = rad_to_deg(2.0 * atan(180.0 / FOCAL))
	camera.near = 1.0
	camera.far = 1000.0
	_clip_view.add_child(camera)
	for i in CLIP_SIZE:
		var node := MeshInstance3D.new()
		_clip_view.add_child(node)
		_clip_nodes.push_back(node)
	parent.add_child(_clip_view)


## Each frame in sniper mode: the iris's opening and pulse, and the rounds of the clip.
func update(delta: float, kurt: Kurt, scripts: MDKScriptRuntime) -> void:
	_update_iris(delta, kurt, scripts)
	_update_clip(kurt, scripts)


## Out of sniper mode the iris is open.
func reset() -> void:
	_iris = 1.0
	_pulse = 1.0
	_clip_view.render_target_update_mode = SubViewport.UPDATE_DISABLED


## The iris closes over 1 s while the strike is selected, the clip is ready and the view has a
## target (0x4641ac), and opens again otherwise; closed, it pulses once a second.
func _update_iris(delta: float, kurt: Kurt, scripts: MDKScriptRuntime) -> void:
	var strike := kurt.inventory.selected_ammo == STRIKE_TYPE
	if strike and kurt.clip_time <= 0.0 and scripts:
		_target = scripts.air_strike.find_target(MDKScriptRuntime.to_mdk(kurt.get_sniper_eye()), scripts.kurt_yaw, kurt.sniper_pitch) != null
		if _target:
			_iris = maxf(_iris - delta, 0.0)
	if not strike or not _target:
		_iris += delta
		if _iris >= 1.0:
			_iris = 1.0
			_pulse = 1.0
			return
	if _iris == 0.0 or _pulse != 1.0:
		_pulse -= delta
		if _pulse < 0.0:
			_pulse = 1.0


## The loaded rounds of the selected type between the clip's keys.
func _update_clip(kurt: Kurt, scripts: MDKScriptRuntime) -> void:
	var mesh := _round_mesh(ROUND_MODELS[kurt.inventory.selected_ammo], scripts)
	var shown := false
	for i in CLIP_SIZE:
		var node := _clip_nodes[i]
		var t := kurt.clip_time + i
		node.visible = mesh != null and i < kurt.clip_rounds and t != 0.0 and t < CLIP_KEYS.size() - 1
		if not node.visible:
			continue
		shown = true
		var k := int(t)
		var f := t - k
		var a: Array = CLIP_KEYS[k]
		var b: Array = CLIP_KEYS[k + 1]
		var angles: Vector3 = (a[1] as Vector3).lerp(b[1], f)
		var scale: float = lerpf(a[2], b[2], f)
		var rotation := Basis(Vector3(0, 0, 1), deg_to_rad(angles.x)) * Basis(Vector3(0, 1, 0), -deg_to_rad(angles.y)) \
				* Basis(Vector3(1, 0, 0), deg_to_rad(angles.z))
		var position: Vector3 = (a[0] as Vector3).lerp(b[0], f)
		node.mesh = mesh
		node.transform = Transform3D(CLIP_TO_CAMERA * rotation.scaled(Vector3.ONE * scale) * GODOT_TO_MDK, CLIP_TO_CAMERA * position)
	_clip_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED


func _round_mesh(model_name: String, scripts: MDKScriptRuntime) -> Mesh:
	if not scripts:
		return null
	if not _clip_meshes.has(model_name):
		var model := scripts.find_model(scripts.current_arena, model_name)
		_clip_meshes[model_name] = MDKMeshBuilder.build_model_mesh(model, model.get_rest_pose(), scripts.get_resolver(scripts.current_arena)) if model else null
	return _clip_meshes[model_name]


## The iris, row by row from the scope's edges inwards: red, the darker pulse ring, red again, then
## the clear hole.
func _draw_iris(canvas: HUD) -> void:
	if _iris >= 1.0:
		return
	var circles: Array = []
	var hole := IRIS_RADIUS * _iris * _iris
	var outer := RING_OUTER * _pulse * _pulse
	var inner := RING_INNER * _pulse * _pulse
	if outer > hole and _pulse != 1.0:
		circles.push_back([outer, RING_COLOUR])
		if inner > hole:
			circles.push_back([inner, IRIS_COLOUR])
	circles.push_back([hole, Color.TRANSPARENT])
	for y in range(IRIS_TOP, IRIS_BOTTOM):
		var dy := y - IRIS_CENTRE.y
		var colour := IRIS_COLOUR
		var outside := IRIS_HALF_WIDTH
		for circle: Array in circles:
			var r: float = circle[0]
			var edge := minf(sqrt(r * r - dy * dy) if absf(dy) < r else 0.0, outside)
			_draw_span(canvas, y, edge, outside, colour)
			outside = edge
			colour = circle[1]
		_draw_span(canvas, y, 0.0, outside, colour)


## A row of the iris between two distances from its centre, on both sides.
func _draw_span(canvas: HUD, y: int, near: float, far: float, colour: Color) -> void:
	if colour.a == 0.0 or far <= near:
		return
	var width := far - near
	canvas.draw_rect(Rect2(VIEW_ORIGIN + Vector2(IRIS_CENTRE.x - far, y), Vector2(width, 1.0)), colour)
	canvas.draw_rect(Rect2(VIEW_ORIGIN + Vector2(IRIS_CENTRE.x + near, y), Vector2(width, 1.0)), colour)


## `SNIPERS1`: 640×480 palette indices without a header; the view's rectangle is cut out.
static func _frame_image(sprites: MDKBni, palette: MDKPalette) -> Image:
	var offset: int = sprites.entries["SNIPERS1"][0]
	var image := Image.create_empty(640, 480, false, Image.FORMAT_RGBA8)
	for y in 480:
		for x in 640:
			if x >= 20 and x < 620 and y >= 60 and y < 420:
				continue
			image.set_pixel(x, y, palette.get_color(sprites.bytes[offset + y * 640 + x]))
	return image


## `SNIPERS2`: `u32 size`, then u16 words over 600-pixel rows: below 0x8000, that many × 4 literal
## bytes follow; 0x8nnn skips `nnn` transparent pixels; 0xFFnn has `nn` literal bytes (1–3); 0xFF00
## ends.
static func _mask_image(sprites: MDKBni, palette: MDKPalette) -> Image:
	var bytes := sprites.bytes
	var offset: int = sprites.entries["SNIPERS2"][0] + 4
	var image := Image.create_empty(600, 360, false, Image.FORMAT_RGBA8)
	var pixel := 0
	while pixel < 600 * 360:
		var word := bytes.decode_u16(offset)
		offset += 2
		var count := 0
		if word == 0xFF00:
			break
		elif word & 0xFF00 == 0xFF00:
			count = word & 0xFF
		elif word & 0x8000:
			pixel += word & 0xFFF
			continue
		else:
			count = word * 4
		for i in count:
			if pixel < 600 * 360:
				image.set_pixel(pixel % 600, pixel / 600, palette.get_color(bytes[offset + i]))
			pixel += 1
		offset += count
	return image


## Draws the sniper screen on `canvas` (already scaled to 640×480 screen pixels).
func draw(canvas: HUD, kurt: Kurt, rounds: MDKSniperRounds) -> void:
	canvas.draw_texture(_frame, Vector2.ZERO)
	for i in ROUND_VIEWS.size():
		var rect: Rect2 = ROUND_VIEWS[i]
		rect.position += VIEW_ORIGIN
		var camera: Dictionary = rounds.get_camera(i) if rounds else {"fill": 0}
		if camera.has("transform"):
			_cameras[i].global_transform = camera.transform
			_views[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS
			canvas.draw_texture_rect(_views[i].get_texture(), rect, false)
			continue
		_views[i].render_target_update_mode = SubViewport.UPDATE_DISABLED
		if camera.fill >= 0:
			canvas.draw_rect(rect, _palette.get_color(camera.fill))
		else:
			# A miss: `SNIPERGA`, a frame every 2 ticks.
			canvas.draw_rect(rect, Color.BLACK)
			var frame := int((30.0 - camera.time) / 2.0) % _miss_frames.size()
			var texture := _miss_frames[frame]
			canvas.draw_texture(texture, rect.get_center() - texture.get_size() / 2.0)
	_draw_iris(canvas)
	canvas.draw_texture(_mask, VIEW_ORIGIN)
	canvas.draw_texture(_cross, VIEW_ORIGIN + CROSSHAIR - Vector2(_cross_hotspot))
	if _clip_view.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		canvas.draw_texture(_clip_view.get_texture(), VIEW_ORIGIN)
	# The zoom in percent: (1 − zoom)² × 1.05194 (59% at 4×), and the gauge showing as much of its
	# height.
	var fraction := clampf(pow(1.0 - kurt.zoom, 2.0) * 1.05194, 0.0, 1.0)
	var percent := roundi(100.0 * fraction)
	canvas._draw_number(percent, VIEW_ORIGIN + ZOOM_DIGITS)
	var goal := roundi(GAUGE_HEIGHT * fraction)
	_gauge_shown = clampi(goal, _gauge_shown - GAUGE_SPEED, _gauge_shown + GAUGE_SPEED)
	if _gauge_shown > 0:
		var top := GAUGE_HEIGHT - _gauge_shown
		canvas.draw_texture_rect_region(_gauge, Rect2(VIEW_ORIGIN + GAUGE + Vector2(0, top), Vector2(_gauge.get_width(), _gauge_shown)),
				Rect2(0, top, _gauge.get_width(), _gauge_shown))
	canvas.draw_texture(_weapon, VIEW_ORIGIN + WEAPON)
	var selected := kurt.inventory.selected_ammo
	for i in 6:
		if i == 0 or kurt.inventory.ammo[i - 1] > 0:
			canvas.draw_texture(_icons[i], VIEW_ORIGIN + TYPE_ICONS[i])
	canvas.draw_texture(_labels[selected], VIEW_ORIGIN + TYPE_LABELS[selected])
	if selected > 0:
		canvas._draw_number(kurt.inventory.ammo[selected - 1], VIEW_ORIGIN + COUNT)
