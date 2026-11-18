## 任务链提示 1.5.12 / Quest Chain Tip 1.5.12

详情窗的触发键可以随便改了：Shift / Ctrl / Alt，或者任意一个键。

The chain window key is now fully configurable: Shift / Ctrl / Alt, or any key you like.

---

### 为什么改 / Why

Questie 在世界地图上也用 Shift（按住 Shift 切换被隐藏的任务标记）。两边撞在一起：玩家想切 Questie 的隐藏任务，我们这边却弹了个详情窗。

Questie also uses Shift on the world map (hold Shift to toggle hidden quest markers). The two collided: toggling hidden quests in Questie would pop our chain window instead.

### 怎么改 / How

设置界面 →「详情窗快捷键」：

- 点主按钮在 `Shift → Ctrl → Alt → 不启用` 之间循环
- 点右边的「自定义…」→ 按一下想用的键，支持组合键（`F`、`1`、`F1`、`CTRL-1`、`SHIFT-鼠标侧键`）
- `Esc` 或点击空白处取消捕获

命令行也支持：

```
/qct key ctrl        改成 Ctrl
/qct key f           改成 F 键
/qct key ctrl-1      改成 Ctrl+1
/qct key none        关掉按键触发（悬停面板照常工作）
```

### 说明 / Notes

- 修饰键（Shift / Ctrl / Alt）走事件监听，零副作用，也不会占用游戏里的按键。
- 自定义键通过 `SetBindingClick` 绑到一个隐藏按钮上，不走键盘钩子，**不会吞你打字**。
  代价是它会占用那个键原本的绑定——界面上有提示，改回修饰键会自动解除。
- 重登 / 换角色会自动重新应用绑定（游戏绑定只有 `SaveBindings` 之后才持久化）。
- 选「不启用」等于关掉「地图上按键弹窗」这条路，仍可用 `/qct detail <任务ID>` 打开详情窗。
- 默认仍是 Shift，老用户升级后行为完全不变。

### 测试 / Tests

- 11 条修饰键断言：四种配置 × 开窗/不开窗，以及显示名。
- 6 条自定义键断言：绑定建立、热键触发开窗、改回修饰键解除绑定、不启用时无残留绑定。
- 本地化断言 38 条，覆盖新增文案（简 / 繁 / 英）。
