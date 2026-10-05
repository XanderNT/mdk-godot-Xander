#!/bin/sh
# Integration test of full saves (F2): LEVEL7 is saved after a walk, then loaded; the state taken
# again right after loading must be the same (same hash), and the level must run on without
# script errors.
# Run from the project folder: sh tests/snapshot_test.sh <godot executable>
GODOT=${1:-godot}
SAVED=$(timeout 90 "$GODOT" --audio-driver Dummy --path . -- --level=7 --delay=0.5 --walk=3 --snapshot=TESTSNAP 2>&1 | grep -E "^snapshot hash|SCRIPT ERROR")
LOADED=$(timeout 90 "$GODOT" --audio-driver Dummy --path . -- --load=TESTSNAP --delay=0.5 --profile=3 2>&1 | grep -E "^restored hash|SCRIPT ERROR")
# The test save isn't left in the game's list (Godot's user folder on Windows or Linux).
SAVES="${APPDATA:-$HOME/.local/share}/Godot/app_userdata/MDK/saves"
[ -d "$SAVES" ] || SAVES="$HOME/.local/share/godot/app_userdata/MDK/saves"
rm -f "$SAVES/TESTSNAP.sav"
echo "$SAVED"
echo "$LOADED"
case "$SAVED$LOADED" in
	*"SCRIPT ERROR"*) echo FAILED; exit 1 ;;
esac
[ -n "$SAVED" ] && [ "${SAVED#snapshot }" = "${LOADED#restored }" ] && echo PASSED && exit 0
echo FAILED
exit 1
