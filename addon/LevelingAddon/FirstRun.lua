-- The player's two choices about which quests to suggest, and the panel that asks for them the
-- first time a character logs in with the addon.
--
-- Dungeon and group quests are left out unless the player switches them on; raid and PvP
-- quests are always left out. The choice is saved per character. While the game runs it lives
-- in ns.Planner.allow, and nowhere else.
local _, ns = ...

-- [setting] = the planner's mark for the quests it lets in.
local MARK = { dungeons = "dungeon", groups = "group" }
local TEXT = { dungeons = "dungeon quests", groups = "group quests" }

ns.charDefaults.setupDone = false -- the panel has been shown and closed with Start

-- A change needs no more than another pass: progress and skipped quests are not touched.
local function apply()
    for key, mark in pairs(MARK) do
        ns.Planner.allow[mark] = ns.char[key]
    end
    ns.Planner.Request()
end

-- ns.AddSetting only knows account-wide settings (ns.db). So ns.char holds the saved choice,
-- and ns.db a copy for the character that is logged in, which the settings page and /lvl set
-- read and write.
for _, key in ipairs({ "dungeons", "groups" }) do
    ns.charDefaults[key] = false
    ns.defaults[key] = false
    ns.AddSetting({
        key = key,
        label = "Include " .. TEXT[key],
        tooltip = "For this character only.",
        onChange = function(value)
            ns.char[key] = value
            apply()
        end,
    })
    -- /lvl dungeons and /lvl groups flip the switch, or take on or off.
    ns.commands[key] = function(arg)
        ns.Set(key, arg == "on" or arg ~= "off" and not ns.char[key])
        ns.say(TEXT[key] .. " " .. (ns.char[key] and "on." or "off."))
    end
end

-- The panel -------------------------------------------------------------------------------

local YELLOW = { 0.95, 0.76, 0.19 }
local DIM = { 0.72, 0.71, 0.67 }
local WIDTH = 260

local panel -- created the first time it is shown

local function createPanel()
    panel = CreateFrame("Frame", "LevelingAddonFirstRun", UIParent)
    panel:SetSize(WIDTH, 150)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true) -- clicks do not fall through to the world

    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.055, 0.06, 0.9)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Welcome to Leveling")
    title:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])

    panel.checks = {}
    for i, key in ipairs({ "dungeons", "groups" }) do
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", 10, -14 - i * 24)
        check:SetScript("OnClick", function(self)
            ns.Set(key, self:GetChecked() and true or false)
        end)
        local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", check, "RIGHT", 2, 0)
        label:SetText("Include " .. TEXT[key])
        panel.checks[key] = check
    end

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 14, -94)
    hint:SetWidth(WIDTH - 28)
    hint:SetJustifyH("LEFT")
    hint:SetText("Drag the window where you want it.")
    hint:SetTextColor(DIM[1], DIM[2], DIM[3])

    local start = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    start:SetSize(90, 22)
    start:SetPoint("BOTTOMRIGHT", -12, 10)
    start:SetText("Start")
    start:SetScript("OnClick", function()
        ns.char.setupDone = true
        panel:Hide()
    end)
end

-- Show the panel beside the real window, so the player can put the window where it suits
-- them and see the suggestions change with the two switches.
local function showPanel()
    if not panel then
        createPanel()
    end
    if not ns.db.shown then
        ns.SetShown(true)
    end
    for key, check in pairs(panel.checks) do
        check:SetChecked(ns.char[key])
    end
    panel:Show()
end
ns.commands.setup = showPanel

-- The panel greets a new character, so Core's one line in chat is not needed.
ns.On("ADDON_LOADED", function()
    ns.firstRun = false
end)

ns.On("PLAYER_LOGIN", function()
    for key in pairs(MARK) do
        ns.db[key] = ns.char[key]
    end
    apply()
    if not ns.char.setupDone then
        showPanel()
    end
end)
