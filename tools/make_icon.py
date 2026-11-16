#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成插件图标。

  Media/QuestChainTip.tga   64x64  32 位未压缩 TGA —— 游戏内 toc 的 IconTexture 用
  docs/icon-64.png          64x64  PNG —— 商店页/README 用
  docs/icon-128.png        128x128 PNG —— Wago 的工程图标
  docs/icon-512.png        512x512 PNG —— CurseForge 项目头像（要求 >= 400x400，用 Pillow 抗锯齿）

不依赖 Pillow：直接按像素画 + 自己写 PNG（zlib），保证在任何机器上都能重现。
图形：深蓝圆角底 + 黄色感叹号（任务）+ 右下角链环（任务链）。
"""

import os
import struct
import zlib

SIZE = 64
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT_TGA = os.path.join(ROOT, "Media", "QuestChainTip.tga")
OUT_PNG_64 = os.path.join(ROOT, "docs", "icon-64.png")
OUT_PNG_128 = os.path.join(ROOT, "docs", "icon-128.png")
OUT_PNG_512 = os.path.join(ROOT, "docs", "icon-512.png")

BG = (26, 36, 54)          # 深蓝底
BORDER = (56, 86, 128)     # 边框
MARK = (255, 209, 0)       # 任务黄
MARK_DARK = (196, 148, 0)  # 感叹号描边
LINK = (120, 200, 255)     # 链环蓝


def rounded_alpha(x, y, radius=10):
    """圆角矩形的覆盖判定，返回 0/1。"""
    left, top = 0, 0
    right, bottom = SIZE - 1, SIZE - 1
    cx = min(max(x, left + radius), right - radius)
    cy = min(max(y, top + radius), bottom - radius)
    dx, dy = x - cx, y - cy
    return 1 if dx * dx + dy * dy <= radius * radius else 0


def inside_rect(x, y, x0, y0, x1, y1):
    return x0 <= x <= x1 and y0 <= y <= y1


def inside_ring(x, y, cx, cy, r_out, r_in):
    dx, dy = x - cx, y - cy
    d = dx * dx + dy * dy
    return r_in * r_in <= d <= r_out * r_out


def pixel(x, y):
    if not rounded_alpha(x, y):
        return (0, 0, 0, 0)

    # 边框：距离边缘 2px 内
    edge = (
        x <= 1 or y <= 1 or x >= SIZE - 2 or y >= SIZE - 2
        or not rounded_alpha(x, y, 12)
    )
    color = BORDER if edge else BG

    # 感叹号：竖条 + 下面的点
    if inside_rect(x, y, 27, 14, 36, 40) or inside_rect(x, y, 27, 45, 36, 53):
        color = MARK
        if inside_rect(x, y, 27, 14, 28, 40) or inside_rect(x, y, 27, 45, 28, 53):
            color = MARK_DARK

    # 右下角链环（两个小环，示意"任务链"）
    # 位置刻意避开感叹号：感叹号占 x=27~36，链环从 x=37 起，不互相遮挡。
    if inside_ring(x, y, 46, 47, 9, 6) or inside_ring(x, y, 53, 55, 5.5, 3.2):
        color = LINK

    return (color[0], color[1], color[2], 255)


def write_png(path, size, rows):
    """rows: 每行一个 bytearray，内容是 RGBA。自己写 PNG，不依赖 Pillow。"""
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)  # 8bit RGBA
    payload = (b"\x89PNG\r\n\x1a\n"
               + chunk(b"IHDR", ihdr)
               + chunk(b"IDAT", zlib.compress(raw, 9))
               + chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(payload)
    print("已生成", os.path.normpath(path), len(payload), "字节")


def upscale(rows, factor):
    """最近邻放大，保持像素画风格。"""
    out = []
    for row in rows:
        wide = bytearray()
        for i in range(0, len(row), 4):
            wide += bytes(row[i:i + 4]) * factor
        for _ in range(factor):
            out.append(wide)
    return out


def make_512(rgba_rows):
    """512x512 抗锯齿版，给 CurseForge 当项目头像。

    用 Pillow 在 4 倍画布上按同一套几何重绘再缩回来，避免最近邻放大后的锯齿方块。
    Pillow 不在时退回最近邻 8 倍放大（照样能用，只是边缘硬一些）。
    """
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        write_png(OUT_PNG_512, SIZE * 8, upscale(rgba_rows, 8))
        return

    size, ss = 512, 4
    k = size / float(SIZE) * ss
    canvas = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    def box(x0, y0, x1, y1):
        return [x0 * k, y0 * k, x1 * k, y1 * k]

    # 底板 + 边框
    draw.rounded_rectangle(box(0, 0, SIZE - 1, SIZE - 1), radius=10 * k, fill=BG + (255,))
    draw.rounded_rectangle(box(1, 1, SIZE - 2, SIZE - 2), radius=11 * k,
                           outline=BORDER + (255,), width=max(1, int(round(2 * k))))

    # 感叹号：竖条 + 下面的点
    draw.rectangle(box(27, 14, 36, 40), fill=MARK + (255,))
    draw.rectangle(box(27, 45, 36, 53), fill=MARK + (255,))
    draw.rectangle(box(27, 14, 28, 40), fill=MARK_DARK + (255,))
    draw.rectangle(box(27, 45, 28, 53), fill=MARK_DARK + (255,))

    # 右下角两个链环
    for cx, cy, r_out, r_in in ((46, 47, 9, 6), (53, 55, 5.5, 3.2)):
        draw.ellipse(box(cx - r_out, cy - r_out, cx + r_out, cy + r_out),
                     outline=LINK + (255,), width=max(1, int(round((r_out - r_in) * k))))

    canvas = canvas.resize((size, size), Image.LANCZOS)
    canvas.save(OUT_PNG_512)
    print("已生成", os.path.normpath(OUT_PNG_512), os.path.getsize(OUT_PNG_512), "字节")


def main():
    os.makedirs(os.path.dirname(OUT_TGA), exist_ok=True)
    os.makedirs(os.path.dirname(OUT_PNG_64), exist_ok=True)

    rows = []
    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            r, g, b, a = pixel(x, y)
            row += bytes((b, g, r, a))  # TGA 是 BGRA
        rows.append(bytes(row))

    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,      # id length
        0,      # color map type
        2,      # image type: uncompressed true-color
        0, 0, 0,  # color map spec
        0, 0,   # x/y origin
        SIZE, SIZE,
        32,     # bits per pixel
        8,      # alpha bits, origin bottom-left
    )

    with open(OUT_TGA, "wb") as handle:
        handle.write(header)
        for row in reversed(rows):  # TGA 默认从下往上存
            handle.write(row)
    print("已生成", os.path.normpath(OUT_TGA), os.path.getsize(OUT_TGA), "字节")

    # PNG 用 RGBA 顺序，需要从 BGRA 换回来
    rgba_rows = []
    for row in rows:
        fixed = bytearray()
        for i in range(0, len(row), 4):
            b, g, r, a = row[i], row[i + 1], row[i + 2], row[i + 3]
            fixed += bytes((r, g, b, a))
        rgba_rows.append(fixed)

    write_png(OUT_PNG_64, SIZE, rgba_rows)
    write_png(OUT_PNG_128, SIZE * 2, upscale(rgba_rows, 2))
    make_512(rgba_rows)


if __name__ == "__main__":
    main()
