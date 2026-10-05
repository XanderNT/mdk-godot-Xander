# Arena BSP and collision

How `MDKD3D.EXE` stores an arena's BSP and sweeps boxes and segments through it. Addresses are
`MDKD3D.EXE`; constants were read from the executable (f64 unless marked f32).

```
world section (arena_parse_world 0x422900)
┌──────────────┬───────────────┬──────────────┬─────────────┬─────────────────┐
│ materials    │ BSP nodes     │ triangles    │ vertices    │ node bitset     │
│ u32 n, 10·n  │ u32 n, 44·n   │ u32 n, 36·n  │ u32 n, 12·n │ u32 bytes, bits │
└──────────────┴───────────────┴──────────────┴─────────────┴─────────────────┘
node ──plane──► triangles on the plane: front list (seen from d ≥ 0), back list (d < 0)
     ──neg child (d < 0)── / ──pos child (d ≥ 0)──   (−1 = empty leaf)
```

The tree is **node-based**: triangles live on the node whose plane contains them; there's no
leaf array. A missing child (−1) is an empty leaf.

## Layout

### Node (44 bytes) ✅

| Off | Type | Meaning |
| --- | --- | --- |
| 0x00 | f32 nx, ny, nz, d | Plane: `dist(p) = n·p + d`. Unit normal (max ‖n‖−1 = 9e−8 over all data). |
| 0x10 | s16 | **Negative child** (taken when `dist < 0`), −1 = none. |
| 0x12 | s16 | **Positive child** (taken when `dist ≥ 0`), −1 = none. |
| 0x14 | u16 count, s16 first | **Front list**: triangles `first … first+count−1` facing the positive side. Empty: `count 0, first −1`. |
| 0x18 | u16 count, s16 first | **Back list**: triangles on the same plane facing the negative side. |
| 0x1c | u32 | Offset into the node bitset, made a pointer at load time. Always 0. No reader found ❓ |
| 0x20 | u32 | Same as 0x1c ❓ |
| 0x24 | ptr | Runtime: object list of the positive empty leaf (`0x40b438`, `0x40bddc` splice objects into it; the draw walk `0x40b9fc` empties it). 0 in the file. |
| 0x28 | ptr | Runtime: object list of the negative empty leaf. 0 in the file. |

- Node 0 is the root. Children always have a higher index than their parent (pre-order), every
  node but the root has exactly one parent, and the null-child count is `nodes + 1` ✅.
- Each triangle is in exactly one node list ✅. A triangle is in the front list when its winding
  is clockwise seen from the positive side (`−(v1−v0)×(v2−v0)` ∥ `+n`); 507 of 94 078 slivers
  disagree 🟡.
- Vertices lie on the node plane: 98.5 % within 0.01, 99.997 % within 1 unit 🟡 (built with a loose
  tolerance).
- 608 **point triangles** (`v0 = v1 = v2`; 435 of them `0,0,0`, material 0, flags 3) only carry a
  split plane. Their point is usually far from the plane. They never hit a ray; the box test
  (below) accepts one if its point is inside the box ❓ (never seen).

### Triangle (36 bytes)

See [formats.md](formats.md#world-section--arena_parse_world). Collision reads only `v0, v1, v2`
(+0, +2, +4, u16 vertex indices) and `flags` (+0x20): bit **0x20** = not solid (skipped by every
test here), 0x10 (not drawn) is ignored by collision ✅.

### After the vertices ✅

`u32 bytes`, then a bit set with one bit per node: `bytes = ceil(nodes / 8)`, all `0xFF` in every
arena and corridor. MTO arena blocks have 4 more bytes after it (garbage); SNI corridors end
exactly there. No code reads the bits ❓ (a vestigial PVS / node mask).

### Load-time fix-up (`arena_parse_world` 0x422900) ✅

```
p = world; nm = u32; mats = p; p += 10·nm (+2 if nm odd)
nn = u32; nodes = p; p += 44·nn
nt = u32; tris = p;  p += 36·nt
nv = u32; verts = p; p += 12·nv
bits = p + 4                         # skips the u32 byte count
for node in nodes: node+0x1c += bits; node+0x20 += bits
```

Children and triangle references stay indices. Outputs go to the arena record: `+0x0c` vertex
count, `+0x10` triangle count, `+0x14` node count, `+0x18` material count, `+0x1c` materials,
`+0x24` vertices, `+0x28` triangles, `+0x2c` nodes, `+0x30` bit set. Corridors (`LEVELnO.SNI`
entries, `0x431914`) use the same parser.

### Verification ✅

A Python check over the 114 worlds (60 MTO arenas + 54 SNI corridors of levels 3–8, 57 985 nodes,
96 935 triangles) found no error: unit normals, children in range or −1, pre-order, one parent
per node, triangle ranges in bounds and covering every triangle exactly once, vertex indices in
range, fields 0x1c–0x28 zero, bit set size and contents as above.

## Box sweep (`bsp_sweep_box` 0x4093e0) ✅

```
int bsp_sweep_box(A=EAX start, B=EDX end, h=EBX half extents, out=ECX,
                  iterations, nodes, tris, verts, slide_k, out_node*, callback)
```

Returns the hit **triangle pointer** (0 = none) and writes the box centre position to `out`.
All state is in globals `0x4d4e30`–`0x4d4eb4` (not re-entrant).

```
if out_node: *out_node = 0
if verts == 0 or nodes == 0: return 0                  # out untouched
D0 = B − A                                              # original move, kept for the slide test
slide_lim = slide_k · |D0|²                             # 0x4d4e58
M = 2.0 · (|hx| + |hy| + |hz|)                          # traversal margin 0x4d4e40, 2.0 @0x4934e8
slide = 1
while iterations ≥ 0 and slide:
    can_slide = iterations ≠ 0;  slide = 0;  hit_tri = 0;  t_best = 5000
    D = B − A
    sweep_node(root)                                    # sets t_best, P, hit_tri, hit_node, S
    if slide:                                           # slid: continue from contact to S
        A = P;  B = S
        callback?(hit_node, hit_tri, &P, 0)
    elif callback and hit_tri:
        callback(hit_node, hit_tri, &P, 1)
    iterations −= 1
if t_best ≥ 100 (@0x4934f0): out = B; return 0          # last pass free
out = P; if out_node: *out_node = hit_node; return hit_tri
```

So with `iterations = n` there are up to n+1 passes and only the last can't slide. A sweep that
slid and then ended free returns **0**, the contact being reported only through the callback.

### `sweep_node` 0x409680 ✅

```
sweep_node(N):
  loop:
    r  = |hx·nx| + |hy·ny| + |hz·nz|                    # box support radius on this plane
    dA = dist(A), dB = dist(B)
    sA = (dA ≥ −M ? 1 : 0) | (dA ≤ M ? 2 : 0)           # bands within M of the plane
    if dA ≥ −M and N.pos ≥ 0: sweep_node(N.pos)         # start side(s) first
    if dA ≤  M and N.neg ≥ 0: sweep_node(N.neg)
    sB = (dB ≥ −M ? 1 : 0) | (dB ≤ M ? 2 : 0)

    if (sA | sB) == 3 and |dB| ≤ |dA| on dA's side:    # (dA<0 and dA≤dB) or (dA≥0 and dB≤dA)
        off = dA ≥ 0 ? min(dA, r) : max(dA, −r)         # = dA if already penetrating
        den = D · n
        if den ≠ 0:
            t = −(dA − off) / den                       # box touches the plane
            if t ≤ t_best and t ≤ 1:
                P = A + t·D
                list = dA < 0 ? N.back : N.front        # only triangles facing the start
                tri = tri_list_test(P, N, h, list)
                if !tri:                                # retry where the centre crosses
                    t2 = min(−dA / den, 1)
                    tri = tri_list_test(A + t2·D, N, h, list)
                    if tri: t = t2                      # quirk: P stays at the first point
                if tri:
                    hit_tri = tri; hit_node = N
                    if can_slide:
                        if (D0·n)² ≤ slide_lim:         # not too head-on → slide
                            s = (1 − t) · den
                            S.xy = B.xy − s·n.xy
                            slide = 1
                            if (0 ≤ nz < 0.75 and den ≤ 0) or (−0.75 < nz ≤ 0 and den ≥ 0):
                                S.z = B.z                               # steep: XY slide only
                                pushout_xy(S, N, r + 0.01)              # 0x409d6c
                            else:
                                S.z = B.z − s·nz                        # 3D projection
                                pushout(S, N, r + 0.01)                 # 0x409cec
                        else:
                            slide = 0; S = P
                    t_best = t; contact = P             # 0x4d4e90

    new = sB & (sA ^ sB)                                # sides only the end reaches
    if new & 1: if N.pos < 0: return; N = N.pos
    elif new & 2: if N.neg < 0: return; N = N.neg
    else: return
```

- Constants: 0.75 @0x4934f8, −0.75 @0x493500, 0.01 @0x493508 ✅.
- Ties (`t == t_best`) go to the node visited last ✅.
- `pushout(p, N, e)`: `d = dist(p)`; if `|d| ≤ e`: `k = d ≥ 0 ? e − d : −d − e`, `p += k·n`
  (to exactly ±e on its side). `pushout_xy` does the same on x, y only ✅.
- The "steep" test is about the face the mover meets: a wall or an up-facing slope steeper than
  41.4° (nz < 0.75) is slid along horizontally without climbing; floors (nz ≥ 0.75) and
  down-facing surfaces get the full 3D projection ✅.

### Triangle list test (`bsp_leaf_tri_test` 0x409c40) ✅

```
for i in first … first+count−1:
    T = tris[i]
    if T.flags & 0x20: continue                         # not solid
    if box_tri_overlap(P, h, N.plane, verts[T.v0], verts[T.v1], verts[T.v2]): return T
return 0
```

### Box–triangle overlap (0x409de0) ✅

Projection test on the coordinate planes, using the **node** normal:

```
for k in 0..2 with |n[k]| ≥ 0.1 (@0x493510):
    (a, b) = ((1,2), (2,0), (0,1))[k]                   # table 0x490578
    q_i = (v_i[a] − P[a], v_i[b] − P[b])                # triangle in box space
    if rect(±h[a], ±h[b]) and triangle q don't overlap: return 0
return 1
```

2D overlap (exact for a convex triangle): outcodes per vertex (1 `u < −hu`, 2 `u > hu`, 4
`v < −hv`, 8 `v > hv`, strict). A vertex with code 0 → overlap. All codes share a bit → none.
Otherwise intersect the triangle with the strip `|u| ≤ hu`: its v range comes from vertices
inside the strip and the edge crossings of `u = ±hu`; overlap unless that whole range is above
`hv` or below `−hv`. (When no vertex is outside in u, use the strip `|v| ≤ hv` the same way.)

## Segment tests (0x421680, 0x421708) ✅

```
node* seg_test(A=EAX, B=EDX, nodes=EBX, tris=ECX, verts, out_point)  # 0 = no hit
```

Hit point → `out_point`; hit triangle → `0x42178c()` (global `0x57ebb4`). Front-to-back walk, so
the first hit is the nearest:

```
walk(N):                                                # 0x421470
  loop:
    dA = dist(A); dB = dist(B)
    near = dA < 0 ? N.neg : N.pos
    if near ≥ 0 and (r = walk(near)): return r
    if dA · dB ≥ 0: return 0                            # no strict crossing: far side not visited
    if mode accepts N:
        X = A + (B − A) · (−dA / ((B − A)·n))           # 0x4213e8 (factor 1 if the dot is 0)
        test the lists below at X; on hit: return N
    far = dA < 0 ? N.pos : N.neg
    if far < 0: return 0
    N = far
```

| Entry | Mode | Planes tested | Lists |
| --- | --- | --- | --- |
| 0x421680 | 0, "any" | all | front, then back (both faces) |
| 0x421708 | 1, "floor" | `|nz| ≥ 0.5` (@0x4948bc) | `nz ≥ 0.5`: front; else back (up-facing triangles only) |
| — | 2 (no caller) | `|nz| ≤ 0.707` (@0x4948b4) | front, then back |

List test (0x421350): skip flag 0x20, then point-in-triangle 0x42de60(X, n, v0, v1, v2): drop the
axis of the largest `|n|` (x → (y, z), y → (x, z), else (x, y)) and count crossings of the ray
`+u` from X with the edges (`v ≥ 0` counts as above). Odd = inside. Point triangles never hit.

## Kurt's move (`damp_collide_move` 0x465e34) ✅

```
int damp_collide_move(dx, dy, dz, slide_k, box*, out_node*)   # returns the hit triangle
box = box ?: (dz == 0 ? (0.6, 0.6, 2.5) @0x4920c0 : (0.4, 0.4, 2.5) @0x4920b4)
lift = dz == 0 ? 0.5 : 0.01                             # box bottom above the feet
A = (K.x, K.y, K.z + box.hz + lift)                     # K = feet 0x5739c0
if collisions(0x573a34):
    tri = bsp_sweep_box(A, A + d, box, &R, 4, Kurt's arena, slide_k, out_node, cb 0x466340)
    if !tri and second(0x573a68) and !streaming(0x573b00) and second active(0x573a6c)
            and !riding(0x573c30):
        tri = bsp_sweep_box(A, R, box, &R, 0, second arena, slide_k, out_node, cb)
    d = R − A
else if out_node: *out_node = 0
bbox 0x5739f4… = A ± box
objects (if 0x573a2c and 0x49001c): see below, changes d.xy only
K += d
return tri
```

- Callback 0x466340: `hit(Kurt's arena, tri, 0, kind 8, type −11, P, …)` (0x40d560, triangle
  group hits), for every pass that hit, even in the second arena ✅.
- Objects: Kurt's arena list (`arena+0x68`), active, alive, no flags 0x810, not the ridden one.
  Broad phase: the move's AABB vs `obj+0x198` (its z min is `K.z + 1` for the platform he stands
  on `0x573b84`), then each visible part box (`part+0x44`), grown by `box`, against the segment
  (0x45f588: XY slabs, z only rejects). First hit, or "start inside" (2): the end becomes the
  point slid along the face; later hits: the entry point. If any object was hit, the BSP is swept
  again (0 iterations, no callback) to the new end and its XY is used. `0x573c2c` = touched
  object ✅ (details of 0x45f588 🟡).

### Callers and parameters ✅

| Caller | Move | slide_k | Iterations | Box |
| --- | --- | --- | --- | --- |
| `damp_move` 0x46836a, `damp_control` 0x466906, 0x467460, `damp_buttslide` 0x469078, 0x46aa73, 0x46ae96, 0x46b711 | dx, dy, (0) | 0.75 | 4 (+0 second arena) | 0.6, 0.6, 2.5 at feet + 3.0 (0x46ae96 may pass its own) |
| `damp_gravity` 0x46a0fc | 0, 0, dz | 0.5 | 4 | 0.4, 0.4, 2.5 at feet + 2.51; `out_node = 0x573c14` |
| `camera_clearance` 0x418066, 0x418142 | dx, dy, 0 | 0.75 | 4 | default |
| Objects 0x45fec4 (flag 4) | velocity·dt | caller's | 2 (+2 other arena with flag 0x80000) | from bounds, see engine.md |
| `camera_clearance` direct sweep | head → camera | 0 | 0 | ±0.1 @0x490e20 |
| 0x43fa0c | | 0 | 0 | 3, 3, 1.5 @0x491e88 |
| Kurt's projectiles 0x462708 | | 0 | 0 | ±0.5 @0x491f24 |

### What the constants mean (derived from the code) 🟡

- **Slide rule** `(D0·n)² ≤ k·|D0|²`: with k = 0.75 a horizontal move slides when it meets the
  normal at ≥ 30°; within 30° of head-on it stops at the contact point.
- **Walk up**: a horizontal move into a face with `nz ≥ 0.75` (≤ 41.4°) is projected in 3D, so
  Kurt climbs; steeper faces are slid along in XY with z kept: walls.
- **Stand**: the vertical sweep (k = 0.5) slides when `|nz| ≤ 0.707` (≥ 45°): Kurt slides down,
  the pass ends free, `0x573c10 = 0` (airborne). Flatter: the pass stops, `0x573c10` = triangle
  (on the floor). So 41.4°–45° slopes hold him but can't be walked up.
- **Steps**: no step-up code. The horizontal box starts 0.5 above the feet, so anything lower is
  walked over. The vertical box starts 0.01 above the feet: on a step top `h` (0.01 < h < 0.5)
  above the feet, the down sweep starts penetrating, gets t = 0 and stops, so Kurt stays with his
  feet up to 0.49 inside the step until he walks off ❓ (not observed in game).

### Floor contact (`damp_gravity` 0x469efc) ✅

```
dz = vz·dt (gravity, updrafts: see gameplay.md)
if vz ≤ 0 and platform(0x573a18 & 2) and K.z + dz ≤ plat_z(0x573a1c):
    dz = plat_z + 0.05 (@0x497a14) − K.z; forced = 1
K0 = K
0x573c10 = damp_collide_move(0, 0, dz, 0.5, default, &0x573c14)   # floor triangle / plane
if !0x573c10 and !forced:
    if K.z < K0.z: vz = (K.z − K0.z) / dt                # actual fall rate (sliding)
elif 0x573be8: vz = (K.z − K0.z) / dt
elif vz > 0: vz = 0; grounded = 0; 0x573c10 = 0         # head hit a ceiling
else:
    if vz ≥ −100 (@0x497a1c) or 0x573bec:
        if |K − K0|² < (0.35 (@0x497a24) · dt)²: K = K0  # no creeping
    else: hard landing: damage 10 (0x46a77c), state 0x326
    vz = 0; grounded (0x573a18 |= 1)
    if !0x573c10: K.z = plat_z                          # forced platform contact
if K.z ≤ arena_min_z(arena+0x44e) − 50 (f32 @0x497a2c): health = 0, vz = 0
```

Downhill glue (`damp_vertical` 0x4694bc, before `damp_gravity`): on the floor, not jumping, not
falling: `n` = floor plane `0x573c14` flipped to `nz ≥ 0`; if `nz > 0.25` (@0x49797c) and the
frame's horizontal move `m` has `m.xy·n.xy > 0` (downhill): `vz = min(vz, −(m.xy·n.xy) / dt)` ✅.

## Open questions

- Node fields 0x1c/0x20 and the node bit set: no reader found ❓.
- The renderer's walk 0x40b9fc visits the viewer's side first (odd for painter's order) ❓.
- Step behaviour above is read from the code, not seen in game ❓.
