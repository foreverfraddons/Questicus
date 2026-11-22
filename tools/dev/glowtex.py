# Questicus' own highlight textures (white on transparent; tinted in game)
import math, random
from PIL import Image, ImageDraw, ImageFilter
import os
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "Questicus", "Media") + os.sep
def save(img, name):
    img.save(OUT + name + ".tga")
def alpha_img(n, fn):
    im = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    px = im.load()
    for y in range(n):
        for x in range(n):
            a = fn((x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1)
            px[x, y] = (255, 255, 255, max(0, min(255, int(a * 255))))
    return im
# soft radial glow
save(alpha_img(128, lambda x, y: max(0, 1 - math.hypot(x, y)) ** 2.2), "qg_glow")
# thin soft ring
def ring(r0, w):
    return lambda x, y: math.exp(-((math.hypot(x, y) - r0) / w) ** 2)
save(alpha_img(256, ring(0.86, 0.035)), "qg_ring")
# soft wide ring (ripples, rift edge)
save(alpha_img(256, ring(0.78, 0.12)), "qg_ring_soft")
# hole (transparent disc in an opaque square: rift core / silhouette cut-out)
save(alpha_img(128, lambda x, y: min(1, max(0, (math.hypot(x, y) - 0.55) / 0.35))), "qg_hole")
# four-point sparkle
def star(x, y):
    r = math.hypot(x, y)
    a = math.exp(-abs(x) * 14) * max(0, 1 - abs(y)) + math.exp(-abs(y) * 14) * max(0, 1 - abs(x))
    return min(1, a + max(0, 1 - r * 3) ** 2)
save(alpha_img(128, star), "qg_spark")
# rune circle: a ring with short glyph strokes
n = 256
im = Image.new("RGBA", (n * 2, n * 2), (255, 255, 255, 0))
d = ImageDraw.Draw(im)
c = n
random.seed(7)
d.ellipse([c - 220, c - 220, c + 220, c + 220], outline=(255, 255, 255, 255), width=6)
d.ellipse([c - 170, c - 170, c + 170, c + 170], outline=(255, 255, 255, 200), width=4)
for i in range(16):
    ang = i / 16 * math.tau
    px, py = c + math.cos(ang) * 195, c + math.sin(ang) * 195
    for k in range(3):
        a1 = ang + random.uniform(-0.6, 0.6)
        l = random.uniform(8, 16)
        ox, oy = random.uniform(-7, 7), random.uniform(-7, 7)
        d.line([px + ox, py + oy, px + ox + math.cos(a1) * l, py + oy + math.sin(a1) * l], fill=(255, 255, 255, 255), width=5)
im = im.resize((n, n), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.8))
save(im, "qg_runes")
# corner bracket (top-left L)
im = Image.new("RGBA", (128, 128), (255, 255, 255, 0))
d = ImageDraw.Draw(im)
d.line([12, 70, 12, 12, 70, 12], fill=(255, 255, 255, 255), width=12, joint="curve")
im = im.filter(ImageFilter.GaussianBlur(1.6))
save(im, "qg_bracket")
# swirl: three spiral arms
def swirl(x, y):
    r = math.hypot(x, y)
    if r > 1 or r < 0.05: return 0
    th = math.atan2(y, x)
    v = math.cos(3 * (th - 4.0 * r))
    return max(0, v) ** 6 * (1 - r) ** 0.8 * min(1, r * 4)
save(alpha_img(256, swirl), "qg_swirl")
# flame tongue (upright teardrop, bright base)
def flame(x, y):
    yy = (y + 1) / 2          # 0 top .. 1 bottom
    w = 0.55 * (yy ** 0.9) * (1 - max(0, yy - 0.8) * 4)
    if w <= 0: return 0
    a = max(0, 1 - abs(x) / w)
    return a ** 1.5 * min(1, (1 - yy) * 6 + 0.2) * yy ** 0.3
save(alpha_img(128, flame), "qg_flame")
# beam column (vertical, fades out at the top)
im = alpha_img(128, lambda x, y: math.exp(-(x / 0.28) ** 2) * ((y + 1) / 2) ** 0.7)
save(im, "qg_beam")
# gem / crystal (diamond with a facet line)
im = Image.new("RGBA", (128, 128), (255, 255, 255, 0))
d = ImageDraw.Draw(im)
d.polygon([(64, 6), (110, 50), (64, 122), (18, 50)], fill=(255, 255, 255, 170))
d.line([(18, 50), (110, 50)], fill=(255, 255, 255, 255), width=4)
d.line([(64, 6), (64, 122)], fill=(255, 255, 255, 220), width=2)
d.polygon([(64, 6), (110, 50), (64, 122), (18, 50)], outline=(255, 255, 255, 255), width=5)
save(im.filter(ImageFilter.GaussianBlur(0.9)), "qg_gem")
# lightning bolt
im = Image.new("RGBA", (128, 256), (255, 255, 255, 0))
d = ImageDraw.Draw(im)
pts = [(70, 0), (50, 70), (78, 80), (44, 170), (70, 178), (52, 256)]
d.line(pts, fill=(255, 255, 255, 255), width=7, joint="curve")
im = Image.alpha_composite(im.filter(ImageFilter.GaussianBlur(6)), im)
save(im, "qg_bolt")
# cloud (cluster of soft blobs)
im = Image.new("RGBA", (256, 128), (255, 255, 255, 0))
d = ImageDraw.Draw(im)
for (cx, cy, r) in [(70, 74, 38), (120, 56, 48), (176, 72, 40), (130, 88, 42), (90, 92, 30), (200, 92, 26)]:
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 200))
save(im.filter(ImageFilter.GaussianBlur(9)), "qg_cloud")
print("ok")
