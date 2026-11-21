-- Shared luacheck config for every addon in this repo. Run from the repo root:
--   luacheck <AddonFolder>
-- Add WoW API globals to read_globals as addons start using them, and each
-- addon's own writable globals (SavedVariables, SLASH_*) to its files entry.

std = "lua51"
max_line_length = false

read_globals = {
    -- Frames and chat
    "CreateFrame",
    "DEFAULT_CHAT_FRAME",
    "GameTooltip",
    "UIParent",
    "UISpecialFrames",

    -- Tabs and sounds
    "PanelTemplates_SetNumTabs",
    "PanelTemplates_SetTab",
    "PanelTemplates_TabResize",
    "PlaySound",
    "SOUNDKIT",

    -- Scroll lists
    "CreateDataProvider",
    "CreateScrollBoxListLinearView",
    "ScrollBoxConstants",
    "ScrollUtil",

    -- Money and number formatting
    "BreakUpLargeNumbers",
    "GetMoneyString",

    -- Namespaced APIs
    "C_AddOns",
    "C_AuctionHouse",
    "C_Item",
    "C_Map",
    "C_Navigation",
    "C_SuperTrack",
    "C_Timer",
    "Settings",

    -- Blizzard UI objects and mixins
    "Enum",
    "Item",
    "MinimalSliderWithSteppersMixin",
    "UiMapPoint",

    -- Unit and zone
    "GetSubZoneText",
    "GetZoneText",
    "InCombatLockdown",
    "IsInInstance",
    "UnitPosition",

    -- Realm and client
    "GetBuildInfo",
    "GetRealmName",

    -- WoW Lua extensions
    "date",
    "debugprofilestop",
    "debugstack",
    "geterrorhandler",
    "strtrim",
    "time",
}

files["ForeverGroundMarkers/"] = {
    globals = {
        "ForeverGroundMarkersDB",
        "SLASH_FOREVERGROUNDMARKERS1",
        "SlashCmdList",
    },
}

files["ForeverVendorSnipe/"] = {
    globals = {
        "ForeverVendorSnipeDB",
        "ForeverVendorSnipeLog",
        "SLASH_FOREVERVENDORSNIPE1",
        "SlashCmdList",
    },
}
