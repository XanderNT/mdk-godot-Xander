## The full-screen strike (0x4398f0): before Bones' air strike (`X_STRIKB`) and Kurt's strike at
## the end of the game (`X_STRIKD`), the game stops and only the sky and that model are drawn. The
## model plays its animation once while it turns at 45°/s; the camera sits at its reference point 1
## looking at its reference point 0 (both moved by the animation), with a long lens (focal length 600 / 0.35265 = 1701 pixels on
## the 600×360 view). Esc skips it. The effects pause, the music goes on.
##
##   game paused ──> [ sky + model, camera on the model's points ] ──> finished ──> game resumes
class_name MDKStrikeScene
extends CanvasLayer

signal finished

## Which strike: Bones' plane, or Kurt's (event 51).
enum Kind { BONES, KURT }

const TURN_RATE := 45.0
const FOCAL := 600.0 / 0.35265395
const VIEW_HEIGHT := 360.0
## A render layer of its own, so the camera sees only the model (and the sky).
const LAYER := 1 << 19
## When Bones dives alone (the last two levels), only the plane's parts show (0x491ddc).
const PLANE_PARTS := ["AWING", "CANOPY", "LEVER", "LEVER01", "LEVER02", "LEVER03", "OBJECT"]

var _model: MDKModel
var _animation: MDKModelAnimation
var _resolver: MDKMeshBuilder.MaterialResolver
var _hidden := 0
var _node := MeshInstance3D.new()
var _camera := Camera3D.new()
var _view := SubViewport.new()
var _yaw := 0.0
var _frame := 0.0
var _meshes := {}
var _poses: Array = []


## Plays the strike of `kind` in `arena_name`; `plane_only` hides Bones (the dive strike).
func play(runtime: MDKScriptRuntime, kind: Kind, plane_only: bool) -> void:
	var arena_name := runtime.current_arena
	var model_name := "X_STRIKB" if kind == Kind.BONES else "X_STRIKD"
	_model = runtime.find_model(arena_name, model_name)
	_animation = runtime.items.get_animation(model_name) if kind == Kind.BONES else runtime.find_arena_animation(arena_name, model_name)
	if not _model or not _animation or _model.reference_points.size() < 2:
		finished.emit.call_deferred()
		return
	_resolver = runtime.get_resolver(arena_name)
	if plane_only:
		for i in _model.parts.size():
			if _model.parts[i].name.to_upper() not in PLANE_PARTS:
				_hidden |= 1 << i

	# The view: the level's world (its sky), only the model's layer.
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Moved every frame while the physics is paused.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_view.size = Vector2i(get_viewport().get_visible_rect().size)
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_camera.cull_mask = LAYER
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.fov = rad_to_deg(2.0 * atan(VIEW_HEIGHT * 0.5 / FOCAL))
	_view.add_child(_camera)
	_node.layers = LAYER
	_view.add_child(_node)
	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.texture = _view.get_texture()
	add_child(rect)

	runtime.get_tree().paused = true
	_update(0.0)


func _process(delta: float) -> void:
	if not _model:
		return
	_frame += delta * 30.0 * _animation.speed
	_yaw += TURN_RATE * delta
	if _frame >= _animation.frame_count:
		_finish()
		return
	_update(delta)


func _input(event: InputEvent) -> void:
	if not _model or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_finish()


## The model's pose and turn, and the camera on its reference points.
func _update(_delta: float) -> void:
	var frame := int(_frame)
	if not _meshes.has(frame):
		if _poses.is_empty():
			_poses = _animation.bake(_model)
		var pose: Array = _poses[frame].duplicate()
		for i in pose.size():
			if _hidden & (1 << i):
				pose[i] = PackedVector3Array()
		_meshes[frame] = MDKMeshBuilder.build_model_mesh(_model, pose, _resolver)
	_node.mesh = _meshes[frame]
	var turn := Basis(Vector3.BACK, deg_to_rad(_yaw))
	_node.basis = Basis(Vector3.UP, deg_to_rad(_yaw))
	var eye := MDKMeshBuilder.to_godot(turn * _reference_point(1, frame))
	var target := MDKMeshBuilder.to_godot(turn * _reference_point(0, frame))
	_camera.look_at_from_position(eye, target, Vector3.UP)


## A reference point in a frame: the animation moves them (the camera follows the plane).
func _reference_point(index: int, frame: int) -> Vector3:
	if index < _animation.reference_points.size():
		return _animation.reference_points[index][frame]
	return _model.reference_points[index]


func _finish() -> void:
	_model = null
	get_tree().paused = false
	finished.emit()
	queue_free()
