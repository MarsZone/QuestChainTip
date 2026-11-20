# 1.5.21

## 先回答你的问题：那个框不是我们插件的

我把你 `Interface/AddOns` 里所有插件都搜了一遍 `RegisterUnitWatch`（创建单位框体的标志性调用）——
**一个都没有**。也就是说没有任何插件在自建目标框体，你看到的那两个框都是客户端自己画的。

- **右下角**（有头像、等级圈、下面还有一条蓝条）：这个是暴雪原生的 `TargetFrame`，
  它本来就有血条、法力条和头像，数字是别的东西加上去的
- **左上角**（名字在上、红条、右边金色框的「23」）：这是客户端自带的另一个目标框体

哪个叫什么名字，用新命令 `/qct health scan` 一看就知道（下面说）。

## 修了我自己的一个 bug：探针写错了

上一版 `/qct health` 又崩了，报的还是 secret：

```
Core.lua:107: invalid value (secret) at index 5 in table for 'concat'
```

问题出在**我用来判断「是不是 secret」的探针**上。我原来用 `text .. ""`（拼空串）来试，
但这个客户端把「拼空串」当成恒等运算放过了 —— 探针通过，secret 被当成普通字符串返回，
最后在 `table.concat` 那里才炸。

现在改成三道探针同时用：`.. "x"`、`string.format`、`string.len`，任一抛错就判定为 secret。

顺带修了后台日志：原来数字类型直接 `tostring` 就返回了，secret 会一路漏到 `table.concat`，
日志本身也能把插件搞崩。现在数字也走同一套探针。

## 找不到框体时也会说话

之前 `UpdateUnit` 在「一个候选框体都没有」时是**静默 return** 的，所以既没有「已挂到」也没有任何提示。
现在会打：

```
没找到可用的 target 框体，血量数字无处可挂。用 /qct health scan 看看有哪些框体。
```

## `/qct health` 多了两项关键信息

```
能格式化成字符串: false
能直接 SetText 原始血量: true
```

这两行把问题彻底分开：

- 前者 false、后者 true → 只是不能读出来加工，直接喂 `SetText` 可以，功能应该正常
- 两个都 false → 这个客户端根本不允许插件显示血量数值，那就不是框体问题，也不用再折腾了

## 新增 `/qct health scan`

列出所有**看得见的、够大的**具名框体，按屏幕位置排序，带坐标和尺寸：

```
  TargetFrame 位置(870,510) 尺寸180x60 [有血条]
  TargetFrameToT 位置(870,450) 尺寸90x30
  ...
```

找到你要的那个框体，直接：

```
/qct health <帧名>      ← 指定
/qct health reset       ← 恢复自动
```

不用等我改代码，当场就能指过去。

## 候选框体的识别也放宽了

原来只认 `child.unit == "target"`，有的 UI 包不给帧设这个字段。现在两个判据取并集：
**unit 字段对得上** 或者 **名字以 target / focus 结尾**（只认后缀，避免把
`TargetFrameSpellBar`、`TargetFrameTextureFrameHealthBar` 这种子帧认进来）。
