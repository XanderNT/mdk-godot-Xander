## The stream's tube (0x434838): a ring buffer of 32 rings of 16 points, one ring per segment of 10
## units, each turned from the previous one by three randomly walking angles. The segment between
## two rings has 32 wall planes facing in, and a colour per point. See docs/gameplay.md,
## "The stream".
##
##   ring:   tail ... head - 1          (head - tail = 31 while generating)
##   slot:   ring & 31
##
##         P[n+1][j] ---- P[n+1][j+1]      two triangles (and planes) per quad,
##            |    \            |          32 per segment
##         P[n][j] ------ P[n][j+1]
class_name StreamTube
extends RefCounted

## The normal tube, or the one after LEVEL8 that straightens and ends at a planet.
enum Kind { NORMAL, GUNTER }

## What `advance()` asks the stream to create.
enum SpawnKind { LIGHT, PLANET }

const RINGS := 32
const SLOT_MASK := RINGS - 1
const POINTS := 16
const SEGMENT_LENGTH := 10.0
const START_RADIUS := 10.0
## The Gunter tube straightens after this segment and stops after the last one.
const STRAIGHTEN_SEGMENT := 168
const LAST_SEGMENT := 186
## `rand()` (0x4794dd) returns 0–0x7FFF; `(rand() − 0x4000) × WALK_STEP` is ±1.
const RAND_MAX := 0x7FFF
const RAND_HALF := 0x4000
const WALK_STEP := 6.10352e-5
## Ring points are jittered by ±10 %: `(rand() − 0x4000 + JITTER) / JITTER`.
const JITTER := 163840.0
const TURN_DAMPING := 0.8
## Colours: 64 ramp entries; the shade target changes every 10 segments.
const RAMP_SIZE := 64
const SHADE_STEP := 0.1
## Vertex alpha by distance from the tail (0x5744d8): levels 0–5 every 5 segments.
const ALPHA := [0x5A, 0x55, 0x50, 0x3C, 0x28, 0x0F]
const LEVEL_SEGMENTS := 5
## The ramp (0x491ccc): a start colour, then 8 keys of 8 steps.
const RAMP_START := Color8(222, 206, 90)
const RAMP_KEYS := [Color8(140, 123, 33), Color8(123, 49, 8), Color8(198, 165, 132), Color8(132, 123, 140),
		Color8(214, 198, 231), Color8(198, 165, 132), Color8(123, 49, 8), Color8(222, 206, 90)]
const RAMP_STEPS := 8
## Lights (0x434f64): in 3 segments of 4, up to ±4 units off the axis, 4–8 in size, flying back
## at 3–7 segments/s. The planet (0x4350dc) is 3 segments before the end, size 36.
const LIGHT_SIZE := 4.0
const LIGHT_SPEED := -3.0
const PLANET_BACK := 3
const PLANET_SIZE := 36.0


class Spawn:
	var kind := SpawnKind.LIGHT
	var t := 0.0
	var x := 0.0
	var z := 0.0
	var size := 0.0
	var speed := 0.0


var tail := 0
var head := 0

var _kind := Kind.NORMAL
var _bases: Array[Basis] = []
var _origins := PackedVector3Array()
var _points: Array[PackedVector3Array] = []
var _colours: Array[PackedByteArray] = []
var _normals: Array[PackedVector3Array] = []
var _distances: Array[PackedFloat32Array] = []
var _spawns: Array[Spawn] = []
var _angles := Vector3()
var _radius := START_RADIUS
var _max_turn := 0.0
var _min_radius := 0.0
var _max_radius := 0.0
var _shade_from := 0
var _shade_to := 0
var _shade := 0.0
var _planet_spawned := false
var _ramp: Array[Color] = []


## `index`: the level just played (0–4); `difficulty`: 0 easy, 1 normal, 2 hard.
func _init(index: int, difficulty: int, kind: Kind) -> void:
	_kind = kind

	# The difficulty's limits (0x433b50, `h = index >> 1`).
	var h := index >> 1
	_max_turn = index + [6.0, 8.0, 10.0][difficulty]
	_min_radius = START_RADIUS - h
	_max_radius = [17.0 - h, 17.0 - index, 13.0 - h][difficulty]

	# The ramp: each key blended from the previous one in 8 steps.
	var previous := RAMP_START
	for key: Color in RAMP_KEYS:
		for i in RAMP_STEPS:
			_ramp.push_back(Color8((key.r8 * i + previous.r8 * (RAMP_STEPS - i)) / RAMP_STEPS,
					(key.g8 * i + previous.g8 * (RAMP_STEPS - i)) / RAMP_STEPS,
					(key.b8 * i + previous.b8 * (RAMP_STEPS - i)) / RAMP_STEPS))
		previous = key

	for i in RINGS:
		_bases.push_back(Basis())
		_origins.push_back(Vector3())
		_points.push_back(PackedVector3Array())
		_colours.push_back(PackedByteArray())
		_normals.push_back(PackedVector3Array())
		_distances.push_back(PackedFloat32Array())

	# 31 rings ahead of Kurt.
	_shade_from = _rand() & (RAMP_SIZE - 1)
	_shade_to = _rand() & (RAMP_SIZE - 1)
	for i in RINGS - 1:
		_generate()


## Kurt passed a segment: the oldest ring goes, a new one comes.
func advance() -> void:
	tail += 1
	_generate()


## The lights and the planet made since the last call.
func take_spawns() -> Array[Spawn]:
	var spawns := _spawns
	_spawns = []
	return spawns


## Whether `t` (in segments) is within the rings still alive.
func contains(t: float) -> bool:
	var s := floori(t)
	return s >= tail and s < head


## The axis at `t` (0x436668).
func centre(t: float) -> Vector3:
	var s := floori(t)
	return _origins[s & SLOT_MASK].lerp(_origins[(s + 1) & SLOT_MASK], t - s)


## The frame at `t` (0x4366f4): forward along the axis, right from the camera's up.
func frame(t: float, up: Vector3) -> Basis:
	var y := (centre(t + 1.0) - centre(t)).normalized()
	var x := y.cross(up).normalized()
	return Basis(x, y, x.cross(y))


## A point of segment `t` at (x, z) across it.
func place(t: float, x: float, z: float) -> Vector3:
	var s := floori(t)
	return _origins[s & SLOT_MASK] + _bases[s & SLOT_MASK] * Vector3(x, SEGMENT_LENGTH * (t - s), z)


## The walls (0x43637c): for the first plane of segment `t` that `position` is within `margin`
## of, the fraction of the way to the axis that puts it back; −1 when it touches none.
func wall_hit(position: Vector3, t: float, margin: float) -> float:
	var slot := floori(t) & SLOT_MASK
	var normals := _normals[slot]
	var distances := _distances[slot]
	for i in normals.size():
		var d := normals[i].dot(position) + distances[i] - margin
		if d > 0.0:
			continue
		var towards := normals[i].dot(position - centre(t))
		return d / towards if towards != 0.0 else 0.0
	return -1.0


## Draws the tube into `mesh` (0x436b00): from the farthest segment to the tail, fading with the
## distance; triangles facing away from `eye` aren't drawn.
func build_mesh(mesh: ImmediateMesh, material: Material, eye: Vector3) -> void:
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for n in range(head - 2, tail - 1, -1):
		var slot := n & SLOT_MASK
		var older := _points[slot]
		var newer := _points[(n + 1) & SLOT_MASK]
		var older_colours := _vertex_colours(n)
		# The newest ring has no colours yet: the first ramp colour at the farthest level.
		var newer_colours := _vertex_colours(n + 1) if n + 2 < head else _flat_colours(0, ALPHA.size() - 1)
		var normals := _normals[slot]
		var distances := _distances[slot]

		for j in POINTS:
			var j1 := (j + 1) % POINTS
			var triangles := [[older[j], newer[j1], older[j1], older_colours[j], newer_colours[j1], older_colours[j1]],
					[older[j], newer[j], newer[j1], older_colours[j], newer_colours[j], newer_colours[j1]]]
			for i in 2:
				var plane := j * 2 + i
				if normals[plane].dot(eye) + distances[plane] < 0.0:
					continue
				var triangle: Array = triangles[i]
				for v in 3:
					mesh.surface_set_color(triangle[v + 3])
					mesh.surface_add_vertex(MDKMeshBuilder.to_godot(triangle[v]))
	mesh.surface_end()


## Makes ring `head` (0x434838): its frame follows the previous one turned by the three angles, its
## points are jittered, and the segment before it gets its wall planes and colours.
func _generate() -> void:
	var n := head
	if _kind == Kind.GUNTER and n > LAST_SEGMENT:
		_spawn_planet(n)
		return

	var slot := n & SLOT_MASK
	if n == tail:
		_bases[slot] = Basis()
		_origins[slot] = Vector3()
	else:
		_turn_ring(n)
		_spawn_light(n)

	_make_points(slot)
	if n != tail:
		_build_segment(n - 1)
	head += 1

	# The angles walk randomly by ±1° per segment (the Gunter tube straightens at the end).
	for axis in [2, 0, 1]:
		if _kind == Kind.GUNTER and head > STRAIGHTEN_SEGMENT:
			_angles[axis] = move_toward(_angles[axis], 0.0, 1.0)
		else:
			_angles[axis] += (_rand() - RAND_HALF) * WALK_STEP
		if absf(_angles[axis]) > _max_turn:
			_angles[axis] *= TURN_DAMPING
	_radius = clampf(_radius + (_rand() - RAND_HALF) * WALK_STEP, _min_radius, _max_radius)


## Ring `n`'s frame: one segment along the previous ring's forward axis, turned by the angles.
func _turn_ring(n: int) -> void:
	var slot := n & SLOT_MASK
	var previous := (n - 1) & SLOT_MASK
	var turn := Basis(Vector3.RIGHT, deg_to_rad(_angles.x)) * Basis(Vector3.UP, deg_to_rad(_angles.y)) \
			* Basis(Vector3.BACK, deg_to_rad(_angles.z))
	var basis := _bases[previous] * turn
	_origins[slot] = _origins[previous] + SEGMENT_LENGTH * _bases[previous].y
	_bases[slot] = Basis(basis.x.normalized(), basis.y.normalized(), basis.z.normalized())


## The ring's 16 points around its axis, each coordinate jittered by ±10 %.
func _make_points(slot: int) -> void:
	var points := PackedVector3Array()
	for j in POINTS:
		var angle := TAU * j / POINTS
		var jx := (_rand() - RAND_HALF + JITTER) / JITTER
		var jz := (_rand() - RAND_HALF + JITTER) / JITTER
		points.push_back(_origins[slot] + _bases[slot] * Vector3(_radius * sin(angle) * jx, 0.0, _radius * cos(angle) * jz))
	_points[slot] = points


## A light in the segment before ring `n`, in 3 segments of 4.
func _spawn_light(n: int) -> void:
	if not _rand() & 3:
		return
	var spawn := Spawn.new()
	spawn.t = n - 1.0
	spawn.size = LIGHT_SIZE + _rand() / 8192.0
	spawn.x = (_rand() - RAND_HALF) / 4096.0
	spawn.z = (_rand() - RAND_HALF) / 4096.0
	spawn.speed = LIGHT_SPEED - _rand() / 8192.0
	_spawns.push_back(spawn)


## The planet at the end of the Gunter tube, once.
func _spawn_planet(n: int) -> void:
	if _planet_spawned:
		return
	_planet_spawned = true
	var spawn := Spawn.new()
	spawn.kind = SpawnKind.PLANET
	spawn.t = n - PLANET_BACK
	spawn.size = PLANET_SIZE
	_spawns.push_back(spawn)


## The wall planes (two per quad, facing in) and the colours of the segment from ring `p` to `p + 1`.
func _build_segment(p: int) -> void:
	var slot := p & SLOT_MASK
	var older := _points[slot]
	var newer := _points[(p + 1) & SLOT_MASK]
	var shade := int((1.0 - _shade) * _shade_from + _shade * _shade_to)
	var colours := PackedByteArray()
	var normals := PackedVector3Array()
	var distances := PackedFloat32Array()
	for j in POINTS:
		# A triangle wave around the ring, one step further each segment: spiral stripes.
		var x := (p + 1 + j) & SLOT_MASK
		var wave := x if x < POINTS else SLOT_MASK - x
		colours.push_back((wave + shade) & (RAMP_SIZE - 1))

		var j1 := (j + 1) % POINTS
		for triangle: Array in [[older[j], newer[j1], older[j1]], [older[j], newer[j], newer[j1]]]:
			var a: Vector3 = triangle[0]
			var b: Vector3 = triangle[1]
			var c: Vector3 = triangle[2]
			var normal := (b - a).cross(c - b).normalized()
			normals.push_back(normal)
			distances.push_back(-normal.dot(a))
	_colours[slot] = colours
	_normals[slot] = normals
	_distances[slot] = distances

	# The shade drifts to a new random target every 10 segments.
	_shade += SHADE_STEP
	if _shade > 1.0:
		_shade = 0.0
		_shade_from = _shade_to
		_shade_to = _rand() & (RAMP_SIZE - 1)


func _vertex_colours(n: int) -> Array[Color]:
	var level := mini((n - tail - 1) / LEVEL_SEGMENTS, ALPHA.size() - 1) if n > tail else 0
	var colours: Array[Color] = []
	var bytes := _colours[n & SLOT_MASK]
	for j in POINTS:
		var colour := _ramp[bytes[j] if j < bytes.size() else 0]
		colour.a = ALPHA[level] / 256.0
		colours.push_back(colour)
	return colours


func _flat_colours(index: int, level: int) -> Array[Color]:
	var colour := _ramp[index]
	colour.a = ALPHA[level] / 256.0
	var colours: Array[Color] = []
	colours.resize(POINTS)
	colours.fill(colour)
	return colours


func _rand() -> int:
	return randi() & RAND_MAX
