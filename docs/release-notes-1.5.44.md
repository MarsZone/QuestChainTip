# 1.5.44

**消掉「Questie 的框闪一下」**

原因：之前是**先让 Questie 画出来**，我们再在 0.12 秒内把它收掉 —— 那一瞬间就是你看到的闪。

## 改成在它画之前拦

Questie 画地图图标提示框走的是纯 Lua 函数
`MapIconTooltip.ShowOnTooltip(self, tooltip, owner, icons)`，我们直接包了一层：

- 能认出任务 **且** 我们自己的面板画得出来 → **我们画，并且不调用原函数**
  → Questie 的框从头到尾没出现过，不可能闪
- 认不出任务 / 我们画不出来 / 功能关掉 → 原样调用，Questie 照常显示
- 万一拿不到 `QuestieLoader` 或这个模块（换版本、换整合包）→ 自动退回上一版的轮询方式

## 回归测试

`tests/run_test_map_takeover.lua` 新增两条：

- 调一次 `ShowOnTooltip` → 返回 `handled=true`、**GameTooltip 始终没显示**、我们的面板在
- 认不出任务的图标 → `ShowOnTooltip` 照常把 Questie 的框显示出来

## 安装

覆盖 `Interface\AddOns\QuestChainTip`，`/reload`。
