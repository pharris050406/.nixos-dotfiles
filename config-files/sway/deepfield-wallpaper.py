#!/usr/bin/env python3
"""Deep Field wallpaper: a procedural deep-sky image in the bar's palette.

Needs numpy and pillow (FreeBSD: pkg install py311-numpy py311-pillow).

    ./deepfield-wallpaper.py                          # 2560x1440, seed 1977
    ./deepfield-wallpaper.py -W 1920 -H 1080 --seed 42 -o ~/.config/sway/deepfield.png

What's in it, and the physics behind each piece:
  * stars       true blackbody colors (Planck-fit sRGB), temperatures drawn
                from a cool-heavy distribution, brightness from a steep power
                law: thousands of faint stars, a handful of bright ones
  * spikes      the brightest stars get JWST-style diffraction spikes: six
                from the hexagonal mirror segments, plus a faint horizontal
                pair from the secondary mirror's vertical strut
  * galaxies    small smudges in the background. The smaller (farther) ones
                are drawn redder, as cosmological redshift would make them
  * nebula      1/f^beta fractal clouds (the power spectrum turbulence gives
                you), tinted with the theme's mauve/blue/teal
  * dust lanes  the same kind of noise, used to *absorb* light along the
                galactic band rather than emit it
"""
import argparse
import math

import numpy as np
from PIL import Image

PALETTE = {
    "bg":    "#181825",
    "fg":    "#cdd6f4",
    "mauve": "#ca9ee6",
    "blue":  "#8caaee",
    "teal":  "#81c8be",
    "gold":  "#e5c890",
}


def rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def blackbody(T):
    """Tanner Helland's fit of blackbody temperature (K) -> sRGB 0..1."""
    t = min(max(T, 1000), 40000) / 100
    r = 255 if t <= 66 else 329.698727446 * (t - 60) ** -0.1332047592
    g = (99.4708025861 * math.log(t) - 161.1195681661) if t <= 66 else 288.1221695283 * (t - 60) ** -0.0755148492
    b = 255 if t >= 66 else (0 if t <= 19 else 138.5177312231 * math.log(t - 10) - 305.0447927307)
    return np.clip(np.array([r, g, b]) / 255, 0, 1)


def saturate(c, k):
    """Push a color away from its own luminance (k > 1 = more saturated)."""
    y = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    return np.clip(y + (c - y) * k, 0, 1)


def fractal(h, w, beta, rng):
    """Noise with power spectrum ~ 1/k^beta, normalized to 0..1."""
    white = rng.standard_normal((h, w))
    ky = np.fft.fftfreq(h)[:, None]
    kx = np.fft.rfftfreq(w)[None, :]
    k = np.sqrt(kx ** 2 + ky ** 2)
    k[0, 0] = 1
    spec = np.fft.rfft2(white) / k ** (beta / 2)
    spec[0, 0] = 0
    out = np.fft.irfft2(spec, s=(h, w))
    out -= out.min()
    return out / out.max()


def upsample(a, w, h):
    return np.asarray(Image.fromarray(a.astype(np.float32), mode="F").resize((w, h), Image.BICUBIC))


def splat(light, x, y, sigma, color, flux):
    """Add a Gaussian point-spread function at (x, y)."""
    H, W, _ = light.shape
    r = max(2, int(math.ceil(sigma * 3.5)))
    x0, x1 = max(0, int(x) - r), min(W, int(x) + r + 2)
    y0, y1 = max(0, int(y) - r), min(H, int(y) + r + 2)
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    g = np.exp(-((xx - x) ** 2 + (yy - y) ** 2) / (2 * sigma ** 2))
    light[y0:y1, x0:x1] += (flux * g)[..., None] * color


def spike(light, x, y, angle, length, color, peak):
    """One diffraction spike: a thin line fading roughly exponentially."""
    H, W, _ = light.shape
    dx, dy = math.cos(angle), math.sin(angle)
    for s in np.arange(2.0, length, 0.5):
        px, py = x + dx * s, y + dy * s
        ix, iy = int(px), int(py)
        if not (0 <= ix < W - 1 and 0 <= iy < H - 1):
            break
        fx, fy = px - ix, py - iy
        v = peak * math.exp(-4.5 * s / length) * 0.5
        light[iy, ix] += v * (1 - fx) * (1 - fy) * color
        light[iy, ix + 1] += v * fx * (1 - fy) * color
        light[iy + 1, ix] += v * (1 - fx) * fy * color
        light[iy + 1, ix + 1] += v * fx * fy * color


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-W", "--width", type=int, default=2560)
    ap.add_argument("-H", "--height", type=int, default=1440)
    ap.add_argument("--seed", type=int, default=1977)
    ap.add_argument("-o", "--out", default="deepfield.png")
    a = ap.parse_args()

    W, H = a.width, a.height
    rng = np.random.default_rng(a.seed)
    P = {k: rgb(v) for k, v in PALETTE.items()}
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)

    # ---- base: theme background with a soft vignette ----
    cx, cy = 0.58 * W, 0.55 * H
    rr = np.sqrt(((xx - cx) / W) ** 2 + ((yy - cy) / H) ** 2)
    base = P["bg"][None, None, :] * (0.7 + 0.45 * np.clip(1 - 1.6 * rr ** 2, 0, 1))[..., None]

    # ---- the galactic band ----
    ang = math.radians(-17)
    bx, by = 0.55 * W, 0.6 * H
    nx, ny = -math.sin(ang), math.cos(ang)              # unit normal to the band
    d = (xx - bx) * nx + (yy - by) * ny
    band = np.exp(-(d / (0.17 * H)) ** 2)

    # ---- clouds (low-res fractal noise, upsampled) ----
    lw, lh = W // 4, H // 4
    n1 = upsample(fractal(lh, lw, 3.0, rng), W, H)
    n2 = upsample(fractal(lh, lw, 2.6, rng), W, H)
    n3 = upsample(fractal(lh, lw, 2.8, rng), W, H)
    n4 = upsample(fractal(lh, lw, 3.4, rng), W, H)

    light = np.zeros((H, W, 3), np.float32)

    # diffuse starlight of the band, clumped
    glow = band * (0.35 + 0.65 * n4)
    light += (0.17 * glow)[..., None] * (0.55 * P["fg"] + 0.45 * P["gold"])

    # emission nebula: mauve/blue, with teal (think O III) where it's densest
    blob = np.exp(-(((xx - 0.74 * W) / (0.42 * W)) ** 2 + ((yy - 0.62 * H) / (0.5 * H)) ** 2))
    neb = np.clip((n1 - 0.42) * 2.4, 0, 1) ** 1.7 * np.clip(blob + 0.5 * band, 0, 1)
    mauve, blue, teal = saturate(P["mauve"], 1.9), saturate(P["blue"], 1.8), saturate(P["teal"], 1.8)
    mixk = np.clip((n2 - 0.35) * 2.2, 0, 1)[..., None]
    tint = mixk * mauve + (1 - mixk) * blue
    light += (0.42 * neb)[..., None] * tint
    core = np.clip((n1 - 0.6) * 4, 0, 1) ** 2 * blob
    light += (0.22 * core)[..., None] * teal

    # dust lanes absorb along the band
    dust = np.clip((n3 - 0.5) * 3.2, 0, 1) * band
    absorb = 1 - 0.75 * dust

    # ---- background galaxies: smaller = farther = redder ----
    for _ in range(int(W * H / 50000)):
        gx, gy = rng.uniform(0, W), rng.uniform(0, H)
        size = rng.uniform(1.2, 5.5)
        T = 2200 + (size - 1.2) / 4.3 * 5500             # tiny ones are redshifted
        q, th = rng.uniform(0.25, 1.0), rng.uniform(0, math.pi)
        r = int(size * 3.5) + 1
        x0, x1, y0, y1 = max(0, int(gx) - r), min(W, int(gx) + r), max(0, int(gy) - r), min(H, int(gy) + r)
        if x0 >= x1 or y0 >= y1:
            continue
        gy_, gx_ = np.mgrid[y0:y1, x0:x1]
        u = (gx_ - gx) * math.cos(th) + (gy_ - gy) * math.sin(th)
        v = -(gx_ - gx) * math.sin(th) + (gy_ - gy) * math.cos(th)
        g = np.exp(-(u ** 2 + (v / q) ** 2) / (2 * size ** 2))
        light[y0:y1, x0:x1] += (0.07 * g)[..., None] * blackbody(T)

    light *= absorb[..., None]

    # ---- unresolved stars: a fine grain of single pixels, dense along the band ----
    m = int(W * H / 40)
    ux, uy = rng.uniform(0, W, m), rng.uniform(0, H, m)
    keep = rng.random(m) < 0.15 + 0.85 * band[uy.astype(int), ux.astype(int)]
    ux, uy = ux[keep].astype(int), uy[keep].astype(int)
    amp = (0.015 + 0.05 * rng.random(ux.size) ** 3) * absorb[uy, ux]
    np.add.at(light, (uy, ux), amp[:, None] * (0.7 * P["fg"] + 0.3 * P["gold"]))

    # ---- stars ----
    n = int(W * H / 520)
    bright = []
    for _ in range(n):
        if rng.random() < 0.5:                           # concentrated toward the band
            t = rng.uniform(-0.2, 1.2) * W               # a point on the band's centerline...
            off = rng.normal(0, 0.09 * H)                # ...pushed off it along the normal
            x = t + nx * off
            y = by + (t - bx) * math.tan(ang) + ny * off
        else:
            x, y = rng.uniform(0, W), rng.uniform(0, H)
        if not (0 <= x < W and 0 <= y < H):
            continue
        b = rng.random() ** 7                             # steep: mostly faint
        T = 2900 + 13000 * rng.random() ** 2.4            # mostly cool
        col = blackbody(T)
        flux = (0.025 + 2.6 * b) * absorb[int(y), int(x)]
        splat(light, x, y, 0.45 + 1.1 * b, col, flux)
        if b > 0.55:
            bright.append((x, y, b, col))

    # JWST diffraction pattern on the brightest
    bright.sort(key=lambda s: -s[2])
    for i, (x, y, b, col) in enumerate(bright[:7]):
        L = (30 + 150 * b ** 2) * (1.6 if i == 0 else 1)
        splat(light, x, y, 2.2 + 3 * b, col, 0.35 * b)  # halo
        for k in range(6):                                # hexagonal segments: 6 spikes
            spike(light, x, y, math.radians(90 + 60 * k), L, col, 0.75 * b)
        for k in (0, 1):                                  # strut: faint horizontal pair
            spike(light, x, y, math.radians(180 * k), L * 0.5, col, 0.3 * b)

    # ---- tone map: light saturates softly onto the base ----
    out = base + (1 - base) * (1 - np.exp(-1.15 * light))
    out += (rng.random(out.shape) - 0.5) / 255            # dither away gradient banding
    img = (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(img, "RGB").save(a.out, optimize=True)
    print(f"wrote {a.out} ({W}x{H}, seed {a.seed})")


if __name__ == "__main__":
    main()
