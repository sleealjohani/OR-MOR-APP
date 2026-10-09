#!/usr/bin/env python3
"""Generate RealityKit textures and brand images for the OR & MOR prototype.

Usage: python3 tools/gen_assets.py <brand-kit-dir> <photos-dir>
  brand-kit-dir: unpacked OR_MOR_App_Kit (logo/, fonts/, app-icon/)
  photos-dir:    café photos named table_top.png, interior.png, entrance.png, exterior.png

Outputs image sets into ORMOR/Resources/Assets.xcassets.
"""
import json, math, os, random, re, shutil, sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "ORMOR", "Resources", "Assets.xcassets")
GLOW_GOLD = (246, 196, 92)
INK_GOLD = (131, 97, 23)


def imageset(name, img):
    d = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(d, exist_ok=True)
    img.save(os.path.join(d, f"{name}.png"), optimize=True)
    with open(os.path.join(d, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)


# ---------- SVG path rasteriser (potrace output: M m c C l L z) ----------
def parse_path(d):
    toks = re.findall(r"[MmCcLlZz]|-?\d*\.?\d+(?:e-?\d+)?", d)
    subpaths, cur, start, pts = [], (0.0, 0.0), (0.0, 0.0), []
    i, cmd = 0, None
    def num():
        nonlocal i
        v = float(toks[i]); i += 1; return v
    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            cmd = t; i += 1
            if cmd in "Zz":
                if pts: subpaths.append(pts)
                pts, cur = [], start
                continue
        if cmd in "Mm":
            x, y = num(), num()
            if cmd == "m": x, y = cur[0] + x, cur[1] + y
            if pts: subpaths.append(pts)
            cur = start = (x, y); pts = [cur]
            cmd = "l" if cmd == "m" else "L"
        elif cmd in "Ll":
            x, y = num(), num()
            if cmd == "l": x, y = cur[0] + x, cur[1] + y
            cur = (x, y); pts.append(cur)
        elif cmd in "Cc":
            v = [num() for _ in range(6)]
            if cmd == "c":
                v = [v[k] + cur[k % 2] for k in range(6)]
            p0 = cur
            for s in range(1, 13):
                u = s / 12; a = (1 - u) ** 3; b = 3 * u * (1 - u) ** 2; c = 3 * u * u * (1 - u); e = u ** 3
                pts.append((a * p0[0] + b * v[0] + c * v[2] + e * v[4], a * p0[1] + b * v[1] + c * v[3] + e * v[5]))
            cur = (v[4], v[5])
    if pts: subpaths.append(pts)
    return subpaths


def logo_groups(svg_text):
    groups = {}
    for gid, body in re.findall(r'<g id="(\w+)"[^>]*>(.*?)</g>', svg_text, re.S):
        groups[gid] = [d for d in re.findall(r'd="([^"]+)"', body)]
    return groups


def render_logo(svg_text, which, color, height, pad=0.06):
    """Render selected logo groups (crest/arabic/latin) with even-odd fill, cropped to content."""
    groups = logo_groups(svg_text)
    polys = []
    for g in which:
        for d in groups[g]:
            for sp in parse_path(d):
                polys.append([(0.1 * x, 501 - 0.1 * y) for x, y in sp])
    xs = [p[0] for poly in polys for p in poly]; ys = [p[1] for poly in polys for p in poly]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    w, h = x1 - x0, y1 - y0
    ss = 4
    scale = height * ss * (1 - 2 * pad) / h
    W, H = int((w * scale) / (1 - 2 * pad)), height * ss
    ox, oy = (W - w * scale) / 2, (H - h * scale) / 2
    mask = Image.new("L", (W, H), 0)
    for poly in polys:  # even-odd via XOR layering
        layer = Image.new("L", (W, H), 0)
        ImageDraw.Draw(layer).polygon([((x - x0) * scale + ox, (y - y0) * scale + oy) for x, y in poly], fill=255)
        mask = Image.frombytes("L", (W, H), bytes(a ^ b for a, b in zip(mask.tobytes(), layer.tobytes())))
    mask = mask.resize((W // ss, H // ss), Image.LANCZOS)
    out = Image.new("RGBA", mask.size, color + (0,))
    out.putalpha(mask)
    return out


# ---------- photo-derived textures ----------
def perspective_coeffs(src, dst):
    import numpy as np
    A, B = [], []
    for (x, y), (u, v) in zip(dst, src):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); B.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); B.append(v)
    return list(np.linalg.solve(np.array(A, float), np.array(B, float)))


def tabletop(photo):
    im = Image.open(photo).convert("RGB")
    # Tabletop corners in the 941x1672 overhead photo (TL, TR, BR, BL), inset past the rounded corners.
    src = [(100, 318), (812, 318), (856, 1004), (84, 988)]
    S = 1024
    dst = [(0, 0), (S, 0), (S, S), (0, S)]
    return im.transform((S, S), Image.PERSPECTIVE, perspective_coeffs(src, dst), Image.BICUBIC)


def crop(photo, box, size=None):
    im = Image.open(photo).convert("RGB").crop(box)
    return im.resize(size, Image.LANCZOS) if size else im


# ---------- procedural textures ----------
def noise_tile(size, base, amp, blur, seed):
    rnd = random.Random(seed)
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            n = rnd.uniform(-amp, amp)
            px[x, y] = tuple(max(0, min(255, int(c + n))) for c in base)
    return img.filter(ImageFilter.GaussianBlur(blur))


def floor_tile():
    # One texture = 2x1 large-format porcelain tiles (each 1.2m x 1.2m in the scene).
    W, H = 1024, 512
    rnd = random.Random(7)
    img = noise_tile(256, (236, 228, 214), 6, 1.2, 3).resize((W, H), Image.BICUBIC)
    d = ImageDraw.Draw(img)
    for _ in range(900):  # faint stone speckle
        x, y = rnd.randrange(W), rnd.randrange(H)
        c = rnd.randint(205, 225)
        d.point((x, y), fill=(c, c - 6, c - 16))
    grout = (196, 186, 170)
    for x in (0, W // 2, W - 1):
        d.line([(x, 0), (x, H)], fill=grout, width=3)
    for y in (0, H - 1):
        d.line([(0, y), (W, y)], fill=grout, width=3)
    return img.filter(ImageFilter.GaussianBlur(0.6))


def wood():
    W, H = 512, 512
    rnd = random.Random(11)
    img = Image.new("RGB", (W, H))
    px = img.load()
    phases = [rnd.uniform(0, 6.28) for _ in range(4)]
    for y in range(H):
        for x in range(W):
            g = math.sin(y * 0.11 + math.sin(x * 0.006 + phases[0]) * 0.9 + phases[1]) * 0.5 + 0.5
            g2 = math.sin(y * 0.47 + math.sin(x * 0.011 + phases[2]) * 0.6) * 0.5 + 0.5
            t = 0.75 * g + 0.25 * g2
            px[x, y] = (int(214 - 34 * t), int(176 - 32 * t), int(128 - 30 * t))
    return img.filter(ImageFilter.GaussianBlur(0.8))


def hotspot_ring():
    S = 512
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = img.load()
    for y in range(S):
        for x in range(S):
            r = math.hypot(x - S / 2, y - S / 2) / (S / 2)
            ring = math.exp(-((r - 0.82) / 0.05) ** 2)
            glow = 0.35 * max(0.0, 1 - r) ** 2
            a = min(1.0, ring + glow)
            px[x, y] = GLOW_GOLD + (int(255 * a),)
    return img


def swift_logo_data(svg_text):
    groups = logo_groups(svg_text)
    out = ["// Generated by tools/gen_assets.py from OR_MOR_Logo.svg (reconstructed vector, viewBox 0 0 551 501).",
           "// Coordinates are potrace units: apply x * 0.1, 501 - y * 0.1 to get viewBox space.",
           "// swiftlint:disable all", "", "enum LogoPathData {"]
    for gid in ("crest", "arabic", "latin"):
        out.append(f"    static let {gid}: [String] = [")
        for d in groups[gid]:
            out.append(f'        "{" ".join(d.split())}",')
        out.append("    ]")
    out.append("}")
    return "\n".join(out) + "\n"


def main():
    kit, photos = sys.argv[1], sys.argv[2]
    svg = open(os.path.join(kit, "logo", "OR_MOR_Logo.svg"), encoding="utf-8").read()

    # Scene textures
    imageset("tex_tabletop", tabletop(os.path.join(photos, "table_top.png")))
    imageset("tex_floor", floor_tile())
    imageset("tex_wood", wood())
    # Real interior details cropped from the interior photo (941x1672).
    interior = os.path.join(photos, "interior.png")
    imageset("tex_display_case", crop(interior, (78, 612, 232, 742), (512, 432)))
    imageset("tex_wall_art_1", crop(interior, (620, 480, 646, 540), (128, 296)))
    imageset("tex_wall_art_2", crop(interior, (638, 538, 666, 612), (128, 338)))
    imageset("tex_coffee_bar", crop(interior, (392, 560, 548, 662), (512, 336)))

    # Brand
    imageset("sign_logotype", render_logo(svg, ["arabic", "latin"], GLOW_GOLD, 512))
    imageset("logo_full_gold", render_logo(svg, ["crest", "arabic", "latin"], INK_GOLD, 1024))
    imageset("logo_crest_gold", render_logo(svg, ["crest"], GLOW_GOLD, 512))

    imageset("tex_hotspot_ring", hotspot_ring())
    with open(os.path.join(ROOT, "ORMOR", "Brand", "LogoPathData.swift"), "w") as f:
        f.write(swift_logo_data(svg))

    # App icon
    icon_dir = os.path.join(ASSETS, "AppIcon.appiconset")
    os.makedirs(icon_dir, exist_ok=True)
    shutil.copy(os.path.join(kit, "app-icon", "OR_MOR_App_Icon_1024.png"), os.path.join(icon_dir, "AppIcon.png"))
    with open(os.path.join(icon_dir, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
    with open(os.path.join(ASSETS, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)


if __name__ == "__main__":
    main()
