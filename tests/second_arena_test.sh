#!/bin/sh
# Integration test: in LEVEL7, Kurt stands at the unlocked door of DANT_1; the door opens and the
# corridor behind it (CDANT_1) must stay the active second arena.
# Run from the project folder: sh tests/second_arena_test.sh <godot executable>
GODOT=${1:-godot}
OUT=$(timeout 60 "$GODOT" --audio-driver Dummy --path . -- --level=7 --at=0,472,18,90 --delay=0.5 --unlock --profile=6 2>&1 | grep "^FPS")
echo "$OUT"
case "$OUT" in
	*"second CDANT_1 (active)"*) echo PASSED ;;
	*) echo FAILED; exit 1 ;;
esac
