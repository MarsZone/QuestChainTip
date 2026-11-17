## 任务链提示 1.5.10 / Quest Chain Tip 1.5.10

修两个 bug：详情窗渲染崩溃、关掉地图后按 Shift 还能弹窗。

Two bug fixes: a crash while rendering the chain window, and the window still popping up after you close the world map.

---

### 修复 / Fixes

- **关掉地图后按 Shift 还会弹详情窗**。地图上 Shift 开窗 → 按 M 关地图 → 再按 Shift，窗口又冒出来。
  根因是关图后 Questie 的地图图标帧对象还在（只是跟着地图一起不可见），
  而判定函数只看结构、不看可见性，仍然认它是「地图图标」；Shift 那条路径也从来没检查过世界地图开没开。
  现在开窗前必须确认世界地图真的开着。
- **世界地图关闭时，详情窗自动收起**。它是「地图上按住 Shift」的产物，
  地图都关了还飘在屏幕中间，玩家会以为关不掉。
- **详情窗渲染中断**：`Data.lua` 里 `SafeString` 先使用后声明——它的实现写在 `GetDescription` 之后，
  函数体里的引用被解析成全局变量（`nil`）。一旦 Questie 没有这条任务的数据、需要回落到客户端接口取目标文本，
  就会抛 `attempt to call a nil value`，窗口只画一半或者内容不刷新。
  触发条件是任务只存在于客户端任务日志里（Questie 未收录，或玩家没装 QuestieDB）。
- 「未安装 QuestieDB 独立插件」的诊断日志改成正常提示语，不再像报错。
- 物品反查在确认不可用后不再重试，原来每 10 秒会往诊断日志刷一行同样的内容。

### 测试 / Tests

- `mock_wow.lua` 新增 `M.Tick()` 驱动帧的 `OnUpdate`。0.12 秒轮询兜底那段逻辑
  以前在测试里根本跑不到（`RunTimers` 只跑 `C_Timer`），这也是上面那个 Shift bug 漏掉的原因之一。
- 补了「关图后 Shift 不该开窗」的回归用例，并修正两处旧用例——它们原先在地图默认隐藏的状态下
  测「地图上 Shift 开窗」，语义不对。

### 说明 / Notes

- 详情窗仍可用 `/qct detail <任务ID>` 单独打开，不依赖地图。
