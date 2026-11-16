--[[
任务链详情窗：在世界地图上按住 Shift 时弹出，把整条任务链上每个任务的
完成条件 / 奖励 / 任务详情 / 在哪接 / 在哪交 / 是否副本任务 全部列出来。

仍然遵守本插件的两条铁律：
1. 不碰 GameTooltip（避免闪烁），也绝不读 tooltip 文本（secret value 会抛错）。
2. 自绘 Frame，不用 GameTooltipTemplate 之类的模板帧。
]]

local ADDON, ns = ...
local QCT = ns
local F = QCT.Format
local D = QCT.Data

local W = {}
QCT.Window = W

local WINDOW_NAME = "QuestChainTipWindow"
local WIDTH, HEIGHT = 580, 640
local PAD = 16
local TITLE_HEIGHT = 30
local SCROLLBAR_WIDTH = 8
local CONTENT_WIDTH = WIDTH - PAD * 2 - SCROLLBAR_WIDTH - 8

local LINE_GAP = 2
local BLOCK_GAP = 10
local MAX_DESC_LINES = 8
local MAX_OBJECTIVE_LINES = 8

local INDENT = "    "

local STATE_TEXT = {
    active = { text = "进行中", r = 1.00, g = 0.82, b = 0.00 },
    completed = { text = "已完成", r = 0.55, g = 0.55, b = 0.55 },
    available = { text = "可接", r = 0.25, g = 1.00, b = 0.25 },
    locked = { text = "条件不足", r = 0.90, g = 0.40, b = 0.40 },
    unknown = { text = "未知", r = 0.60, g = 0.60, b = 0.60 },
}

local KIND_TEXT = {
    prereq = { text = "前置", r = 0.60, g = 0.60, b = 0.60 },
    current = { text = "当前", r = 1.00, g = 0.82, b = 0.00 },
    next = { text = "后续", r = 0.35, g = 0.85, b = 1.00 },
}

--------------------------------------------------------------------------------
-- 小工具
--------------------------------------------------------------------------------

local fontPath, fontSize, fontFlags

local function GetFont()
    if fontPath then return fontPath, fontSize, fontFlags end

    local source = _G["GameTooltipTextLeft1"]
    if source and source.GetFont then
        local ok, path, size, flags = pcall(source.GetFont, source)
        if ok and path and size then
            fontPath, fontSize, fontFlags = path, size, flags or ""
            return fontPath, fontSize, fontFlags
        end
    end
    fontPath, fontSize, fontFlags = "Fonts\\ARKaiT.ttf", 12, ""
    return fontPath, fontSize, fontFlags
end

local function StateLine(state)
    local info = STATE_TEXT[state] or STATE_TEXT.unknown
    return F.Hex(info.r, info.g, info.b, info.text)
end

local function KindTag(kind)
    local info = KIND_TEXT[kind] or KIND_TEXT.next
    return F.Hex(info.r, info.g, info.b, "[" .. info.text .. "]")
end

--------------------------------------------------------------------------------
-- 创建
--------------------------------------------------------------------------------

local function MakeBackdrop(frame)
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0.04, 0.04, 0.05, 0.96)
        frame:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
        return
    end
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    background:SetAllPoints()
    background:SetVertexColor(0.04, 0.04, 0.05, 0.96)
end

function W:Create()
    if self.frame then return self.frame end

    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local frame = CreateFrame("Frame", WINDOW_NAME, UIParent, template)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    MakeBackdrop(frame)
    frame:Hide()

    self.frame = frame

    -- 标题栏（可拖动）
    local title = frame:CreateFontString(nil, "OVERLAY")
    local path, size, flags = GetFont()
    title:SetFont(path, size + 2, flags)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -10)
    title:SetJustifyH("LEFT")
    title:SetTextColor(1, 0.82, 0.2)
    self.title = title

    -- 关闭按钮（自绘，避免模板缺失）
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    local closeBg = close:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    closeBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    closeBg:SetVertexColor(0.35, 0.1, 0.1, 0.9)
    local closeText = close:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(path, size + 3, flags)
    closeText:SetPoint("CENTER")
    closeText:SetText("×")
    closeText:SetTextColor(1, 0.9, 0.9)
    close:SetScript("OnClick", function() W:Close() end)
    close:SetScript("OnEnter", function()
        closeBg:SetVertexColor(0.65, 0.15, 0.15, 1)
    end)
    close:SetScript("OnLeave", function()
        closeBg:SetVertexColor(0.35, 0.1, 0.1, 0.9)
    end)
    self.close = close

    -- 「显示已完成 / 隐藏已完成」切换按钮（右上，关闭键左边）
    local toggle = CreateFrame("Button", nil, frame)
    toggle:SetSize(104, 20)
    toggle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -9)
    local toggleBg = toggle:CreateTexture(nil, "BACKGROUND")
    toggleBg:SetAllPoints()
    toggleBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    toggleBg:SetVertexColor(0.16, 0.16, 0.2, 0.95)
    local toggleLabel = toggle:CreateFontString(nil, "OVERLAY")
    toggleLabel:SetFont(path, size - 1, flags)
    toggleLabel:SetPoint("CENTER")
    toggleLabel:SetTextColor(0.85, 0.85, 0.85)
    toggle:SetScript("OnClick", function() W:ToggleShowCompleted() end)
    toggle:SetScript("OnEnter", function()
        toggleBg:SetVertexColor(0.28, 0.28, 0.34, 1)
    end)
    toggle:SetScript("OnLeave", function()
        toggleBg:SetVertexColor(0.16, 0.16, 0.2, 0.95)
    end)
    self.completedToggle = toggle
    self.completedLabel = toggleLabel

    -- 分隔线
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(0.4, 0.4, 0.4, 0.8)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TITLE_HEIGHT + 4))
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(TITLE_HEIGHT + 4))

    -- 滚动区
    local scroll = CreateFrame("ScrollFrame", WINDOW_NAME .. "Scroll", frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TITLE_HEIGHT + 12))
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(PAD + SCROLLBAR_WIDTH + 6), PAD)
    scroll:EnableMouse(true)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        W:Scroll(delta)
    end)
    scroll:SetScript("OnSizeChanged", function()
        W:UpdateScrollbar()
    end)
    self.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, 100)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    -- 必须开启鼠标：否则行里的物品链接（|Hitem:...|h）收不到悬停事件
    content:EnableMouse(true)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta) W:Scroll(delta) end)
    scroll:SetScrollChild(content)
    self.content = content
    self:AttachItemLinks(content)

    -- 自绘滚动条
    local track = frame:CreateTexture(nil, "BACKGROUND")
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    track:SetVertexColor(0.15, 0.15, 0.15, 0.8)
    track:SetWidth(SCROLLBAR_WIDTH)
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    self.track = track

    local thumb = CreateFrame("Button", nil, frame)
    thumb:SetWidth(SCROLLBAR_WIDTH)
    thumb:SetHeight(40)
    local thumbTexture = thumb:CreateTexture(nil, "ARTWORK")
    thumbTexture:SetAllPoints()
    thumbTexture:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumbTexture:SetVertexColor(0.55, 0.55, 0.55, 0.95)
    thumb:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    thumb:EnableMouse(true)
    thumb:SetScript("OnMouseDown", function(self)
        self.dragging = true
        local _, cursorY = GetCursorPosition()
        self.startCursorY = cursorY / UIParent:GetEffectiveScale()
        self.startScroll = scroll:GetVerticalScroll() or 0
    end)
    thumb:SetScript("OnMouseUp", function(self) self.dragging = false end)
    thumb:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / UIParent:GetEffectiveScale()
        local travel = math.max(1, (self.trackHeight or 100) - self:GetHeight())
        local ratio = (self.startCursorY - cursorY) / travel
        W:ScrollTo((self.startScroll or 0) + ratio * (self.maxScroll or 0))
    end)
    self.thumb = thumb

    self.rows = {}
    self.dividers = {}

    if UISpecialFrames then
        local found = false
        for _, name in ipairs(UISpecialFrames) do
            if name == WINDOW_NAME then found = true break end
        end
        if not found then table.insert(UISpecialFrames, WINDOW_NAME) end
    end

    return frame
end

--------------------------------------------------------------------------------
-- 行
--------------------------------------------------------------------------------

---行里的物品链接（|Hitem:...|h[name]|h）悬停时弹物品提示、点击打开物品。
---用 GameTooltip（和 RXPGuides 一样）而不是 ItemRefTooltip：本客户端实测这条路可用。
local function ItemTipFrame()
    return _G.GameTooltip or _G.ItemRefTooltip
end

local function IsForbidden(obj)
    if not obj or type(obj.IsForbidden) ~= "function" then return false end
    local ok, value = pcall(obj.IsForbidden, obj)
    return ok and value == true
end

function W:HideItemTip(owner)
    local tip = ItemTipFrame()
    if not tip then return end
    -- 只关自己开的那个，别把别人（任务提示）的 tooltip 关掉
    local sameOwner = true
    if owner and type(tip.GetOwner) == "function" then
        local ok, current = pcall(tip.GetOwner, tip)
        sameOwner = ok and current == owner
    end
    if sameOwner and not IsForbidden(tip) then
        tip:Hide()
    end
end

---注意两件事：
---1) 超链接脚本只能挂在 **Frame** 上，FontString 是 Region，没有脚本能力
---   （挂上去会报 "script type not supported by this object"）。
---2) Frame 默认**不处理超链接**，必须 SetHyperlinksEnabled(true)，
---   否则 OnHyperlinkEnter/Leave/Click 一次都不会触发。
---所以统一挂在内容帧上，由它接住内部所有行里的链接事件。
---@param frame table
function W:AttachItemLinks(frame)
    if not frame or frame.qctLinks then return end
    frame.qctLinks = true

    local hasHyperlinks = type(frame.SetHyperlinksEnabled) == "function"
    if hasHyperlinks then
        local ok, err = pcall(frame.SetHyperlinksEnabled, frame, true)
        if not ok then
            hasHyperlinks = false
            if QCT.Log then QCT.Log:Add("error", "SetHyperlinksEnabled 失败:", tostring(err)) end
        end
    end
    if QCT.Log then
        QCT.Log:Add("window", "超链接支持 | SetHyperlinksEnabled:", hasHyperlinks and "有" or "没有",
            "| GameTooltip:", type(_G.GameTooltip),
            "| ItemRefTooltip:", type(_G.ItemRefTooltip))
    end

    local function setScript(event, handler)
        -- 万一某个客户端连这个脚本类型都不支持，也不能让窗口渲染整体崩掉
        local ok, err = pcall(frame.SetScript, frame, event, handler)
        if not ok and QCT.Log then
            QCT.Log:Add("error", "挂超链接脚本失败:", event, "|", tostring(err))
        end
    end

    setScript("OnHyperlinkEnter", function(self, link)
        if QCT.Log then QCT.Log:Add("window", "超链接悬停:", tostring(link)) end
        local tip = ItemTipFrame()
        if not tip or IsForbidden(tip) or not link then return end
        tip:SetOwner(self, "ANCHOR_CURSOR")
        tip:SetHyperlink(link)
        tip:Show()
    end)

    setScript("OnHyperlinkLeave", function(self)
        W:HideItemTip(self)
    end)

    setScript("OnHyperlinkClick", function(_, link, text, button)
        if type(SetItemRef) == "function" then
            pcall(SetItemRef, link, text, button)
        end
    end)
end

function W:AcquireRow(index)
    local row = self.rows[index]
    if row then return row end

    local path, size, flags = GetFont()
    row = self.content:CreateFontString(nil, "ARTWORK")
    row:SetFont(path, size, flags)
    row:SetJustifyH("LEFT")
    row:SetJustifyV("TOP")
    row:SetWordWrap(true)
    row:SetWidth(CONTENT_WIDTH)
    self.rows[index] = row
    return row
end

function W:ResetRows()
    for _, row in ipairs(self.rows) do
        row:SetText("")
        row:Hide()
    end
    for _, divider in ipairs(self.dividers or {}) do
        divider:Hide()
    end
    self.rowIndex = 0
    self.dividerIndex = 0
    self.cursorY = 0
end

---分隔线用贴图而不是字符：字符宽度随字体变，容易溢出换行
function W:PushDivider()
    self.dividerIndex = (self.dividerIndex or 0) + 1
    local divider = self.dividers[self.dividerIndex]
    if not divider then
        divider = self.content:CreateTexture(nil, "ARTWORK")
        divider:SetTexture("Interface\\Buttons\\WHITE8X8")
        divider:SetVertexColor(0.35, 0.35, 0.35, 0.85)
        divider:SetHeight(1)
        self.dividers[self.dividerIndex] = divider
    end

    divider:SetWidth(CONTENT_WIDTH)
    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(self.cursorY + 4))
    divider:Show()

    self.cursorY = self.cursorY + 9
end

function W:Push(text, width, r, g, b)
    if not text or text == "" then return end

    self.rowIndex = self.rowIndex + 1
    local row = self:AcquireRow(self.rowIndex)

    row:SetWidth(width or CONTENT_WIDTH)
    row:SetTextColor(r or 1, g or 1, b or 1)
    row:SetText(text)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.cursorY)
    row:Show()

    local height = row:GetStringHeight() or 0
    if height <= 0 then height = 14 end
    self.cursorY = self.cursorY + height + LINE_GAP
end

function W:PushBlank(height)
    self.cursorY = self.cursorY + (height or BLOCK_GAP)
end

function W:PushWrapped(text, prefix, width, r, g, b)
    local lines = F.Wrap(text, prefix or "", width or CONTENT_WIDTH, self.content)
    for _, line in ipairs(lines) do
        self:Push(line, width or CONTENT_WIDTH, r, g, b)
    end
end

--------------------------------------------------------------------------------
-- 内容
--------------------------------------------------------------------------------

local function RewardLines(detail)
    local out = {}

    local parts = {}
    if detail.xp and detail.xp > 0 then
        local r, g, b = F.DifficultyColor(detail.level, detail.id)
        parts[#parts + 1] = F.Hex(r, g, b, F.Number(detail.xp) .. " 经验")
    end
    if detail.money and detail.money > 0 then
        parts[#parts + 1] = F.Coins(detail.money)
    end
    if #parts > 0 then
        out[#out + 1] = table.concat(parts, "   ")
    end

    if detail.items and #detail.items > 0 then
        local texts = {}
        for _, item in ipairs(detail.items) do
            texts[#texts + 1] = item.text
        end
        out[#out + 1] = table.concat(texts, "   ")
    end

    for _, rep in ipairs(detail.reputations or {}) do
        local text = (rep.value > 0 and "+" or "") .. rep.value .. " " .. rep.faction
        out[#out + 1] = F.Hex(0.35, 0.55, 1, text)
    end

    return out
end

function W:RenderQuestBlock(detail, kind)
    if not detail then return end

    -- 分隔线（第一个块不画）
    if self.rowIndex and self.rowIndex > 0 then
        self:PushDivider()
    end

    -- 标题行：[前置] [31] 任务名   (精英 · 副本)   (进行中)
    local levelText = (detail.level and detail.level > 0) and ("[" .. detail.level .. "] ") or ""
    local r, g, b = F.DifficultyColor(detail.level, detail.id)
    local head = KindTag(kind) .. " " .. F.Hex(r, g, b, levelText .. detail.name)

    local tags = {}
    if detail.isDungeon then
        tags[#tags + 1] = F.Hex(1, 0.55, 0.25, detail.tagId == 81 and "副本任务" or "团队副本")
    elseif detail.tagText then
        tags[#tags + 1] = F.Hex(0.85, 0.75, 0.45, detail.tagText)
    end
    if #tags > 0 then
        head = head .. "  " .. F.Hex(0.5, 0.5, 0.5, "(") .. table.concat(tags, F.Hex(0.5, 0.5, 0.5, " · ")) .. F.Hex(0.5, 0.5, 0.5, ")")
    end
    head = head .. "   " .. F.Hex(0.5, 0.5, 0.5, "(") .. StateLine(detail.state) .. F.Hex(0.5, 0.5, 0.5, ")")

    self:Push(head)

    -- 在哪接 / 在哪交
    local startText
    if detail.startName then
        startText = detail.startName .. (detail.startZone and ("  ·  " .. detail.startZone) or "")
    elseif detail.startZone then
        startText = detail.startZone
    end
    if startText then
        self:Push(INDENT .. F.Hex(0.6, 0.6, 0.6, "接取：") .. F.Hex(0.85, 0.85, 0.85, startText))
    end

    local endText
    if detail.endName then
        endText = detail.endName .. (detail.endZone and ("  ·  " .. detail.endZone) or "")
    elseif detail.endZone then
        endText = detail.endZone
    end
    if endText then
        self:Push(INDENT .. F.Hex(0.6, 0.6, 0.6, "交付：") .. F.Hex(0.85, 0.85, 0.85, endText))
    end

    -- 任务详情
    local desc = detail.description or {}
    if #desc > 0 then
        self:Push(INDENT .. F.Hex(0.55, 0.55, 0.55, "任务详情"))
        local used = 0
        for _, paragraph in ipairs(desc) do
            if used >= MAX_DESC_LINES then break end
            for _, line in ipairs(F.Wrap(paragraph, INDENT .. "  ", CONTENT_WIDTH - 12, self.content)) do
                if used >= MAX_DESC_LINES then break end
                self:Push(line, CONTENT_WIDTH - 12, 0.86, 0.86, 0.86)
                used = used + 1
            end
        end
        if used >= MAX_DESC_LINES then
            self:Push(INDENT .. "  " .. F.Hex(0.5, 0.5, 0.5, "…（描述较长，已截断）"))
        end
    end

    -- 完成条件
    local objectives = detail.objectives or {}
    if #objectives > 0 then
        self:Push(INDENT .. F.Hex(0.55, 0.55, 0.55, "完成条件"))
        local used = 0
        for _, line in ipairs(objectives) do
            if used >= MAX_OBJECTIVE_LINES then break end
            for _, wrapped in ipairs(F.Wrap(line, INDENT .. "  - ", CONTENT_WIDTH - 12, self.content)) do
                if used >= MAX_OBJECTIVE_LINES then break end
                self:Push(wrapped, CONTENT_WIDTH - 12, 1, 0.95, 0.75)
                used = used + 1
            end
        end
        if used >= MAX_OBJECTIVE_LINES then
            self:Push(INDENT .. "  " .. F.Hex(0.5, 0.5, 0.5, "…（条件较多，已截断）"))
        end
    end

    -- 奖励
    local rewards = RewardLines(detail)
    if #rewards > 0 then
        self:Push(INDENT .. F.Hex(0.55, 0.55, 0.55, "奖励"))
        for _, line in ipairs(rewards) do
            self:PushWrapped(line, INDENT .. "  ", CONTENT_WIDTH - 12, 1, 1, 1)
        end
    end

    self:PushBlank(BLOCK_GAP)
end

--------------------------------------------------------------------------------
-- 渲染 / 显示
--------------------------------------------------------------------------------

function W:Render(questId)
    self:Create()
    self:ResetRows()

    local maxDepth = tonumber(QCT.db.chainDepthShift) or 30
    if maxDepth < 1 then maxDepth = 30 end
    local entries = D:BuildFullChain(questId, maxDepth)

    local rendered = 0
    local hiddenCompleted = 0
    local completedTotal = 0

    for _, entry in ipairs(entries) do
        local detail = D:GetQuestDetail(entry.id)
        if detail then
            -- 已完成的任务默认折叠起来，当前任务无论什么状态都显示
            local isCompleted = (detail.state == "completed")
            if isCompleted then completedTotal = completedTotal + 1 end

            if isCompleted and entry.kind ~= "current" and not self.showCompleted then
                hiddenCompleted = hiddenCompleted + 1
            else
                self:RenderQuestBlock(detail, entry.kind)
                rendered = rendered + 1
            end
        end
    end

    self.hiddenCompleted = hiddenCompleted
    self.completedCount = completedTotal

    if hiddenCompleted > 0 then
        self:PushDivider()
        self:Push(F.Hex(0.55, 0.55, 0.55,
            "已隐藏 " .. hiddenCompleted .. " 个已完成的任务 · 点右上角「显示全部」展开"))
    end

    if rendered == 0 then
        self:Push(F.Hex(1, 0.4, 0.4, "没有取到任务数据（Questie 数据源可能未就绪）"))
        self:PushBlank(20)
    end

    self.content:SetHeight(math.max(1, self.cursorY + 8))
    self.questId = questId

    local name = D:GetName(questId) or ("任务 " .. tostring(questId))
    local suffix = "（" .. rendered .. " 环"
        .. (hiddenCompleted > 0 and ("，已隐藏 " .. hiddenCompleted .. " 个已完成") or "") .. "）"
    self.title:SetText("任务链详情 · " .. name .. F.Hex(0.6, 0.6, 0.6, suffix))

    self:UpdateCompletedToggle()

    self.scroll:SetVerticalScroll(0)
    self:UpdateScrollbar()

    QCT.Log:Add("window", "渲染详情窗 | 任务:", questId, "| 显示环节:", rendered,
        "| 隐藏已完成:", hiddenCompleted, "| 展开全部:", self.showCompleted and "是" or "否")
end

---右上角「显示全部 / 隐藏已完成」按钮的状态
function W:UpdateCompletedToggle()
    local toggle = self.completedToggle
    if not toggle then return end

    -- 整条链里压根没有已完成的任务，按钮就不用出现
    if (self.completedCount or 0) == 0 then
        toggle:Hide()
        return
    end

    toggle:Show()
    if self.showCompleted then
        self.completedLabel:SetText("隐藏已完成")
        self.completedLabel:SetTextColor(1, 0.82, 0.2)
    else
        self.completedLabel:SetText("显示全部 (" .. (self.hiddenCompleted or 0) .. ")")
        self.completedLabel:SetTextColor(0.85, 0.85, 0.85)
    end
end

function W:ToggleShowCompleted()
    self.showCompleted = not self.showCompleted
    if self.questId then
        local ok, err = pcall(self.Render, self, self.questId)
        if not ok then QCT.Log:Add("window", "切换显示失败:", tostring(err)) end
    end
end

function W:Scroll(delta)
    local step = 40
    self:ScrollTo((self.scroll:GetVerticalScroll() or 0) - delta * step)
end

function W:ScrollTo(value)
    local maxScroll = self.maxScroll or 0
    if value < 0 then value = 0 end
    if value > maxScroll then value = maxScroll end
    self.scroll:SetVerticalScroll(value)
    self:UpdateScrollbar()
end

function W:UpdateScrollbar()
    if not (self.scroll and self.thumb and self.track) then return end

    local viewHeight = self.scroll:GetHeight() or 1
    local contentHeight = self.content:GetHeight() or 1
    local maxScroll = contentHeight - viewHeight
    if maxScroll < 0 then maxScroll = 0 end
    self.maxScroll = maxScroll

    local trackHeight = viewHeight
    self.thumb.trackHeight = trackHeight
    self.thumb.maxScroll = maxScroll

    if maxScroll <= 0 then
        self.thumb:Hide()
        return
    end

    self.thumb:Show()
    local thumbHeight = math.max(30, trackHeight * (viewHeight / contentHeight))
    self.thumb:SetHeight(thumbHeight)

    local scroll = self.scroll:GetVerticalScroll() or 0
    if scroll > maxScroll then scroll = maxScroll end
    local travel = trackHeight - thumbHeight
    local offset = (maxScroll > 0) and (scroll / maxScroll * travel) or 0
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOPLEFT", self.track, "TOPLEFT", 0, -offset)
end

function W:Open(questId)
    if not questId then return end
    if not QCT.db.enabled then return end

    -- 每次打开都回到默认状态：已完成的先折叠
    self.showCompleted = false

    local ok, err = pcall(self.Render, self, questId)
    if not ok then
        QCT.Log:Add("window", "渲染出错:", tostring(err))
        if self.lastPrintedError ~= tostring(err) then
            self.lastPrintedError = tostring(err)
            QCT:Print("任务链窗口渲染出错：" .. tostring(err))
        end
        return
    end

    self.frame:Show()

    -- 详情窗已经把同样的内容展开得更全了，行内面板就收起来，避免两份信息互相挡
    if QCT.Tooltip and QCT.Tooltip.Hide then
        pcall(QCT.Tooltip.Hide, QCT.Tooltip)
    end
end

function W:Close()
    self:HideItemTip()
    if self.frame then self.frame:Hide() end
end

function W:IsShown()
    return self.frame ~= nil and self.frame:IsShown() == true
end

function W:Toggle(questId)
    if self:IsShown() then
        self:Close()
    else
        self:Open(questId)
    end
end
