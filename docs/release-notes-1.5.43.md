# 1.5.43

**修「一收 Questie，我们的也没了」**

## 原因

我们主动 `GameTooltip:Hide()`（为了只留自己的框），但这个动作会触发 GameTooltip 的
`OnHide` 钩子 —— 那个钩子是给「玩家把鼠标移开」用的，里面直接 `T:Hide()`。
于是连锁反应：

收 Questie 的框 → 我们的面板被自己的钩子收掉 → 下一帧发现「我们的面板没显示」→
清掉接管状态 → 两边都空。

你截图里的 `我们的面板: 隐藏 | 接管中的图标: 无 | GameTooltip: 隐藏` 就是这个状态。

## 修法

- 关提示框时加一个「安静关」标志：`suppressTipHide`，`OnHide` 钩子见到它就跳过
- 如果我们的面板真的没了，不再只清状态，而是**把 Questie 的提示框叫回来**（重发图标 OnEnter）
- 新增回归测试 `tests/run_test_map_takeover.lua`：
  接管后必须「Questie 的框没了、我们的还在」，光标离开才收 —— 这条测试在修复前是红的

## 现在应该是

悬停图标 → 只剩我们那张贴光标的框；光标移开 → 面板收起、Questie 的提示框恢复。

## 安装

覆盖 `Interface\AddOns\QuestChainTip`，`/reload`。
