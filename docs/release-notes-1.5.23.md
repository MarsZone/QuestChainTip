# 1.5.23

**你说对了：那就是姓名板。所以数字直接挂到姓名板上**

---

## 一、诊断结果：这是「现代 API 的客户端」

你那张 `/qct qlog` 截图里有三条决定性信息：

```
日志帧: QuestLogPopupDetailFrameInset(隐), QuestLogPopupDetailFrameShareButton(隐), ...
选中: nil | 条目: nil
GetMouseFocus: 无 | GetQuestLink: 有 | GetQuestLogSelection: 无
```

`GetQuestLogSelection` 在 **8.0 就被暴雪移除了**，`GetMouseFocus` 在 **10.0 被移除**。
也就是说：无限服 1.60.1 虽然内容是最老的版本，但**底层是一套现代 API 的客户端**
（有 `C_NamePlate`、有 `C_QuestLog`）。

这就解释了前面几版为什么全废：我们一直在用 1.12 时代的接口找东西。

## 二、血量：挂到「目标的姓名板」上

既然那个框是姓名板，就不该去找「目标框」了。现代 API 直接给：

```lua
C_NamePlate.GetNamePlateForUnit("target")   -- 目标那块牌子
plate.UnitFrame.healthBar                   -- 牌子上的血条
```

现在姓名板是**第一候选**：

- 目标有姓名板 → 数字挂牌子上，跟着牌子走（牌子移动、缩放都对）
- 怪物进出视野导致牌子重建 → 监听 `NAME_PLATE_UNIT_ADDED` / `REMOVED` 自动重挂
- 目标没有姓名板（友方、或姓名板关掉了）→ 才退回暴雪那个框体

如果还是不显示，`/qct health float` 那个可拖动的数字依然在，随时能用。

## 三、任务日志按 Alt：改用 `C_QuestLog.GetSelectedQuest()`

`GetQuestLogSelection` 不存在了，替代品是 `C_QuestLog.GetSelectedQuest()`，
它**直接返回任务 ID**，连索引都不用换算。

用法不变：**在任务日志里点一下任务行（让它选中），然后按 Alt。**

## 四、诊断也换成现代 API

`/qct qlog` 现在会打：

```
C_QuestLog: 有 | C_QuestLog.GetSelectedQuest: 有 | C_QuestLog.GetInfo: 有 | C_NamePlate: 有
当前选中的任务: 3001
```

按 Alt 没开窗时的自动播报也是这一套。如果还有问题，把这两行发我即可。

---

安装：解压到 `Interface/AddOns/QuestChainTip`，`/reload` 生效。
