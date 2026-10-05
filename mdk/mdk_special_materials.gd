## The level's special materials (palette "colours" ≥ 256, see docs/formats.md, "Special
## materials"): glass in the level's colours, mirrors showing a panorama. `NONE`, `PEN_ENV` and
## `RIPPLE` aren't drawn (the Direct3D renderer skips `RIPPLE`).
class_name MDKSpecialMaterials
extends RefCounted

const MIRROR_SHADER := preload("res://mdk/shaders/mirror.gdshader")
## A mirror's panorama row is 8 rows per value from `MIRRMED` (1000): `MIRRLOW` (990) 80 lower,
## `MIRRHIGH` (1010) 80 higher.
const MIRROR_MIDDLE := 1000
const MIRROR_ROWS_PER_VALUE := 8.0

var _dti: MDKDti
var _materials := {}


func _init(dti: MDKDti) -> void:
	_dti = dti


## The material for a special value, or `null` when it isn't drawn.
func get_material(value: int) -> Material:
	if not _materials.has(value):
		_materials[value] = _make(value)
	return _materials[value]


func _make(value: int) -> Material:
	if value >= MDKMeshBuilder.SPECIAL_GLASS_FIRST and value <= MDKMeshBuilder.SPECIAL_GLASS_LAST:
		return _glass(_dti.glass[value - MDKMeshBuilder.SPECIAL_GLASS_FIRST])
	if value >= MDKMeshBuilder.SPECIAL_MIRROR_FIRST and value <= MDKMeshBuilder.SPECIAL_MIRROR_LAST:
		return _mirror(value)
	return null


## Untextured and blended by its alpha, both faces (0x471290).
static func _glass(colour: Color) -> Material:
	var material := MDKMeshBuilder.make_color_material(colour, true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _mirror(value: int) -> Material:
	var material := ShaderMaterial.new()
	material.shader = MIRROR_SHADER
	material.set_shader_parameter(&"sky_index", _dti.mirror_sky.get_index_texture())
	material.set_shader_parameter(&"palette", _dti.palette.get_texture())
	material.set_shader_parameter(&"texture_width", float(_dti.mirror_sky.width))
	material.set_shader_parameter(&"wrap_width", float(_dti.sky_wrap_width))
	material.set_shader_parameter(&"horizon_row", float(_dti.sky_horizon_row))
	material.set_shader_parameter(&"offset", float(_dti.sky_offset))
	material.set_shader_parameter(&"row_shift", (MIRROR_MIDDLE - value) * MIRROR_ROWS_PER_VALUE)
	return material
