## An SNI archive (`TRAVERSE.SNI`, `LEVELnS.SNI`, `LEVELnO.SNI`).
##
## Layout: common header, `u32 count`, then per entry `char[12] name, u16 flags, u16 volume,
## u32 offset, u32 length` (offset relative to file offset 4). Flag 1 loops the sound, flag 2 marks
## music; the volume is the sound's default (0–0x7FFF). Most entries are RIFF WAV sounds;
## in `LEVELnO.SNI`, the corridor entries (`CHMO_n`, `CMEAT_n`, …) hold the corridors' world geometry
## instead (same layout as an arena's world section).
class_name MDKSni
extends RefCounted

const FLAG_LOOP := 1

var bytes := PackedByteArray()
## Entry name to `[offset, length, flags, volume]`.
var entries := {}

var _sounds := {}
var _animations := {}


## `header` is where the entry count is: after the common header, or 4 in the 1996 demo's files
## (`MDKBeta`), whose names are in lower case.
static func load_file(path: String, header := 0x14) -> MDKSni:
	var sni := MDKSni.new()
	sni.bytes = FileAccess.get_file_as_bytes(path)
	if sni.bytes.is_empty():
		push_error("Couldn't read %s" % path)
		return null
	var r := BinReader.new(sni.bytes, header)
	var count := r.u32()
	for i in count:
		var entry_name := r.name(12).to_upper()
		var flags := r.u16()
		var volume := r.u16()
		var offset := 4 + r.u32()
		sni.entries[entry_name] = [offset, r.u32(), flags, volume]
	return sni


func is_sound(entry_name: String) -> bool:
	var offset: int = entries[entry_name][0]
	return bytes.slice(offset, offset + 4).get_string_from_ascii() == "RIFF"


## Returns a sound (AudioStreamWAV, looping when its flag 1 is set, its default volume in the
## `volume` meta), or `null` if the entry isn't a sound.
func get_sound(entry_name: String) -> AudioStreamWAV:
	if _sounds.has(entry_name):
		return _sounds[entry_name]
	if not entries.has(entry_name) or not is_sound(entry_name):
		return null

	var entry: Array = entries[entry_name]
	var sound := MDKSound.load_wav(bytes.slice(entry[0], entry[0] + entry[1]), entry[2] & FLAG_LOOP != 0)
	sound.set_meta(&"volume", entry[3])
	_sounds[entry_name] = sound
	return sound


## Returns a sprite animation of the archive (Kurt's extra frames in `LEVELnS.SNI`), or `null`.
func get_animation(entry_name: String) -> MDKSpriteAnimation:
	if not entries.has(entry_name) or is_sound(entry_name):
		return null
	if not _animations.has(entry_name):
		_animations[entry_name] = MDKSpriteAnimation.parse(entry_name, bytes, entries[entry_name][0] + 4)
	return _animations[entry_name]


## Returns every sound of the archive, by name.
func get_sounds() -> Dictionary:
	var sounds := {}
	for entry_name: String in entries:
		if is_sound(entry_name):
			sounds[entry_name] = get_sound(entry_name)
	return sounds
