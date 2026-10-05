#!/bin/sh
# Bug test: gliding with the chute (state 701) shows `K_CHUTE` opening, then `K_CHUTEC` (the
# canopy is painted in Kurt's frames, `damp_animate` 0x4646a4), not the end of level's `K_FLOATC`.
# Run from the project folder: sh tests/chute_test.sh <godot executable>
GODOT=${1:-godot}
OUT=$(timeout 60 "$GODOT" --audio-driver Dummy --path . -- --level=7 --at=0,4,300 --delay=0.5 --jump --profile=1.5 2>&1 | grep "^Kurt shows")
echo "$OUT"
[ "$OUT" = "Kurt shows K_CHUTEC" ] && echo PASSED && exit 0
echo FAILED
exit 1
