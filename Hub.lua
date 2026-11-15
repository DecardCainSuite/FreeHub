-- Free Hub - one window for every "Free" addon: a sidebar on the left, and on the right
-- either the addon's own options (embedded) or a product page (description + gallery).
-- Same look as Free Swing Timer / Free Unit Frames. Own frames only.

local ADDON, ns = ...

local MEDIA  = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local WHITE  = "Interface\\Buttons\\WHITE8x8"
local CIRCLE = MEDIA .. "circle"
local FONT   = "Fonts\\ARIALN.TTF"

local C = {
    bg       = { 0.070, 0.074, 0.085, 0.97 },
    side     = { 0.058, 0.061, 0.071, 1 },
    panel    = { 0.098, 0.104, 0.118, 1 },
    control  = { 0.145, 0.151, 0.170, 1 },
    hover    = { 0.190, 0.197, 0.222, 1 },
    text     = { 0.930, 0.937, 0.955, 1 },
    dim      = { 0.700, 0.712, 0.750, 1 },
    muted    = { 0.500, 0.515, 0.560, 1 },
    accent   = { 1.000, 0.540, 0.240, 1 },
    accentHi = { 1.000, 0.640, 0.380, 1 },
    onAccent = { 0.100, 0.050, 0.020, 1 },
    good     = { 0.450, 0.800, 0.450, 1 },
}

local SIDE_W = 210
local PAGE_W, PAGE_H = 720, 620

local GetAddOnInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
local IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local EnableAddOn = C_AddOns and C_AddOns.EnableAddOn or EnableAddOn

-- ------------------------------------------------------------ public API
-- An addon calls FreeHub:Register(id, info) when it loads. info fields (all optional):
--   embed(parent)  -> puts its options frame inside parent and returns it
--   unembed()      -> takes its options frame back
--   minimap(show)  -> shows / hides its own minimap button (without changing its saved choice)
local registry = {}
FreeHub = FreeHub or {}
FreeHub.version = 1

function FreeHub:Register(id, info)
    registry[id] = info or {}
    if info and info.minimap and self:ManagesMinimap() then info.minimap(false) end
end
function FreeHub:IsRegistered(id) return registry[id] ~= nil end
function FreeHub:ManagesMinimap() return FreeHubDB == nil or FreeHubDB.hideChildButtons ~= false end

-- ------------------------------------------------------------ helpers
local function SetFont(obj, size, flags)
    obj:SetFont(FONT, size, flags or "")
    if not obj:GetFont() then obj:SetFont(STANDARD_TEXT_FONT, size, flags or "") end
end
local function Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    SetFont(fs, size)
    fs:SetTextColor(unpack(color))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
end
local function Fill(parent, color, layer, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetTexture(WHITE)
    t:SetVertexColor(unpack(color))
    return t
end
local function Border(f, alpha, layer)
    f.edges = {}
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
                         { "TOPLEFT", "BOTTOMLEFT", "v" }, { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
        local e = f:CreateTexture(nil, layer or "BORDER")
        e:SetTexture(WHITE)
        e:SetVertexColor(1, 1, 1, alpha or 0.07)
        e:SetPoint(p[1]); e:SetPoint(p[2])
        if p[3] == "h" then e:SetHeight(1) else e:SetWidth(1) end
        f.edges[i] = e
    end
end
local function BorderColor(f, r, g, b, a) for _, e in ipairs(f.edges) do e:SetVertexColor(r, g, b, a) end end
local function Button(parent, label, width, primary, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 28)
    b.bg = Fill(b, primary and C.accent or C.control)
    b.bg:SetAllPoints()
    if not primary then Border(b, 0.08) end
    b.label = Text(b, 13, primary and C.onAccent or C.text)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b:SetScript("OnEnter", function(self) self.bg:SetVertexColor(unpack(primary and C.accentHi or C.hover)) end)
    b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(unpack(primary and C.accent or C.control)) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- installed / loaded / enabled state of an addon folder
local function State(id)
    local name, _, _, loadable, reason = GetAddOnInfo(id)
    if not name or reason == "MISSING" then return "missing" end
    if IsAddOnLoaded(id) then return "loaded" end
    if reason == "DISABLED" or not loadable then return "disabled" end
    return "installed"
end
local function Version(id)
    local v = GetAddOnMetadata and GetAddOnMetadata(id, "Version")
    return v and v ~= "" and ("v" .. v) or nil
end
local STATE_LABEL = { loaded = "Loaded", disabled = "Disabled", installed = "Not loaded", missing = "Not installed" }

-- ------------------------------------------------------------ window
local frame, side, content, current, embedded
local entries = {}
local Select -- forward

-- Size and place: the window keeps its top-left corner and the size the player gave it.
-- It only grows when an addon's options need more room than it has.
local DEFAULT_W, DEFAULT_H = SIDE_W + 900, 720
local function MinSize()
    local w, h = SIDE_W + PAGE_W, PAGE_H
    for _, info in pairs(registry) do
        if info.minW then w = math.max(w, SIDE_W + info.minW) end
        if info.minH then h = math.max(h, info.minH) end
    end
    return w, h
end
local function SavePlace()
    if not frame or not FreeHubDB then return end
    local l, t = frame:GetLeft(), frame:GetTop()
    if l and t then FreeHubDB.left, FreeHubDB.top = l, t end
    local w, h = frame:GetSize()
    if w and h then FreeHubDB.w, FreeHubDB.h = w, h end
end
local function Place()
    frame:ClearAllPoints()
    if FreeHubDB.left and FreeHubDB.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", FreeHubDB.left, FreeHubDB.top)
    else
        frame:SetPoint("CENTER")
    end
end
local function Resize(w, h)
    -- only grows: room for an embedded addon of natural size w x h
    local mw, mh = MinSize()
    if w then mw = math.max(mw, SIDE_W + w) end
    if h then mh = math.max(mh, h) end
    if frame.SetResizeBounds then frame:SetResizeBounds(mw, mh)
    elseif frame.SetMinResize then frame:SetMinResize(mw, mh) end
    local cw, ch = frame:GetSize()
    cw, ch = cw or DEFAULT_W, ch or DEFAULT_H
    if cw < mw or ch < mh then
        -- keep the top-left corner where it is
        local l, t = frame:GetLeft(), frame:GetTop()
        frame:SetSize(math.max(cw, mw), math.max(ch, mh))
        if l and t then frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t) end
        SavePlace()
    end
end

local function Unembed()
    if embedded and registry[embedded] and registry[embedded].unembed then
        pcall(registry[embedded].unembed)
    end
    embedded = nil
end

-- product page -------------------------------------------------------
local page = {}
local function BuildPage()
    local p = CreateFrame("Frame", nil, content)
    p:SetAllPoints()
    page.frame = p

    local icon = p:CreateTexture(nil, "ARTWORK"); icon:SetSize(64, 64); icon:SetPoint("TOPLEFT", 24, -24)
    local iconBorder = CreateFrame("Frame", nil, p); iconBorder:SetAllPoints(icon); Border(iconBorder, 0.10)
    local title = Text(p, 22, C.text); title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 16, -2)
    local by = Text(p, 12, C.muted); by:SetPoint("LEFT", title, "RIGHT", 10, -2)
    local summary = Text(p, 13, C.dim); summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8); summary:SetWidth(PAGE_W - 280)
    local tagHolder = CreateFrame("Frame", nil, p); tagHolder:SetSize(400, 22); tagHolder:SetPoint("TOPLEFT", icon, "BOTTOMRIGHT", 16, 18)
    page.icon, page.title, page.by, page.summary, page.tagHolder, page.tags = icon, title, by, summary, tagHolder, {}

    -- status + action (top right)
    local status = Text(p, 12, C.muted); status:SetPoint("TOPRIGHT", -24, -28); status:SetJustifyH("RIGHT")
    local action = Button(p, "", 150, true, function() if page.onAction then page.onAction() end end)
    action:SetPoint("TOPRIGHT", -24, -50)
    page.status, page.action = status, action

    -- tabs
    local tabY = -116
    local line = Fill(p, { 1, 1, 1, 0.07 }, "BORDER"); line:SetHeight(1)
    line:SetPoint("TOPLEFT", 24, tabY - 30); line:SetPoint("TOPRIGHT", -24, tabY - 30)
    page.tabs = {}
    local tx = 24
    for _, t in ipairs({ { "overview", "Overview" }, { "gallery", "Gallery" } }) do
        local b = CreateFrame("Button", nil, p)
        b.label = Text(b, 15, C.dim); b.label:SetPoint("LEFT"); b.label:SetText(t[2])
        b:SetSize(b.label:GetStringWidth() + 4, 30)
        b:SetPoint("TOPLEFT", tx, tabY)
        b.under = Fill(b, C.accent, "ARTWORK"); b.under:SetHeight(2); b.under:SetPoint("BOTTOMLEFT", 0, -1); b.under:SetPoint("BOTTOMRIGHT", 0, -1)
        b:SetScript("OnClick", function() page.tab = t[1]; page.Refresh() end)
        page.tabs[t[1]] = b
        tx = tx + b:GetWidth() + 26
    end

    -- overview: the CurseForge description (headings, paragraphs, bullets), scrolls with the mouse wheel
    local ov = CreateFrame("ScrollFrame", nil, p); ov:SetPoint("TOPLEFT", 24, tabY - 46); ov:SetPoint("BOTTOMRIGHT", -30, 66)
    local ovc = CreateFrame("Frame", nil, ov); ovc:SetSize(PAGE_W - 54, 10); ov:SetScrollChild(ovc)
    ov:EnableMouseWheel(true)
    ov:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, (ovc:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - d * 40)))
        if page.UpdateScrollBar then page.UpdateScrollBar() end
    end)
    local track = Fill(p, { 1, 1, 1, 0.06 }, "ARTWORK"); track:SetWidth(4)
    track:SetPoint("TOPRIGHT", -22, tabY - 46); track:SetPoint("BOTTOMRIGHT", -22, 66)
    local thumbBar = Fill(p, C.accent, "ARTWORK", 2); thumbBar:SetWidth(4)
    function page.UpdateScrollBar()
        local vh, ch = ov:GetHeight() or 1, ovc:GetHeight() or 1
        local shown = ov:IsShown() and ch > vh + 2
        track:SetShown(shown); thumbBar:SetShown(shown)
        if not shown then return end
        local th = math.max(20, vh * vh / ch)
        local off = (ov:GetVerticalScroll() or 0) / (ch - vh)
        thumbBar:SetHeight(th); thumbBar:ClearAllPoints()
        thumbBar:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -(vh - th) * off)
    end
    page.overview, page.ovChild, page.blocks, page.bullets = ov, ovc, {}, {}
    local function block(i)
        local fs = page.blocks[i]
        if not fs then
            fs = Text(ovc, 13, C.dim); fs:SetJustifyH("LEFT"); fs:SetSpacing(2)
            page.blocks[i] = fs
            local dot = ovc:CreateTexture(nil, "ARTWORK"); dot:SetTexture(WHITE); dot:SetSize(5, 5)
            dot:SetVertexColor(unpack(C.accent)); dot:SetPoint("TOPRIGHT", fs, "TOPLEFT", -9, -5)
            page.bullets[i] = dot
        end
        return fs, page.bullets[i]
    end
    page.Block = block

    -- gallery: thumbnails 3 per row, click to enlarge
    local gal = CreateFrame("Frame", nil, p); gal:SetPoint("TOPLEFT", 24, tabY - 46); gal:SetPoint("BOTTOMRIGHT", -24, 70)
    page.gallery, page.thumbs = gal, {}
    local TW, TH = 214, 107
    for i = 1, 6 do
        local b = CreateFrame("Button", nil, gal)
        b:SetSize(TW, TH)
        b:SetPoint("TOPLEFT", ((i - 1) % 3) * (TW + 9), -math.floor((i - 1) / 3) * (TH + 9))
        b.bg = Fill(b, C.panel); b.bg:SetAllPoints()
        b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints()
        Border(b, 0.08, "OVERLAY")
        b:SetScript("OnEnter", function(self) BorderColor(self, C.accent[1], C.accent[2], C.accent[3], 1) end)
        b:SetScript("OnLeave", function(self) BorderColor(self, 1, 1, 1, 0.08) end)
        b:SetScript("OnClick", function(self) page.ShowImage(self.index) end)
        page.thumbs[i] = b
    end
    local noImg = Text(gal, 13, C.muted); noImg:SetPoint("TOPLEFT"); noImg:SetText("No pictures yet.")
    page.noImg = noImg

    -- lightbox
    local lb = CreateFrame("Button", nil, p)
    lb:SetAllPoints(content)
    lb:SetFrameLevel(p:GetFrameLevel() + 20)
    local lbbg = Fill(lb, { 0, 0, 0, 0.88 }); lbbg:SetAllPoints()
    local img = lb:CreateTexture(nil, "ARTWORK"); img:SetSize(PAGE_W - 80, (PAGE_W - 80) / 2); img:SetPoint("CENTER", 0, 10)
    local count = Text(lb, 12, C.dim); count:SetPoint("TOP", img, "BOTTOM", 0, -10)
    local function arrow(label, side, dir)
        local a = Button(lb, label, 36, false, function() page.ShowImage((page.imgIndex or 1) + dir) end)
        a:SetPoint(side, side == "LEFT" and 16 or -16, 10)
        return a
    end
    arrow("<", "LEFT", -1)
    arrow(">", "RIGHT", 1)
    local lbHint = Text(lb, 11, C.muted); lbHint:SetPoint("BOTTOM", 0, 16); lbHint:SetText("Click anywhere to close")
    lb:SetScript("OnClick", function(self) self:Hide() end)
    lb:Hide()
    page.lightbox, page.lbImage, page.lbCount = lb, img, count

    -- footer: link
    local foot = CreateFrame("Frame", nil, p); foot:SetPoint("BOTTOMLEFT"); foot:SetPoint("BOTTOMRIGHT"); foot:SetHeight(56)
    local fbg = Fill(foot, C.panel, "BACKGROUND", -5); fbg:SetAllPoints()
    local fl = Fill(foot, { 1, 1, 1, 0.06 }, "BORDER"); fl:SetHeight(1); fl:SetPoint("TOPLEFT"); fl:SetPoint("TOPRIGHT")
    local linkLabel = Text(foot, 12, C.muted); linkLabel:SetPoint("LEFT", 24, 0)
    local link = CreateFrame("EditBox", nil, foot)
    link:SetHeight(26); link:SetPoint("LEFT", 150, 0); link:SetPoint("RIGHT", -80, 0)
    link:SetAutoFocus(false); link:SetTextInsets(8, 8, 0, 0)
    SetFont(link, 12); link:SetTextColor(unpack(C.text))
    local lbg2 = Fill(link, C.control); lbg2:SetAllPoints(); Border(link, 0.08)
    link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    link:SetScript("OnTextChanged", function(self, user) if user then self:SetText(page.url or ""); self:HighlightText() end end)
    link:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local copyHint = Text(foot, 11, C.muted); copyHint:SetPoint("LEFT", link, "RIGHT", 10, 0); copyHint:SetText("Ctrl+C")
    page.linkLabel, page.link, page.copyHint = linkLabel, link, copyHint

    -- follow the window size
    p:SetScript("OnSizeChanged", function(_, w, h)
        w = w or PAGE_W
        summary:SetWidth(math.max(200, w - 280))
        if page.ovChild then page.ovChild:SetWidth(math.max(200, w - 54)) end
        local iw = math.min(w - 120, 2 * ((h or PAGE_H) - 120))
        img:SetSize(iw, iw / 2)
        if page.entry and page.Refresh then page.Refresh() end
    end)

    function page.ShowImage(i)
        local list = page.entry and page.entry.gallery or {}
        if #list == 0 then return end
        i = tonumber(i) or 1
        if i < 1 then i = #list elseif i > #list then i = 1 end
        page.imgIndex = i
        local g = list[i]
        page.lbImage:SetTexture(type(g) == "table" and g.path or g)
        local cap = (type(g) == "table" and g.title) and ("|cffedeff3" .. g.title .. "|r" .. (g.text and ("  —  " .. g.text) or "") .. "     ") or ""
        page.lbCount:SetText(cap .. "|cff808590" .. i .. " / " .. #list .. "|r")
        page.lightbox:Show()
    end

    function page.Refresh()
        local e = page.entry
        if not e then return end
        local st = State(e.id)
        icon:SetTexture(e.icon)
        title:SetText(e.title)
        by:SetText("by " .. (e.author or "?"))
        summary:SetText(e.summary or "")
        -- tags
        for _, t in ipairs(page.tags) do t:Hide() end
        local x = 0
        for i, tag in ipairs(e.tags or {}) do
            local t = page.tags[i]
            if not t then
                t = CreateFrame("Frame", nil, tagHolder); t:SetHeight(20)
                t.bg = Fill(t, C.control); t.bg:SetAllPoints(); Border(t, 0.10)
                t.label = Text(t, 11, C.dim); t.label:SetPoint("CENTER")
                page.tags[i] = t
            end
            t.label:SetText(tag)
            t:SetWidth(t.label:GetStringWidth() + 16)
            t:ClearAllPoints(); t:SetPoint("LEFT", tagHolder, "LEFT", x, 0)
            x = x + t:GetWidth() + 6
            t:Show()
        end
        -- status and action
        local v = Version(e.id)
        status:SetText((STATE_LABEL[st] or "") .. (v and st ~= "missing" and ("  ·  " .. v) or ""))
        status:SetTextColor(unpack(st == "loaded" and C.good or C.muted))
        page.onAction = nil
        if st == "disabled" or st == "installed" then
            action.label:SetText("Enable and reload")
            page.onAction = function() EnableAddOn(e.id, UnitName("player")); ReloadUI() end
            action:Show()
        elseif st == "loaded" and registry[e.id] and registry[e.id].embed then
            action.label:SetText("Open options")
            page.onAction = function() Select(e.id, true) end
            action:Show()
        else
            action:Hide()
        end
        -- link
        page.url = e.url
        if e.url then
            linkLabel:SetText(st == "missing" and "Get it on CurseForge" or "CurseForge page")
            link:SetText(e.url); link:Show(); copyHint:Show()
        else
            linkLabel:SetText("Not published yet")
            link:Hide(); copyHint:Hide()
        end
        -- tabs
        page.tab = page.tab or "overview"
        for k, b in pairs(page.tabs) do
            local on = (k == page.tab)
            b.under:SetShown(on)
            b.label:SetTextColor(unpack(on and C.text or C.dim))
        end
        ov:SetShown(page.tab == "overview")
        gal:SetShown(page.tab == "gallery")
        -- overview blocks
        local W = math.max(200, (ov:GetWidth() or (PAGE_W - 54)))
        ovc:SetWidth(W)
        local y, n = 0, 0
        for i, blk in ipairs(e.description or {}) do
            n = i
            local fs, dot = page.Block(i)
            fs:ClearAllPoints(); dot:Hide()
            if blk.h then
                SetFont(fs, 16); fs:SetTextColor(unpack(C.text)); fs:SetText(blk.h)
                y = y - (i > 1 and 12 or 0)
                fs:SetWidth(W); fs:SetPoint("TOPLEFT", ovc, "TOPLEFT", 0, y)
                y = y - (fs:GetStringHeight() or 16) - 8
            elseif blk.li then
                SetFont(fs, 13); fs:SetTextColor(unpack(C.dim)); fs:SetText(blk.li)
                fs:SetWidth(W - 18); fs:SetPoint("TOPLEFT", ovc, "TOPLEFT", 18, y); dot:Show()
                y = y - (fs:GetStringHeight() or 14) - 5
            else
                SetFont(fs, 13); fs:SetTextColor(unpack(C.dim)); fs:SetText(blk.p or "")
                fs:SetWidth(W); fs:SetPoint("TOPLEFT", ovc, "TOPLEFT", 0, y)
                y = y - (fs:GetStringHeight() or 14) - 10
            end
            fs:Show()
        end
        for i = n + 1, #page.blocks do page.blocks[i]:Hide(); page.bullets[i]:Hide() end
        ovc:SetHeight(math.max(10, -y))
        if page.lastEntry ~= e then ov:SetVerticalScroll(0); page.lastEntry = e end
        page.UpdateScrollBar()
        -- gallery
        local list = e.gallery or {}
        for i, b in ipairs(page.thumbs) do
            local g = list[i]
            if g then b.tex:SetTexture(type(g) == "table" and g.path or g); b.index = i; b:Show() else b:Hide() end
        end
        page.noImg:SetShown(#list == 0)
    end
end

local function ShowPage(e)
    if not page.frame then BuildPage() end
    page.entry = e
    page.tab = "overview"
    page.lightbox:Hide()
    page.Refresh()
    page.frame:Show()
end

-- sidebar ----------------------------------------------------------------
local function RefreshSidebar()
    local installed, missing = {}, {}
    for _, e in ipairs(ns.CATALOG) do
        if e.id ~= ADDON then
            if State(e.id) == "missing" then missing[#missing + 1] = e else installed[#installed + 1] = e end
        end
    end
    local y = -70
    local function caption(cap, text)
        cap:ClearAllPoints(); cap:SetPoint("TOPLEFT", side, "TOPLEFT", 16, y); cap:SetText(text); y = y - 22
    end
    local function place(list)
        for _, e in ipairs(list) do
            local b = entries[e.id]
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", side, "TOPLEFT", 8, y)
            local st = State(e.id)
            b.icon:SetTexture(e.icon)
            b.name:SetText(e.title)
            local v = Version(e.id)
            b.state:SetText(STATE_LABEL[st] .. (v and st ~= "missing" and ("  ·  " .. v) or ""))
            b.state:SetTextColor(unpack(st == "loaded" and C.good or C.muted))
            b.icon:SetDesaturated(st == "missing")
            b.icon:SetAlpha(st == "missing" and 0.6 or 1)
            local on = (current == e.id)
            b.bg:SetVertexColor(unpack(on and C.control or C.side))
            b.mark:SetShown(on)
            b:Show()
            y = y - 50
        end
        y = y - 8
    end
    caption(side.capInstalled, "INSTALLED")
    if #installed == 0 then side.none:SetPoint("TOPLEFT", side, "TOPLEFT", 16, y); side.none:Show(); y = y - 30 else side.none:Hide() end
    place(installed)
    side.capMissing:SetShown(#missing > 0)
    if #missing > 0 then caption(side.capMissing, "NOT INSTALLED"); place(missing) end
end

function Select(id, forceOptions)
    current = id
    Unembed()
    if page.frame then page.frame:Hide() end
    local e
    for _, it in ipairs(ns.CATALOG) do if it.id == id then e = it end end
    local reg = registry[id]
    -- loaded addons that support the hub show their own options; others get the product page
    if reg and reg.embed and State(id) == "loaded" and (forceOptions or not FreeHubDB.pageFirst) then
        local ok, child = pcall(reg.embed, content)
        if ok and child then
            embedded = id
            Resize(child.fhNaturalW, child.fhNaturalH)
            RefreshSidebar()
            return
        end
    end
    if e then ShowPage(e) end
    RefreshSidebar()
end

local function Build()
    frame = CreateFrame("Frame", "FreeHubFrame", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:SetSize(FreeHubDB.w or DEFAULT_W, FreeHubDB.h or DEFAULT_H)
    Place()
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    tinsert(UISpecialFrames, "FreeHubFrame")
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetTexture(MEDIA .. "shadow"); shadow:SetVertexColor(0, 0, 0, 0.8)
    shadow:SetPoint("TOPLEFT", -36, 36); shadow:SetPoint("BOTTOMRIGHT", 36, -36)
    local bg = Fill(frame, C.bg, "BACKGROUND", -6); bg:SetAllPoints()
    Border(frame, 0.09)

    -- sidebar
    side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT"); side:SetPoint("BOTTOMLEFT"); side:SetWidth(SIDE_W)
    local sbg = Fill(side, C.side, "BACKGROUND", -5); sbg:SetAllPoints()
    local sline = Fill(side, { 1, 1, 1, 0.06 }, "BORDER"); sline:SetWidth(1); sline:SetPoint("TOPRIGHT"); sline:SetPoint("BOTTOMRIGHT")
    local top = Fill(side, C.accent, "BORDER", 2); top:SetHeight(2); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    local head = CreateFrame("Frame", nil, side); head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(56)
    head:EnableMouse(true); head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() frame:StartMoving() end)
    head:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); SavePlace() end)
    local hicon = head:CreateTexture(nil, "ARTWORK"); hicon:SetTexture(MEDIA .. "icon"); hicon:SetSize(30, 30); hicon:SetPoint("LEFT", 14, -2)
    local htitle = Text(head, 16, C.text); htitle:SetPoint("LEFT", hicon, "RIGHT", 10, 6); htitle:SetText("Free Hub")
    local hsub = Text(head, 11, C.muted); hsub:SetPoint("TOPLEFT", htitle, "BOTTOMLEFT", 0, -3); hsub:SetText("by DecardCain")
    side.capInstalled = Text(side, 11, C.accent)
    side.capMissing = Text(side, 11, C.accent)
    side.none = Text(side, 12, C.muted); side.none:SetText("No Free addon found.")
    -- click the Free Hub title: its own product page (description, gallery, CurseForge link)
    local about = CreateFrame("Button", nil, head); about:SetPoint("TOPLEFT", 8, -6); about:SetSize(SIDE_W - 30, 44)
    about:RegisterForDrag("LeftButton")
    about:SetScript("OnDragStart", function() frame:StartMoving() end)
    about:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); SavePlace() end)
    about:SetScript("OnEnter", function() htitle:SetTextColor(unpack(C.accent)) end)
    about:SetScript("OnLeave", function() htitle:SetTextColor(unpack(C.text)) end)
    about:SetScript("OnClick", function() Select(ADDON); RefreshSidebar() end)
    for _, e in ipairs(ns.CATALOG) do
        local b = CreateFrame("Button", nil, side)
        b:SetSize(SIDE_W - 16, 44)
        b.bg = Fill(b, C.side); b.bg:SetAllPoints()
        b.mark = Fill(b, C.accent, "ARTWORK"); b.mark:SetWidth(2); b.mark:SetPoint("TOPLEFT"); b.mark:SetPoint("BOTTOMLEFT")
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(30, 30); b.icon:SetPoint("LEFT", 10, 0)
        b.name = Text(b, 13, C.text); b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, -1); b.name:SetPoint("RIGHT", -6, 0); b.name:SetWordWrap(false)
        b.state = Text(b, 11, C.muted); b.state:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 10, 1)
        b:SetScript("OnEnter", function(self) if current ~= e.id then self.bg:SetVertexColor(unpack(C.panel)) end end)
        b:SetScript("OnLeave", function(self) if current ~= e.id then self.bg:SetVertexColor(unpack(C.side)) end end)
        b:SetScript("OnClick", function() Select(e.id) end)
        entries[e.id] = b
    end

    -- sidebar footer: settings
    local sf = CreateFrame("Frame", nil, side); sf:SetPoint("BOTTOMLEFT", 0, 0); sf:SetPoint("BOTTOMRIGHT", -1, 0); sf:SetHeight(84)
    local sfl = Fill(sf, { 1, 1, 1, 0.06 }, "BORDER"); sfl:SetHeight(1); sfl:SetPoint("TOPLEFT"); sfl:SetPoint("TOPRIGHT")
    local function toggleRow(y, label, get, set)
        local r = CreateFrame("Button", nil, sf); r:SetSize(SIDE_W - 24, 22); r:SetPoint("TOPLEFT", 12, y)
        local box = r:CreateTexture(nil, "ARTWORK"); box:SetSize(12, 12); box:SetPoint("LEFT"); box:SetTexture(WHITE)
        local l = Text(r, 11, C.dim); l:SetPoint("LEFT", box, "RIGHT", 8, 0); l:SetPoint("RIGHT"); l:SetText(label)
        local function paint() box:SetVertexColor(unpack(get() and C.accent or C.control)) end
        r:SetScript("OnClick", function() set(not get()); paint() end)
        r.paint = paint
        return r
    end
    side.optMinimap = toggleRow(-12, "One minimap button (hide the addons' own)",
        function() return FreeHubDB.hideChildButtons ~= false end,
        function(v)
            FreeHubDB.hideChildButtons = v
            for _, info in pairs(registry) do if info.minimap then pcall(info.minimap, not v) end end
        end)
    side.optPage = toggleRow(-38, "Open product page first",
        function() return FreeHubDB.pageFirst end,
        function(v) FreeHubDB.pageFirst = v end)

    -- content
    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", SIDE_W, 0); content:SetPoint("BOTTOMRIGHT")

    local close = CreateFrame("Button", nil, frame); close:SetSize(26, 26); close:SetPoint("TOPRIGHT", -10, -12)
    close:SetFrameLevel(frame:GetFrameLevel() + 40)
    local x1 = Fill(close, C.dim, "ARTWORK"); x1:SetSize(14, 2); x1:SetPoint("CENTER"); x1:SetRotation(math.rad(45))
    local x2 = Fill(close, C.dim, "ARTWORK"); x2:SetSize(14, 2); x2:SetPoint("CENTER"); x2:SetRotation(math.rad(-45))
    close:SetScript("OnEnter", function() x1:SetVertexColor(unpack(C.accent)); x2:SetVertexColor(unpack(C.accent)) end)
    close:SetScript("OnLeave", function() x1:SetVertexColor(unpack(C.dim)); x2:SetVertexColor(unpack(C.dim)) end)
    close:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnShow", function()
        side.optMinimap.paint(); side.optPage.paint()
        Select(current or (ns.CATALOG[1] and ns.CATALOG[1].id))
    end)
    -- resize grip (bottom-right corner)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(18, 18); grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 60)
    for i = 1, 3 do
        local d = Fill(grip, C.muted, "OVERLAY"); d:SetSize(2 + 4 * i, 2)
        d:SetPoint("BOTTOMRIGHT", -2, 2 + 4 * (i - 1)); d:SetRotation(math.rad(-45))
        grip["d" .. i] = d
    end
    local function gripColor(c) for i = 1, 3 do grip["d" .. i]:SetVertexColor(unpack(c)) end end
    grip:SetScript("OnEnter", function() gripColor(C.accent) end)
    grip:SetScript("OnLeave", function() gripColor(C.muted) end)
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); SavePlace() end)

    -- an embedded addon moves the hub from its own header: remember where it went
    if hooksecurefunc then hooksecurefunc(frame, "StopMovingOrSizing", function() SavePlace() end) end
    frame:SetScript("OnHide", function() SavePlace(); Unembed() end)
    Resize()
    frame:Hide()
end

function FreeHub:Open(id)
    if not frame then Build() end
    if id then current = id end
    if frame:IsShown() then Select(current) else frame:Show() end
end
function FreeHub:Toggle(id)
    if not frame then Build() end
    if frame:IsShown() and (not id or id == current) then frame:Hide() else self:Open(id) end
end
function FreeHub:Hide() if frame then frame:Hide() end end
-- the hub window, so an embedded addon can move it from its own header
function FreeHub:GetFrame() if not frame then Build() end return frame end

-- ------------------------------------------------------------ boot, minimap, slash
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        FreeHubDB = FreeHubDB or {}
        if FreeHubDB.hideChildButtons == nil then FreeHubDB.hideChildButtons = true end
        FreeHubDB.minimap = FreeHubDB.minimap or { hide = false }
    elseif event == "PLAYER_LOGIN" then
        local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
        local Icon = LibStub and LibStub("LibDBIcon-1.0", true)
        if LDB and Icon then
            local obj = LDB:NewDataObject("FreeHub", {
                type = "launcher", text = "Free Hub", icon = MEDIA .. "icon",
                OnClick = function() FreeHub:Toggle() end,
                OnTooltipShow = function(tt)
                    tt:AddLine("Free Hub")
                    tt:AddLine("|cffffffffClick|r  open the Free addons", 0.8, 0.8, 0.8)
                end,
            })
            if obj then Icon:Register("FreeHub", obj, FreeHubDB.minimap) end
        end
        -- the addons registered before PLAYER_LOGIN: apply the minimap choice now
        for _, info in pairs(registry) do if info.minimap then pcall(info.minimap, not FreeHub:ManagesMinimap()) end end
    end
end)

SLASH_FREEHUB1 = "/free"
SLASH_FREEHUB2 = "/freehub"
SlashCmdList.FREEHUB = function() FreeHub:Toggle() end
