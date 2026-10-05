# Animated textures

## Loader: `texture_archive_register` 0x422c00 ✅

Builds a 0x38-byte material per archive entry (`matdef`, loadmats.c):

| Offset | Value |
| --- | --- |
| +0x00 | log2(width) |
| +0x04 | width |
| +0x08 | height (palette index for colours) |
| +0x0c | flags: `kind & 0xFFFF \| frame_count << 16` (animated), `kind` (static), -1 (colour) |
| +0x10/+0x18 | width mask / ~mask |
| +0x1c | entry `value` |
| +0x20 | entry f32 (3.5) |
| +0x24 | pixel pointer (first frame) |
| +0x28 | name (8 bytes) |
| +0x34 | D3D texture (FUN_00474978 uploads `width × height` at +0x24) |

```
if kind & 0x10000 or kind & 0x20000:   // animated
    n = u32; w = u16; h = u16; pixels = header + 8
    flags = (kind & 0xFFFF) | n << 16   // 0x10000 vs 0x20000 is dropped
else:
    w = u16; h = u16; pixels = header + 4
```

- Header is the same for both kinds; only the data after the first frame differs ✅.
- Low bits: bit 0 (0x10001) is passed to the D3D texture (+0x10 & 1, FUN_00474c9c), selecting the
  transparent pixel format when the card supports it ❓.
- f32 field: 3.5 in every entry of every archive (static textures and colours too). Not read by
  the animation code ❓ (unused).

## Kind 0x10000 / 0x10001: full frames ✅

`n` frames of `w × h`, back to back. Frame chosen by the owner (sprites 0x407048 by life,
explosions 0x4126ac by object time), not by a global clock.

## Kind 0x20000: base frame + delta stream ✅

Only `M_COMM`. Layout after the `n, w, h` header:

```
u8   base[w*h]            // frame 0
f32  current_frame        // runtime state, 0.0 in the file
u32  offsets[2*n]         // relative to the end of current_frame (T)
                          //   offsets[k]     = control block of delta k
                          //   offsets[n + k] = data block of delta k
...  blocks               // ctrl0, data0, ctrl1, data1, ...
```

Control block (FUN_0042dadc 0x42dadc), units are dwords (4 pixels):

```
u16 start; u16 runs; then runs × (u8 copy, u8 skip)
dst = base + start*4
for each run: copy `copy` dwords from data; dst += (copy + skip) dwords
```

Delta k turns frame k into frame k+1; delta n-1 turns frame n-1 back into frame 0 (verified:
applying all 6 to `M_COMM` restores the base image). The image is patched in place, then the D3D
texture is released and re-uploaded.

`M_COMM` (DANT_5): `n = 6`, 128 × 129, offsets `48 188 3048 5880 6464 6824 | 76 284 3140 5948 6528 6872`.
Deltas touch rows 2–59. Row 128 is never changed and holds no image ❓ (the original uses h = 129,
so 1/h = 1/129 for UVs).

## Run time: `texture_set_frame` 0x42d9c0 ✅

Called only from script opcodes 90 (0x452c2c, model texture) and 133 (0x452d69, arena texture).
No per-frame timer drives it.

```
texture_set_frame(mat, relative, value):
    hdr = mat.pixels + w*h; cur = f32 hdr; n = mat.flags >> 16
    target = relative ? cur + value : value
    wrap target into [0, n)
    while trunc(cur) != trunc(target):     // 0x4797c0 = frndint with chop
        apply delta trunc(cur)
        cur += 1; if cur >= n: cur -= n
    f32 hdr = target
    if changed: re-upload D3D texture
```

Forward loop only (no ping-pong). Opcode 133: mode 0 absolute (`value - 1`), mode 1
`value × g_frame_dt` (frames/s), else `value` frames.

### Scripts using it (find_opcode.py, opcode 90 unused) ✅

| Level | Arena | Use |
| --- | --- | --- |
| 4 | MEAT_3 | `M_COMM` 6 fps / 12 fps |
| 7 | DANT_5 | `M_COMM` 6 fps / 12 fps |

DANT_5 main loop gosubs 0x11ab7 every frame:

```
if arena flag 7: return              // device destroyed: frozen
4/s chance: COMM / BEEP sound
if arena flag 8: M_COMM += 12 * dt   // after first hit (group 16 hit handler sets flag 8, boss bar)
else:            M_COMM +=  6 * dt
```

Flag 7 is set when the counter reaches 200 (group 16 shattered).

## Inventory (all archives) ✅

| Name | Kind | Frames | Size | Where |
| --- | --- | --- | --- | --- |
| M_COMM | 0x20000 | 6 (delta) | 128×129 | L4 MEAT_3, L7 DANT_3, DANT_5, TLEVEL DANT_3/5 |
| EXPLODE | 0x10001 | 26 | 128×128 | LEVEL3–8S.MTI, FALL3D_1–5.MTI |
| TRAIL | 0x10001 | 11 | 64×64 | LEVEL3–8S.MTI |
| SB_MED / SB_SMA | 0x10001 | 15 | 32² / 16² | LEVEL3–8S.MTI |
| SL_BIG / SL_MED / SL_SMA | 0x10001 | 30 | 64² / 32² / 16² | LEVEL3–8S.MTI |
| BUBB | 0x10001 | 6 | 30×31 | LEVEL3–8S.MTI |
| BUBB_POP | 0x10001 | 4 | 33×30 | LEVEL3–8S.MTI |
| PULSE | 0x10000 | 30 | 32×32 | LEVEL3S.MTI |
| FIRE | 0x10000 | 36 | 64×73 | LEVEL3–5S.MTI |
| BONEFLC | 0x10000 | 24 | 64×36 | LEVEL4S.MTI |
| SW_EWJ | 0x10000 | 1 | 32×28 | LEVEL3–8S.MTI |

DANT_3's `M_COMM` has no script: always frame 0. Kind 2 (static floors/tubes, e.g. `D3_FLR`,
`H1_FLR`, `M_TUBE`) is not animated.

## Port fix

- `MDKTexture.parse_animated`: if `kind & 0x20000`, read the base frame, then rebuild frames
  1..n-1 by applying deltas 0..n-2 (above); stack them as today. Keep h = 129.
- Shader: don't run `M_COMM` on `TIME × 15`. Drive its frame from opcode 133 (per arena,
  `frame = fmod(frame + value × dt, n)`, `floor`); fallback constant 6 fps for DANT_5/MEAT_3,
  frame 0 elsewhere.
