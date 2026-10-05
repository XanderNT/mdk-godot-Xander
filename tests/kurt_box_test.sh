#!/bin/sh
# Bug test: `if_kurt_in_box` (opcode 103) with a box whose corners are given backwards (LEVEL7
# DANT_3: z from -77 to -200) must test the axes without an error (it's never true, as the
# original's comparisons).
# Run from the project folder: sh tests/kurt_box_test.sh <godot executable>
GODOT=${1:-godot}
OUT=$(timeout 60 "$GODOT" --audio-driver Dummy --path . -- --level=7 --delay=0.5 --teleport=DANT_3,0,1300,-60 --profile=2 2>&1)
COUNT=$(echo "$OUT" | grep -c "AABB size is negative")
echo "negative AABB errors: $COUNT"
echo "$OUT" | grep -q "^FPS" && [ "$COUNT" -eq 0 ] && echo PASSED && exit 0
echo FAILED
exit 1
