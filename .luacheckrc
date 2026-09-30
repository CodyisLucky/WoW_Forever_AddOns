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

    -- Namespaced APIs
    "C_AddOns",
    "C_Map",
    "C_Timer",
    "Settings",

    -- Unit and zone
    "GetSubZoneText",
    "GetZoneText",
    "InCombatLockdown",
    "IsInInstance",
    "UnitPosition",

    -- WoW Lua extensions
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
