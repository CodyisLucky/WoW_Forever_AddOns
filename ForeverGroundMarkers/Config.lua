--[[
    Config.lua
    Builds the addon's page in Options > AddOns with Blizzard's Settings API, and
    provides /fgm config to open it. Each control is bound directly to a key in ns.db,
    so changes save automatically. Beacon.lua reads the values on its next update.
]]

local addonName, ns = ...

local CATEGORY_NAME = "Forever Ground Markers"
-- Setting variable names must be unique across all addons, so they're prefixed.
local SETTING_PREFIX = addonName .. "_"
local RANGE_MIN, RANGE_MAX, RANGE_STEP = 10, 500, 10 -- yards

--- Builds the tracking mode dropdown's choices: stored value, label and tooltip.
--- Passed to Settings.CreateDropdown as a function, which Blizzard calls when the dropdown opens.
---@return table options
local function getTrackingModeOptions()
    local modes = ns.TRACKING_MODES
    local container = Settings.CreateControlTextContainer()
    container:Add(modes.YIELD, "Only when nothing else is tracked",
        "Markers appear only while you aren't tracking a quest or your own map pin.")
    container:Add(modes.RESTORE, "Take over, then restore",
        "Markers replace your tracked quest or map pin while shown, which come back afterwards.")
    container:Add(modes.MANUAL, "Manual (" .. ns.SLASH_COMMAND .. " show / hide)",
        "Markers appear only after " .. ns.SLASH_COMMAND .. " show. Your tracking is restored after " .. ns.SLASH_COMMAND .. " hide.")
    return container:GetData()
end

--- Formats the range slider's value label, e.g. "100 yd".
---@param value number
---@return string
local function formatYards(value)
    return value .. " yd"
end

--- Adds the tracking mode dropdown, bound to ns.db.trackingMode.
---@param category table The settings category
local function addTrackingModeDropdown(category)
    local setting = Settings.RegisterAddOnSetting(category, SETTING_PREFIX .. "trackingMode", "trackingMode",
        ns.db, Settings.VarType.String, "Tracking mode", ns.defaults.trackingMode)
    Settings.CreateDropdown(category, setting, getTrackingModeOptions,
        "How markers share the game's single tracked destination with quests and your own map pin.")
end

--- Adds the maximum range slider, bound to ns.db.maxRange.
---@param category table The settings category
local function addRangeSlider(category)
    local setting = Settings.RegisterAddOnSetting(category, SETTING_PREFIX .. "maxRange", "maxRange",
        ns.db, Settings.VarType.Number, "Maximum range", ns.defaults.maxRange)
    local options = Settings.CreateSliderOptions(RANGE_MIN, RANGE_MAX, RANGE_STEP)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatYards)
    Settings.CreateSlider(category, setting, options,
        "Only the nearest marker within this distance is shown.")
end

--- Adds the off-screen checkbox, bound to ns.db.showOffscreen.
---@param category table The settings category
local function addOffscreenCheckbox(category)
    local setting = Settings.RegisterAddOnSetting(category, SETTING_PREFIX .. "showOffscreen", "showOffscreen",
        ns.db, Settings.VarType.Boolean, "Show at screen edge when off-screen", ns.defaults.showOffscreen)
    Settings.CreateCheckbox(category, setting,
        "When the marker's spot is off-screen, keep the marker at the edge of the screen pointing toward it.")
end

--- Registers the settings page and its controls.
--- Called once from ADDON_LOADED (ForeverGroundMarkers.lua), after ns.db exists, since
--- every control is bound to it. Stores the category so /fgm config can open it.
function ns.InitSettings()
    local category = Settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)
    addTrackingModeDropdown(category)
    addRangeSlider(category)
    addOffscreenCheckbox(category)
    Settings.RegisterAddOnCategory(category)
    ns.settingsCategory = category
end

--- Handles /fgm config: opens this addon's page in the Options panel.
local function openSettings()
    Settings.OpenToCategory(ns.settingsCategory:GetID())
end

ns.commands.config = { description = "Open the settings panel", handler = openSettings }
