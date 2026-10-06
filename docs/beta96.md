# The 1996 beta demo ("96" levels)

`MDKDEMO.EXE` of 6 August 1996 is a non-interactive DOS demo ("only 15% complete") that plays back
recorded keys in three levels. The port runs these levels as playable extras:

| Port number | Demo folder | Contents |
| --- | --- | --- |
| 961 | `TRAVERSE/LEVEL1` | The city: `ARENA_1`–`ARENA10` and the corridors `CORR_1`–`CORR_9` between them |
| 963 | `TRAVERSE/LEVEL3` | `HMO_1`: the wheel `XW3` with its four guns, `XB3` riding it, the rolling `XM3` |
| 966 | `TRAVERSE/LEVEL6` | `OLYM_1`: mostly flat colours and glass, `XB2`, bombs, doors |

Everything below comes from the demo's files and from `MDKDEMO.EXE` (Watcom, DOS/4GW, an
unoptimised build, which makes it easy to read). Addresses are those of the executable's first
object loaded at 0x10000 ([`tools/python/beta96.py`](../tools/python/beta96.py) `--unpack` writes
that image). Legend: ✅ verified by loading and running the levels, 🟡 partly understood, ❓ guess.

## Running

The demo isn't part of the port. Unpack it and either set `MDK_BETA_DIR` to its folder (the one
with `TRAVERSE`), name it as `beta` in `mdk_paths.cfg` (see the README), or name the folder `BETA96` or `MDK (1996-08-06) (beta demo)` and put it in or
next to the retail game's folder or the project's.

- `--level=961`, `--level=963`, `--level=966` start a level directly.
- The main menu has a "Beta Levels" page when the demo is found. Its levels start at once: the
  demo has no briefing, fall or stream.
- The retail game is still needed: the menus, the fonts and the sprites the demo lacks come from
  it. Sounds come from the demo's archives only, so sounds the demo doesn't have stay silent.

## How the port runs it

The demo's formats are earlier versions of the retail ones, so [`MDKBeta`](../mdk/formats/mdk_beta.gd)
reads them into the objects the retail loaders make (`MDKDti`, `MDKMto`, `MDKArena`, `MDKCmi`,
`MDKSni`, `MDKTextureArchive`) and the game runs them unchanged. Names are in lower case in most
of the demo's files and are made upper case.

The scripts are an earlier version of the retail bytecode.
[`MDKBetaScriptDecoder`](../mdk/script/beta_script_decoder.gd) decodes them into the instructions
`MDKScriptVM` already runs; five things have no retail equivalent and got their own handlers (see
[Scripts](#scripts-)).

What the demo shows of itself: Kurt's sprites (`K_STILL`, `K_IDLE`, `K_RUN`, `K_SIDE`, `K_JUMP`,
`K_RJMP`, `K_CHUTE`, `K_SHOT`, `K_RUNFIR`, `K_HANG`, `K_LOOKU`), the health display (`SC_STAT`,
`SC_BSTAT`), the crosshair, the loading screens (`DEMO/SCREENn.LBB`), the music and an ambient
loop per arena.

## Files ✅

| File | Contents |
| --- | --- |
| `LEVELn.SET` | Text: start arena index, Kurt's position (and angle in levels 1 and 6); sky fill colours (top, bottom) and horizon row; four glass colours `r g b opacity` |
| `LEVELn.CON` | Text: the number of arenas; per arena its name, a portal count and the portals `C<arena index> <side> <z> <plane> <from> <to>` (not used by the port) |
| `Ln_PAL.LBP`, `ARENAS/<name>.LBP` | 768-byte palettes (8-bit RGB). An arena's differs from the level's only in colours 64–175, as in the retail game |
| `ARENAS/<name>.BSP` | The arena's geometry |
| `ARENAS/<name>.HOT` | Text: the arena's records |
| `LEVELnO.MTO` | The arenas' textures |
| `LEVELnS.MTI` | The level's textures and palette colour materials |
| `LEVELn.CMI` | Scripts, paths, models and animations |
| `LEVELnO.SNI`, `LEVELnS.SNI`, `TRAVERSE.SNI` | Sounds |
| `SCREENS/BACK_n.LBB` | The sky: 1804 × 360 palette indices without a header |
| `SPRITES/*.ABB` | RLE sprite animations: `u32 size`, then the retail layout (`MDKSpriteAnimation`) |
| `SPRITES/HUD/*.LBB` | Plain images: `u16 width, u16 height`, palette indices |
| `*.LBA` | Animated textures: `u32 frame count, u16 width, u16 height`, the frames |
| `DEMO/SCREENn.LBB`, `DEMO/*CITY.LBB`, `DEMOFALL.LBB` | Screens: a 768-byte palette, `u16 width, u16 height` (600 × 360), the pixels (the retail `LOAD_n.LBB` layout) |
| `DEMO/*.KEY` | The recorded keys (chunks `demo`, `keys`, `rate`, …); not decoded ❓ |

`LEVEL3`'s and `LEVEL6`'s corridors (`CHMO_1`, `COLYM_1`) are copies of the city's `CORR_1` with
no connection to their arena. `LEVEL6.CON` doesn't list `COLYM_1`, so it isn't loaded; the port
hides `CHMO_1` like the retail arenas nothing leads to (its textures aren't in the level).
`BACK_3.LBB` is a copy of the city's sky, whose colours only fit level 1's palette (the demo's
`HMO_1` is closed, so it's never seen); the port draws it in the nearest colours of level 3's.
`LEVEL3.SET` has no start angle; the port uses 90° (facing +Y, into the arena).

### `.BSP` (arena geometry) ✅

The retail world section (see [formats.md](formats.md#world-section--arena_parse_world)) with two
differences: material names are `char[16]`, and BSP nodes are 36 bytes (`f32 plane[4]`, then ten
`s16`) instead of 44. Triangles are the same 36 bytes. Their flags are 0, 1 ❓ or 2; flag 2 marks
simple shapes that are solid but not drawn (their UVs are all 0, and they lie under the detailed
triangles), which the port hides. There are no triangle groups. A bit field follows the
vertices ❓ (visibility between nodes, probably).

### `.HOT` (records) ✅

One record per line; the demo stores them in the 36-byte layout of the retail DTI records and with
the same type numbers (`level_load` 0x43104):

| Line | Type | Meaning |
| --- | --- | --- |
| `ASHOW <arena> x1 y1 x2 y2` | 1 | Walking into the rectangle shows that arena (`NONE`: no second arena) |
| `ALIEN <type> <id> <n> x y z` | 2 | An alien, run by the script `<arena>$<type>_<id>`; `n` isn't read when it's created ❓ |
| `MSWAP` + 6 numbers | 3 | A material swap ❓ (in no file) |
| `PICKUP <type> x y z` | 4 | A pickup (`SW_INTER`, `SW_DUMMY`, `SW_SMALL`, `SW_BONES`) |
| `HIDEPT <id> x y z` | 5 | A cover spot (`find_cover_spot`) |
| `CONNECT <id> x1 x2 y1 y2 z1 z2` | 6 | A doorway; the arena and its corridor each have one with the same id |

### `LEVELnO.MTO`, `LEVELnS.MTI` (textures) ✅

`LEVELnO.MTO` only has textures: `u32 count`, per arena `char[8] name, u32 offset`; at the offset
`u32 size`, then a texture archive. `LEVELnS.MTI` is `u32 size`, then a texture archive. The
archives have the retail entries (see [formats.md](formats.md#texture-archive-matmti-)) without the
16-byte name and size before the count; offsets are relative to the count.

### `.SNI` (sounds) ✅

`u32 size, u32 count`, then the retail 24-byte entries (offsets relative to file offset 4). The
demo's corridors aren't in them.

### `LEVELn.CMI` ✅

`u32 size`, then the four directories of the retail file (alien scripts, models, object type
scripts, arenas), with offsets relative to file offset 4. Then:

- **Arena records**: two strings, the arena's music (`SONG_ACTIVE`, `SONG_MEDIUM`, `SONG_LIGHT`)
  and its ambient loop (`AMB1`, `ARENA_1`, …). Arenas have no scripts yet: aliens and pickups
  come from the `.HOT` files.
- **Scripts** and their **paths**.
- **Models**, in the retail format.
- **Animations**, one after the other up to the end of the file. Scripts point at them directly
  (the retail scripts name animations kept in the arenas).

Path (0x32ff8): `u32 count`, the first position (3 `f32`), then `count − 1` steps of 3 `f32`, one
per frame. An object on a path adds its path speed × ticks to its place on it, takes the steps it
passed, turns to where it moved, and starts again at the first position after the last frame.
The port turns each path into a retail spline record with a key per frame.

Animation:

```
+0   u32 track count T
+4   u32 frame count F
+8   u32 track offset[T]         relative to the animation
     f32 root motion[F][3]
     f32 bounds[F][6]            the model's box in each frame
     u32 reference point count R, f32[R][F][3]
track: char[12] part name, u32 vertex count, f32 scale, f32 base[n][3],
       then for each of the other F − 1 frames s8 delta[n][3]
```

Compared with the retail format there's no speed, every frame has a delta record (so they carry
no frame numbers), no track uses matrices, and the box of each frame is stored.

## Scripts ✅

The interpreter is 0x47f6c (`tr_alcmd.c`). It works like the retail `script_run`: a restart point,
a wait timer, a gosub stack of 4, a timer per gosub level, the hit event cleared by `0xFF`. All
the scripts of the three levels decode (143, 337 and 640 instructions) and run without an opcode
the port doesn't handle.

- **Opcodes** 1–92 and 128–131 have the retail numbers. There's no 7, 30, 33, 55, 56 or 93+.
- **Branch actions**: `0x0C` goto, `0xF0` gosub, `0xF1` return (retail: `0x0C`, `0xFC`, `0xFD`;
  there's no gosub-or-else).
- **Gosub** and **return** are the opcodes `0xF0` (a count and that many targets, one picked at
  random, like goto) and `0xF1`.
- Values, comparisons and strings are encoded as in the retail scripts.

Opcodes whose operands differ from the retail ones:

| Opcode | Demo operands | Notes |
| --- | --- | --- |
| 2 `follow_path` | `off32 path` | Keeps the object's place on the path; resumes a path stopped by 21 |
| 3, 59 animations | `off32 animation` | Points at the animation itself |
| 4 `command_objects` | as retail, selectors 2, 4, 5 only, `u8 id` | |
| 5 | action | Branches when `obj+0x108` is 0 ❓ (in no script) |
| 21 | none | Stops the path where it is (the path time becomes negative) |
| 23 | none | Always sets the flag |
| 28 | action | Branches while an object in the alarm state was just deleted (`0xe21de`) |
| 41 | none | Does nothing |
| 61 `fire` | origin, `u8 aim`, `f32 range, accuracy, ?` | Fires a bolt without a script, see below |
| 77 `debug_msg` | `pstr` | |
| 81 `push_hit_dir` | value | Not multiplied by the frame time |
| 89 `play_sound` | `pstr` | At the object |
| 90 | `pstr, u8` | Looks an arena up by name ❓ (in no script) |
| 92 `if_anim_frame` | `u8 frame`, action | The frame itself, not the frame + 1 |
| 129 `blow_off_parts` | count, names | No mode |

`fire` (opcode 61, movement 0x3d in 0x4e2ec): the bolt starts at a reference point or a part's
centre, turned to the target when `aim` is set (with the random error of the retail `aim_target`
unless the accuracy is 100) or along the object's yaw. It flies 75 units a second, ends when it
hits the arena, and takes 10 off Kurt's health when it touches him. Kurt's health is 100 and only
goes down to 0: the demo has no death. The port's Kurt dies as in the retail game.

## Kurt 🟡

The demo's `damp_animate` (0x36cf4) loads 17 animations (`K_BCKUP` and `K_FIRE_M` are in the folder
but never loaded) and has states the retail game dropped. In the demo's levels the port adds:

- **Rolls** (states 701 and 702, `K_ROLLL` / `K_ROLLR`): the animation plays once, a frame per
  tick, while Kurt moves sideways at 8 × 0.05 units per tick and turns 90° the other way over the
  animation, a quarter circle around what he faces. The two files are identical (a roll to the
  right), so the port mirrors the frames for the roll to the left. No code of the demo asks for these states, so
  the keys are the port's: **Z** rolls left, **C** right.
- **The helmet** (states 703 and 900, `K_HELM`): it goes on before sniper mode starts and comes
  off, the same frames backwards, when it ends.
- **Backing up** shows `K_BCKUP` instead of the run played backwards ❓ (the port's guess at what
  the file is for).

State 704 (`K_LOOKU` / `K_LOOKD`, the frame picked by a pitch of ±30° the look keys change) isn't
done: the port's Kurt has no pitch outside sniper mode.

The chain gun's hits name a part in these levels (`MDKScriptRuntime._beta_hit_part`): the demo's
scripts test the hit part of every object (`XW3`'s guns, `XB2`'s eyes and nose, the grunts'
heads). How the demo picks the part wasn't read ❓; the port takes a shown part near the line
Kurt fires along.

Wall and model textures use palette index 0 as black; the port makes it opaque (the retail game
keeps index 0 for the see-through parts of effects).

Triangle flag 2 is skipped by the demo's drawing (0x15d90) and by two loops that test triangles
(the callers of 0x2c6d0) ❓; the port doesn't draw these triangles and has them stop Kurt but not
the scripts' rays (shots, lines of sight).

### Teleports

`TRAVERSE/TELEPORT.TXT` has a line `<arena> x y z` per digit; the demo takes Kurt to the line of
a digit typed when the level has that arena (0x440c4). The port does it on a digit while **T** or **Alt** is held, in
the demo's levels (the digits alone pick items). The city needs it: `ARENA_4` is entered at the bottom
(z −139) and left at the top (z −29), and the demo's Kurt has no way up, as its vertical movement
(0x3a2b8) knows only the jump, gravity and the chute; teleport 4 is the top platform. Level 6 has
one line, the file's 11th (`OLYM_1`, marked `tel0`); the port counts only the lines of the
level's own arenas, so it is Alt + 0 there.

## Not done

- The demo's recorded keys (`DEMO/*.KEY`) aren't played back.
- The freefall part of the demo isn't in the unpacked folder (`freefall/…` files are missing).
- The sniper screen (`SCREENS/SNIPER*`), the 1996 pickup icons (`PICKUPS.ABB`, 4 frames) and
  Kurt's `K_LOOKU`, `K_LOOKD` and `K_FIRE_M` sprites aren't used: the retail sniper mode and
  inventory are.
- Pickups (only `ARENA10` has them) weren't tested; `SW_SMALL` has no retail item.
- Portals (`LEVELn.CON`), `MSWAP`, the third number of `ALIEN`, triangle flag 1 and the bit field
  at the end of the `.BSP` files aren't understood.
