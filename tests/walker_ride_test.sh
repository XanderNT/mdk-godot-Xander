#!/bin/sh
# Bug test: riding LEVEL7's XD2 for 12 s Kurt stays on the floor; he must not collide with the
# walker he sits in (the original's moves ignore the ridden object), which threw him above the map.
# Run from the project folder: sh tests/walker_ride_test.sh <godot executable>
GODOT=${1:-godot}
OUT=$(timeout 60 "$GODOT" --audio-driver Dummy --path . -- --level=7 --delay=0.5 --at=46,4807,-25,270 --ride=XD2 --walk=12 --profile=13 2>&1 | grep -E "^riding|^Kurt at")
echo "$OUT"
Z=$(echo "$OUT" | grep "^Kurt at" | tr -d '(),' | cut -d' ' -f5)
echo "$OUT" | grep -q "^riding XD2" && awk "BEGIN { exit !($Z > -40 && $Z < 0) }" && echo PASSED && exit 0
echo FAILED
exit 1
