# 1.5.32

**背包物品那条路补了两条兜底（1.5.31 里它其实没生效）**

## 为什么没生效

这个客户端的**提示框文本是 secret value**：`GameTooltip:GetItem()` 能拿到字符串，
但只要你真去读（`match` 抠 item ID），立刻抛错。代码里那一层是静默的，
所以按 Alt 什么都不发生，看起来就是"功能没做"。

## 现在怎么拿物品

只在「能从链接里抠出物品 ID」时才认提示框，抠不出来就**改问背包接口**：

- 光标下的格子按名字认：`ContainerFrame<包序号>Item<槽位>`
  （暴雪写死的命名，包号从 **0** 开始，`ContainerFrame1` 就是背包 0 号）
- 链接优先 `GetContainerItemLink(bag, slot)`，没有就 `C_Container.GetContainerItemLink(bag, slot)`

这条路径完全不碰提示框文本，所以不受 secret value 影响。

## 新增诊断：`/qct item`

鼠标停在物品上（背包里的也行），敲 `/qct item`，会打印：

```
---- 物品诊断 ----
提示框: 显示 | GameTooltip.GetItem: 有
  GetItem -> 调用成功 | 名字: xxx | 链接: |Hitem:12345:...
光标下的背包格子: ContainerFrame1Item5 | 包: 0 | 槽位: 5
物品来源: 背包格子 ContainerFrame1Item5 | 链接: |Hitem:12345:... | 物品 ID: 12345
LibQuestieDB: 有 | Item.startQuest: 有
  这件物品开启的任务: 4001
```

哪一行是 `nil` / `取不到`，问题就出在哪一环。

## 用法（没变）

鼠标停在**任务起始物品**上按住 Alt → 弹出它开启的整条任务链。
不是任务起始物品（比如任务奖励物品）→ 什么都不弹。

## 安装

覆盖 `Interface\AddOns\QuestChainTip`，`/reload`。
