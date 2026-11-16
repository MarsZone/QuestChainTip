#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成插件图标。

  Media/QuestChainTip.tga   64x64  32 位未压缩 TGA —— 游戏内 toc 的 IconTexture 用
  docs/icon-64.png          64x64  PNG —— 商店页/README 用
  docs/icon-128.png        128x128 PNG —— CurseForge / Wago 的工程图标要求 128x128

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
    if inside_ring(x, y, 44, 46, 11, 7) or inside_ring(x, y, 54, 54, 8, 4):
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


if __name__ == "__main__":
    main()
