## The main menu's slideshow (0x4279a0): once `MDK12.FLC` ends, an idle menu shows
## `MISC/MDKS_001.GIF` after 5 s (without the menu items) for 4 s, then the others 2 s each with the
## items, then the video's last frame again, and so on. Any input starts the wait again; on the
## first image it shows the next one at once. See docs/gameplay.md, "Videos".
##
##   last frame ──5 s──▶ MDKS_001 (no items) ──4 s──▶ MDKS_002 ──2 s──▶ … MDKS_008 ──2 s──▶ last frame
class_name MenuSlideshow
extends RefCounted

const IMAGE_PATH := "MISC/MDKS_%03d.GIF"
const FIRST_DELAY := 5.0
const FIRST_TIME := 4.0
const NEXT_TIME := 2.0

## The image shown: 0 the video's last frame, 1… the GIFs.
var image := 0

var _video: MDKVideo
var _items: Control
var _images: Array[MDKGif] = []
var _last: Array[Image] = []
var _time := 0.0
var _running := false


func _init(video: MDKVideo, items: Control) -> void:
	_video = video
	_items = items


## Starts once the video has ended, keeping its last frame.
func start() -> void:
	_last = _video.get_still()
	_running = true
	_time = 0.0
	if _images.is_empty():
		_load_images()


func update(delta: float) -> void:
	if not _running or _images.is_empty():
		return
	_time += delta
	if _time >= _duration():
		_next()


## Menu input: the wait starts again, and the first image gives way at once.
func reset() -> void:
	if image == 1:
		_time = _duration()
		return
	_time = 0.0


func _duration() -> float:
	match image:
		0:
			return FIRST_DELAY
		1:
			return FIRST_TIME
	return NEXT_TIME


func _next() -> void:
	_time = 0.0
	image = (image + 1) % (_images.size() + 1)
	_items.visible = image != 1
	if image == 0:
		_video.show_still(_last[0].get_width(), _last[0].get_height(), _last[0].get_data(), _last[1].get_data())
		return
	var gif := _images[image - 1]
	_video.show_still(gif.width, gif.height, gif.indices, gif.palette)


func _load_images() -> void:
	var i := 1
	while true:
		var gif := MDKGif.load_file(MDKData.path(IMAGE_PATH % i))
		if not gif:
			return
		_images.push_back(gif)
		i += 1
