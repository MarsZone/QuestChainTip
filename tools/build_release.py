#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""打包发布用 zip。

规则（各大平台通用）：
  * zip 里必须有一个和插件同名的顶层文件夹：QuestChainTip/QuestChainTip.toc
  * 只放运行需要的文件：toc 里列出的 lua + toc 自己 + Media/
  * tools/、tests/、*.md 这些不进包（CurseForge / 网易DD / 新手盒子都只要运行文件）

用法：
  python tools/build_release.py            # 生成 dist/QuestChainTip-<版本>.zip
  python tools/build_release.py --check    # 只做检查，不打包
"""

import os
import re
import sys
import zipfile

ADDON = "QuestChainTip"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")


def read_toc():
    path = os.path.join(ROOT, ADDON + ".toc")
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()

    meta = {}
    files = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if line.startswith("##"):
            body = line[2:]
            if ":" in body:
                key, value = body.split(":", 1)
                meta[key.strip()] = value.strip()
            continue
        if line.startswith("#"):
            continue
        files.append(line)

    return meta, files


def collect(meta, files):
    """返回 [(磁盘绝对路径, zip 内相对路径)]"""
    entries = []

    toc_name = ADDON + ".toc"
    entries.append((os.path.join(ROOT, toc_name), toc_name))

    for name in files:
        path = os.path.join(ROOT, name.replace("\\", "/"))
        entries.append((path, name.replace("\\", "/")))

    media_dir = os.path.join(ROOT, "Media")
    if os.path.isdir(media_dir):
        for name in sorted(os.listdir(media_dir)):
            full = os.path.join(media_dir, name)
            if os.path.isfile(full):
                entries.append((full, "Media/" + name))

    return entries


def check(meta, entries):
    problems = []
    for key in ("Interface", "Title", "Version", "SavedVariables"):
        if key not in meta:
            problems.append("toc 缺少字段: " + key)

    for disk, rel in entries:
        if not os.path.isfile(disk):
            problems.append("toc 里列了但文件不存在: " + rel)

    # 图标路径必须指向自己包里的文件，不能指向 Questie（用户没装 Questie 就裂图）
    icon = meta.get("IconTexture", "")
    if icon:
        expected = "Interface\\AddOns\\" + ADDON + "\\"
        if not icon.startswith(expected):
            problems.append("IconTexture 没有指向本插件目录: " + icon)
        else:
            rel = icon[len(expected):].replace("\\", "/")
            if not os.path.isfile(os.path.join(ROOT, rel)):
                problems.append("IconTexture 指向的文件不存在: " + rel)
            if not rel.lower().endswith((".tga", ".blp")):
                problems.append("图标格式建议用 .tga/.blp: " + rel)

    if "OptionalDeps" in meta and "Questie" not in meta["OptionalDeps"]:
        problems.append("OptionalDeps 里没有 Questie")

    return problems


def build(meta, entries):
    version = meta.get("Version", "0.0.0")
    os.makedirs(DIST, exist_ok=True)
    out = os.path.join(DIST, "%s-%s.zip" % (ADDON, version))

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for disk, rel in entries:
            archive.write(disk, ADDON + "/" + rel)

    return out


def main():
    meta, files = read_toc()
    entries = collect(meta, files)

    problems = check(meta, entries)
    if problems:
        print("检查未通过：")
        for item in problems:
            print("  - " + item)
        return 1

    print("版本: %s | 文件数: %d" % (meta.get("Version"), len(entries)))
    for _, rel in entries:
        print("  " + rel)

    if "--check" in sys.argv:
        print("检查通过（未打包）")
        return 0

    out = build(meta, entries)
    size = os.path.getsize(out)
    print("\n已生成 %s（%.1f KB）" % (os.path.normpath(out), size / 1024.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
