"""生成 iOS App 图标（无外部依赖，只用 Pillow）。"""

import json
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "DSHClient", "Resources", "Assets.xcassets")
ICONSET = os.path.join(ASSETS, "AppIcon.appiconset")

SIZE = 1024


def gradient(top, bottom):
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(SIZE):
            pixels[x, y] = color
    return image


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def build_icon():
    image = gradient((58, 82, 255), (112, 76, 255))
    draw = ImageDraw.Draw(image)

    # 对话气泡
    rounded(draw, (150, 232, 874, 700), 150, (255, 255, 255))
    draw.polygon([(300, 690), (300, 838), (452, 700)], fill=(255, 255, 255))

    # 三个圆点
    for center in ((368, 466), (512, 466), (656, 466)):
        r = 44
        draw.ellipse((center[0] - r, center[1] - r, center[0] + r, center[1] + r), fill=(74, 96, 255))

    return image


SIZES = [
    ("iphone", "20x20", "2x", 40),
    ("iphone", "20x20", "3x", 60),
    ("iphone", "29x29", "2x", 58),
    ("iphone", "29x29", "3x", 87),
    ("iphone", "40x40", "2x", 80),
    ("iphone", "40x40", "3x", 120),
    ("iphone", "60x60", "2x", 120),
    ("iphone", "60x60", "3x", 180),
    ("ipad", "20x20", "1x", 20),
    ("ipad", "20x20", "2x", 40),
    ("ipad", "29x29", "1x", 29),
    ("ipad", "29x29", "2x", 58),
    ("ipad", "40x40", "1x", 40),
    ("ipad", "40x40", "2x", 80),
    ("ipad", "76x76", "1x", 76),
    ("ipad", "76x76", "2x", 152),
    ("ipad", "83.5x83.5", "2x", 167),
    ("ios-marketing", "1024x1024", "1x", 1024),
]


def main():
    os.makedirs(ICONSET, exist_ok=True)
    icon = build_icon()

    images = []
    seen = {}
    for idiom, size, scale, pixels in SIZES:
        filename = f"AppIcon-{size.replace('.', '_')}@{scale}.png"
        if pixels not in seen:
            resized = icon.resize((pixels, pixels), Image.LANCZOS)
            resized.save(os.path.join(ICONSET, filename), "PNG")
            seen[pixels] = filename
        else:
            filename = seen[pixels]
        images.append({"idiom": idiom, "size": size, "scale": scale, "filename": filename})

    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(ICONSET, "Contents.json"), "w", encoding="utf-8") as handle:
        json.dump(contents, handle, ensure_ascii=False, indent=2)

    with open(os.path.join(ASSETS, "Contents.json"), "w", encoding="utf-8") as handle:
        json.dump({"info": {"author": "xcode", "version": 1}}, handle, ensure_ascii=False, indent=2)

    print("icons:", len(seen), "files in", ICONSET)


if __name__ == "__main__":
    main()
