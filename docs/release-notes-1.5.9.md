## 任务链提示 1.5.9 / Quest Chain Tip 1.5.9

界面支持简体 / 繁体 / 英文三种语言。繁体与英文客户端不再显示方块。

The UI now ships in Simplified Chinese, Traditional Chinese and English. No more tofu boxes on zhTW and enUS clients.

---

### 修复 / Fixes

- **繁体客户端界面全是方块**。根因有两层：文案写死简体，而繁体客户端字体是 Big5，
  不含简体特有字（链、奖、励、据这些直接没有字形）。现在按 `GetLocale()` 分流，繁体环境走 `zhTW` 表。
- **英文客户端整个界面不可用**。英文字体 `FRIZQT` 一个中文字形都没有，
  连设置界面的「关闭」按钮都渲染成方块，玩家只能按 Esc 退出。
- **英文折行会切断单词**。原来的折行是逐字符测量，`description` 会被切成 `descri` / `ption`。
  现在 CJK 按字断、拉丁按空格断词，只有单个词超宽（长 URL）才退化成硬切。
- `ChainWindow.lua` 的兜底字体名 `ARKaiT.ttf` → `ARKai_T.ttf`。原文件名并不存在，兜底一直失败。

### 新增 / Added

- `Locale.lua`：**以简体原文作为 key**，简体环境查不到就返回 key 自身，现有文案零改动；
  繁体、英文各一张表，覆盖 104 条界面文案。
- `/qct locale <zhCN|zhTW|enUS|auto>`：手动切换界面语言，照顾客户端语言和习惯语言不一致的玩家。
- 货币单位跟随语言：`金/银/铜` → `金/銀/銅` → `g/s/c`。
- `toc` 补了 `Title-zhTW` / `Notes-zhTW`。
- `tests/run_test_locale.lua`：32 条断言，覆盖三语言取值、占位符、兜底、中英折行、货币单位。

### 说明 / Notes

- 任务名、NPC 名、物品名不受影响：它们来自 Questie 的本地化数据，一直跟随客户端语言。
- 诊断输出（`/qct why`、`/qct log`、`/qct dump`）仍为中文。它们是排查工具，正常游玩不会看到。
- 切换语言后建议 `/reload`，已创建的面板与窗口才会全部用新语言重建。
