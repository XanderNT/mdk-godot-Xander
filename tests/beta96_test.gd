## Test of the 1996 demo's levels (`MDKBeta`, docs/beta96.md): their files load, and every script
## decodes into instructions the VM knows. Skipped when the demo isn't found.
## Run: godot --headless --path . -s tests/beta96_test.gd
extends SceneTree

## Level → [arenas and corridors, aliens placed, instructions, paths].
const EXPECTED := {1: [19, 35, 640, 22], 3: [2, 2, 143, 0], 6: [1, 10, 337, 0]}

var _failures := 0


func _initialize() -> void:
	if not MDKBeta.is_available():
		print("SKIPPED (the demo wasn't found; set MDK_BETA_DIR)")
		quit(0)
		return
	for level: int in EXPECTED:
		_check_level(level, EXPECTED[level])
	print("FAILED %d" % _failures if _failures else "PASSED")
	quit(1 if _failures else 0)


func _check_level(level: int, expected: Array) -> void:
	var dti := MDKBeta.load_dti(level)
	var aliens := 0
	for arena in dti.arenas:
		for record: Dictionary in arena.records:
			if record.type == MDKBeta.RECORD_ALIEN:
				aliens += 1
	_expect(dti.arenas.size() == expected[0], "LEVEL%d: %d arenas" % [level, dti.arenas.size()])
	_expect(aliens == expected[1], "LEVEL%d: %d aliens" % [level, aliens])
	_expect(dti.sky.indices.size() == dti.sky.width * dti.sky.height, "LEVEL%d: sky size" % level)

	var mto := MDKBeta.load_mto(level)
	for arena_name: String in mto.get_arena_names():
		var arena := mto.get_arena(arena_name)
		_expect(not arena.vertices.is_empty() and not arena.triangle_materials.is_empty(), "%s: empty" % arena_name)
		_expect(arena.palette_rgb.size() == MDKBeta.ARENA_COLORS * 3, "%s: palette" % arena_name)

	var cmi := MDKBeta.load_cmi(level)
	_expect(cmi.beta_paths.size() == expected[3], "LEVEL%d: %d paths" % [level, cmi.beta_paths.size()])
	var decoder := MDKBetaScriptDecoder.new(cmi)
	var seen := {}
	var todo := MDKBetaScriptDecoder.get_entry_points(cmi)
	while not todo.is_empty():
		var pc: int = todo.pop_back()
		while pc > 0 and not seen.has(pc):
			var ins := decoder.decode(pc)
			if ins == null:
				_fail("LEVEL%d: unknown opcode %d at 0x%x" % [level, cmi.bytes[pc], pc])
				break
			seen[pc] = true
			todo.append_array(decoder.get_beta_targets(ins))
			# Animations are inside the file and parse.
			if ins.opcode in [3, 59]:
				_expect(cmi.get_beta_animation(ins.operands[0]).frame_count > 0, "animation at 0x%x" % ins.operands[0])
			if ins.opcode in [0xFF, 9, 12, 253]:
				break
			pc = ins.next
	_expect(seen.size() == expected[2], "LEVEL%d: %d instructions" % [level, seen.size()])
	for model_name: String in cmi.model_offsets:
		_expect(cmi.get_model(model_name) != null, "LEVEL%d: model %s" % [level, model_name])
	print("LEVEL%d: %d arenas, %d aliens, %d instructions, %d paths, %d models" % [level, dti.arenas.size(), aliens,
			seen.size(), cmi.beta_paths.size(), cmi.model_offsets.size()])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	print("FAIL " + message)
