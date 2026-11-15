-- The guide window: a list of steps with the current one always in the same row. Finished and
-- skipped steps stay above it; the mouse wheel scrolls through the whole route.
--
-- Nothing is drawn behind the list unless the player turns the backplate on: the text is
-- outlined to stay readable over the scene, and the current step is the larger, brighter line
-- with the yellow bar. A row's control shows only while the pointer is on it, and so does the
-- header above the list: a dark bar that is the one place to drag the window from.
--
-- This is a plain frame. It is never anchored to one of the game's protected frames, so it
-- may be shown, hidden, moved and resized during combat.
local _, ns = ...

local Window = {}
ns.Window = Window

local WIDTH = 240
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 20
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
local KIND_TEXTURE = {
    kill = "Interface\\Cursor\\Attack",
    loot = "Interface\\Cursor\\Pickup",
    go = "Interface\\Cursor\\Taxi", -- be somewhere: an escort, an exploration
    sell = "Interface\\Cursor\\Buy", -- a vendor, when the bags run low
}
local KIND_GLYPH = { accept = "!", turnin = "?" }

-- A game font object, outlined: there is no plate behind the text to give it contrast.
local function setFont(text, object)
    text:SetFontObject(object)
    local file, size = text:GetFont()
    if file then
        text:SetFont(file, size, "OUTLINE")
    end
end

local function setColor(region, color, alpha)
    region:SetVertexColor(color[1], color[2], color[3], alpha or 1)
end

-- The window is dragged by its header, or by itself while it is only the pause mark, unless
-- it is locked. `allowed` says whether this region may start a drag now.
local function makeDraggable(region, allowed)
    region:EnableMouse(true)
    region:RegisterForDrag("LeftButton")
    region:SetScript("OnDragStart", function()
        if not ns.db.locked and (not allowed or allowed()) then
            Window.moving = true
            Window.frame:StartMoving()
        end
    end)
    region:SetScript("OnDragStop", function()
        if Window.moving then
            Window.moving = false
            Window:StopMoving()
        end
    end)
end

local function createRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(WIDTH)
    row.current = 0 -- nothing drawn yet: not the same as an empty row

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
    row.glyph = row:CreateFontString(nil, "ARTWORK")
    setFont(row.glyph, "GameFontNormal")
    row.glyph:SetPoint("CENTER", row.icon, "CENTER")

    row.name = row:CreateFontString(nil, "ARTWORK")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.count = row:CreateFontString(nil, "ARTWORK")
    setFont(row.count, "GameFontNormal")
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

-- Draw one row for the step at `index`, or leave it empty when there is no such step. A row
-- that already shows exactly this is left alone, also when the planner has handed over the
-- same step in a new table.
local function drawRow(row, index, currentIndex)
    local step = ns.Steps.list[index]
    local status = step and ns.Steps:Status(index)
    local have = step and ns.Steps:Progress(index)
    local current = step ~= nil and index == currentIndex
    local kind, name, need = step and step.kind, step and step.name, step and step.need
    row.index = index
    row.step = step
    if
        row.kind == kind
        and row.text == name
        and row.need == need
        and row.status == status
        and row.have == have
        and row.current == current
    then
        return
    end
    row.kind, row.text, row.need, row.status, row.have, row.current = kind, name, need, status, have, current

    -- The pointer's control may belong to what the row showed before; the pointer check
    -- brings it back if it still applies.
    row.hot = nil
    row.skip:Hide()
    row.restore:Hide()
    row.hover:Hide()
    if not step then
        row.bar:Hide()
        row.icon:Hide()
        row.glyph:Hide()
        row.name:Hide()
        row.count:Hide()
        row.strike:Hide()
        row:SetHeight(ROW_HEIGHT)
        return
    end
    row.name:Show()
    row.count:Show()
    row:SetHeight(current and CURRENT_HEIGHT or ROW_HEIGHT)
    row.bar:SetShown(current)

    local color = current and BRIGHT or DIM
    setFont(row.name, current and "GameFontHighlightLarge" or "GameFontHighlight")
    row.name:SetText(step.name)
    row.name:SetTextColor(color[1], color[2], color[3])

    -- Progress is automatic: a count while the step is open, a tick once it is finished.
    local done = status == "done"
    if step.need and not done and step.kind ~= "go" then -- a place has no count
        row.count:SetText(have .. "/" .. step.need)
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
    self.combat = InCombatLockdown()
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    makeDraggable(frame, function()
        return self.paused
    end)
    frame:EnableMouseWheel(true)

    -- The header sits above the first row, outside the frame, so the list does not move when
    -- it comes and goes. The clamp reaches up to keep it on the screen.
    frame:SetClampRectInsets(0, 0, HEADER_HEIGHT, 0)
    local header = CreateFrame("Frame", nil, frame)
    self.header = header
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("BOTTOMLEFT", frame, "TOPLEFT")
    header:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT")
    makeDraggable(header)
    header:Hide()
    local plate = header:CreateTexture(nil, "BACKGROUND")
    plate:SetAllPoints()
    plate:SetColorTexture(0.05, 0.055, 0.06, 0.8)
    for column = 0, 1 do -- the grip: two columns of three dots
        for line = -1, 1 do
            local dot = header:CreateTexture(nil, "ARTWORK")
            dot:SetSize(2, 2)
            dot:SetPoint("CENTER", header, "LEFT", 15 + column * 5, line * 5)
            dot:SetColorTexture(BRIGHT[1], BRIGHT[2], BRIGHT[3], 1)
        end
    end
    local title = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    title:SetPoint("LEFT", 32, 0)
    title:SetText("Leveling Guide")

    self.background = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    self.background:SetAllPoints()

    -- In a dungeon there is nothing to guide to: the window shrinks to this pause mark.
    self.pause = CreateFrame("Frame", nil, frame)
    self.pause:SetAllPoints()
    for _, x in ipairs({ -3, 3 }) do
        local bar = self.pause:CreateTexture(nil, "ARTWORK")
        bar:SetSize(3, 10)
        bar:SetPoint("CENTER", x, 0)
        bar:SetColorTexture(DIM[1], DIM[2], DIM[3], 1)
    end

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
        self.combat = event == "PLAYER_REGEN_DISABLED"
        self.scroll = 0
        self:Refresh()
    end)

    self:RestorePosition()
end

-- While the window is shown: which row is under the pointer, whether the header is up, and the
-- return of a scrolled list. The header stays while it is under the pointer or being dragged.
ns.Task("window", 0.05, function()
    local self = Window
    local header = self.header
    local over = self.frame:IsMouseOver() or (header:IsShown() and header:IsMouseOver()) or self.moving or false
    header:SetShown(over and not ns.db.locked)
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

-- Instances have no map position to guide to. PLAYER_ENTERING_WORLD follows every loading
-- screen, so it is the moment to look.
ns.On("PLAYER_ENTERING_WORLD", function()
    local paused = IsInInstance and IsInInstance() and true or false
    if paused ~= (Window.paused or false) then
        Window.paused = paused
        if paused then
            ns.say("paused in here. It comes back outside.")
        end
        Window:Refresh()
    end
end)

function ns.commands.lock()
    ns.Set("locked", not ns.db.locked)
    ns.say("window " .. (ns.db.locked and "locked." or "unlocked: drag it to move it."))
end

function Window:Refresh()
    local frame = self.frame
    if not frame then
        return
    end
    local paused = self.paused or false
    frame:SetShown(ns.db.shown)
    ns.SetTask("window", ns.db.shown and not paused)
    if not ns.db.shown then
        return
    end
    local folded = self.combat and ns.db.combatDim
    frame:SetScale(ns.db.scale)
    frame:SetAlpha(folded and COMBAT_ALPHA or 1)
    frame:SetWidth(paused and ROW_HEIGHT or WIDTH)
    self.background:SetColorTexture(0.05, 0.055, 0.06, ns.db.opacity)
    self.pause:SetShown(paused)
    if paused or ns.db.locked then
        self.header:Hide() -- the pointer check is off while paused
    end

    local total = ns.Steps:Count()
    local current = ns.Steps:CurrentIndex() or total + 1
    local visible = paused and 0 or folded and 1 or ns.db.rows

    -- At rest the current step is in the third row. Scrolling moves the view, limited to the
    -- route's first and last steps.
    local home = folded and current or current - HISTORY_ROWS
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
            if row.y ~= y then
                row.y = y
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
            end
            row:Show()
            y = y + row:GetHeight()
        elseif row then
            row:Hide()
        end
    end
    frame:SetHeight(math.max(y, ROW_HEIGHT))

    local span = math.max(last - first + visible, 1)
    self.thumb:SetShown(not folded and not paused and span > visible)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -y * (top - first) / span)
    self.thumb:SetHeight(math.max(y * visible / span, 8))
end
