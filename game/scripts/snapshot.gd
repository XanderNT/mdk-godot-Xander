## Packs and unpacks objects' script variables for full saves (F2, `GameState.KIND_SNAPSHOT`, the
## original's `AREN`/`ALIE` packets). Values become plain data (`var_to_str` can write them):
##
##   MDKObject in the object list   → {"#obj": index}
##   arena script object             → {"#fixed": key}   (see `MDKScriptRuntime.snapshot`)
##   MDKModelAnimation               → {"#anim": name}
##   other objects (meshes, voices)  → left out, rebuilt by the owner
##
## Private variables (`_…`) and `SKIPPED` ones aren't saved: nodes, the model (found again by the
## type name), sound voices (restarted by name) and wounds (effects aren't saved).
class_name MDKSnapshot
extends RefCounted

const SKIPPED := ["model", "loop_sound", "tracked_voice", "wounds"]
const OBJECT_KEY := "#obj"
const FIXED_KEY := "#fixed"
const ANIMATION_KEY := "#anim"

var _objects: Array[MDKObject] = []
var _index := {}
var _fixed := {}
var _fixed_keys := {}
## Turns an animation name back into the animation for an object (`MDKScriptRuntime`).
var _find_animation: Callable


## `objects` are referred to by index, `fixed` (key → object) by key.
func _init(objects: Array[MDKObject], fixed: Dictionary, find_animation: Callable) -> void:
	_objects = objects
	for i in objects.size():
		if objects[i]:
			_index[objects[i]] = i
	_fixed = fixed
	for key: String in fixed:
		_fixed_keys[fixed[key]] = key
	_find_animation = find_animation


## The script variables of an object, as plain data.
func pack(obj: Object) -> Dictionary:
	var data := {}
	for property in obj.get_property_list():
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var property_name: String = property.name
		if property_name.begins_with("_") or property_name in SKIPPED:
			continue
		data[property_name] = encode(obj.get(property_name))
	return data


## Sets an object's script variables back. Arrays are filled in place, so typed arrays keep their
## type.
func unpack(obj: MDKObject, data: Dictionary) -> void:
	for property_name: String in data:
		var value: Variant = decode(data[property_name], obj)
		var current: Variant = obj.get(property_name)
		if current is Array and value is Array:
			(current as Array).assign(value)
			continue
		obj.set(property_name, value)


func encode(value: Variant) -> Variant:
	if value is MDKObject:
		if _index.has(value):
			return {OBJECT_KEY: _index[value]}
		if _fixed_keys.has(value):
			return {FIXED_KEY: _fixed_keys[value]}
		return null
	if value is MDKModelAnimation:
		return {ANIMATION_KEY: value.name}
	if value is Object:
		return null
	if value is Array:
		return (value as Array).map(encode)
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = encode(value[key])
		return out
	return value


## `obj` is the object the value belongs to (animations are looked up in its arena).
func decode(value: Variant, obj: MDKObject) -> Variant:
	if value is Array:
		return (value as Array).map(decode.bind(obj))
	if not value is Dictionary:
		return value
	var data: Dictionary = value
	if data.size() == 1 and data.has(OBJECT_KEY):
		var i: int = data[OBJECT_KEY]
		return _objects[i] if i >= 0 and i < _objects.size() else null
	if data.size() == 1 and data.has(FIXED_KEY):
		return _fixed.get(data[FIXED_KEY])
	if data.size() == 1 and data.has(ANIMATION_KEY):
		return _find_animation.call(obj, data[ANIMATION_KEY])
	var out := {}
	for key: Variant in data:
		out[key] = decode(data[key], obj)
	return out
