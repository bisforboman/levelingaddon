-- The guide window: a list of steps with the current one always in the same row. Finished and
-- skipped steps stay above it; the mouse wheel scrolls through the whole route.
--
-- This is a plain frame. It is never anchored to one of the game's protected frames, so it
-- may be shown, hidden, moved and resized during combat.
local _, ns = ...

local Window = {}
ns.Window = Window

local WIDTH = 240
local ROW_HEIGHT = 20
local CURRENT_HEIGHT = 26 -- the current step is set in larger type
local HISTORY_ROWS = 2 -- rows kept above the current step, so it sits in the third row
local RETURN_AFTER = 5 -- seconds before a scrolled list goes back to the current step
local COMBAT_ALPHA = 0.4

local YELLOW = { 0.95, 0.76, 0.19 }
local BRIGHT = { 0.96, 0.95, 0.90 }
local DIM = { 0.72, 0.71, 0.67 }

-- Art that ships with the game. The atlas names are in the Forever UI source; the two cursor
-- files are engine art that the source does not list, so check them in the client.
local ATLAS_DONE = "common-icon-checkmark"
local ATLAS_SKIP = "common-icon-redx"
local ATLAS_RESTORE = "common-icon-undo"
local KIND_TEXTURE = { kill = "Interface\\Cursor\\Attack", loot = "Interface\\Cursor\\Pickup" }
local KIND_GLYPH = { accept = "!", turnin = "?" }

local function setColor(region, color, alpha)
    region:SetVertexColor(color[1], color[2], color[3], alpha or 1)
end

local function createRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(WIDTH)
    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function()
        parent:StartMoving()
    end)
    row:SetScript("OnDragStop", function()
        Window:StopMoving()
    end)

    row.band = row:CreateTexture(nil, "BACKGROUND")
    row.band:SetAllPoints()
    row.band:SetColorTexture(YELLOW[1], YELLOW[2], YELLOW[3], 0.16)
    row.bar = row:CreateTexture(nil, "BORDER")
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetWidth(3)
    row.bar:SetColorTexture(YELLOW[1], YELLOW[2], YELLOW[3], 1)
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 10, 0)
    row.glyph = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.glyph:SetPoint("CENTER", row.icon, "CENTER")

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.count = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.count:SetPoint("RIGHT", -30, 0)
    row.name:SetPoint("LEFT", row, "LEFT", 32, 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)

    -- A line through the name of a skipped step.
    row.strike = row:CreateTexture(nil, "OVERLAY")
    row.strike:SetHeight(1)
    row.strike:SetPoint("LEFT", row.name, "LEFT", 0, 0)
    row.strike:SetColorTexture(DIM[1], DIM[2], DIM[3], 1)

    -- Skip sits at the right end of a pending row. Restore sits on the left of a skipped row,
    -- in place of its icon. Both show only while the pointer is on the row.
    row.skip = CreateFrame("Button", nil, row)
    row.skip:SetSize(16, 16)
    row.skip:SetPoint("RIGHT", -8, 0)
    row.skip:SetNormalAtlas(ATLAS_SKIP)
    row.skip:SetScript("OnClick", function()
        ns.Steps:Skip(row.index)
        ns.Refresh()
    end)
    row.restore = CreateFrame("Button", nil, row)
    row.restore:SetSize(16, 16)
    row.restore:SetPoint("CENTER", row.icon, "CENTER")
    row.restore:SetNormalAtlas(ATLAS_RESTORE)
    row.restore:SetScript("OnClick", function()
        ns.Steps:Restore(row.index)
        Window.scroll = 0
        ns.Refresh()
    end)
    return row
end

-- Draw one row for the step at `index`, or leave it empty when there is no such step.
local function drawRow(row, index, currentIndex)
    local step = ns.Steps.list[index]
    row.index = index
    row.step = step
    for _, region in ipairs({ row.band, row.bar, row.icon, row.glyph, row.name, row.count, row.strike }) do
        region:SetShown(step ~= nil)
    end
    if not step then
        row.status = nil
        row:SetHeight(ROW_HEIGHT)
        return
    end

    local status = ns.Steps:Status(index)
    local current = index == currentIndex
    row.status = status
    row:SetHeight(current and CURRENT_HEIGHT or ROW_HEIGHT)
    row.band:SetShown(current)
    row.bar:SetShown(current)

    local color = current and BRIGHT or DIM
    row.name:SetFontObject(current and "GameFontHighlightLarge" or "GameFontHighlight")
    row.name:SetText(step.name)
    row.name:SetTextColor(color[1], color[2], color[3])

    -- Progress is automatic: a count while the step is open, a tick once it is finished.
    local done = status == "done"
    if step.need and not done then
        row.count:SetText(ns.Steps:Progress(index) .. "/" .. step.need)
        row.count:SetTextColor(unpack(status == "pending" and YELLOW or DIM))
    else
        row.count:SetText("")
    end

    local glyph = not done and KIND_GLYPH[step.kind]
    row.glyph:SetShown(glyph ~= nil and glyph ~= false)
    row.icon:SetShown(not glyph)
    if glyph then
        row.glyph:SetText(glyph)
        row.glyph:SetTextColor(unpack(current and YELLOW or DIM))
    elseif done then
        row.icon:SetAtlas(ATLAS_DONE)
        setColor(row.icon, DIM)
    else
        row.icon:SetTexture(KIND_TEXTURE[step.kind])
        setColor(row.icon, color)
    end

    row.strike:SetShown(status == "skipped")
    row.strike:SetWidth(math.min(row.name:GetStringWidth(), WIDTH - 80))
    row:SetAlpha((done or status == "skipped") and 0.8 or 1)
end

-- Show the one control the pointer's row offers: skip on a pending step, restore on a skipped one.
local function setHot(row, hot)
    if row.hot == hot and row.hotStatus == row.status then
        return
    end
    row.hot = hot
    row.hotStatus = row.status
    local pending = row.status == "pending"
    local skipped = row.status == "skipped"
    row.hover:SetShown(hot and row.step ~= nil)
    row.skip:SetShown(hot and pending)
    row.restore:SetShown(hot and skipped)
    if skipped then
        row.icon:SetShown(not hot and not KIND_GLYPH[row.step.kind])
        row.glyph:SetShown(not hot and KIND_GLYPH[row.step.kind] ~= nil)
    end
end

function Window:Create()
    local frame = CreateFrame("Frame", "LevelingAddonWindow", UIParent)
    self.frame = frame
    self.rows = {}
    self.scroll = 0
    self.folded = InCombatLockdown()
    frame:SetWidth(WIDTH)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)

    local background = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.055, 0.06, 0.66)

    -- A thin bar on the right edge showing where the view is in the route.
    self.thumb = frame:CreateTexture(nil, "OVERLAY")
    self.thumb:SetWidth(2)
    self.thumb:SetColorTexture(DIM[1], DIM[2], DIM[3], 0.7)

    frame:SetScript("OnMouseWheel", function(_, delta)
        self.scroll = self.scroll - delta
        self.returnAt = GetTime() + RETURN_AFTER
        self:Refresh()
    end)

    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
        self.folded = event == "PLAYER_REGEN_DISABLED"
        self.scroll = 0
        self:Refresh()
    end)

    self:RestorePosition()
end

-- While the window is shown: which row is under the pointer, and the return of a scrolled list.
ns.Task("window", 0.05, function()
    local self = Window
    local over = self.frame:IsMouseOver()
    for _, row in ipairs(self.rows) do
        setHot(row, over and row:IsShown() and row:IsMouseOver())
    end
    if self.scroll ~= 0 then
        if over then
            self.returnAt = GetTime() + RETURN_AFTER
        elseif GetTime() > (self.returnAt or 0) then
            self.scroll = 0
            self:Refresh()
        end
    end
end)

-- The position is kept in our own saved settings. SetUserPlaced(false) stops the client's
-- layout cache from restoring it as well.
function Window:StopMoving()
    local frame = self.frame
    frame:StopMovingOrSizing()
    frame:SetUserPlaced(false)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    ns.db.point = { point, relativePoint, x, y }
end

function Window:RestorePosition()
    local frame = self.frame
    local saved = ns.db.point
    frame:ClearAllPoints()
    if saved then
        frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -230, -190)
    end
end

function Window:Refresh()
    local frame = self.frame
    if not frame then
        return
    end
    frame:SetShown(ns.db.shown)
    ns.SetTask("window", ns.db.shown)
    if not ns.db.shown then
        return
    end
    frame:SetScale(ns.db.scale)
    frame:SetAlpha(self.folded and COMBAT_ALPHA or 1)

    local total = ns.Steps:Count()
    local current = ns.Steps:CurrentIndex() or total + 1
    local visible = self.folded and 1 or ns.db.rows

    -- At rest the current step is in the third row. Scrolling moves the view, limited to the
    -- route's first and last steps.
    local home = self.folded and current or current - HISTORY_ROWS
    local first = math.min(1, home)
    local last = math.max(total - visible + 1, home)
    local top = math.max(first, math.min(last, home + self.scroll))
    self.scroll = top - home

    local y = 0
    for slot = 1, math.max(visible, #self.rows) do
        local row = self.rows[slot]
        if slot <= visible then
            if not row then
                row = createRow(frame)
                self.rows[slot] = row
            end
            drawRow(row, top + slot - 1, current)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
            row:Show()
            row.hot = nil -- the row may now hold another step; let the pointer check redo it
            row.skip:Hide()
            row.restore:Hide()
            row.hover:Hide()
            y = y + row:GetHeight()
        elseif row then
            row:Hide()
        end
    end
    frame:SetHeight(math.max(y, ROW_HEIGHT))

    local span = math.max(last - first + visible, 1)
    self.thumb:SetShown(not self.folded and span > visible)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -y * (top - first) / span)
    self.thumb:SetHeight(math.max(y * visible / span, 8))
end
