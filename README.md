# 任务链提示 / Quest Chain Tip

一个给《魔兽世界》怀旧服用的任务插件：**悬停任务时，把任务描述、奖励、以及整条后续任务链都显示出来——包括你已经接取、正在做的任务。**

Questie 只对「可接」的任务显示描述、奖励和后续链；已经接下的任务，鼠标移上去只有完成条件。这个插件补的就是这块空白。

---

## 中文

### 功能

- **悬停面板**（默认开启，仅世界地图）：补全任务描述（可配置行数）、经验/金钱/物品奖励、声望、后续任务链、前置任务
  - 显示范围三档：关闭 / 仅世界地图（默认）/ 全部位置
  - **小地图上永远不弹**；聊天框里也永远不弹（那里要复制、要点击链接）
  - 任务日志里不弹，Shift+点击仍然是把任务链接贴到聊天框
- **在世界地图上按住 Shift**：弹出整条任务链的详情窗口，每条任务都有
  - 完成条件（目标列表）
  - 奖励（经验、金钱、物品——带品质颜色，可悬停查看物品详情、左键点开）
  - 任务详情（任务文本）
  - 在哪接、在哪交（NPC 名字 + 区域）
  - 是否副本任务 / 团本任务 / 精英任务
  - 任务状态（可接 / 进行中 / 已完成）
- **默认折叠已完成的任务**，右上角按钮可展开全部
- 窗口可拖动、可滚动，`Esc` 关闭
- 全部文案走自绘面板，不往系统 tooltip 里塞行，所以**不会闪烁**

### 依赖

| 插件 | 说明 |
| --- | --- |
| [Questie](https://www.curseforge.com/wow/addons/questie) | **必需**，提供任务数据库 |
| [QuestieDB](https://www.curseforge.com/wow/addons/questiedb) | **必需**，Questie 的数据源 |

没有 Questie 就只是个空壳，不会报错，但也没内容。

### 安装

1. 关闭游戏
2. 把 `QuestChainTip` 文件夹解压到 `World of Warcraft\_forever_\Interface\AddOns\`
3. 确认路径是 `...\AddOns\QuestChainTip\QuestChainTip.toc`
4. 启动游戏，角色选择界面点「插件」，确认两个插件都勾上

### 命令

| 命令 | 作用 |
| --- | --- |
| `/qct` | 打开设置界面 |
| `/qct on` / `off` | 开关插件 |
| `/qct depth <n>` | 悬停面板显示多少层后续任务（默认 3） |
| `/qct depthshift <n>` | 弹窗显示多少层（默认 20） |
| `/qct detail <任务ID>` | 直接打开详情窗（不带 ID 用最后悬停的任务） |
| `/qct desc` / `reward` / `chain` / `reward2` / `prereq` | 逐项开关 |
| `/qct log` | 打印后台日志（排查问题用） |
| `/qct why` | 诊断：为什么这个提示没识别出任务 |
| `/qct rewards <任务ID>` | 查某条任务的物品奖励 |
| `/qct dump <任务ID>` | 打印某条任务的原始数据 |

### 已知限制

- 物品奖励的来源有三个：客户端接口（只对**已在任务日志里**的任务有效）、本地缓存（接过/交过的任务）、QuestieDB 物品表反查（对未接任务也有效，登录后台扫描一次）
- 不按 Shift 的跟随面板里，物品名**不能**悬停——鼠标一离开任务按钮，面板就消失了，物理上够不到
- 界面文案目前是中文

---

## English

A quest addon for World of Warcraft Classic (Forever / Era client): **shows quest description, rewards and the entire follow-up chain on quest tooltips — including quests you have already accepted.**

Questie only enriches quests you *can* accept. For quests already in your log it shows objectives only. This addon fills that gap.

### Features

- **Hover panel** (off by default, enable in settings): description (configurable lines), XP / money / item rewards, reputation, follow-up chain, prerequisites
  - Scope: off / world map only / everywhere. Never shown in the chat frame
  - Off by default so it cannot cover quest entries and break Shift-click quest linking
- **Hold Shift on the world map for the chain window**: a detail window covering every quest in the chain
  - Objectives
  - Rewards (XP, money, items — quality coloured, hover for the item tooltip, click to open)
  - Quest description
  - Where to accept / hand in (NPC + zone)
  - Dungeon / raid / elite flag
  - Quest state (available / in progress / completed)
- **Completed quests collapsed by default**, toggle button in the top-right
- Draggable, scrollable, `Esc` to close
- Everything is drawn on its own frame — nothing is appended to the system tooltip, so **no flickering**

### Requirements

- [Questie](https://www.curseforge.com/wow/addons/questie) — **required**, provides the quest database
- [QuestieDB](https://www.curseforge.com/wow/addons/questiedb) — **required**, Questie's data source

### Install

Extract the `QuestChainTip` folder into `World of Warcraft\_forever_\Interface\AddOns\` so that
`...\AddOns\QuestChainTip\QuestChainTip.toc` exists, then enable it in the addon list.

### Commands

`/qct` settings · `/qct on|off` · `/qct depth <n>` · `/qct depthshift <n>` · `/qct log` · `/qct why`

### Building a release

```bash
python tools/build_release.py     # reads the version from the .toc -> dist/QuestChainTip-<version>.zip
python tools/make_icon.py         # Media/QuestChainTip.tga + docs/icon-64.png + docs/icon-128.png
```

The zip has a single top-level `QuestChainTip/` folder containing only runtime files and `Media/`.
Full step-by-step publishing guide (per platform, Chinese): [docs/publish-checklist.md](docs/publish-checklist.md)

### Known limitations

- Item rewards come from three sources: the client API (only for quests **currently in your log**), a local cache (quests you accepted before), and a reverse lookup in the QuestieDB item table (works for quests you have not accepted yet; built once per session in the background)
- Item links in the *follow* tooltip panel are not hoverable — the panel disappears as soon as the mouse leaves the quest button
- UI text is currently Chinese only

---

## License

MIT. See [LICENSE](LICENSE).

Questie and QuestieDB are separate projects under their own licenses; this addon only reads their public API at runtime and does not redistribute their data.
