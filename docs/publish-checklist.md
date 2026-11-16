# 发布清单（Quest Chain Tip）

这份清单是「照着做就能发出去」的版本。物料已经全部备齐，只差你在各平台上点几下。

---

## 一、现在手上有什么

| 物料 | 路径 | 说明 |
|---|---|---|
| 发布包 | `dist/QuestChainTip-1.5.8.zip` | 45.8 KB，顶层是 `QuestChainTip/` 文件夹，`toc` 在文件夹根部 |
| 工程图标 | `docs/icon-128.png` | 128×128 PNG，CurseForge / Wago 的工程图标要求这个尺寸 |
| 小图标 | `docs/icon-64.png` | 64×64，README / 帖子配图用 |
| 游戏内图标 | `Media/QuestChainTip.tga` | 已打进包，`toc` 的 `IconTexture` 指向它 |
| 中文文案 | `docs/listing-zh.md` | 简介 + 详细说明 + 标签 + 截图建议，可直接粘 |
| 英文文案 | `docs/listing-en.md` | 同上，英文版 |
| 更新日志 | `CHANGELOG.md` | 建议每次发版把当前版本那一段贴到平台 |
| 许可证 | `LICENSE` | MIT，已打进包 |

**截图还没做**，平台一般要 3–5 张。按 `docs/listing-zh.md` 最后的顺序拍：

1. 世界地图上悬停任务图标 → 补全面板
2. 世界地图上按住 Shift → 整条链详情窗
3. 详情窗里物品名悬停 → 物品提示
4. 设置界面
5. 对比图（Questie 原生 vs 本插件）

> 拍图小技巧：用 `/console screenshotFormat png`，`PrintScreen` 存到 `World of Warcraft\_forever_\Screenshots\`。
> 建议裁掉黑边，统一成 16:9，第一张最重要——它就是列表页的封面。

---

## 二、发布前 60 秒自检

```bash
cd E:/AI/wowaddones/QuestChainTip

# 1) 语法 + 自动化测试（应输出「全部通过」）
python /tmp/runtests.py | grep -E "FAIL|全部通过"

# 2) 重新打包（版本号取自 toc，会顺带校验 toc 字段和文件是否齐全）
python tools/build_release.py

# 3) 确认包结构：顶层必须是 QuestChainTip/ 文件夹，不能是散文件
python -c "import zipfile;print('\n'.join(zipfile.ZipFile('dist/QuestChainTip-1.5.8.zip').namelist()))"
```

包结构应该是这样（9 个文件，不多不少）：

```
QuestChainTip/QuestChainTip.toc
QuestChainTip/Core.lua
QuestChainTip/Log.lua
QuestChainTip/Format.lua
QuestChainTip/Data.lua
QuestChainTip/Tooltip.lua
QuestChainTip/ChainWindow.lua
QuestChainTip/Options.lua
QuestChainTip/Media/QuestChainTip.tga
```

`tools/`、`docs/`、`tests/`、`dist/` 不会被打进包——这是对的，玩家不需要。

---

## 三、发布顺序（照这个顺序做）

| 顺序 | 渠道 | 为什么排这里 | 需要什么 |
|---|---|---|---|
| **1** | **GitHub Release** | 不需要审核，几分钟就能拿到一个固定链接；后面所有渠道都链它，以后修 bug 只改这一处 | 只要 zip + 发布说明，**不需要截图** |
| **2** | 截图 | 新手盒子/UU 都要求 3–5 张，没有就过不了审 | 进游戏拍，见上一节 |
| **3** | **新手盒子** | 国内永久60/怀旧服玩家真正聚集的地方，流量在这儿 | zip + 文案 + 截图 + 依赖 |
| **4** | **网易UU / DD** | 第二个国内分发点，同一份 zip 和文案直接复用 | 同上 |
| **5** | NGA 插件区 | 发帖 + 附件，收 bug 反馈最快；正文里放 GitHub 链接 | 帖子 |
| **6** | Wago.io | 国外，支持自定义 Interface，比 CurseForge 好过 | zip + 英文文案 + 128 图标 |
| **7** | CurseForge | 见下面「注意」，Interface 16001 可能被判不兼容 | 最后再试 |

> **一句话**：GitHub 先发拿链接 → 拍截图 → 新手盒子 → 网易UU → NGA。
> GitHub 之所以排第一不是因为它面向国内玩家，而是它**不用审核、不用截图**，
> 可以立刻把「版本 1.5.8 就是这个 zip」这件事钉死。

> ⚠️ **关于 CurseForge**：它的版本识别是读 `toc` 的 `## Interface: 16001`，
> 而 16001 不是暴雪官方版本号（官方 Classic Era 是 115xx 这一档）。
> 上传后大概率会被标成「不支持的版本」或需要手动指定 Game Version。
> 如果你的用户主要是永久60 客户端，**优先国内盒子 + GitHub + Wago**，CurseForge 可以最后再说。

---

## 四、各平台操作

### 1. 新手盒子（wclbox.com）

> ⚠️ **前置门槛**：这个站不是开放上传，是**创作者准入制**。
> 必须先通过「Mod、存档创作者」入驻审核（要求内容平台播放量 + 其他平台发布记录），
> 才会解锁上传入口。入驻材料怎么准备、话术怎么写，见 **`docs/wclbox-apply.md`**。
> 入驻是账号级的，通过一次以后发新插件都不用再审。

站点确认过：`wclbox.com` → **魔兽世界插件库**在 `wclbox.com/games/1`，
右上角头像菜单里有 **创作者中心**，插件就是在那儿发。

**字段对照表（照这个填）**

| 表单字段 | 填什么 |
|---|---|
| 名称 | `任务链提示 Quest Chain Tip` |
| 分类 | **任务**（Questie、QuestieDB 都在这个分类，审核一看就懂） |
| 简介 | `docs/listing-zh.md` 的「一句话简介」 |
| 详细说明 | `docs/listing-zh.md` 的「详细说明」整段 |
| 版本号 | `1.5.8`（和 toc 一致） |
| 文件 | `dist/QuestChainTip-1.5.8.zip`（不要解压、不要重压） |
| 图标 | `docs/icon-128.png` |
| 截图 | `docs/screenshots/01~03`，第一张当封面 |
| 依赖 | `Questie`、`QuestieDB`（本平台已收录：Questie = PluginItem/20，QuestieDB = PluginItem/32949） |
| 项目主页（可选） | `https://github.com/MarsZone/QuestChainTip` |

> ⚠️ 该站魔兽分区里的插件卡片大多标着「泰坦重铸」。如果表单里的「客户端/游戏版本」只有这一项，
> 就按最接近的选，并**在详细说明开头补一句**：
> 「适用客户端：永久60 / Interface 16001（与 QuestieDB_Forever 一致）」。
> 不写清楚的话，用官方客户端的人装了会显示过期。

> 平台如果要求填「插件 ID / 文件夹名」，就是 `QuestChainTip`，必须和 zip 里的文件夹同名。

### 2. 网易DD

流程基本同上：新建条目 → 传 zip → 填文案 → 传图 → 提审。
两个平台可以复用同一份 zip 和同一份文案，不用改。

### 3. NGA / 论坛帖

标题建议：

```
[插件] 任务链提示 Quest Chain Tip 1.5.8 —— 已接的任务也能看后续链、奖励和详情
```

正文 = `docs/listing-zh.md` 的详细说明 + 截图 + zip 附件。
把「已接任务看不到后续链」这个痛点写在第一段，这是这个插件唯一的卖点。

### 4. GitHub（单一真源，先发这个）

本地仓库**已经建好并打好 tag 了**（`v1.5.8`，工作区干净），只差推到远端。

**第一步：在 github.com 新建一个空仓库**（不要勾 README / .gitignore / license），名字建议 `QuestChainTip`。

**第二步：推上去**

```bash
cd E:/AI/wowaddones/QuestChainTip

git remote add origin https://github.com/<你的账号>/QuestChainTip.git
git push -u origin main
git push origin v1.5.8
```

> 如果 `git push -u origin main` 报 `src refspec main does not match`，说明当前分支叫 `master`，
> 先 `git branch -M main` 再推。

**第三步：建 Release**

网页上 **Releases → Draft a new release**：

- Tag：选已有的 `v1.5.8`（别新建）
- Title：`Quest Chain Tip 1.5.8`
- 描述：整个文件复制 `docs/release-notes-1.5.8.md`（中英双语，已写好）
- 附件：上传 `dist/QuestChainTip-1.5.8.zip`
- 发布

发完之后这个 Release 的下载链接就是**唯一真源**，后面新手盒子 / 网易DD / NGA 帖子里都可以链它：

```
https://github.com/<你的账号>/QuestChainTip/releases/latest
```

**装了 gh CLI 的话可以一条命令搞定**（可选）：

```bash
gh repo create QuestChainTip --public --source=. --push
gh release create v1.5.8 dist/QuestChainTip-1.5.8.zip \
  --title "Quest Chain Tip 1.5.8" \
  --notes-file docs/release-notes-1.5.8.md
```

### 5. Wago.io（国外，最好过）

New Addon → 填名称 → 上传同一份 zip → 版本号会自动从 `toc` 读出来 → 贴英文文案 → 传图标和截图。
Wago 允许自定义 game version，不会因为 `16001` 卡住，是国外最省事的一个。

### 6. CurseForge（国外流量最大，但可能卡版本）

New Project → 类型 **World of Warcraft** → 上传 zip → 手动把 Game Version 勾到 Classic Era →
贴 `docs/listing-en.md` → 传 `docs/icon-128.png` → 传截图 → License 选 MIT。
如果提示版本不兼容，忽略即可，玩家仍能手动安装。

### 7. WoWInterface（国外老站）

上传流程和 CurseForge 类似，审核较慢但会长期挂着，属于「放着不用管」的渠道。

### 8. 社区曝光（不是托管，但决定有没有人看见）

- **Reddit**：`r/wowaddons`（发插件首选）、`r/classicwow`（附截图，标题写清解决什么问题）
- **Discord**：Classic Era / 私服相关的插件频道，发一条带 GitHub 链接的短介绍
- **Wago 的 addon 页**自带评论，比 CurseForge 活跃

> ⚠️ **国外发之前先想清楚一件事**：插件界面目前**只有中文**。
> 国外玩家装了会看到「悬停面板」「后续任务链」这种中文标签，体验是断的。
> 如果只是想「有个海外入口」，GitHub + Wago 足够；
> 想真让国外玩家用，建议先做英文 UI（`GetLocale()` 分流），再发 CurseForge 和 Reddit。

---

## 五、以后发新版本（固定四步）

```bash
cd E:/AI/wowaddones/QuestChainTip

# 1) 改版本号（只改 toc，脚本会读它）
sed -i 's/^## Version: .*/## Version: 1.5.9/' QuestChainTip.toc

# 2) 在 CHANGELOG.md 顶部加一段 ## 1.5.9

# 3) 跑测试 + 打包
python /tmp/runtests.py | grep -E "FAIL|全部通过"
python tools/build_release.py

# 4) 装到游戏里自测一遍
cp -f *.lua *.toc "F:/Wow/World of Warcraft/_forever_/Interface/AddOns/QuestChainTip/"
```

然后到各平台「上传新版本」，zip 换成新的就行，插件 ID 不用变——老用户的更新会自动接上。

**版本号三处一致**：`toc` 的 `## Version`、`CHANGELOG.md` 的段落标题、zip 文件名。
`build_release.py` 是读 `toc` 生成文件名的，所以只要改 `toc`，另外两个跟着对就行。

### 各平台更新动作

| 平台 | 更新怎么做 |
|---|---|
| GitHub | 打完包建一个新 Release（tag `v1.5.9`），附件换成新 zip |
| Wago | `addons.wago.io` → 头像 → My Addons → 点插件 → `Upload New Version` → 传新 zip |
| 新手盒子 | 创作者中心 → 我的插件 → 上传新版本 → 传新 zip |
| NGA | 编辑原帖，改标题里的版本号，附件换新 zip |

> **Wago 用的是 Custom Addon（手动上传）**，更新就是手动传一个 zip，slug 和链接不变，
> 装过的人在 Wago 客户端里能看到新版本。
> 另一个入口 `GitHub Addon Creation` 可以绑定仓库、从 GitHub Release 自动同步，
> 但要求 tag / Release / zip 结构严格对应，出问题排查成本比手动高。
> 这个插件稳定后发版频率很低，**手动传一次不到一分钟，不建议切**。

---

## 六、容易踩的坑

1. **zip 里多一层或少一层**：必须是 `QuestChainTip/xxx.toc`。多包一层变成
   `QuestChainTip/QuestChainTip/xxx.toc`，玩家装上插件列表里就是空的。
   → `build_release.py` 已经保证这一点，别手动重新压。
2. **别用 Windows 右键「压缩到 zip」**：会带 `__MACOSX` 或反斜杠路径，某些管理器解压后目录是乱的。
3. **`## Interface` 写错**：这个客户端是 `16001`（和 QuestieDB 一致）。写错会被标成「过期插件」。
4. **`IconTexture` 指向包外**：现在指向 `Interface\AddOns\QuestChainTip\Media\QuestChainTip.tga`，
   是包内文件，正确。换成别的插件的图标会在别人机器上变成问号。
5. **依赖没写**：Questie / QuestieDB 是硬依赖。没写的话玩家装上会看到「没有找到 Questie」的提示。
6. **聊天框诊断默认是关的**：设置里有「聊天框显示诊断信息」（`/qct explain` 也能开关），
   默认关闭，玩家不会看到任何调试行。让反馈问题的玩家打开这个再截图，效率最高。
