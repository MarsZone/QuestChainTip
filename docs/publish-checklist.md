# 发布清单（Quest Chain Tip）

这份清单是「照着做就能发出去」的版本。物料已经全部备齐，只差你在各平台上点几下。

---

## 一、现在手上有什么

| 物料 | 路径 | 说明 |
|---|---|---|
| 发布包 | `dist/QuestChainTip-1.5.8.zip` | 45.8 KB，顶层是 `QuestChainTip/` 文件夹，`toc` 在文件夹根部 |
| 工程图标 | `docs/icon-128.png` | 128×128 PNG，CurseForge / Wago 的工程图标要求这个尺寸 |
| 小图标 | `docs/icon-64.png` | 64×64，README / 帖子配图用 |
| 游戏内图标 | `Media/QuestChainTip.tga` | 已打进包，`toc` 的 `IconTexture` 指向它 |
| 中文文案 | `docs/listing-zh.md` | 简介 + 详细说明 + 标签 + 截图建议，可直接粘 |
| 英文文案 | `docs/listing-en.md` | 同上，英文版 |
| 更新日志 | `CHANGELOG.md` | 建议每次发版把当前版本那一段贴到平台 |
| 许可证 | `LICENSE` | MIT，已打进包 |

**截图还没做**，平台一般要 3–5 张。按 `docs/listing-zh.md` 最后的顺序拍：

1. 世界地图上悬停任务图标 → 补全面板
2. 世界地图上按住 Shift → 整条链详情窗
3. 详情窗里物品名悬停 → 物品提示
4. 设置界面
5. 对比图（Questie 原生 vs 本插件）

> 拍图小技巧：用 `/console screenshotFormat png`，`PrintScreen` 存到 `World of Warcraft\_forever_\Screenshots\`。
> 建议裁掉黑边，统一成 16:9，第一张最重要——它就是列表页的封面。

---

## 二、发布前 60 秒自检

```bash
cd E:/AI/wowaddones/QuestChainTip

# 1) 语法 + 自动化测试（应输出「全部通过」）
python /tmp/runtests.py | grep -E "FAIL|全部通过"

# 2) 重新打包（版本号取自 toc，会顺带校验 toc 字段和文件是否齐全）
python tools/build_release.py

# 3) 确认包结构：顶层必须是 QuestChainTip/ 文件夹，不能是散文件
python -c "import zipfile;print('\n'.join(zipfile.ZipFile('dist/QuestChainTip-1.5.8.zip').namelist()))"
```

包结构应该是这样（9 个文件，不多不少）：

```
QuestChainTip/QuestChainTip.toc
QuestChainTip/Core.lua
QuestChainTip/Log.lua
QuestChainTip/Format.lua
QuestChainTip/Data.lua
QuestChainTip/Tooltip.lua
QuestChainTip/ChainWindow.lua
QuestChainTip/Options.lua
QuestChainTip/Media/QuestChainTip.tga
```

`tools/`、`docs/`、`tests/`、`dist/` 不会被打进包——这是对的，玩家不需要。

---

## 三、渠道怎么选

| 渠道 | 面向 | 建议 |
|---|---|---|
| **新手盒子** | 国内，永久60/怀旧服玩家最多 | **首选**，先发这里 |
| **网易DD** | 国内 | 第二发，同一份 zip 直接传 |
| **NGA 插件区** | 国内硬核玩家 | 发帖 + 附件，回复里收集问题最快 |
| **GitHub Release** | 国外 + 想留源码 | 必做，后面所有渠道都可以链到这里 |
| **Wago.io** | 国外 | 支持自定义 Interface，比 CurseForge 好过 |
| **CurseForge** | 国外最大 | 见下面「注意」，Interface 16001 可能被判不兼容 |

> ⚠️ **关于 CurseForge**：它的版本识别是读 `toc` 的 `## Interface: 16001`，
> 而 16001 不是暴雪官方版本号（官方 Classic Era 是 115xx 这一档）。
> 上传后大概率会被标成「不支持的版本」或需要手动指定 Game Version。
> 如果你的用户主要是永久60 客户端，**优先国内盒子 + GitHub + Wago**，CurseForge 可以最后再说。

---

## 四、各平台操作

### 1. 新手盒子

1. 进「插件上传 / 创作者中心」，新建插件
2. 名称填 `任务链提示`（英文名 `Quest Chain Tip` 一起填，如果表单有英文名字段）
3. 分类选 **任务 / Quests**
4. 适用客户端选 **永久60 / 怀旧服**
5. 上传 `dist/QuestChainTip-1.5.8.zip`（**不要解压、不要重新压**）
6. 简介、详细说明：从 `docs/listing-zh.md` 复制
7. 依赖填 `Questie`、`QuestieDB`（这两个是硬依赖，一定要写，否则玩家装上不工作）
8. 上传截图，第一张当封面
9. 提交审核

> 平台如果要求填「插件 ID / 文件夹名」，就是 `QuestChainTip`，必须和 zip 里的文件夹同名。

### 2. 网易DD

流程基本同上：新建条目 → 传 zip → 填文案 → 传图 → 提审。
两个平台可以复用同一份 zip 和同一份文案，不用改。

### 3. NGA / 论坛帖

标题建议：

```
[插件] 任务链提示 Quest Chain Tip 1.5.8 —— 已接的任务也能看后续链、奖励和详情
```

正文 = `docs/listing-zh.md` 的详细说明 + 截图 + zip 附件。
把「已接任务看不到后续链」这个痛点写在第一段，这是这个插件唯一的卖点。

### 4. GitHub（单一真源，先发这个）

本地仓库**已经建好并打好 tag 了**（`v1.5.8`，工作区干净），只差推到远端。

**第一步：在 github.com 新建一个空仓库**（不要勾 README / .gitignore / license），名字建议 `QuestChainTip`。

**第二步：推上去**

```bash
cd E:/AI/wowaddones/QuestChainTip

git remote add origin https://github.com/<你的账号>/QuestChainTip.git
git push -u origin main
git push origin v1.5.8
```

> 如果 `git push -u origin main` 报 `src refspec main does not match`，说明当前分支叫 `master`，
> 先 `git branch -M main` 再推。

**第三步：建 Release**

网页上 **Releases → Draft a new release**：

- Tag：选已有的 `v1.5.8`（别新建）
- Title：`Quest Chain Tip 1.5.8`
- 描述：整个文件复制 `docs/release-notes-1.5.8.md`（中英双语，已写好）
- 附件：上传 `dist/QuestChainTip-1.5.8.zip`
- 发布

发完之后这个 Release 的下载链接就是**唯一真源**，后面新手盒子 / 网易DD / NGA 帖子里都可以链它：

```
https://github.com/<你的账号>/QuestChainTip/releases/latest
```

**装了 gh CLI 的话可以一条命令搞定**（可选）：

```bash
gh repo create QuestChainTip --public --source=. --push
gh release create v1.5.8 dist/QuestChainTip-1.5.8.zip \
  --title "Quest Chain Tip 1.5.8" \
  --notes-file docs/release-notes-1.5.8.md
```

### 5. Wago.io

New Addon → 填名称 → 上传同一份 zip → 版本号会自动从 `toc` 读出来 → 贴英文文案 → 传图标和截图。

### 6. CurseForge（可选）

New Project → 类型 **World of Warcraft** → 上传 zip → 手动把 Game Version 勾到 Classic Era →
贴 `docs/listing-en.md` → 传 `docs/icon-128.png` → 传截图 → License 选 MIT。
如果提示版本不兼容，忽略即可，玩家仍能手动安装。

---

## 五、以后发新版本（固定四步）

```bash
cd E:/AI/wowaddones/QuestChainTip

# 1) 改版本号（只改 toc，脚本会读它）
sed -i 's/^## Version: .*/## Version: 1.5.9/' QuestChainTip.toc

# 2) 在 CHANGELOG.md 顶部加一段 ## 1.5.9

# 3) 跑测试 + 打包
python /tmp/runtests.py | grep -E "FAIL|全部通过"
python tools/build_release.py

# 4) 装到游戏里自测一遍
cp -f *.lua *.toc "F:/Wow/World of Warcraft/_forever_/Interface/AddOns/QuestChainTip/"
```

然后到各平台「上传新版本」，zip 换成新的就行，插件 ID 不用变——老用户的更新会自动接上。

**版本号三处一致**：`toc` 的 `## Version`、`CHANGELOG.md` 的段落标题、zip 文件名。
`build_release.py` 是读 `toc` 生成文件名的，所以只要改 `toc`，另外两个跟着对就行。

---

## 六、容易踩的坑

1. **zip 里多一层或少一层**：必须是 `QuestChainTip/xxx.toc`。多包一层变成
   `QuestChainTip/QuestChainTip/xxx.toc`，玩家装上插件列表里就是空的。
   → `build_release.py` 已经保证这一点，别手动重新压。
2. **别用 Windows 右键「压缩到 zip」**：会带 `__MACOSX` 或反斜杠路径，某些管理器解压后目录是乱的。
3. **`## Interface` 写错**：这个客户端是 `16001`（和 QuestieDB 一致）。写错会被标成「过期插件」。
4. **`IconTexture` 指向包外**：现在指向 `Interface\AddOns\QuestChainTip\Media\QuestChainTip.tga`，
   是包内文件，正确。换成别的插件的图标会在别人机器上变成问号。
5. **依赖没写**：Questie / QuestieDB 是硬依赖。没写的话玩家装上会看到「没有找到 Questie」的提示。
6. **聊天框诊断默认是关的**：设置里有「聊天框显示诊断信息」（`/qct explain` 也能开关），
   默认关闭，玩家不会看到任何调试行。让反馈问题的玩家打开这个再截图，效率最高。
