"""Draws mac/voice-dot-head.png, the grey picture behind the Voice guide's dot face.

Run it from the project folder:  .venv/bin/python mac/make_dot_head.py

The outline is traced from mac/voice-workshop-head.jpg (Voice Workshop by Fabio Angela, Apache-2.0) so the dot face sits
exactly over the painted head. The shading is our own: the outline is inflated into a soft relief, a few features are
added (ear, eye, nose, lips, jaw) and it is lit from the front. One pixel is one dot; the app dithers it at run time.
"""
import struct, subprocess, zlib
from pathlib import Path
import numpy as np
from scipy import ndimage as ni

HERE = Path(__file__).parent
W, H, COLS, ROWS = 1024, 1536, 156, 232
K = 1320 / ROWS
X0, Y0 = 40 - (COLS * K - 880) / 2, 70
Y, X = np.mgrid[0:H, 0:W].astype(np.float64)


def ramp(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def turned(cx, cy, rot):
    c, s, dx, dy = np.cos(rot), np.sin(rot), X - cx, Y - cy
    return dx * c + dy * s, -dx * s + dy * c


def blob(cx, cy, sx, sy, rot=0.0):
    u, v = turned(cx, cy, rot)
    return np.exp(-0.5 * ((u / sx) ** 2 + (v / sy) ** 2))


def ell(cx, cy, rx, ry, rot=0.0):
    u, v = turned(cx, cy, rot)
    return np.hypot(u / rx, v / ry)


def line(pts):
    d = np.full((H, W), 1e9)
    for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
        vx, vy = bx - ax, by - ay
        t = np.clip(((X - ax) * vx + (Y - ay) * vy) / (vx * vx + vy * vy), 0, 1)
        d = np.minimum(d, np.hypot(X - ax - t * vx, Y - ay - t * vy))
    return d


def ridge(d, s):
    return np.exp(-0.5 * (d / s) ** 2)


def inside(poly):
    o = np.zeros((H, W), bool)
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        if y0 != y1:
            o ^= ((y0 <= Y) != (y1 <= Y)) & (X < x0 + (Y - y0) * (x1 - x0) / (y1 - y0))
    return o


def outline():
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(HERE / "voice-workshop-head.jpg"), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], check=True, capture_output=True).stdout
    dark = np.frombuffer(raw, np.uint8).reshape(H, W, 3).max(2) < 40
    lab, _ = ni.label(dark)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    sil = ni.binary_opening(ni.binary_fill_holes(~np.isin(lab, edge[edge > 0])), iterations=3)
    lab, n = ni.label(sil)
    sil = lab == 1 + int(np.argmax(ni.sum(sil, lab, range(1, n + 1))))
    sil = sil | (ell(813, 737, 27, 31) < 1) | (ell(797, 810, 31, 35) < 1)  # lips
    return ni.gaussian_filter(sil.astype(float), 3) > 0.5


def grey():
    sil = outline()
    t = np.clip(ni.distance_transform_edt(sil) / 210, 0, 1)
    z = ni.gaussian_filter(210 * np.sqrt(1 - (1 - t) ** 2), 9)
    z += 16 * ridge(ell(398, 492, 60, 118, -0.16) - 1, 0.16) * (1 - 0.6 * ramp(0.2, 1.0, (X - 398) / 60))  # ear rim
    z += -14 * blob(410, 492, 24, 58, -0.16) + 9 * blob(404, 598, 20, 20) + 7 * blob(432, 500, 9, 26, -0.16)  # ear hollow, lobe, tragus
    z += -26 * blob(722, 398, 44, 30) + 10 * blob(728, 404, 20, 12) + 12 * blob(735, 340, 60, 16, -0.15)  # eye socket, lid, brow
    z += 16 * blob(640, 520, 70, 55) - 8 * blob(610, 330, 70, 60)  # cheekbone, temple
    z += 8 * blob(840, 590, 22, 20) - 12 * ridge(line([(806, 560), (800, 590), (812, 618)]), 6)  # nose wing
    z -= 10 * ridge(line([(770, 640), (752, 700), (730, 770), (722, 800)]), 14)  # fold beside the mouth
    z += 8 * blob(770, 950, 40, 40) - 4 * ridge(line([(700, 880), (770, 878)]), 16)  # chin
    z += 12 * ridge(line([(730, 985), (620, 985), (530, 960), (480, 890)]), 42)  # jaw bone
    jaw = [(700, 1028), (620, 1034), (545, 1040), (495, 985), (455, 905), (432, 800), (418, 690), (410, 640)]
    z -= 7 * ridge(line(jaw) - 16, 16) * (Y > 640)
    z += 9 * ridge(line([(372, 690), (410, 900), (455, 1120), (478, 1340)]), 26) + 5 * ridge(line([(250, 780), (240, 1000), (235, 1340)]), 40)  # neck
    z = ni.gaussian_filter(z, 2.5)
    zy, zx = np.gradient(z)
    norm = np.sqrt(zx * zx + zy * zy + 1)

    def lit(lx, ly, lz):
        return np.clip((-zx * lx - zy * ly + lz) / np.sqrt(lx * lx + ly * ly + lz * lz) / norm, 0, 1)

    g = 0.04 + 0.78 * lit(0.74, -0.5, 0.45) ** 1.25 + 0.4 * lit(-0.9, -0.25, 0.18) ** 1.5 + 0.1 * lit(0.1, -0.95, 0.3) + 0.22 * lit(1, 0.25, 0.15) ** 2
    g += 0.3 * blob(770, 866, 36, 52)  # keeps the lower lip joined to the chin when the mouth opens
    neck = inside([(760, 1034)] + jaw + [(330, 655), (200, 700), (40, 745), (0, 760), (0, 1536), (1024, 1536), (1024, 1034)])
    shade = ni.gaussian_filter(neck.astype(float), 16)
    g *= 1 - 0.25 * shade - 0.3 * shade * np.exp(-line(jaw) / 80)
    g *= 1 - 0.92 * ridge(np.maximum(0, ell(737, 405, 25, 10, -0.1) - 0.6), 0.35)  # eye
    g *= 1 - 0.75 * ridge(line([(688, 372), (725, 356), (770, 358)]), 7)  # eyebrow
    g *= 1 - 0.5 * blob(823, 490, 70, 15, 1.05)  # side of the nose
    g *= 1 - 0.85 * blob(836, 606, 11, 7, -0.4)  # nostril
    g *= 1 - 0.9 * ridge(line([(705, 778), (845, 768)]), 3.2)  # mouth line, where the app opens the jaw
    g *= 1 - 0.85 * ramp(1150, 1361, Y)  # the bust fades out
    return np.clip(g, 0, 1) * sil


def cells():
    g, n = ni.gaussian_filter(grey(), K / 2.6), 4
    cy, cx = np.mgrid[0:ROWS * n, 0:COLS * n]
    s = ni.map_coordinates(g, [Y0 + (cy + 0.5) * K / n - 0.5, X0 + (cx + 0.5) * K / n - 0.5], order=1, mode="constant")
    return np.round(s.reshape(ROWS, n, COLS, n).mean((1, 3)) * 255).astype(np.uint8)


def save(path, a):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    rows = b"".join(b"\x00" + a[y].tobytes() for y in range(a.shape[0]))
    head = struct.pack(">IIBBBBB", a.shape[1], a.shape[0], 8, 0, 0, 0, 0)
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", head) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    save(HERE / "voice-dot-head.png", cells())
    print("Wrote mac/voice-dot-head.png")
