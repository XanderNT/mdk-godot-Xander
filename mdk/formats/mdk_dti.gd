## `LEVELn.DTI`: level settings, arena list, base palette and sky.
## The game loads the file without its first 4 bytes; block offsets are relative to that.
class_name MDKDti
extends RefCounted

## `GLASS1`–`GLASS4`.
const GLASS_COUNT := 4

var bytes := PackedByteArray()
var palette: MDKPalette

## Index in `arenas` of the arena Kurt starts in (`level_load` 0x41b0c0; 0 in every level).
var start_arena := 0
## Player start position (MDK coordinates) and angle (degrees; 90 faces +Y).
var start_position := Vector3()
var start_angle := 0.0

## Sky panorama. Rows are `sky.width` pixels, of which the first `sky_wrap_width` cover 360°
## (the remaining columns repeat the start, for wrapping).
var sky: MDKTexture
var sky_wrap_width := 0
## Panorama row at eye level.
var sky_horizon_row := 0
## Horizontal panorama offset in pixels.
var sky_offset := 0
## Palette indices used to fill the screen above and below the panorama.
var sky_top_color := 0
var sky_bottom_color := 0
## The panorama mirrors show (`MIRRLOW`…`MIRRHIGH`): the second one where the level has it (levels 5
## and 6), else the sky.
var mirror_sky: MDKTexture
## `GLASS1`–`GLASS4`: colour and opacity (block 0, after the sky fields).
var glass: Array[Color] = []
## Arenas and corridors (`HMO_n`, `CHMO_n`), in file order. Each is a Dictionary with
## `name`, `value` (the camera pitch in degrees, positive looks down) and `records` (Array of Dictionaries with `type`, `id`, `angle`, `position`, `box_end`, `name`).
var arenas: Array[Dictionary] = []


static func load_file(path: String) -> MDKDti:
	var dti := MDKDti.new()
	dti.bytes = FileAccess.get_file_as_bytes(path)
	if dti.bytes.is_empty():
		push_error("Couldn't read %s" % path)
		return null
	dti._parse()
	return dti


func _panorama(offset: int, height: int) -> MDKTexture:
	var texture := MDKTexture.new()
	texture.name = "SKY"
	texture.width = sky_wrap_width + 4
	texture.height = height
	texture.indices = bytes.slice(offset, offset + texture.width * texture.height)
	return texture


func _block(index: int) -> int:
	return 4 + bytes.decode_u32(4 + 0x10 + index * 4)


func _parse() -> void:
	# Block 3: u32 (number of arena colors, 112), then the 256-color palette.
	var palette_offset := _block(3) + 4
	palette = MDKPalette.from_rgb(bytes.slice(palette_offset, palette_offset + 768))

	# Block 0: level settings.
	var r0 := BinReader.new(bytes, _block(0))
	start_arena = r0.u32()
	start_position = r0.vec3()
	start_angle = r0.f32()
	sky_top_color = r0.u32()
	sky_bottom_color = r0.u32()
	sky_horizon_row = r0.u32()
	sky_offset = r0.u32()
	sky_wrap_width = r0.u32()
	var sky_height := r0.u32()
	# If positive, the level has a second panorama (levels 5 and 6), for the mirrors only.
	var second_sky_top_color := r0.s32()
	var _second_sky_bottom_color := r0.s32()
	for i in GLASS_COUNT:
		var rgba := [r0.u32(), r0.u32(), r0.u32(), r0.u32()]
		glass.push_back(Color8(rgba[0], rgba[1], rgba[2], rgba[3]))

	# Block 4: sky panorama(s) (each row has 4 extra pixels for wrapping).
	sky = _panorama(_block(4), sky_height)
	mirror_sky = sky
	if second_sky_top_color > 0:
		mirror_sky = _panorama(_block(4) + sky.width * sky.height, sky_height)

	# Block 2: arenas and corridors, with their object records.
	var r := BinReader.new(bytes, _block(2))
	var count := r.u32()
	for i in count:
		var arena := {name = r.name(8)}
		var records_offset := 4 + r.u32()
		arena.value = r.f32()
		arena.records = _parse_records(records_offset)
		arenas.push_back(arena)


func _parse_records(offset: int) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var r := BinReader.new(bytes, offset)
	var count := r.u32()
	for i in count:
		var record := {type = r.u32(), id = r.s32(), angle = r.f32()}
		record.position = r.vec3()
		# Boxes (fan hotspots of type 7, wind zones of type 9) keep their far corner in the name.
		record.box_end = r.vec3()
		r.skip(-12)
		record.name = r.name(12)
		records.push_back(record)
	return records
