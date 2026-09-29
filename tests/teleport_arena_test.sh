#!/bin/sh
# Integration test: in LEVEL8, Kurt is teleported into GUNT_9, a room no connection leads to, which
# overlaps GUNT_1. He must stay in GUNT_9: the original only changes his arena by crossing a
# connection (or another teleport).
# Run from the project folder: sh tests/teleport_arena_test.sh <godot executable>
GODOT=${1:-godot}
OUT=$(timeout 60 "$GODOT" --path . -- --level=8 --delay=0.5 --teleport=GUNT_9,-20,70,5 --profile=3 2>&1 | grep "^FPS")
echo "$OUT"
case "$OUT" in
	*"arena GUNT_9,"*) echo PASSED ;;
	*) echo FAILED; exit 1 ;;
esac
