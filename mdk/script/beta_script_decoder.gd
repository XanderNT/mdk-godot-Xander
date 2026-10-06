## Decodes the scripts of the 1996 demo (`MDKBeta`) into the retail instructions `MDKScriptVM` runs.
##
## The demo's interpreter (`MDKDEMO.EXE` 0x47f6c) is an early version of the retail one: opcodes
## 1–92 and 128–131 have the retail numbers and mostly the retail operands, branch actions are
## `0x0C` goto, `0xF0` gosub and `0xF1` return, and gosub and return are the opcodes 0xF0 and
## 0xF1. Where an opcode differs, the operands the retail handler expects are made here; the few
## that have no retail equivalent get a number above 255 (`BETA_*`). See docs/beta96.md.
class_name MDKBetaScriptDecoder
extends MDKScriptDecoder

## `follow_path` of the demo: `[path]`. The object keeps its place on the path (a path stopped by
## opcode 21 goes on), turns along it, and the path's positions are absolute.
const BETA_FOLLOW_PATH := 302
## Opcode 5: branches when the object's field `+0x108` is 0 ❓ (in no script of the demo).
const BETA_IF_FIELD_108 := 305
## Opcode 28: branches while an object that sounded the alarm (movement command 15) was just
## deleted (`0xe21de`, 10 ticks).
const BETA_IF_ALARM_ENDED := 328
## Opcodes 41 (nothing) and 90 (`name, u8`, an arena looked up by name ❓; in no script).
const BETA_NOTHING := 300
## `fire` of the demo: `[origin, aim, range, accuracy, ?]`: a `BOLT` without a script, see
## `MDKScriptVM`.
const BETA_FIRE := 361

const ACTION_GOTO := 0x0C
const ACTION_GOSUB := 0xF0
const ACTION_RETURN := 0xF1

## Demo opcode to its operands (the codes of `MDKScriptDecoder._read`) and, when it isn't the
## same, the retail opcode. Opcodes 2, 4 and 61 are read by `_decode_beta`.
const LAYOUTS := {
	1: [[]], 3: [["data32"]], 5: [["action"], BETA_IF_FIELD_108], 6: [[]], 8: [["s16"]], 9: [[]],
	10: [["pstr", "u8", "action"]], 11: [["u8"]], 12: [["repeat:code32"]], 13: [["action"]],
	14: [["u16", "u8", "action"]], 15: [[]], 16: [["u16"]], 17: [["action"]], 18: [["f32", "action"]],
	19: [[]], 20: [[]], 21: [[]], 22: [["action"]], 23: [[]], 24: [["u8", "pstr"]], 25: [["pstr"]],
	26: [["pstr"]], 27: [["action"]], 28: [["action"], BETA_IF_ALARM_ENDED], 29: [["u8", "pstr", "code32"]],
	31: [["repeat:pstr"]], 32: [["repeat:pstr"]], 34: [["action"]], 35: [["u8"]], 36: [["u8"]],
	37: [["action"]], 38: [["cond", "action"]], 39: [["value"]], 40: [["value"]], 41: [[], BETA_NOTHING],
	42: [["pstr", "action"]], 43: [["f32", "f32"]], 44: [["action"]], 45: [["cond", "action"]],
	46: [["action"]], 47: [["f32", "action"]], 48: [["f32", "action"]], 49: [["u8", "action"]],
	50: [["value"]], 51: [["value"]], 52: [["value"]], 53: [["value"]], 54: [["cond", "action"]],
	57: [["u16", "u8", "action"]], 58: [["value"]], 59: [["data32"]], 60: [[]], 62: [["cond", "action"]],
	63: [["u8"]], 64: [["value"]], 65: [["u8", "u8", "f32"]], 66: [["u8", "u8", "f32"]],
	67: [["u8", "u8", "cond", "action"]], 68: [["u8", "u8"]], 69: [["u8", "u8"]], 70: [["u8", "u8"]],
	71: [["u8", "u8", "action"]], 72: [["u8", "u8", "action"]], 73: [["u8"]], 74: [["u8", "u8", "pstr"]],
	75: [[]], 76: [["code32"]], 77: [["pstr"]], 78: [["f32", "f32", "f32"]], 79: [["f32", "f32", "f32"]],
	80: [["f32", "f32", "f32"]], 81: [["value"]], 82: [["value"]], 83: [["value"]], 84: [["value"]],
	85: [["u8"]], 86: [["f32", "f32", "f32", "pstr", "code32"]], 87: [["u16", "u16", "u8", "action"]],
	88: [["u8"]], 89: [["pstr"]], 90: [["pstr", "u8"], BETA_NOTHING], 91: [["value"]],
	92: [["u8", "action"]], 128: [["pstr", "u8", "u8"]], 129: [["repeat:pstr"]], 130: [[]], 131: [["u8"]],
	0xF0: [["repeat:code32"], 252], 0xF1: [[], 253],
}

var _cmi: MDKCmi


func _init(cmi: MDKCmi) -> void:
	super(cmi.bytes)
	_cmi = cmi


func decode(pc: int) -> Instruction:
	if _cache.has(pc):
		return _cache[pc]
	var ins := Instruction.new()
	ins.pc = pc
	ins.opcode = bytes[pc]
	_p = pc + 1
	if ins.opcode != 0xFF and not _decode_beta(ins):
		_cache[pc] = null
		return null
	ins.next = _p
	_cache[pc] = ins
	return ins


func _decode_beta(ins: Instruction) -> bool:
	var opcode := ins.opcode
	var o := ins.operands
	match opcode:
		2:  # follow_path: only the path
			var path := _offset()
			ins.opcode = BETA_FOLLOW_PATH
			o.push_back(_cmi.beta_paths.get(path, 0))
			return true
		4:  # command_objects: the selector's id is a byte
			var command := _u8()
			var arguments: Variant = null
			if command == 7:
				ins.action = _action()
				arguments = ins.action
			elif command == 43:
				arguments = _floats(2)
			var selector := _u8()
			var selected := []
			if selector in [2, 4, 5]:
				selected.push_back(_pstr())
			if selector == 5:
				selected.push_back(_u8())
			o.assign([command, arguments, selector, selected])
			return true
		61:  # fire: where from, whether it's aimed, then three floats
			var mode := _u8()
			var origin := [mode, _u8() if mode == 0 else _pstr()]
			ins.opcode = BETA_FIRE
			o.assign([origin, _u8(), _f32(), _f32(), _f32()])
			return true
	if not LAYOUTS.has(opcode):
		return false
	var layout: Array = LAYOUTS[opcode]
	for code: String in layout[0]:
		o.push_back(_read(code, ins))
	if layout.size() > 1:
		ins.opcode = layout[1]
	# The operands the retail handlers take.
	match opcode:
		21:  # stops the path where it is
			o.push_back(-2)
		23:
			o.push_back(1)
		77:
			o.push_front(1)
		81:  # not multiplied by the frame time
			o.push_front(0)
		89:  # played where the object is
			o.assign([0, null, o[0]])
		92:  # the frame itself, not the frame + 1
			o[0] += 1
		129:  # no mode
			var parts := []
			for entry: Array in o[0]:
				parts.push_back(entry[0])
			o.assign([0, parts])
	return true


func _action() -> Array:
	var action := _u8()
	match action:
		ACTION_GOSUB:
			return ["gosub", _offset()]
		ACTION_GOTO:
			return ["goto", _offset()]
		ACTION_RETURN:
			return ["return"]
	return ["none", action]


## Names are in lower case in the demo's scripts; the port's are in upper case.
func _pstr() -> String:
	return super().to_upper()


## The entry points of the file's scripts: the aliens' and the object types'.
static func get_entry_points(cmi: MDKCmi) -> Array[int]:
	var entries: Array[int] = []
	for directory: Dictionary in [cmi.alien_scripts, cmi.object_scripts]:
		for offset: int in directory.values():
			if offset != 0:
				entries.push_back(offset)
	return entries


## Turns the demo's paths into the retail spline records `MDKObjectMotion` follows, appended to
## the file's bytes (`cmi.beta_paths`: old offset to new).
##
## A demo path is `u32 count`, the first position, then `count − 1` steps of 3 `f32`, one per
## frame (0x32ff8). Every frame becomes a key whose tangents are the steps to its neighbours,
## which makes the spline a straight line between them. The paths are found by walking the
## scripts from their entry points.
static func convert_paths(cmi: MDKCmi) -> void:
	var paths := {}
	var seen := {}
	var todo := get_entry_points(cmi)
	# A decoder of its own: its instructions are decoded before the paths are known.
	var decoder := MDKBetaScriptDecoder.new(cmi)
	while not todo.is_empty():
		var pc: int = todo.pop_back()
		while pc > 0 and pc < cmi.bytes.size() and not seen.has(pc):
			seen[pc] = true
			var opcode := cmi.bytes[pc]
			if opcode == 2:
				paths[4 + cmi.bytes.decode_u32(pc + 1)] = true
			var ins := decoder.decode(pc)
			if ins == null:
				push_warning("Beta script: unknown opcode %d at 0x%x" % [opcode, pc])
				break
			todo.append_array(decoder.get_beta_targets(ins))
			if opcode in [0xFF, 9, 12, 0xF1]:
				break
			pc = ins.next
	for path: int in paths:
		cmi.beta_paths[path] = _convert_path(cmi, path)


## The offsets an instruction can go on to, besides the next one.
func get_beta_targets(ins: Instruction) -> Array[int]:
	var targets: Array[int] = []
	_collect_targets(ins.operands, targets, ins.opcode)
	return targets


func _collect_targets(operands: Array, targets: Array[int], opcode: int) -> void:
	match opcode:
		12, 252:
			for entry: Array in operands[0]:
				if entry[0] != 0:
					targets.push_back(entry[0])
		29:
			targets.push_back(operands[2])
		76:
			targets.push_back(operands[0])
		86:
			targets.push_back(operands[4])
	for operand: Variant in operands:
		if operand is Array and operand.size() == 2 and operand[0] is String and operand[0] in ["goto", "gosub"]:
			targets.push_back(operand[1])


static func _convert_path(cmi: MDKCmi, path: int) -> int:
	var source := cmi.bytes
	var count := source.decode_u32(path)
	var positions := PackedVector3Array()
	var position := Vector3.ZERO
	for i in count:
		var p := path + 4 + i * 12
		var step := Vector3(source.decode_float(p), source.decode_float(p + 4), source.decode_float(p + 8))
		position = step if i == 0 else position + step
		positions.push_back(position)
	# The path starts again from its first position after the last frame.
	positions.push_back(positions[0])

	var record := PackedByteArray()
	record.resize(4 + positions.size() * 40)
	record.encode_u32(0, positions.size())
	for i in positions.size():
		var key := 4 + i * 40
		record.encode_s32(key, i)
		var incoming := positions[i] - positions[maxi(i - 1, 0)]
		var outgoing := positions[mini(i + 1, positions.size() - 1)] - positions[i]
		var vectors: Array[Vector3] = [positions[i], incoming, outgoing]
		for k in 3:
			record.encode_float(key + 4 + k * 12, vectors[k].x)
			record.encode_float(key + 8 + k * 12, vectors[k].y)
			record.encode_float(key + 12 + k * 12, vectors[k].z)
	var offset := cmi.bytes.size()
	cmi.bytes.append_array(record)
	return offset
