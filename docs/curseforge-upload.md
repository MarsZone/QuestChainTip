# CurseForge 上传清单 —— Quest Chain Tip 1.5.9

> 目标：在 CurseForge 建一个公开项目，让 WowUp / CurseBreaker / CurseForge 客户端的玩家能搜到并安装。
> 全部字段照抄本文，不需要自己想文案。

---

## 先说结论：能传，而且版本号精确匹配

我之前判断「CurseForge 会因 `Interface: 16001` 判不兼容」是**错的**，现在纠正。

CurseForge 早就有了 **Forever** 这个分支，专门对应 1.60.x 客户端。证据（都是刚抓的页面）：

| 项目 | 文件上标的 Game Versions | Flavors |
|---|---|---|
| **Questie**（Project ID 334372） | `1.60.1` 排在第一位 | `Forever` / MoP Classic / Titan Reforged Classic / Classic / Classic TBC |
| **AtlasLoot Forever** | `1.60.1+1` | `Classic+1` |
| Questie 的 Forever 筛选 | `gameVersionTypeId=88568` | — |

所以 `## Interface: 16001` 会被 CurseForge 解析成 **1.60.1**，自动落到 Forever 分支上，和 Wago 的 `Supported Forever patch: 1.60.1` 是同一套体系。

**不要为了传 CurseForge 去改 `toc` 里的 16001。** 改了反而和真实客户端对不上。

---

## 一、创建项目

入口：登录 `curseforge.com` → 右上角头像 → **Author Dashboard** → **Create Project**
（或直接开 `https://authors.curseforge.com/#/projects/create`）

| 字段 | 填什么 |
|---|---|
| **Game** | `World of Warcraft` |
| **Project Name** | `Quest Chain Tip` |
| **Project Slug / URL** | 自动生成 `quest-chain-tip`，不要改 |
| **Summary** | 见下方「Summary」，≤ 200 字符 |
| **Category（Primary）** | `Quests & Leveling` |
| **Additional Categories** | `Map & Minimap`、`Tooltip` |
| **Project Avatar** | `docs\icon-512.png`（512×512，CurseForge 要求 ≥ 400×400） |
| **License** | `MIT` |
| **Description** | 见下方「Description」，编辑器切到 **Markdown** 再粘 |
| **Allow Comments** | 勾上 |
| **EULA / 条款** | 必须同意 Author Agreement 才能建项目 |

**Summary**（复制这一行，不要换行）：

```
Questie enriches quests you can still accept. This adds the same for quests already in your log: description, rewards and the whole follow-up chain. Hover on the world map, hold Shift for the full chain window.
```

---

## 二、上传文件

项目建好后 → 左侧 **Files** → **Upload File**

| 字段 | 填什么 |
|---|---|
| **File** | `E:\AI\wowaddones\QuestChainTip\dist\QuestChainTip-1.5.9.zip` |
| **Display Name** | 自动读成 `Quest Chain Tip 1.5.9`，不用改 |
| **Release Type** | `Release` |
| **Game Versions** | 应自动勾上 **`1.60.1`**；如果没勾上，手动在列表里找到 `1.60.1` 勾选 |
| **Changelog** | 见下方「Changelog」 |
| **Changelog Type** | `Markdown` |

> ⚠️ 上传框是系统级弹窗，路径可以直接 `Ctrl+V` 粘进去再回车：
> `E:\AI\wowaddones\QuestChainTip\dist\QuestChainTip-1.5.9.zip`

---

## 三、Description（整段复制，编辑器切到 Markdown）

```markdown
### The gap it fills

Questie shows description, rewards and the follow-up chain only for quests you have **not** accepted yet. Once a quest is in your log, hovering it gives you objectives and nothing else — you cannot tell how many steps remain, what they reward, or whether the chain sends you into a dungeon.

Quest Chain Tip fills that gap for every quest: available, in progress, and completed.

### Hover panel on the world map

- Quest description (configurable line count)
- Rewards: XP, money, items (quality coloured), reputation
- Follow-up chain (configurable depth, default 3)
- Prerequisites

Shown only on world map quest markers by default; can be set to "off" or "everywhere". It never shows on the minimap, never in the chat frame (so Shift-click quest linking still works), and never in the quest log — Shift-click there stays the native "link to chat" behaviour.

### Hold Shift on the world map for the chain window

One card per quest in the chain:

- Objectives
- Rewards — XP, money, items. Items are quality coloured, hover for the item tooltip, click to open
- Quest description text
- Where to accept / hand in (NPC name + zone)
- Dungeon / raid / elite flag
- State: available / in progress / completed

Completed quests are collapsed by default; one button in the top-right expands everything. The window is draggable and scrollable, `Esc` closes it.

### Requirements

- **Questie** — required, ships the quest database
- **QuestieDB** — required, ships the item table used for the reward index
- Client: WoW "Forever" 1.60.1 (Interface 16001)

This addon does **not** redistribute the Questie database. It only reads it.

### Notes

- Nothing is appended to the system tooltip — everything is drawn on its own frame, so there is no flicker
- Item rewards also work for quests you have not accepted: the addon scans the QuestieDB item table (`questRewards`) once per session and builds a reverse quest → item index
- Panel background, border and font are read live from `GameTooltip`, so it matches whatever UI or tooltip skin you run

### Commands

| Command | What it does |
|---|---|
| `/qct` | Open settings |
| `/qct depth 5` | Show 5 levels of the follow-up chain |
| `/qct detail` | Toggle the chain window |
| `/qct explain` | Toggle chat diagnostics (off by default) |
| `/qct why` · `/qct log` | Attach these when reporting a problem |

### Localisation

Quest names, NPC names and item names follow your client locale via Questie. The addon's own labels are currently **Chinese only** — an English UI pass is planned. If you do not read Chinese, wait for that version or open an issue on GitHub.

### Links

- Source and issue tracker: https://github.com/MarsZone/QuestChainTip
```

> 最后一段「Localisation」是故意写的。界面目前只有中文，与其让国外玩家装了发现看不懂再给差评，
> 不如提前说明，同时把「英文版在做了」这个信息传出去。

---

## 四、Changelog（整段复制）

```markdown
First public release.

Questie only enriches quests you can still accept. This adds the same for quests already in your log: description, rewards and the whole follow-up chain. Hover a world map quest marker for the summary panel, hold Shift for the full chain window.

**Hover panel (world map)**
- Quest description (configurable line count)
- Rewards: XP, money, items (quality coloured), reputation
- Follow-up chain (configurable depth, default 3)
- Prerequisites

**Chain window (hold Shift)**
- One card per quest: objectives, rewards, quest text, where to accept / hand in, dungeon flag, state
- Completed quests collapsed by default, one button expands all
- Draggable, scrollable, Esc closes

**Notes**
- Requires Questie and QuestieDB
- Client: WoW "Forever" 1.60.1 (Interface 16001)
- Nothing is appended to the system tooltip — drawn on its own frame, so there is no flicker
```

---

## 五、图标与截图

**Project Avatar**：`docs\icon-512.png`（512×512）

**Gallery**（左侧 `Gallery` 标签，按这个顺序传，第一张是封面）：

```
E:\AI\wowaddones\QuestChainTip\docs\screenshots\01-hover-panel.png
E:\AI\wowaddones\QuestChainTip\docs\screenshots\02-chain-window.png
E:\AI\wowaddones\QuestChainTip\docs\screenshots\03-item-tooltip.png
```

三张都是 1280×720，不用再裁。

---

## 六、依赖关系（建议做，两分钟）

项目左侧 **Relations** → **Add Relation**

| 字段 | 填 |
|---|---|
| Type | `Required Dependency` |
| Project | 搜 `Questie`，选作者 `TheCrux_BB` 那个（Project ID `334372`） |

设了之后，玩家从 CurseForge 装这个插件时，客户端会提示「还需要 Questie」，能挡掉一批「装了没反应」的反馈。

QuestieDB 在 CurseForge 上没有独立项目（它是 Questie 的一部分），所以只挂 Questie 一个。

---

## 七、几个容易踩的坑

**1. 上传后状态不是 `Approved`**
新项目首次上传可能进审核队列，几分钟到几小时。显示 `Under Review` 属正常，等它变绿。期间项目页已经能打开，只是下载按钮灰的。

**2. 版本号没自动识别**
如果 Game Versions 显示 `Unknown` 或空白，手动勾 `1.60.1`。**不要去改 toc**。

**3. 域名和国内访问**
`curseforge.com` 国内直连不通，需要走你那个 1081 代理。上传大文件时如果卡住，换 Chrome 无痕窗口重试。

**4. 别开「Hide from search」**
CurseForge 没有这个选项，但有 **Private / Unlisted** 状态。项目必须保持 **Public**，否则更新器收录不到。

**5. 描述里的 Markdown**
CurseForge 的描述编辑器默认可能是富文本模式。粘之前先点右上角切到 **Markdown**，否则 `###` 和列表符号会原样显示成一堆井号。

---

## 八、以后更新

CurseForge 有个比 Wago 好的地方：**支持 GitHub 自动打包**。

但和 Wago 一样，我不建议现在就配。手动传一次的成本是两分钟，而自动打包要求 tag 格式、Release 附件、zip 内部结构三者严格对应，配错了是静默失败，排查比手动传累。

手动更新流程：

```
Files → Upload File → 传 dist\QuestChainTip-1.5.9.zip
→ Release Type: Release
→ Game Versions: 1.60.1
→ Changelog 粘新版说明
```

旧版本文件会自动变成「历史版本」，玩家仍能下载，不用删。

---

## 九、传完要回填的三处

1. **CurseForge 项目链接** → 填进 `docs/wclbox-apply.md` 的「已发布渠道」（新手盒子入驻申请）
2. **CurseForge 项目链接** → 填进 NGA 帖子正文的「下载」段
3. **CurseForge 项目链接** → 填进 GitHub 仓库右侧的 About → Website

CurseForge 链接格式：`https://www.curseforge.com/wow/addons/quest-chain-tip`
