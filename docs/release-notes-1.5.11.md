## 任务链提示 1.5.11 / Quest Chain Tip 1.5.11

详情窗的触发键可以改了：Shift / Ctrl / Alt / 不启用。

The chain window key is now configurable: Shift / Ctrl / Alt / Disabled.

---

### 为什么改 / Why

Questie 在世界地图上也用 Shift（按住 Shift 切换被隐藏的任务标记）。两边撞在一起：玩家想切 Questie 的隐藏任务，我们这边却弹了个详情窗。

Questie also uses Shift on the world map (hold Shift to toggle hidden quest markers). The two collided: toggling hidden quests in Questie would pop our chain window instead.

### 新增 / Added

- 设置界面新增「详情窗快捷键」一行，点按钮在 `Shift → Ctrl → Alt → 不启用` 之间循环。
- 新增命令 `/qct key <shift|ctrl|alt|none>`，不想开设置界面的话一条命令就够。
- 只认配置的那一族修饰键：配成 Ctrl 之后，按 Shift 完全不会触发（左右 Ctrl 都覆盖）。
- 面板底部的「按住 Shift 查看完整任务链」提示会跟着变，显示当前配置的键名。

### 兼容 / Compatibility

- 默认仍是 Shift，老用户升级后行为完全不变。
- 选「不启用」等于关掉「地图上按键弹窗」这条路，悬停面板照常工作，
  仍可用 `/qct detail <任务ID>` 打开详情窗。

### 测试 / Tests

- 新增 11 条快捷键断言：四种配置 × 开窗/不开窗，以及显示名。
- 本地化断言补到 38 条，覆盖新增的快捷键文案（简 / 繁 / 英）。
