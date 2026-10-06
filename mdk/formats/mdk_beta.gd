## The levels of the MDK beta demo of 6 August 1996 (`MDKDEMO.EXE`, a non-interactive DOS demo):
## `LEVEL1` (the city, 10 arenas and their corridors), `LEVEL3` (`HMO_1`) and `LEVEL6` (`OLYM_1`).
##
## The demo keeps its data in loose files and in earlier versions of the retail formats; this
## class reads them into the objects the retail loaders make (`MDKDti`, `MDKMto`, `MDKCmi`, …), so
## the rest of the port runs them like any other level. See docs/beta96.md for the formats.
##
## The beta levels are numbered 961, 963 and 966 in the port (`--level=961`).
class_name MDKBeta
extends RefCounted

## The demo's `TRAVERSE/LEVELn` folders.
const LEVELS: Array[int] = [1, 3, 6]
## Added to a beta level's number to tell it from the retail levels.
const NUMBER_BASE := 960
## The folder the demo is usually unpacked to, looked for next to the game data and the project.
const FOLDER := "MDK (1996-08-06) (beta demo)"
const MARKER := "TRAVERSE/LEVEL1/LEVEL1.SET"
## Arena colours are palette indices 64–175, as in the retail game.
const ARENA_COLORS := 112
const SKY_WIDTH := 1800
const SKY_HEIGHT := 360
## Record types of the `.HOT` files, the same numbers as the retail DTI records.
const RECORD_SHOW := 1
const RECORD_ALIEN := 2
const RECORD_PICKUP := 4
const RECORD_HIDE_POINT := 5
const RECORD_CONNECTION := 6
## `MSWAP` (3 in the demo) isn't a retail type 3 record (which loads an arena ahead).
const RECORD_MATERIAL_SWAP := 103
## Black in every palette of the demo (the first colour after the 16 system colours).
const OPAQUE_BLACK := 16
## Textures of the level archives whose index 0 is see-through (projectiles).
const SEE_THROUGH_TEXTURES := ["BULLET", "BOLT"]
## A triangle's flags in the `.BSP` files: 2 = not drawn and not hit by rays; 1 ❓.
const TRIANGLE_NOT_DRAWN := 2
## `LEVEL3.SET` has no start angle (the demo keeps the one it had); 90 faces +Y, into the arena.
const DEFAULT_START_ANGLE := 90.0
## `BACK_3.LBB` is a copy of the city's sky, which only has its colours in level 1's palette (the
## demo's `HMO_1` is closed, so its sky is never seen): the port draws it in the nearest colours
## of the level's own palette.
const SKY_PALETTES := {3: 1}
## The camera pitch the retail levels usually give their arenas (degrees).
const CAMERA_PITCH := 4.0
## Kurt's sprites and the HUD images the demo has its own versions of: file to `TRAVSPRT.BNI` entry.
const SPRITE_FILES := {
	"SPRITES/K_STILL.ABB": "K_STILL", "SPRITES/K_IDLE.ABB": "K_IDLE", "SPRITES/K_RUN.ABB": "K_RUN",
	"SPRITES/K_SIDE.ABB": "K_SIDE", "SPRITES/K_JUMP.ABB": "K_JUMP", "SPRITES/K_RJMP.ABB": "K_RJMP",
	"SPRITES/K_CHUTE.ABB": "K_CHUTE", "SPRITES/K_SHOT.ABB": "K_SHOT", "SPRITES/K_RUNFIR.ABB": "K_RUNFIR",
	"SPRITES/K_HANG.ABB": "K_HANG", "SPRITES/K_LOOKU.ABB": "K_LOOKU", "SPRITES/CROSS.ABB": "CROSS",
	"SPRITES/K_ROLLL.ABB": "K_ROLLL", "SPRITES/K_ROLLR.ABB": "K_ROLLR", "SPRITES/K_HELM.ABB": "K_HELM",
	"SPRITES/K_BCKUP.ABB": "K_BCKUP", "SPRITES/K_LOOKD.ABB": "K_LOOKD", "SPRITES/K_FIRE_M.ABB": "K_FIRE_M",
	"SPRITES/HUD/SC_STAT.LBB": "SC_STAT", "SPRITES/HUD/SC_BSTAT.LBB": "SC_BSTAT",
}

static var _dir := ""
static var _searched := false


static func is_beta(number: int) -> bool:
	return number > NUMBER_BASE


## The demo's level (1, 3, 6) of one of the port's numbers.
static func level_of(number: int) -> int:
	return number - NUMBER_BASE


## The port's number of a beta level (961, 963, 966).
static func number_of(level: int) -> int:
	return NUMBER_BASE + level


## Returns the demo's folder (the one with `TRAVERSE`), or an empty string if it can't be found:
## `MDK_BETA_DIR`, `beta` in `mdk_paths.cfg` (`MDKData.get_local_path`), or a `BETA96` or "MDK (1996-08-06) (beta demo)" folder in or next to the game
## data or the project.
static func find_dir() -> String:
	if _searched:
		return _dir
	_searched = true
	var candidates: Array[String] = []
	var env_dir := OS.get_environment("MDK_BETA_DIR")
	if not env_dir.is_empty():
		candidates.push_back(env_dir)
	# The game data's folder, from the `MDKData` autoload (which tests run as scripts don't have).
	var data := (Engine.get_main_loop() as SceneTree).root.get_node_or_null(^"MDKData")
	if data:
		var local_dir: String = data.get_local_path("beta")
		if not local_dir.is_empty():
			candidates.push_back(local_dir)
	var bases: Array[String] = [data.data_dir if data else "", ProjectSettings.globalize_path("res://")]
	if OS.has_feature("template"):
		bases.push_back(OS.get_executable_path().get_base_dir())
	for base in bases:
		if base.is_empty():
			continue
		for folder: String in ["BETA96", FOLDER]:
			candidates.push_back(base.path_join(folder))
			candidates.push_back(base.path_join("..").path_join(folder).simplify_path())
	for candidate in candidates:
		if FileAccess.file_exists(candidate.path_join(MARKER)):
			_dir = candidate
			break
	return _dir


static func is_available() -> bool:
	return not find_dir().is_empty()


static func path(relative_path: String) -> String:
	return find_dir().path_join(relative_path)


static func _level_dir(level: int) -> String:
	return "TRAVERSE/LEVEL%d/" % level


static func _read(relative_path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path(relative_path))


## Palette indices drawn with `from` as the nearest colours of `to`.
static func _remap(indices: PackedByteArray, from: MDKPalette, to: MDKPalette) -> PackedByteArray:
	var table := PackedByteArray()
	table.resize(256)
	for i in 256:
		var colour := from.get_color(i)
		var best := 0
		var best_distance := INF
		for k in 256:
			var other := to.get_color(k)
			var distance := Vector3(colour.r - other.r, colour.g - other.g, colour.b - other.b).length_squared()
			if distance < best_distance:
				best = k
				best_distance = distance
		table[i] = best
	var out := indices.duplicate()
	for i in out.size():
		out[i] = table[out[i]]
	return out


## The lines of a text file as lists of words, without comments (`;`) and empty lines.
static func _read_lines(relative_path: String) -> Array[PackedStringArray]:
	var lines: Array[PackedStringArray] = []
	for line: String in _read(relative_path).get_string_from_ascii().split("\n"):
		var words := line.get_slice(";", 0).replace("\t", " ").replace("\r", " ").split(" ", false)
		if not words.is_empty():
			lines.push_back(words)
	return lines


# Level settings: `LEVELn.SET`, `LEVELn.CON`, the `.HOT` files, palettes and the sky.

## The level's settings as the retail `LEVELn.DTI` has them.
##
## - `LEVELn.SET` (text): the start arena's index and Kurt's position (and angle), the sky's fill
##   colours and horizon row, then the four glass colours (`r g b opacity`).
## - `LEVELn.CON` (text): the number of arenas, then per arena its name, a number of portals and
##   the portals (`C<arena index> <side> <z> <plane> <from> <to>`, not used by the port).
## - `ARENAS/<name>.HOT` (text): the arena's records, see `_load_records`.
## - `Ln_PAL.LBP`: the level's palette (768 bytes); `SCREENS/BACK_n.LBB`: the sky panorama,
##   1804 × 360 pixels without a header.
static func load_dti(level: int) -> MDKDti:
	var dir := _level_dir(level)
	var dti := MDKDti.new()
	dti.palette = MDKPalette.from_rgb(_read(dir + "L%d_PAL.LBP" % level))

	var settings := _read_lines(dir + "LEVEL%d.SET" % level)
	dti.start_arena = int(settings[0][0])
	dti.start_position = Vector3(float(settings[0][1]), float(settings[0][2]), float(settings[0][3]))
	dti.start_angle = float(settings[0][4]) if settings[0].size() > 4 else DEFAULT_START_ANGLE
	dti.sky_top_color = int(settings[1][0])
	dti.sky_bottom_color = int(settings[1][1])
	dti.sky_horizon_row = int(settings[1][2])
	for i in 4:
		var rgba := settings[2 + i]
		dti.glass.push_back(Color8(int(rgba[0]), int(rgba[1]), int(rgba[2]), int(rgba[3])))

	dti.sky_wrap_width = SKY_WIDTH
	dti.sky = MDKTexture.new()
	dti.sky.name = "SKY"
	dti.sky.width = SKY_WIDTH + 4
	dti.sky.height = SKY_HEIGHT
	dti.sky.indices = _read("TRAVERSE/SCREENS/BACK_%d.LBB" % level)
	dti.sky.indices.resize(dti.sky.width * dti.sky.height)
	if SKY_PALETTES.has(level):
		var sky_level: int = SKY_PALETTES[level]
		var sky_palette := MDKPalette.from_rgb(_read(_level_dir(sky_level) + "L%d_PAL.LBP" % sky_level))
		dti.sky.indices = _remap(dti.sky.indices, sky_palette, dti.palette)
	dti.mirror_sky = dti.sky

	var names := get_arena_names(level)
	for arena_name in names:
		dti.arenas.push_back({name = arena_name, value = CAMERA_PITCH,
				records = _load_records(dir + "ARENAS/%s.HOT" % arena_name, names)})
	return dti


## The level's arenas and corridors in the order of `LEVELn.CON` (their indices are used by the
## start arena and the `ASHOW` records), in upper case.
static func get_arena_names(level: int) -> Array[String]:
	var names: Array[String] = []
	var lines := _read_lines(_level_dir(level) + "LEVEL%d.CON" % level)
	var line := 1
	for i in int(lines[0][0]):
		names.push_back(lines[line][0].to_upper())
		line += 1 + int(lines[line][1])
	return names


## An arena's `.HOT` file as DTI records. Its lines:
## - `ASHOW <arena> x1 y1 x2 y2`: walking into the rectangle shows that arena (`NONE`: none).
## - `ALIEN <type> <id> <n> x y z`: an alien, run by the script `<arena>$<type>_<id>`.
## - `PICKUP <type> x y z`, `HIDEPT <id> x y z` (a cover spot),
##   `CONNECT <id> x1 x2 y1 y2 z1 z2` (a doorway between an arena and a corridor, in pairs),
##   `MSWAP` with six numbers (a material swap, in no file of the demo).
static func _load_records(relative_path: String, arena_names: Array[String]) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for words in _read_lines(relative_path):
		var numbers := PackedFloat32Array()
		var first := 1 if words[0].to_upper() in ["HIDEPT", "CONNECT", "MSWAP"] else 2
		for i in range(first, words.size()):
			numbers.push_back(float(words[i]))
		var record := {type = 0, id = -1, angle = 0.0, position = Vector3.ZERO, box_end = Vector3.ZERO,
				name = words[1].to_upper() if first == 2 else ""}
		match words[0].to_upper():
			"ASHOW":
				record.type = RECORD_SHOW
				record.id = arena_names.find(record.name)
				record.position = Vector3(numbers[0], numbers[1], 0.0)
				record.box_end = Vector3(numbers[2], numbers[3], 0.0)
			"ALIEN":
				record.type = RECORD_ALIEN
				record.id = int(numbers[0])
				record.position = Vector3(numbers[2], numbers[3], numbers[4])
			"PICKUP":
				record.type = RECORD_PICKUP
				record.position = Vector3(numbers[0], numbers[1], numbers[2])
			"HIDEPT":
				record.type = RECORD_HIDE_POINT
				record.id = int(numbers[0])
				record.position = Vector3(numbers[1], numbers[2], numbers[3])
			"CONNECT":
				record.type = RECORD_CONNECTION
				record.id = int(numbers[0])
				record.position = Vector3(numbers[1], numbers[3], numbers[5])
				record.box_end = Vector3(numbers[2], numbers[4], numbers[6])
			"MSWAP":
				record.type = RECORD_MATERIAL_SWAP
			_:
				continue
		records.push_back(record)
	return records


## The demo's teleports, `TRAVERSE/TELEPORT.TXT`: a line `<arena> x y z` per digit (the first is
## 0). The demo takes Kurt to the line of a digit typed, when the level has its arena (0x440c4).
## Returns `[arena, position]` per line.
static func load_teleports() -> Array[Array]:
	var teleports: Array[Array] = []
	for words in _read_lines("TRAVERSE/TELEPORT.TXT"):
		if words.size() >= 4:
			teleports.push_back([words[0].to_upper(), Vector3(float(words[1]), float(words[2]), float(words[3]))])
	return teleports


# Arenas: `LEVELnO.MTO` (textures), `ARENAS/<name>.BSP` (geometry) and `<name>.LBP` (palette).

## The level's arenas. `LEVELnO.MTO` only has their textures: `u32 count`, per arena
## `char[8] name, u32 offset`; at the offset `u32 size`, then a texture archive without the retail
## header (`u32 count`, the entries, the textures; offsets relative to the count).
static func load_mto(level: int) -> MDKMto:
	var dir := _level_dir(level)
	var mto := MDKMto.new()
	mto.bytes = _read(dir + "LEVEL%dO.MTO" % level)
	var texture_offsets := {}
	var r := BinReader.new(mto.bytes, 0)
	for i in r.u32():
		var arena_name := r.name(8).to_upper()
		texture_offsets[arena_name] = r.u32() + 4
	for arena_name in get_arena_names(level):
		if is_corridor(arena_name):
			continue
		var arena := load_world(level, arena_name)
		if not arena:
			continue
		if texture_offsets.has(arena_name):
			arena.textures = MDKTextureArchive.parse(mto.bytes, texture_offsets[arena_name], 0)
			_make_opaque(arena.textures)
		var palette := _read(dir + "ARENAS/%s.LBP" % arena_name)
		if palette.size() >= 768:
			var first := MDKPalette.ARENA_FIRST_INDEX * 3
			arena.palette_rgb = palette.slice(first, first + ARENA_COLORS * 3)
		mto.add_arena(arena)
	return mto


## Corridors have no textures or palette of their own, like the retail ones.
static func is_corridor(arena_name: String) -> bool:
	return arena_name.begins_with("C")


## The corridors between the arenas (`CORR_n`; level 3's `CHMO_1` is a copy of the city's `CORR_1`).
static func load_corridors(level: int) -> Array[MDKArena]:
	var corridors: Array[MDKArena] = []
	for arena_name in get_arena_names(level):
		if is_corridor(arena_name):
			var corridor := load_world(level, arena_name)
			if corridor:
				corridors.push_back(corridor)
	return corridors


## An arena's geometry, `ARENAS/<name>.BSP`: the retail world section with 16-character material
## names and 36-byte BSP nodes (`f32 plane[4]`, then ten `s16`).
static func load_world(level: int, arena_name: String) -> MDKArena:
	var bytes := _read(_level_dir(level) + "ARENAS/%s.BSP" % arena_name)
	if bytes.is_empty():
		return null
	var arena := MDKArena.new()
	arena.name = arena_name
	arena.textures = MDKTextureArchive.new()
	var r := BinReader.new(bytes, 0)
	for i in r.u32():
		arena.materials.push_back(r.name(16).to_upper())
	arena.bsp_node_count = r.u32()
	r.skip(arena.bsp_node_count * 36)
	arena.read_triangles(r)
	return arena


## The triangles of an arena with flag 2: simple shapes around the detailed ones (their UVs are all
## 0) that the demo doesn't draw (0x15d90) and leaves out of its triangle tests (0x18390's
## caller, 0x2c6d0's). The port has them stop Kurt only.
static func get_clip_triangles(arena: MDKArena) -> PackedInt32Array:
	var hidden := PackedInt32Array()
	for tri in arena.triangle_flags.size():
		if arena.triangle_flags[tri] & TRIANGLE_NOT_DRAWN:
			hidden.push_back(tri)
	return hidden


# Textures, sounds, sprites.

## `LEVELnS.MTI`: `u32 size`, then a texture archive without the retail header.
static func load_textures(level: int) -> MDKTextureArchive:
	var archive := MDKTextureArchive.parse(_read(_level_dir(level) + "LEVEL%dS.MTI" % level), 4, 0)
	_make_opaque(archive)
	# The effect textures are loose files of animated textures (`u32 frames, u16 width, u16 height`).
	for file: String in ["TRAVERSE/LEVEL1/TEXTURES/TRAIL.LBA", "TRAVERSE/SPRITES/SLIME/SL_BIG.LBA",
			"TRAVERSE/SPRITES/SLIME/SL_MED.LBA", "TRAVERSE/SPRITES/SLIME/SL_SMA.LBA",
			"TRAVERSE/SPRITES/SLIME/SB_MED.LBA", "TRAVERSE/SPRITES/SLIME/SB_SMA.LBA"]:
		var bytes := _read(file)
		var texture_name := file.get_file().get_basename()
		if not bytes.is_empty() and not archive.textures.has(texture_name):
			archive.textures[texture_name] = MDKTexture.parse_animated(texture_name, bytes, 0)
	return archive


## The demo's walls and models use palette index 0 as black (a tenth of the city's wall textures
## have it), where the retail game keeps it for the see-through parts of effects. Their index 0
## becomes `OPAQUE_BLACK`; animated textures and `SEE_THROUGH_TEXTURES` keep theirs.
static func _make_opaque(archive: MDKTextureArchive) -> void:
	for texture: MDKTexture in archive.textures.values():
		if texture.frame_count > 1 or texture.name in SEE_THROUGH_TEXTURES:
			continue
		var at := texture.indices.find(0)
		while at >= 0:
			texture.indices[at] = OPAQUE_BLACK
			at = texture.indices.find(0, at + 1)


## The sound archives in the order of `Level.sound_archives`: `TRAVERSE.SNI`, `LEVELnS.SNI`,
## `LEVELnO.SNI`. They have no name header: `u32 size, u32 count`, then the retail entries.
static func load_sounds(level: int) -> Array[MDKSni]:
	var dir := _level_dir(level)
	var archives: Array[MDKSni] = []
	for file: String in ["TRAVERSE/TRAVERSE.SNI", dir + "LEVEL%dS.SNI" % level, dir + "LEVEL%dO.SNI" % level]:
		archives.push_back(MDKSni.load_file(path(file), 4))
	return archives


## Puts the demo's versions of Kurt's sprites and of the HUD's images over the retail ones
## (`*.ABB` are RLE sprite animations and `*.LBB` plain images, as in `TRAVSPRT.BNI`).
static func add_sprites(sprites: MDKBni) -> void:
	for file: String in SPRITE_FILES:
		var bytes := _read("TRAVERSE/" + file)
		if not bytes.is_empty():
			sprites.add_entry(SPRITE_FILES[file], bytes)


# Scripts, models and animations: `LEVELn.CMI`.

## `LEVELn.CMI`: `u32 size`, the four directories of the retail file, the scripts (see
## `MDKBetaScriptDecoder`) and their paths, the models (the retail format) and the animations
## (`MDKModelAnimation.parse_beta`), which the scripts point at.
##
## An arena's record (directory 3) is two strings, its music and its ambient loop; arenas have
## no scripts yet.
static func load_cmi(level: int) -> MDKCmi:
	var cmi := MDKCmi.new()
	cmi.beta = true
	cmi.bytes = _read(_level_dir(level) + "LEVEL%d.CMI" % level)
	var r := BinReader.new(cmi.bytes, 4)
	for directory: Dictionary in [cmi.alien_scripts, cmi.model_offsets, cmi.object_scripts, cmi.arena_scripts]:
		for i in r.u32():
			var entry_name := r.pascal_name().to_upper()
			directory[entry_name] = 4 + r.u32()
	for arena_name: String in cmi.arena_scripts:
		var record := BinReader.new(cmi.bytes, cmi.arena_scripts[arena_name])
		cmi.arena_music[arena_name] = record.pascal_name().to_upper()
		cmi.arena_ambience[arena_name] = record.pascal_name().to_upper()
		cmi.arena_scripts[arena_name] = 0
	MDKBetaScriptDecoder.convert_paths(cmi)
	return cmi
