## Bug test: `M_COMM` (kind 0x20000) is a base image and deltas, not frames back to back: every
## frame keeps most of the base image (the port read the deltas as pixels and showed unrelated
## images). Run: godot --headless --path . -s tests/anim_texture_test.gd
extends SceneTree

const MTO := "C:/Games/MDK/TRAVERSE/LEVEL7/LEVEL7O.MTO"
## Share of a frame's pixels equal to the base image's at least.
const SAME_MIN := 0.5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var mto = load("res://mdk/formats/mdk_mto.gd").load_file(MTO)
	var texture = mto.get_arena("DANT_5").textures.textures["M_COMM"]
	var size: int = texture.width * texture.height
	var failures := 0
	for frame in range(1, texture.frame_count):
		var same := 0
		for i in size:
			if texture.indices[frame * size + i] == texture.indices[i]:
				same += 1
		print("frame %d: %.0f %% like the base" % [frame, 100.0 * same / size])
		if float(same) / size < SAME_MIN:
			failures += 1
	print("FAILED %d" % failures if failures else "PASSED")
	quit(1 if failures else 0)
