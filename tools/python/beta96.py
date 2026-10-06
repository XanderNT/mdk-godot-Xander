"""Reference decoder for the MDK beta demo of 6 August 1996 (see docs/beta96.md).

Usage:
    python beta96.py <demo dir>                    # check the files of the three levels
    python beta96.py <demo dir> <level> [script]   # disassemble the level's scripts (or one)
    python beta96.py <demo dir> --unpack <out>     # MDKDEMO.EXE's objects as a flat image at 0x10000
"""
import os
import struct
import sys

LEVELS = (1, 3, 6)
# Demo opcode to operand codes (see MDKBetaScriptDecoder.LAYOUTS).
LAYOUTS = {
    1: [], 2: ["data"], 3: ["data"], 4: ["op4"], 5: ["act"], 6: [], 8: ["s16"], 9: [], 10: ["pstr", "u8", "act"],
    11: ["u8"], 12: ["rep"], 13: ["act"], 14: ["u16", "u8", "act"], 15: [], 16: ["u16"], 17: ["act"],
    18: ["f32", "act"], 19: [], 20: [], 21: [], 22: ["act"], 23: [], 24: ["u8", "pstr"], 25: ["pstr"],
    26: ["pstr"], 27: ["act"], 28: ["act"], 29: ["u8", "pstr", "code"], 31: ["reps"], 32: ["reps"],
    34: ["act"], 35: ["u8"], 36: ["u8"], 37: ["act"], 38: ["cond", "act"], 39: ["val"], 40: ["val"], 41: [],
    42: ["pstr", "act"], 43: ["f32", "f32"], 44: ["act"], 45: ["cond", "act"], 46: ["act"], 47: ["f32", "act"],
    48: ["f32", "act"], 49: ["u8", "act"], 50: ["val"], 51: ["val"], 52: ["val"], 53: ["val"],
    54: ["cond", "act"], 57: ["u16", "u8", "act"], 58: ["val"], 59: ["data"], 60: [], 61: ["op61"],
    62: ["cond", "act"], 63: ["u8"], 64: ["val"], 65: ["u8", "u8", "f32"], 66: ["u8", "u8", "f32"],
    67: ["u8", "u8", "cond", "act"], 68: ["u8", "u8"], 69: ["u8", "u8"], 70: ["u8", "u8"],
    71: ["u8", "u8", "act"], 72: ["u8", "u8", "act"], 73: ["u8"], 74: ["u8", "u8", "pstr"], 75: [],
    76: ["code"], 77: ["pstr"], 78: ["f32"] * 3, 79: ["f32"] * 3, 80: ["f32"] * 3, 81: ["val"], 82: ["val"],
    83: ["val"], 84: ["val"], 85: ["u8"], 86: ["f32", "f32", "f32", "pstr", "code"],
    87: ["u16", "u16", "u8", "act"], 88: ["u8"], 89: ["pstr"], 90: ["pstr", "u8"], 91: ["val"],
    92: ["u8", "act"], 128: ["pstr", "u8", "u8"], 129: ["reps"], 130: [], 131: ["u8"], 0xF0: ["rep"], 0xF1: [],
}


def u32(d, o):
    return struct.unpack_from("<I", d, o)[0]


def load_cmi(demo_dir, level):
    """Returns (bytes, [4 directories of (name, file offset)])."""
    d = open(os.path.join(demo_dir, "TRAVERSE", "LEVEL%d" % level, "LEVEL%d.CMI" % level), "rb").read()
    p = 4
    dirs = []
    for _ in range(4):
        entries = []
        count = u32(d, p)
        p += 4
        for _ in range(count):
            length = d[p]
            name = d[p + 1:p + 1 + length].rstrip(b"\0").decode("latin1")
            entries.append((name, u32(d, p + 1 + length) + 4))
            p += length + 5
        dirs.append(entries)
    return d, dirs


class Reader:
    def __init__(self, d, p):
        self.d, self.p, self.targets, self.data = d, p, [], []

    def u8(self):
        self.p += 1
        return self.d[self.p - 1]

    def u16(self):
        self.p += 2
        return struct.unpack_from("<H", self.d, self.p - 2)[0]

    def s16(self):
        self.p += 2
        return struct.unpack_from("<h", self.d, self.p - 2)[0]

    def f32(self):
        self.p += 4
        return round(struct.unpack_from("<f", self.d, self.p - 4)[0], 4)

    def pstr(self):
        length = self.u8()
        self.p += length
        return self.d[self.p - length:self.p].rstrip(b"\0").decode("latin1")

    def code(self):
        self.p += 4
        value = u32(self.d, self.p - 4)
        if value:
            self.targets.append(value + 4)
        return "L%x" % (value + 4) if value else "null"

    def act(self):
        action = self.u8()
        if action == 0x0C:
            return "goto " + self.code()
        if action == 0xF0:
            return "gosub " + self.code()
        return "return" if action == 0xF1 else "none(%#x)" % action

    def val(self):
        kind = self.u8()
        return self.f32() if kind == 3 else "var%d[%d]" % (kind, self.u8())

    def cond(self):
        op = self.u8()
        return (op, self.f32(), self.f32()) if op in (7, 8) else (op, self.f32())

    def read(self, code):
        if code == "data":
            self.p += 4
            self.data.append(u32(self.d, self.p - 4) + 4)
            return "D%x" % self.data[-1]
        if code == "rep":
            return [self.code() for _ in range(self.u8())]
        if code == "reps":
            return [self.pstr() for _ in range(self.u8())]
        if code == "op4":
            command = self.u8()
            out = [command]
            if command == 7:
                out.append(self.act())
            elif command == 43:
                out += [self.f32(), self.f32()]
            selector = self.u8()
            out.append("selector %d" % selector)
            if selector in (2, 4, 5):
                out.append(self.pstr())
            if selector == 5:
                out.append(self.u8())
            return out
        if code == "op61":
            mode = self.u8()
            return [mode, self.u8() if mode == 0 else self.pstr(), self.u8(), self.f32(), self.f32(), self.f32()]
        return getattr(self, code)()


def walk(d, entries):
    """Decodes every instruction reachable from the entry points: {offset: (opcode, operands, next)}."""
    seen, todo, errors, data = {}, list(entries), [], {}
    while todo:
        p = todo.pop()
        while p not in seen:
            r = Reader(d, p)
            opcode = r.u8()
            if opcode != 0xFF and opcode not in LAYOUTS:
                errors.append("unknown opcode %d at %x" % (opcode, p))
                break
            operands = [r.read(code) for code in LAYOUTS.get(opcode, [])]
            seen[p] = (opcode, operands, r.p)
            todo += r.targets
            for offset in r.data:
                data[offset] = opcode
            if opcode in (0xFF, 9, 12, 0xF1):
                break
            p = r.p
    return seen, errors, data


def model_end(d, o):
    """Returns the end of a model (the retail layout)."""
    flags = u32(d, o)
    o += 8 + 16 * u32(d, o + 4)
    parts = u32(d, o) if flags else 1
    o += 4 if flags else 0
    for _ in range(parts):
        o += 24 if flags else 0
        o += 4 + 12 * u32(d, o)
        o += 4 + 36 * u32(d, o)
        o += 24 if flags else 0
    o += 24
    return o + 4 + 12 * u32(d, o)


def animation_end(d, a):
    """Returns the end of an animation, or None if its tracks don't follow each other."""
    tracks, frames = u32(d, a), u32(d, a + 4)
    offsets = [u32(d, a + 8 + 4 * i) for i in range(tracks)]
    o = a + 8 + 4 * tracks + 36 * frames
    o += 4 + 12 * frames * u32(d, o)
    for offset in offsets:
        if o != a + offset:
            return None
        vertices = u32(d, o + 12)
        o += 20 + 12 * vertices + 3 * vertices * (frames - 1)
    return o


def check_world(path):
    d = open(path, "rb").read()
    o = 4 + 16 * u32(d, 0)
    o += 4 + 36 * u32(d, o)
    triangles = u32(d, o)
    o += 4 + 36 * triangles
    vertices = u32(d, o)
    return triangles, vertices, len(d) - (o + 4 + 12 * vertices)


def check(demo_dir):
    for level in LEVELS:
        d, dirs = load_cmi(demo_dir, level)
        seen, errors, data = walk(d, [o for _, o in dirs[0] + dirs[2]])
        end = model_end(d, max(o for _, o in dirs[1]))
        animations = 0
        while end is not None and end < len(d):
            end = animation_end(d, end)
            animations += 1
        print("LEVEL%d: %d instructions, %d paths, %d models, %d animations%s%s" % (
            level, len(seen), sum(1 for op in data.values() if op == 2), len(dirs[1]), animations,
            "" if end == len(d) else ", THE ANIMATIONS DON'T END AT THE FILE'S END", "".join("\n  " + e for e in errors)))
        arenas = os.path.join(demo_dir, "TRAVERSE", "LEVEL%d" % level, "ARENAS")
        for name in sorted(os.listdir(arenas)):
            if name.upper().endswith(".BSP"):
                print("  %-12s %4d triangles, %4d vertices, %d bytes after them" % ((name,) + check_world(os.path.join(arenas, name))))


def disassemble(demo_dir, level, script):
    d, dirs = load_cmi(demo_dir, level)
    names = {o: n for n, o in dirs[0] + dirs[2]}
    entries = [o for n, o in dirs[0] + dirs[2] if not script or n.lower() == script.lower()]
    seen, errors, _ = walk(d, entries)
    for offset in sorted(seen):
        if offset in names:
            print("; ---- %s" % names[offset])
        opcode, operands, _ = seen[offset]
        print("%05x  %3d %s" % (offset, opcode, " ".join(str(o) for o in operands)))
    for error in errors:
        print("; " + error)


def unpack(demo_dir, out):
    """Writes the LE executable's objects, with its 32-bit fixups applied, as one image at 0x10000."""
    d = open(os.path.join(demo_dir, "MDKDEMO.EXE"), "rb").read()
    le = d.find(b"LE\0\0")
    h = lambda o: u32(d, le + o)
    pages, page_size, last_page = h(0x14), h(0x28), h(0x2C)
    objects = [struct.unpack_from("<6I", d, le + h(0x40) + 24 * i) for i in range(h(0x44))]
    low = min(o[1] for o in objects)
    image = bytearray(max(o[1] + o[0] for o in objects) - low)
    page_base = {}
    for _, base, _, first, count, _ in objects:
        for i in range(count):
            page = first + i
            page_base[page] = base + i * page_size
            start = h(0x80) + (page - 1) * page_size
            chunk = d[start:start + (page_size if page < pages else last_page)]
            image[base - low + i * page_size:base - low + i * page_size + len(chunk)] = chunk
    table, records = le + h(0x68), le + h(0x6C)
    for page in range(1, pages + 1):
        o, end = records + u32(d, table + 4 * (page - 1)), records + u32(d, table + 4 * page)
        while o < end:
            source, flags = d[o], d[o + 1]
            o += 2
            if flags & 3:
                break
            count = 1
            if source & 0x20:
                count = d[o]
                o += 1
            else:
                sources = [struct.unpack_from("<h", d, o)[0]]
                o += 2
            obj = struct.unpack_from("<H", d, o)[0] if flags & 0x40 else d[o]
            o += 2 if flags & 0x40 else 1
            target = 0
            if source & 0xF != 2:
                target = u32(d, o) if flags & 0x10 else struct.unpack_from("<H", d, o)[0]
                o += 4 if flags & 0x10 else 2
            if source & 0x20:
                sources = [struct.unpack_from("<h", d, o + 2 * i)[0] for i in range(count)]
                o += 2 * count
            for offset in sources:
                address = page_base[page] + offset
                if source & 0xF == 7:
                    value = objects[obj - 1][1] + target
                elif source & 0xF == 8:
                    value = objects[obj - 1][1] + target - (address + 4)
                else:
                    continue
                for i, byte in enumerate(struct.pack("<I", value & 0xFFFFFFFF)):
                    if 0 <= address - low + i < len(image):
                        image[address - low + i] = byte
    open(out, "wb").write(image)
    print("%s: %d bytes at %#x, entry %#x" % (out, len(image), low, objects[h(0x18) - 1][1] + h(0x1C)))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if len(sys.argv) > 3 and sys.argv[2] == "--unpack":
        unpack(sys.argv[1], sys.argv[3])
    elif len(sys.argv) > 2:
        disassemble(sys.argv[1], int(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else "")
    else:
        check(sys.argv[1])
