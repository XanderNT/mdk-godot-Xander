#!/bin/sh
# Bug test: in sniper mode the scope's 640×480 frame covers the whole screen of the original; in a
# wider window the sides beside it must be black, not the scene.
# Run from the project folder: sh tests/sniper_wide_test.sh <godot executable>
GODOT=${1:-godot}
SHOT="${TMPDIR:-/tmp}/sniper_wide.png"
rm -f "$SHOT"
timeout 60 "$GODOT" --audio-driver Dummy --resolution 1920x1080 --path . -- --level=3 --delay=0.5 --sniper --wait=0.5 --screenshot="$SHOT" >/dev/null 2>&1
python - "$SHOT" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
w, h = im.size
side = [im.getpixel((x, y)) for x in (5, w - 6) for y in (h // 4, h // 2, 3 * h // 4)]
print("size", w, h, "side pixels", side)
sys.exit(0 if w > h * 4 // 3 and all(p == (0, 0, 0) for p in side) else 1)
PY
[ $? -eq 0 ] && echo PASSED && exit 0
echo FAILED
exit 1
