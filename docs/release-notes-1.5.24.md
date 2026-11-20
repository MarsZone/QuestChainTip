# 1.5.24

**按 Alt 没反应的真因：这个客户端没有 `GetMouseFocus`**

你 1.5.23 发回来的那两行播报已经说明一切了：

```
按 Alt 没找到任务 | 日志帧: QuestLogPopupDetailFrameInset(隐), … | 选中: nil | 条目: nil
                 | 提示框: 显示 | 持有者: 无
  能定位到的任务: nil | 来源: nil | C_QuestLog: 有 | GetSelectedQuest: 有 | GetMouseFocus: 无
```

`GetMouseFocus: 无` —— 这个客户端根本没这个函数。而 1.5.18~1.5.23 里所有
「问鼠标停在哪个按钮上」的路子全靠它，所以一条都没走通。

## 这一版怎么改的

按键那一刻**把客户端里所有帧遍历一遍，逐个问它自己 `IsMouseOver()`**。
不依赖 `GetMouseFocus`、不依赖钩子、不依赖提示框持有者，全都不用。

识别分三级，前一级不成立就走下一级：

1. 帧上直接挂着任务 ID（Questie 追踪条、服务器任务搜索列表的 `rec.id` 都这么存）
2. 沿祖先链找名字带 `QuestLog` 的帧，用它的 `GetID()` 当日志索引换任务 ID
   —— 行按钮叫 `QuestLogTitle1` 也好、没名字也好、改叫别的名字也好，都能覆盖
3. 兜底：任务日志开着 + 提示框显示着 + 鼠标下是个带数字 ID 的按钮，
   而这个 ID 能换出真任务 —— 那就是任务行

## 顺手修的诊断

- **「日志帧」播报以前等于白播**：前六名全是 `QuestLogPopupDetailFrameInset`、
  `…ShareButton`、`…CloseButton` 这类子件，真正的日志帧被挤到第七名以后。
  现在只列根帧，并单独报告 `QuestLogFrame` 有没有
- 新增一行「鼠标下: 帧名(类型:ID) , …」，一眼能看出鼠标到底压着什么
- `/qct mouse` 重写：不依赖 `GetMouseFocus`，列出鼠标下所有帧和每个帧的祖先链
- 条目数 / 选中行补了 `C_QuestLog` 兜底（老函数这个客户端没有，所以以前都显示 nil）

## 怎么试

1. 打开任务日志，鼠标停在任意一条任务上
2. 按 **Alt**

如果还是没弹，聊天框会自己播报两行，其中「鼠标下」那行是关键：
如果它是「什么都没压到」，说明这个客户端的 `IsMouseOver()` 也不可用，
把那两行发我，我改成钩提示框绘制。

## 安装

覆盖 `Interface\AddOns\QuestChainTip`，`/reload`。
