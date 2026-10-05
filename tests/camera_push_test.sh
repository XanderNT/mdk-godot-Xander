#!/bin/sh
# Integration test: in LEVEL7 Kurt stands with his back 2 units from the corridor wall at x 14; the
# camera 8 units behind him would be in the wall, so the original pushes him away from it
# (`camera_clearance` 0x417ee8) instead of moving the camera closer.
# Run from the project folder: sh tests/camera_push_test.sh <godot executable>
GODOT=${1:-godot}
OUT=$(timeout 60 "$GODOT" --audio-driver Dummy --path . -- --level=7 --at=12,100,12,180 --delay=0.5 --profile=1 2>&1 | grep "^Kurt at" | cut -d' ' -f3-5)
echo "Kurt at $OUT"
X=$(echo "$OUT" | tr -d '(),' | cut -d' ' -f1)
awk "BEGIN { exit !($X < 9) }" && echo PASSED && exit 0
echo FAILED
exit 1
