#!/bin/sh
# Integration test: at the start of LEVEL7 Kurt collides with DANT_1 only; at its door, also with
# the active second arena CDANT_1 (`damp_collide_move` 0x465e34).
# Run from the project folder: sh tests/kurt_arenas_test.sh <godot executable>
GODOT=${1:-godot}
START=$(timeout 60 "$GODOT" --audio-driver Dummy --path . -- --level=7 --delay=0.5 --profile=2 2>&1 | grep "^solid for Kurt")
DOOR=$(timeout 60 "$GODOT" --audio-driver Dummy --path . -- --level=7 --at=0,472,18,90 --delay=0.5 --unlock --profile=6 2>&1 | grep "^solid for Kurt")
echo "$START"
echo "$DOOR"
[ "$START" = "solid for Kurt: DANT_1" ] && [ "$DOOR" = "solid for Kurt: DANT_1, CDANT_1" ] && echo PASSED && exit 0
echo FAILED
exit 1
