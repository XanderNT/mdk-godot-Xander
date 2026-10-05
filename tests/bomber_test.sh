#!/bin/sh
# Integration test: in LEVEL7's DANT_5 the comm device calls the XE; Kurt lands on it and rides it,
# the view sinks into it, the script unlocks the controls and Kurt drops a bomb (`MDKBomber`).
# Run from the project folder: sh tests/bomber_test.sh <godot executable>
GODOT=${1:-godot}
OUT=$(timeout 120 "$GODOT" --audio-driver Dummy --path . -- --level=7 --delay=0.5 --teleport=DANT_5,100,2320,-60 --bomber=drop --profile=0.5 2>&1 | grep -E "^riding|^bomber|XBN_BOMB|SCRIPT ERROR")
echo "$OUT"
case "$OUT" in
	*"SCRIPT ERROR"*) echo FAILED; exit 1 ;;
	*"riding XE"*"bomber view 0.0, locked false, bombs 9"*"XBN_BOMB"*) echo PASSED ;;
	*) echo FAILED; exit 1 ;;
esac
