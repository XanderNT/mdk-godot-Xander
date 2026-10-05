# The practice room (LEVEL7 `DANT_2`)

## Geometry ✅

All in `DANT_2` (LEVEL7O.MTO). Red glass = `GLASS2` (special material 1025, level 7: 255,0,0 a48);
`GLASS1` isn't used in `DANT_2`.

| What | Where | Top |
| --- | --- | --- |
| Pedestal A (open pentagonal glass tube, textured `D2_FLR4` top) | x −25..−9, y 934..950 | z −20 |
| Pedestal B | x −32..−16, y 953..968 | z −15 |
| Pedestal C | x −31..−15, y 971..984 | z −10 |
| Pedestal D | x −16..0, y 984..999 | z −7 |
| Pedestal E | x 1..17, y 977..992 | z −1 |
| Glass gable roof | y 879..999 | z 9..22 |
| Ledge, group 3 (glass "eyes" in its front wall y 1002, z 76..85) | x −39..−19, y 1002..1023 | z 76 |
| Ledge, group 4 (front y 1035, glass z 78..87) | x −18..13, y 1035..1055 | z 78 |
| Ledge, group 5 (front y 1011, glass z 90..99) | x 14..38, y 1011..1032 | z 90 |

Floor z −27. Glass triangles have no 0x20 flag: they stop BSP rays (0x421350 skips only 0x20) ✅.

## Who stands where ✅

- `XGHTARG` (spawn 0x4f31.., script 0x52a8) and the three `XG` (0x4ff6.., scripts 0x5037/0x505d/0x5083)
  use the **ledges**, not the pedestals. Spawn points are behind and 20 below each ledge. Jump
  (gosub 0x53b8): `flags_set 6`, `add_vel_local(-20,0,40)` at yaw −90 → v = (0, −20, 40),
  g = 32 → lands after 1.81 s, 36 units forward, on z 76/78/90. The `XG` wait first (`flags_clear 6`,
  hanging at the spawn point, `if_chance_per_second 1`), then jump the same way.
  The port does this correctly (traced: (−35,1010,76), (−3,1043,78), (33,1019,90)).
- The **pedestals** belong to the `XGTARG` (big target shield) that `XGEN` (0,967,−27) spits out once
  the crate `XBANG` is shot (flag 1.7, 0x4c8d): scripts 0x5437/0x546f/0x54a7, `add_vel_local(0,0,25|30|40)`,
  then `move_to_point 30 → (−17,941,−22) / (−24,959,−15) / (−23,977,−10)` = pedestals A, B, C.
  These are the grunts the bug report is about.

## Spawn z ✅

`enemy_spawn` 0x45cdec copies (x,y,z) to obj+0x10.. as is: z absolute, no floor snap, no bounds or
height offset. Port matches.

## Bug 1: XGTARG hang against pedestals B and C ✅

`move_to_point` (opcode 200, handler 0x459555):

```
d = target − pos
L = |dx| + |dy| (+ |dz| unless flags & 0x2 gravity); L < 0.5 → action; L = max(L, 0.1)
push[k] = clamp(speed·dt·d[k]/L, to ±|d[k]|) / dt   for x, y (and z without gravity)
```

Port (`script_vm.gd`, case 200): Euclidean normalization, and z dropped on flag 0x4 (collides)
instead of 0x2 (gravity). Euclid makes diagonal moves faster: towards B 28.5 instead of 22.5 u/s
along x, so the XGTARG reaches the side of the pedestal 0.13 s earlier, lower in its arc
(z −17.4 / −11.5 against tops −15 / −10). It sticks to the glass, `vz = 0` on every wall hit,
and slides down ~1 u/s. Pedestal A (top −20) is low enough, so the first one lands.

Fix: Manhattan normalization, per-axis clamp, gravity flag 0x2. Tested in a copy: all three land
(−17,941,−20), (−24,959,−15), (−23,977,−10). Not yet applied to the port.
❓ The original *sets* obj+0x294.. (=) where the port adds (+=); matters only with other pushes
the same frame.

## Bug 2: chain gun does nothing to the target grunt ✅ (original behaviour)

- The chain gun (0x41a304) sets the hit event obj+0x21e = −1 except on weak parts: never a part
  index. So `if_hit_part TARGET01`, `TARGET` or `ANY` can't fire from the chain gun.
- `XGTARG`: gosub 0x551c runs `set_health 10000` every frame; it dies only by a head hit, a part hit
  with weapon 2/3/4/−5, or 13 part hits (0x565e). Chain gun: 1 damage per tick, reset next frame.
- `XGHTARG`: health 100 after landing, so 100 ticks of chain gun would kill it, but the aim test
  needs a clear ray (glass roof, ledge walls) and distance < size + 140; from the floor it fails.
- Hints `DA2_SNIP` "Shoot targets using sniper mode", `DA2_GLAS` "Sniper OVER the red glass".
  Sniper rounds give part events (`sniper_rounds.gd` hit_event = part + 1). Port is right.
