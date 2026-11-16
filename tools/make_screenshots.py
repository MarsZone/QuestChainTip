#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把游戏内截图排版成商店页用的 1280x720 图（左侧文案 + 右侧截图）。

输入:  docs/screenshots/src/*.png|jpg
输出:  docs/screenshots/01-hover-panel.png / 02-chain-window.png / 03-item-tooltip.png

依赖 Pillow（pip install pillow）。中文字体用 Windows 自带的微软雅黑。
"""

import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "docs", "screenshots", "src")
OUT = os.path.join(ROOT, "docs", "screenshots")

W, H = 1280, 720
MARGIN = 44
TEXT_W = 470                     # 左侧文案区宽度
IMG_X0 = MARGIN + TEXT_W + 24    # 右侧截图区起点
IMG_X1 = W - MARGIN
IMG_Y0, IMG_Y1 = 54, H - 54

BG_TOP = (11, 15, 20)
BG_BOTTOM = (20, 28, 38)
ACCENT = (255, 209, 0)           # 任务黄
TITLE = (255, 255, 255)
BODY = (176, 188, 202)
DIM = (120, 132, 146)

FONT_DIR = r"C:\Windows\Fonts"


def font(name, size):
    path = os.path.join(FONT_DIR, name)
    if not os.path.exists(path):
        return ImageFont.load_default()
    return ImageFont.truetype(path, size)


def gradient(size):
    img = Image.new("RGB", size, BG_TOP)
    draw = ImageDraw.Draw(img)
    for y in range(size[1]):
        t = y / max(size[1] - 1, 1)
        color = tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3))
        draw.line([(0, y), (size[0], y)], fill=color)
    return img


def wrap(draw, text, fnt, max_width):
    """按像素宽度折行，中英文都按单字切；避免最后一行只剩一两个字。"""
    lines, current = [], ""
    for ch in text:
        if ch == "\n":
            lines.append(current)
            current = ""
            continue
        trial = current + ch
        if draw.textlength(trial, font=fnt) <= max_width:
            current = trial
        else:
            lines.append(current)
            current = ch
    if current:
        lines.append(current)

    # 末行只有 1~2 个字时，从上一行挪几个下来，看起来更整齐
    if len(lines) >= 2 and len(lines[-1]) <= 2 and len(lines[-2]) > 4:
        need = 3 - len(lines[-1])
        moved = lines[-2][-need:]
        lines[-2] = lines[-2][:-need]
        lines[-1] = moved + lines[-1]
    return lines


def fit(img, box_w, box_h):
    """等比缩放到框内，但不放大超过原图 1.35 倍（避免糊）。"""
    scale = min(box_w / img.width, box_h / img.height, 1.35)
    size = (max(1, int(img.width * scale)), max(1, int(img.height * scale)))
    return img.resize(size, Image.LANCZOS)


def compose(src_name, out_name, kicker, title, bullets, note):
    canvas = gradient((W, H))
    draw = ImageDraw.Draw(canvas)

    # 左侧竖线装饰
    draw.rectangle([MARGIN - 14, IMG_Y0, MARGIN - 11, IMG_Y1], fill=ACCENT)

    # 顶部小标签
    f_kick = font("msyh.ttc", 19)
    draw.text((MARGIN, 96), kicker, font=f_kick, fill=DIM)

    # 主标题
    f_title = font("msyhbd.ttc", 36)
    y = 128
    for line in wrap(draw, title, f_title, TEXT_W):
        draw.text((MARGIN, y), line, font=f_title, fill=TITLE)
        y += 48

    y += 14
    f_body = font("msyh.ttc", 20)
    for bullet in bullets:
        draw.ellipse([MARGIN + 2, y + 9, MARGIN + 9, y + 16], fill=ACCENT)
        for line in wrap(draw, bullet, f_body, TEXT_W - 26):
            draw.text((MARGIN + 26, y), line, font=f_body, fill=BODY)
            y += 32
        y += 6

    # 底部说明
    f_note = font("msyh.ttc", 17)
    draw.text((MARGIN, H - 74), note, font=f_note, fill=DIM)

    # 右侧截图
    src = Image.open(os.path.join(SRC, src_name)).convert("RGB")
    shot = fit(src, IMG_X1 - IMG_X0, IMG_Y1 - IMG_Y0)
    x = IMG_X0 + (IMG_X1 - IMG_X0 - shot.width) // 2
    yy = IMG_Y0 + (IMG_Y1 - IMG_Y0 - shot.height) // 2

    # 阴影 + 描边，让截图从深色底上浮起来
    shadow = Image.new("RGBA", (shot.width + 24, shot.height + 24), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [0, 0, shadow.width - 1, shadow.height - 1], radius=10, fill=(0, 0, 0, 150))
    canvas.paste(shadow, (x - 12, yy - 10), shadow)
    draw.rectangle([x - 1, yy - 1, x + shot.width, yy + shot.height], outline=(70, 84, 100))
    canvas.paste(shot, (x, yy))

    canvas.save(os.path.join(OUT, out_name), "PNG", optimize=True)
    print("已生成", out_name, canvas.size)


def main():
    os.makedirs(OUT, exist_ok=True)

    compose(
        "01-hover-panel.png", "01-hover-panel.png",
        "世界地图 · 悬停任务图标",
        "已接的任务也能看全",
        [
            "可接、在做、已完成的任何任务都有完整信息",
            "任务描述 · 经验 / 金钱 / 物品奖励",
            "后续任务链（层数可配置）· 前置任务",
            "小地图、聊天框、任务日志里都不弹",
        ],
        "任务链提示 · Quest Chain Tip · 需要 Questie / QuestieDB",
    )

    compose(
        "02-chain-window.jpg", "02-chain-window.png",
        "世界地图 · 按住 Shift",
        "整条链一次看完",
        [
            "每条任务一张卡片：完成条件、奖励、任务详情",
            "在哪接、在哪交（NPC 名字 + 所在区域）",
            "副本 / 团本 / 精英标记",
            "默认折叠已完成，右上角一键展开",
        ],
        "窗口可拖动、可滚动，Esc 关闭",
    )

    compose(
        "03-item-tooltip.png", "03-item-tooltip.png",
        "详情窗 · 物品奖励",
        "奖励物品可悬停查看",
        [
            "物品带品质颜色，和游戏里一致",
            "悬停出物品提示，可和身上装备对比",
            "左键点开完整物品详情",
        ],
        "未接取的任务也能看到物品奖励",
    )


if __name__ == "__main__":
    main()
