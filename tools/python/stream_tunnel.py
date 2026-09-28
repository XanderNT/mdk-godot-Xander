"""Dumps the data of MDK's stream (game state 5, `STREAM/`) and replays the tunnel generator.

Usage:
    python stream_tunnel.py <STREAM dir> [--exe MDKD3D.EXE] [--png <out dir>]
                            [--obj <file.obj>] [--segments N] [--level L] [--difficulty D]
                            [--seed S]

Prints:
- the entries of STREAM.BNI (name, file offset, size);
- the pixel-index range of the images BG (600x360), PLANET (128x128), LIGHT (64x64);
- the 64-colour tunnel ramp built by 0x433b50 from the table at 0x491ccc (read from the exe
  when --exe is given, else the copy below), as RGB, with the 6 distance alphas;
- a replay of the generator 0x434838 (see docs/stream_tunnel_draft.md): per segment the origin,
  the forward axis, the radius, the turn angles, and a check that the wall planes face inwards.

--obj writes the generated tunnel (rings of 16 points, 2 triangles per quad, vertex colours from
the ramp) as a Wavefront OBJ with `v x y z r g b` lines (world Z up, forward starts at +Y).
--png writes BG/PLANET/LIGHT as PNGs with the PAL palette (needs Pillow; indices 0-63 really
come from the global palette 0x5735e4, PAL's first 192 bytes are used here instead).
"""
import math
import os
import struct
import sys

# 0x491ccc: start colour (3 bytes + pad), then (b, g, r, count) until b = g = r = 0.
# Bytes are in B, G, R order (RGBQUAD order, see the draft doc).
RAMP_TABLE = bytes.fromhex(
    "5acede00" "217b8c08" "08317b08" "84a5c608" "8c7b8408"
    "e7c6d608" "84a5c608" "08317b08" "5acede08" "00000000")
ALPHAS = (0x5A, 0x55, 0x50, 0x3C, 0x28, 0x0F)  # 0x5744d8 + level * 0x100, byte 3


def read_bni(path):
    data = open(path, "rb").read()
    size, count = struct.unpack_from("<II", data, 0)
    entries = []
    for i in range(count):
        name, offset = struct.unpack_from("<12sI", data, 8 + i * 16)
        entries.append((name.split(b"\0")[0].decode("latin1"), offset + 4))
    ends = sorted(o for _, o in entries) + [len(data)]
    out = {}
    for name, offset in entries:
        end = min(e for e in ends if e > offset)
        out[name] = (offset, data[offset:end])
    return [n for n, _ in entries], out


def ramp_table_from_exe(exe):
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "ghidra"))
    import const  # noqa: E402
    data = open(exe, "rb").read()
    return const.read(data, const.sections(data), 0x491CCC, 0x40)


def build_ramp(table):
    """0x433b50: 64 colours (B, G, R) interpolated between the table's key colours."""
    prev = list(table[0:3])
    out = []
    i = 4
    while len(out) < 64:
        b, g, r, n = table[i:i + 4]
        i += 4
        if b == 0 and g == 0 and r == 0:
            break
        for k in range(n):
            out.append(tuple((new * k + old * (n - k)) // n for new, old in zip((b, g, r), prev)))
        prev = [b, g, r]
    return out  # list of (b, g, r)


class Rand:
    """Watcom rand(): state = state * 0x41c64e6d + 0x3039, returns (state >> 16) & 0x7fff."""

    def __init__(self, seed=1):
        self.state = seed & 0xFFFFFFFF

    def __call__(self):
        self.state = (self.state * 0x41C64E6D + 0x3039) & 0xFFFFFFFF
        return (self.state >> 16) & 0x7FFF


def rot_xyz(a, b, c):
    """0x46de70 with scale 1: rows of Rx(a) * Ry(b) * Rz(c), angles in degrees."""
    sa, ca = math.sin(math.radians(a)), math.cos(math.radians(a))
    sb, cb = math.sin(math.radians(b)), math.cos(math.radians(b))
    sc, cc = math.sin(math.radians(c)), math.cos(math.radians(c))
    return [[cb * cc, -cb * sc, sb],
            [sa * sb * cc + ca * sc, ca * cc - sa * sb * sc, -sa * cb],
            [sa * sc - ca * sb * cc, ca * sb * sc + sa * cc, ca * cb]]


def mat_mul(p, l):
    return [[sum(p[i][k] * l[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mat_vec(m, v):
    return [sum(m[i][k] * v[k] for k in range(3)) for i in range(3)]


def sub(a, b):
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def norm(a):
    length = math.sqrt(sum(x * x for x in a))
    return [x / length for x in a] if length > 0 else a


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def limits(level, difficulty):
    """0x433b50: max turn angle 0x520898, min/max radius 0x52089c/0x5208a0."""
    half = level >> 1
    if difficulty == 0:
        return level + 6.0, 10.0 - half, 17.0 - half
    if difficulty == 1:
        return level + 8.0, 10.0 - half, 17.0 - level
    return level + 10.0, 10.0 - half, 13.0 - half


def generate(segments, level=0, difficulty=1, seed=1):
    """Replays 0x433b50 + 0x434838 for `segments` rings, consuming rand() in the game's order
    (the light sprites spawned by 0x434f64 use 4 calls each; their data is not kept)."""
    rnd = Rand(seed)
    max_angle, r_min, r_max = limits(level, difficulty)
    final = level > 3                     # 0x520894, the Gunta variant
    rot = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
    org = [0.0, 0.0, 0.0]
    radius = 10.0
    angles = [0.0, 0.0, 0.0]              # 0x520500 (about X), 0x520504 (about Y), 0x5204fc (about Z)
    shade_a = rnd() & 0x3F                # 0x520510
    shade_b = rnd() & 0x3F                # 0x520514
    shade_t = 0.0                         # 0x520518
    rings, colours, planes, info = [], [], [], []
    for w in range(segments):
        if final and w > 186:
            break
        if w > 0:
            l_rot = rot_xyz(angles[0], angles[1], angles[2])
            org = [org[i] + rot[i][1] * 10.0 for i in range(3)]   # prev * (0, 10, 0)
            rot = mat_mul(rot, l_rot)
            for j in range(3):                                     # 0x438f50: normalise columns
                n = math.sqrt(sum(rot[i][j] ** 2 for i in range(3)))
                for i in range(3):
                    rot[i][j] /= n
            if rnd() & 3:                                          # 3 in 4: a LIGHT sprite (0x434f64)
                for _ in range(4):                                 # x, z, size, speed
                    rnd()
        ring = []
        for j in range(16):
            th = math.radians(22.5 * j)
            jx = (rnd() - 0x4000 + 163840) * 6.10352e-06
            jz = (rnd() - 0x4000 + 163840) * 6.10352e-06
            local = [radius * math.sin(th) * jx, 0.0, radius * math.cos(th) * jz]
            p = mat_vec(rot, local)
            ring.append([p[0] + org[0], p[1] + org[1], p[2] + org[2]])
        if w > 0:
            prev = rings[-1]
            shade = int((1.0 - shade_t) * shade_a + shade_b * shade_t)
            cols, pls = [], []
            for j in range(16):
                n = (w + j) & 31
                cols.append(((n if n < 16 else 31 - n) + shade) & 0x3F)
                j1 = (j + 1) & 15
                na = norm(cross(sub(ring[j1], prev[j]), sub(prev[j1], ring[j1])))
                nb = norm(cross(sub(ring[j], prev[j]), sub(ring[j1], ring[j])))
                pls.append((na, -dot(na, prev[j]), nb, -dot(nb, prev[j])))
            colours.append(cols)
            planes.append(pls)
            shade_t += 0.1
            if shade_t > 1.0:
                shade_t = 0.0
                shade_a = shade_b
                shade_b = rnd() & 0x3F
        rings.append(ring)
        info.append((org[:], [rot[0][1], rot[1][1], rot[2][1]], radius, angles[:]))
        if not final or w + 1 <= 168:
            for i in (2, 0, 1):                                    # 0x5204fc, 0x520500, 0x520504
                angles[i] += (rnd() - 0x4000) * 6.10352e-05
        else:
            for i in range(3):
                angles[i] = min(angles[i] + 1.0, 0.0) if angles[i] <= 0 else max(angles[i] - 1.0, 0.0)
        for i in range(3):
            if abs(angles[i]) > max_angle:
                angles[i] *= 0.8
        radius += (rnd() - 0x4000) * 6.10352e-05
        if radius < r_min:
            radius = r_min
        elif radius > r_max:
            radius = r_max
    return rings, colours, planes, info


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    stream = argv[1]
    opts = {}
    i = 2
    while i < len(argv):
        opts[argv[i]] = argv[i + 1]
        i += 2
    names, entries = read_bni(os.path.join(stream, "STREAM.BNI"))
    print("STREAM.BNI:")
    for name in names:
        offset, blob = entries[name]
        print(f"  {name:10s} 0x{offset:06x} {len(blob):7d}")
    pal = entries["PAL"][1][:768]
    for name in ("BG", "PLANET", "LIGHT"):
        blob = entries[name][1]
        w, h = struct.unpack_from("<HH", blob, 0)
        px = blob[4:4 + w * h]
        used = sorted(set(px))
        print(f"{name}: {w}x{h}, indices {used[0]}..{used[-1]}, {len(used)} distinct,"
              f" {sum(1 for p in px if p == 0)} zero pixels")
    table = ramp_table_from_exe(opts["--exe"]) if "--exe" in opts else RAMP_TABLE
    ramp = build_ramp(table)
    print("Tunnel ramp (index: R G B), alphas per distance level:", [hex(a) for a in ALPHAS])
    for k in range(0, 64, 8):
        print("  " + "  ".join(f"{k + j:2d}:{c[2]:3d},{c[1]:3d},{c[0]:3d}" for j, c in enumerate(ramp[k:k + 8])))
    level = int(opts.get("--level", 0))
    difficulty = int(opts.get("--difficulty", 1))
    rings, colours, planes, info = generate(int(opts.get("--segments", 40)), level, difficulty,
                                            int(opts.get("--seed", 1)))
    print(f"Generator (level {level}, difficulty {difficulty}): limits {limits(level, difficulty)}")
    for w, (org, fwd, radius, ang) in enumerate(info[:40]):
        print(f"  seg {w:3d} origin ({org[0]:8.2f},{org[1]:8.2f},{org[2]:8.2f}) forward"
              f" ({fwd[0]:5.2f},{fwd[1]:5.2f},{fwd[2]:5.2f}) r {radius:5.2f}"
              f" angles ({ang[0]:5.2f},{ang[1]:5.2f},{ang[2]:5.2f})")
    inside = 0
    total = 0
    for s, pls in enumerate(planes):
        centre = [sum(p[i] for p in rings[s] + rings[s + 1]) / 32 for i in range(3)]
        for na, da, nb, db in pls:
            total += 2
            inside += (dot(na, centre) + da > 0) + (dot(nb, centre) + db > 0)
    print(f"Wall planes with the tunnel axis on their positive side: {inside}/{total}")
    if "--obj" in opts:
        with open(opts["--obj"], "w") as f:
            for s, ring in enumerate(rings):
                for j, p in enumerate(ring):
                    c = ramp[colours[min(s, len(colours) - 1)][j]] if colours else (255, 255, 255)
                    f.write(f"v {p[0]:.4f} {p[1]:.4f} {p[2]:.4f} {c[2] / 255:.3f} {c[1] / 255:.3f} {c[0] / 255:.3f}\n")
            for s in range(len(rings) - 1):
                for j in range(16):
                    j1 = (j + 1) & 15
                    o, n = s * 16 + 1, (s + 1) * 16 + 1
                    f.write(f"f {o + j} {n + j1} {o + j1}\n")
                    f.write(f"f {o + j} {n + j} {n + j1}\n")
        print("wrote", opts["--obj"])
    if "--png" in opts:
        from PIL import Image
        os.makedirs(opts["--png"], exist_ok=True)
        for name in ("BG", "PLANET", "LIGHT"):
            blob = entries[name][1]
            w, h = struct.unpack_from("<HH", blob, 0)
            img = Image.frombytes("P", (w, h), blob[4:4 + w * h])
            img.putpalette(pal)
            img.save(os.path.join(opts["--png"], name + ".png"))
        print("wrote PNGs to", opts["--png"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
