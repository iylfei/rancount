#!/usr/bin/env python3
"""从已选定的 RanCount 图标生成品牌图片和 Android adaptive 素材。

用法：python scripts/gen_adaptive_icons.py
随后：dart run flutter_launcher_icons

彩色版保留原图构图；Android XML 的 16% inset 为系统裁切留出空间。
主题图标只读取 alpha，使用 R、图表、钱包与硬币的简化镂空轮廓。
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "icon"
SOURCE = OUT_DIR / "rancount-source.png"
CANVAS = 1024


def gen_monochrome(source):
    """取白色 R 轮廓，并补齐原图中彩色的图表、钱包和硬币。"""
    width, height = source.size
    mask = Image.new("L", source.size, 0)
    pixels = source.load()
    alpha = mask.load()
    for y in range(round(height * 0.15), round(height * 0.83)):
        for x in range(round(width * 0.23), round(width * 0.84)):
            red, green, blue = pixels[x, y]
            if (red > 150 and green > 160 and blue > 160
                    and max(red, green, blue) - min(red, green, blue) < 100):
                alpha[x, y] = 255

    draw = ImageDraw.Draw(mask)

    def box(coords):
        return tuple(round(value * (width if i % 2 == 0 else height))
                     for i, value in enumerate(coords))

    for bounds in [
        (0.304, 0.439, 0.363, 0.531),
        (0.376, 0.389, 0.438, 0.507),
        (0.450, 0.331, 0.514, 0.482),
    ]:
        draw.rounded_rectangle(box(bounds), radius=round(width * 0.010), fill=255)

    draw.rounded_rectangle(box((0.237, 0.511, 0.511, 0.814)),
                           radius=round(width * 0.048), fill=255)
    draw.ellipse(box((0.439, 0.646, 0.478, 0.689)), fill=0)

    # 圆环与镂空货币标记避免 themed icon 把整枚硬币变成实心圆点。
    draw.ellipse(box((0.505, 0.623, 0.651, 0.814)), fill=255)
    draw.ellipse(box((0.521, 0.639, 0.635, 0.798)), fill=0)
    line_width = round(width * 0.014)
    dollar = [
        (0.602, 0.684), (0.589, 0.678), (0.568, 0.678),
        (0.554, 0.693), (0.557, 0.710), (0.590, 0.725),
        (0.599, 0.738), (0.593, 0.753), (0.571, 0.757),
        (0.554, 0.750),
    ]
    draw.line([(round(x * width), round(y * height)) for x, y in dollar],
              fill=255, width=line_width, joint="curve")
    draw.line([(round(width * 0.576), round(height * 0.668)),
               (round(width * 0.576), round(height * 0.767))],
              fill=255, width=round(width * 0.010))

    result = Image.new("RGBA", (CANVAS, CANVAS), (255, 255, 255, 0))
    result.putalpha(mask.resize(result.size, Image.Resampling.LANCZOS))
    return result


def update_ios_icons(source):
    """按现有尺寸更新图片，保留 Xcode 的 Contents.json 配置。"""
    icon_dir = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    manifest = icon_dir / "Contents.json"
    if not manifest.exists():
        return
    entries = json.loads(manifest.read_text(encoding="utf-8"))["images"]
    for entry in entries:
        if "filename" not in entry:
            continue
        size = round(float(entry["size"].split("x")[0])
                     * float(entry["scale"].removesuffix("x")))
        source.resize((size, size), Image.Resampling.LANCZOS).save(
            icon_dir / entry["filename"])


def main():
    source = Image.open(SOURCE).convert("RGB")
    if source.width != source.height:
        raise ValueError("RanCount 图标源文件必须是正方形")
    artwork = source.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)
    artwork.save(OUT_DIR / "launcher_legacy.png")
    artwork.save(OUT_DIR / "adaptive_foreground.png")
    gen_monochrome(source).save(OUT_DIR / "adaptive_monochrome.png")
    for filename, size in [("logo2.png", 800), ("logo_512.png", 512),
                           ("logo_216.png", 216)]:
        source.resize((size, size), Image.Resampling.LANCZOS).save(
            ROOT / "assets" / filename)
    update_ios_icons(source)
    print("RanCount 品牌图片、Android adaptive 素材及 iOS 图标已生成")


if __name__ == "__main__":
    main()
