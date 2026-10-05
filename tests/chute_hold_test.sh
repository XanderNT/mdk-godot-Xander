#!/bin/sh
# Bug test: holding jump from the take-off opens the chute once Kurt falls (`damp_vertical`
# 0x4694bc: falling and the key held, nothing else), without letting go and pressing it again.
# Run from the project folder: sh tests/chute_hold_test.sh <godot executable>
GODOT=${1:-godot}
OUT=$(timeout 60 "$GODOT" --audio-driver Dummy --path . -- --level=7 --delay=1 --jump --profile=1.3 2>&1 | grep "^Kurt shows")
echo "$OUT"
case "$OUT" in
	"Kurt shows K_CHUTE"*) echo PASSED ;;
	*) echo FAILED; exit 1 ;;
esac
