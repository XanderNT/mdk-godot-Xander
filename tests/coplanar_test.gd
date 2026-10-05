## Bug test: the original draws without a depth buffer (back to front), so a poster lying on a wall
## in the same plane simply covers it; with Godot's depth buffer such triangles flicker. In the
## arena meshes no two overlapping triangles facing the same way may stay in the same plane (LEVEL7
## DANT_6).
## Run: godot --headless --path . -s tests/coplanar_test.gd
extends SceneTree

const MTO := "C:/Games/MDK/TRAVERSE/LEVEL7/LEVEL7O.MTO"
const ARENA := "DANT_6"
const PLANE_EPSILON := 0.001


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var mto = load("res://mdk/formats/mdk_mto.gd").load_file(MTO)
	var arena = mto.get_arena(ARENA)
	var builder = load("res://mdk/mdk_mesh_builder.gd")
	var positions: PackedVector3Array = builder.arena_positions(arena)
	var flickering := 0
	var count: int = arena.triangle_materials.size()
	for a in count:
		var pa := _triangle(positions, a)
		var normal := (pa[2] - pa[0]).cross(pa[1] - pa[0]).normalized()
		var centre: Vector3 = (pa[0] + pa[1] + pa[2]) / 3.0
		for b in range(a + 1, count):
			var pb := _triangle(positions, b)
			if absf(normal.dot(pb[0] - pa[0])) > PLANE_EPSILON or absf(normal.dot(pb[1] - pa[0])) > PLANE_EPSILON \
					or absf(normal.dot(pb[2] - pa[0])) > PLANE_EPSILON:
				continue
			# Faces turned away from each other never show together (back faces aren't drawn).
			if normal.dot((pb[2] - pb[0]).cross(pb[1] - pb[0])) <= 0.0:
				continue
			var centre_b: Vector3 = (pb[0] + pb[1] + pb[2]) / 3.0
			if _inside(centre, pb, normal) or _inside(centre_b, pa, normal):
				flickering += 1
	print("overlapping triangles in one plane: %d" % flickering)
	print("PASSED" if flickering == 0 else "FAILED")
	quit(0 if flickering == 0 else 1)


static func _triangle(positions: PackedVector3Array, t: int) -> Array[Vector3]:
	return [positions[t * 3], positions[t * 3 + 1], positions[t * 3 + 2]]


## Whether `point` (in the triangle's plane) is inside it.
static func _inside(point: Vector3, tri: Array[Vector3], normal: Vector3) -> bool:
	for i in 3:
		var edge: Vector3 = tri[(i + 1) % 3] - tri[i]
		if normal.dot(edge.cross(point - tri[i])) * normal.dot(edge.cross(tri[(i + 2) % 3] - tri[i])) < 0.0:
			return false
	return true
