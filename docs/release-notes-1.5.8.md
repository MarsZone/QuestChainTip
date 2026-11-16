## 任务链提示 1.5.8 / Quest Chain Tip 1.5.8

已接取的任务也能看到后续任务链、奖励和完整详情。世界地图上悬停任务图标出简介面板，按住 Shift 出整条链的详情窗。

Questie only enriches quests you can still accept. This adds the same for quests already in your log: description, rewards and the whole follow-up chain. Hover a world map quest marker for the summary panel, hold Shift for the full chain window.

---

### 本版修复 / Fixes

- **世界地图上悬停/按 Shift 终于稳定可用**。之前几版用「祖先链里有没有 ScrollFrame」判断是不是列表行，
  而这个客户端的世界地图画布本身就是滚动帧，导致整张地图的任务标记被一次性排掉。
  现在只保留两条有名字依据的排除：名字带 `QuestLog` 的行、聊天框。
- **地图标记与右侧任务列表分开**：两者结构几乎一样（都是无名 Button 套无名 ScrollFrame），
  唯一稳定差别是画布那个 ScrollFrame 的父级直接是 `WorldMapFrame`。按这条区分。
- **小地图永远不弹**：Questie 图标按 `miniMapIcon` 区分地图/小地图。
- **悬停面板默认改为「仅世界地图」**（原来默认关闭）。老存档做一次性迁移。
- **聊天框诊断改为设置项，默认关闭**（`/qct explain` 或设置里勾选）。
- 修复 `QCT:Print` 只输出第一个参数（之前所有诊断信息都只有冒号前半句）。
- 修复提示框持有者依赖 `SetOwner` 钩子、钩子失效时全部判定同时失效且不报错。
- 钩子改为逐个独立安装，Shift 监听第一个装——任一钩子失败不再连坐。

### 功能 / Features

- 悬停面板：任务描述（行数可配置）、经验/金钱/物品奖励（带品质颜色）、声望、后续链（层数可配置）、前置任务
- Shift 详情窗：每条任务一张卡片——完成条件、奖励、任务文本、接取/交付 NPC + 区域、副本/团本/精英标记、任务状态
- 默认折叠已完成任务，右上角一键展开
- 物品奖励对**未接取**的任务也有效（后台扫描 QuestieDB 物品表反查）
- 全部自绘，不往系统 tooltip 追加内容，不会闪烁

### 依赖 / Requirements

- Questie（必需）
- QuestieDB（必需）

### 安装 / Install

把 `QuestChainTip` 文件夹解压到 `World of Warcraft\_forever_\Interface\AddOns\`，
使 `...\AddOns\QuestChainTip\QuestChainTip.toc` 存在，然后在插件列表里启用。

### 客户端 / Client

永久 60 / 怀旧服，`## Interface: 16001`

---

完整更新日志见 [CHANGELOG.md](https://github.com/OWNER/QuestChainTip/blob/main/CHANGELOG.md)。
