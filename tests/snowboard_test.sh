#!/bin/sh
# Integration test: in LEVEL4, Kurt is teleported just above the snowboard of CMEAT_3. He must land
# on it (it's standable though Kurt passes through it otherwise), ride it, and break through the ice
# wall (triangle group 3) on the way: after 12 seconds he's past y 4500.
# Run from the project folder: sh tests/snowboard_test.sh <godot executable>
GODOT=${1:-godot}
OUT=$(timeout 60 "$GODOT" --audio-driver Dummy --path . -- --level=4 --delay=0.5 --teleport=CMEAT_3,420,4285,-570 --profile=12 2>&1 | grep "^riding\|^Kurt at")
echo "$OUT"
Y=$(echo "$OUT" | sed -n 's/^Kurt at ([^,]*, \([-0-9.]*\),.*/\1/p')
case "$OUT" in
	*"riding XSNOWB"*) ;;
	*) echo FAILED; exit 1 ;;
esac
if [ "${Y%.*}" -gt 4500 ]; then echo PASSED; else echo FAILED; exit 1; fi
