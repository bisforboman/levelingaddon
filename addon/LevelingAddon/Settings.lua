-- The addon's page in the game's own settings panel, and the one function a feature calls to
-- put a control on it. Every setting can also be changed with /lvl set, which is all there is
-- on a client without the Settings API.
local _, ns = ...

local PAGE = "Leveling Addon"

local list = {} -- in the order added, which is the order on the page
local byKey = {}
local category -- the page, once the game has accepted it

-- Put a control on the settings page. Call it at file scope, from the feature's own file:
--     ns.defaults.greet = true
--     ns.AddSetting({ key = "greet", label = "Greet at login" })
-- key       the name in ns.db; its default in ns.defaults decides the control: a boolean is a
--           checkbox, a number a slider, a string a dropdown
-- label     the text beside the control
-- tooltip   optional, shown on hover
-- min, max, step   for a slider
-- options   for a dropdown: the values it offers, each a string
-- onChange  optional function(value), called after ns.db[key] has changed. Without it,
--           ns.Refresh() is called. Either way the change applies at once.
-- func      instead of key: a button that calls func()
function ns.AddSetting(spec)
    table.insert(list, spec)
    if spec.key then
        byKey[spec.key] = spec
    end
end

-- Change a setting added with ns.AddSetting, from anywhere, and apply it at once. A number is
-- kept within the slider's range and on its steps.
function ns.Set(key, value)
    local spec = byKey[key]
    if spec.max then
        value = math.floor(value / spec.step + 0.5) * spec.step
        value = math.max(spec.min, math.min(spec.max, value))
    end
    ns.db[key] = value
    local apply = spec.onChange or ns.Refresh
    apply(value)
end

local function sliderLabel(spec)
    return function(value)
        return spec.step < 1 and string.format("%d%%", value * 100 + 0.5) or tostring(value)
    end
end

-- Build the page from the list, with the game's standard controls.
local function build()
    local page, layout = Settings.RegisterVerticalLayoutCategory(PAGE)
    for _, spec in ipairs(list) do
        local key = spec.key
        if spec.func then
            layout:AddInitializer(CreateSettingsButtonInitializer("", spec.label, spec.func, spec.tooltip, true))
        else
            local default = ns.defaults[key]
            local setting = Settings.RegisterProxySetting(
                page,
                "LevelingAddon_" .. key,
                type(default),
                spec.label,
                default,
                function()
                    return ns.db[key]
                end,
                function(value)
                    ns.Set(key, value)
                end
            )
            if type(default) == "number" then
                local options = Settings.CreateSliderOptions(spec.min, spec.max, spec.step)
                if MinimalSliderWithSteppersMixin then
                    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, sliderLabel(spec))
                end
                Settings.CreateSlider(page, setting, options, spec.tooltip)
            elseif spec.options then
                -- Not on a client without dropdowns; /lvl set still has it.
                local createDropdown = Settings.CreateDropdown or Settings.CreateDropDown
                if createDropdown and Settings.CreateControlTextContainer then
                    createDropdown(page, setting, function()
                        local container = Settings.CreateControlTextContainer()
                        for _, option in ipairs(spec.options) do
                            container:Add(option, (option:gsub("^%l", string.upper)))
                        end
                        return container:GetData()
                    end, spec.tooltip)
                end
            else
                local createCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox
                createCheckbox(page, setting, spec.tooltip)
            end
        end
    end
    Settings.RegisterAddOnCategory(page)
    return page
end

-- At login every feature file has run, so the list is complete. A client whose Settings API
-- is missing or differs gets no page; /lvl set still works.
ns.On("PLAYER_LOGIN", function()
    if Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting then
        local ok, page = pcall(build)
        category = ok and page or nil
    end
end)

function ns.commands.settings()
    if category then
        Settings.OpenToCategory(category:GetID())
    else
        ns.say("this client has no settings page for addons. /lvl set lists the settings.")
    end
end

-- /lvl set lists the settings; /lvl set key value changes one. A switch takes on or off, or
-- flips when no value is given; a choice takes one of its values.
function ns.commands.set(arg)
    local key, value = strsplit(" ", arg or "", 2)
    local spec = byKey[key]
    if not spec then
        local parts = {}
        for _, each in ipairs(list) do
            if each.key then
                table.insert(parts, each.key .. " " .. tostring(ns.db[each.key]))
            end
        end
        ns.say("/lvl set and one of: " .. table.concat(parts, ", "))
        return
    end
    if type(ns.defaults[key]) == "number" then
        value = tonumber(value)
        if not value then
            ns.say(key .. " takes a number from " .. spec.min .. " to " .. spec.max .. ".")
            return
        end
    elseif spec.options then
        local known = false
        for _, option in ipairs(spec.options) do
            known = known or option == value
        end
        if not known then
            ns.say(key .. " takes one of: " .. table.concat(spec.options, ", ") .. ".")
            return
        end
    elseif value == "on" or value == "off" then
        value = value == "on"
    else
        value = not ns.db[key]
    end
    ns.Set(key, value)
    ns.say(key .. " " .. tostring(ns.db[key]) .. ".")
end

-- The settings the owner chose for the first version (docs/ui-concepts.md, section 7), plus
-- rows in view and the lock.
ns.defaults.opacity = 0 -- of a dark plate behind the list: none unless the player wants one
ns.defaults.combatDim = true -- fold to the current step and dim while in combat
ns.defaults.locked = false -- the window cannot be dragged

ns.AddSetting({ key = "scale", label = "Scale", min = 0.6, max = 2, step = 0.05 })
ns.AddSetting({ key = "opacity", label = "Background opacity", min = 0, max = 1, step = 0.05 })
ns.AddSetting({ key = "rows", label = "Steps in view", min = 3, max = 16, step = 1 })
ns.AddSetting({ key = "arrow", label = "Arrow", tooltip = "Point at the current step." })
ns.AddSetting({ key = "pin", label = "Map pin", tooltip = "Mark the current target on the map and the minimap." })
ns.AddSetting({ key = "combatDim", label = "Dim in combat", tooltip = "Show only the current step, dimmed." })
ns.AddSetting({ key = "locked", label = "Lock position", tooltip = "The window cannot be dragged and has no header." })
ns.AddSetting({
    label = "Reset position",
    tooltip = "Put the window back where it starts.",
    func = function()
        ns.commands.reset()
    end,
})
