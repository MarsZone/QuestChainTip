## 任务链提示 1.5.16 / Quest Chain Tip 1.5.16

修 1.5.15 的三个问题：血量数字不显示、小地图图标变空格子、任务日志按 Alt 不弹。

Fixes three issues from 1.5.15.

---

### 1. 血量数字不显示 / Health text not visible

文字原来建在 `TargetFrame` 上，而血条是它的**子帧**——WoW 里子帧的绘制层级永远高于父帧的任何 layer，所以文字被血条整个盖住了。

现在直接建在血条自己身上。顺带改成「优先找名字带 `Health` 的 StatusBar」，避免把法力条当血条。

### 2. 小地图图标变成空格子 / Minimap button left an empty slot

装了按钮收集器（MBB / MinimapButtonBag 之类）时，收集器会把按钮 `SetParent` 到自己的网格里接管显示。我们还在按角度往小地图边缘摆，于是网格里留一个空格、图标飘在外面。

现在检测到按钮已被接管（父级不再是 `Minimap`）就不再抢位置，拖动也一起跳过。

### 3. 任务日志按 Alt 不弹 / Alt did nothing in the quest log

原来靠 `IsAltKeyDown()` 判断，这个客户端上不一定可靠。现在直接用 `MODIFIER_STATE_CHANGED` 事件里的键名判断——`LALT` / `RALT` 本身就带够信息，不再查询按键状态 API。

自定义热键（`/qct key f` 那条路）不受影响，仍然直接放行。

### 测试 / Tests

- 血量：新增「文字必须挂在血条上」断言，防止层级问题回归
- 地图：新增「地图上按 Alt 不开窗」断言，确认两个键不会互相串
- 全部测试通过，本地化 51 条
