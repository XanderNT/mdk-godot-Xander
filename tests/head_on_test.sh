#!/bin/sh
# Integration test: in LEVEL7 Kurt runs into a wall 25° off head-on (within 30°); the original stops him
# there instead of sliding along (`damp_collide_move`: slides only if (m·n)² ≤ 0.75·|m|²), so he
# must be at the same place after 3 and after 5 seconds.
# Run from the project folder: sh tests/head_on_test.sh <godot executable>
GODOT=${1:-godot}
A=$(timeout 60 "$GODOT" --path . -- --level=7 --at=0,100,12,25 --delay=0.5 --walk=3 --profile=0.2 2>&1 | grep "^Kurt at" | cut -d' ' -f3-5)
B=$(timeout 60 "$GODOT" --path . -- --level=7 --at=0,100,12,25 --delay=0.5 --walk=5 --profile=0.2 2>&1 | grep "^Kurt at" | cut -d' ' -f3-5)
echo "after 3 s: $A"
echo "after 5 s: $B"
[ -n "$A" ] && [ "$A" = "$B" ] && echo PASSED && exit 0
echo FAILED
exit 1
