## 任务链提示 1.5.14 / Quest Chain Tip 1.5.14

设置界面右上角显示版本号。

The options panel now shows the addon version in the top-right corner.

---

### 为什么 / Why

玩家反馈「不知道装的是不是最新版」——界面里没有任何版本信息，只能靠猜。之前 `QCT.VERSION` 在代码里写死成 `1.0.0`，从来没跟着发版改过，就算想显示也是错的。

### 改了什么 / What changed

- 设置界面（`/qct`）标题右侧常驻显示 `v1.5.14`，灰色小字，不抢视线
- 版本号改成运行时读 `toc` 的 `## Version`：
  - 先试 `GetAddOnMetadata(addon, "Version")`
  - 再试 `C_AddOns.GetAddOnMetadata(...)`（新客户端）
  - 都读不到才显示 `v?`
- `/qct why` 诊断输出的第一行也带上版本号，反馈问题时能直接确认装的是哪一版
- 发版只需改 `toc` 一处，代码里不再有第二份版本号

### 测试 / Tests

- 设置界面测试新增断言：版本号来自 toc 元数据、界面上确实渲染了 `v<版本>`
- 全部测试通过，本地化断言 51 条
