--[[
    ForeverGroundMarkers.lua
    Core of the addon. Owns the single event frame, initializes SavedVariables,
    and dispatches /fgm subcommands. Loaded first, so every other file can use
    ns.Print, ns.RegisterEvent, ns.db (after ADDON_LOADED) and ns.commands.
]]

local addonName, ns = ...

local CHAT_PREFIX_COLOR = "|cff33ff99"
local SLASH_COMMAND = "/fgm"
local DEFAULT_COMMAND = "help"

-- Account-wide defaults, merged into ForeverGroundMarkersDB on load.
-- markers is keyed by marker ID. nextMarkerId only ever increases, so an ID
-- is never reused after its marker is removed.
ns.defaults = {
    nextMarkerId = 1,
    markers = {},
    debug = false,
}

ns.SLASH_COMMAND = SLASH_COMMAND

--- Merges default values into a SavedVariables table without overwriting user choices.
--- Walks `defaults` recursively. Missing keys are copied in, nested tables are created
--- and filled the same way, and existing user values are left untouched.
--- Called from ADDON_LOADED before anything reads the settings.
---@param db table The SavedVariables table to fill (modified in place)
---@param defaults table The default values to merge in
local function applyDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            -- Replace non-table values too, so a corrupted entry can't break nested lookups.
            if type(db[key]) ~= "table" then
                db[key] = {}
            end
            applyDefaults(db[key], value)
        elseif db[key] == nil then
            db[key] = value
        end
    end
end

--- Prints a message to the default chat frame, prefixed with the colored addon title.
--- Converts non-string values with tostring so callers can pass numbers or booleans.
---@param msg any The message to print
function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX_COLOR .. "Ground Markers|r: " .. tostring(msg))
end

--- Prints a diagnostic message, but only while debug mode is on (/fgm debug).
--- Reuses ns.Print with a "[debug]" tag so debug lines are easy to spot. Does nothing
--- before ADDON_LOADED, since the debug setting lives in SavedVariables.
---@param msg any The message to print
function ns.Debug(msg)
    if ns.db and ns.db.debug then
        ns.Print("[debug] " .. tostring(msg))
    end
end

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

--- Routes a game event to the handler registered for it.
--- Installed as the event frame's OnEvent script. Events with no handler are ignored.
---@param event string The game event name
---@param ... any The event's payload, passed straight through to the handler
local function dispatchEvent(_, event, ...)
    local handler = eventHandlers[event]
    if handler then
        handler(...)
    end
end
eventFrame:SetScript("OnEvent", dispatchEvent)

--- Registers a handler for a game event on the addon's shared event frame.
--- One handler per event. Registering again replaces the previous handler.
---@param event string The game event name, e.g. "PLAYER_LOGIN"
---@param handler fun(...) Called with the event's payload
function ns.RegisterEvent(event, handler)
    eventHandlers[event] = handler
    eventFrame:RegisterEvent(event)
end

--- Stops listening for a game event and removes its handler.
---@param event string The game event name
function ns.UnregisterEvent(event)
    eventHandlers[event] = nil
    eventFrame:UnregisterEvent(event)
end

--- Initializes SavedVariables once this addon has loaded.
--- ADDON_LOADED fires for every addon, so this ignores the others, then unregisters
--- itself. Creates the saved table on first run, merges defaults, and exposes it
--- as ns.db for the other files.
---@param loadedName string Name of the addon that just loaded
local function onAddonLoaded(loadedName)
    if loadedName ~= addonName then
        return
    end
    ns.UnregisterEvent("ADDON_LOADED")

    ForeverGroundMarkersDB = ForeverGroundMarkersDB or {}
    applyDefaults(ForeverGroundMarkersDB, ns.defaults)
    ns.db = ForeverGroundMarkersDB
end

--- Announces the loaded version in chat once the player is in the world.
--- Reads the version from the .toc so it never drifts from the packaged version.
local function onPlayerLogin()
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
    ns.Print("v" .. tostring(version) .. " loaded. Type " .. SLASH_COMMAND .. " help for commands.")
end

ns.RegisterEvent("ADDON_LOADED", onAddonLoaded)
ns.RegisterEvent("PLAYER_LOGIN", onPlayerLogin)

-- Slash subcommands, keyed by the word typed after /fgm. Each entry is:
--   description  shown by /fgm help
--   arguments    optional usage hint shown by /fgm help, e.g. "<id>"
--   handler      called with the rest of the input line as a string
-- Other files add their own entries (see Markers.lua).
ns.commands = {}

--- Prints every registered subcommand with its arguments and description.
--- Sorts by name first, because pairs() order is unpredictable and the list
--- should read the same every time.
local function showHelp()
    local names = {}
    for name in pairs(ns.commands) do
        names[#names + 1] = name
    end
    table.sort(names)

    ns.Print("Commands:")
    for _, name in ipairs(names) do
        local command = ns.commands[name]
        local usage = SLASH_COMMAND .. " " .. name
        if command.arguments then
            usage = usage .. " " .. command.arguments
        end
        ns.Print("  " .. usage .. " - " .. command.description)
    end
end

ns.commands.help = { description = "Show this list", handler = showHelp }

--- Handles /fgm debug: turns debug output on or off and confirms the new state.
--- The setting is saved, so debug mode survives /reload and relogging.
local function toggleDebug()
    ns.db.debug = not ns.db.debug
    ns.Print("Debug mode " .. (ns.db.debug and "on" or "off") .. ".")
end

ns.commands.debug = { description = "Toggle diagnostic output", handler = toggleDebug }

--- Handles /fgm input by looking up the first word in ns.commands.
--- Splits the input into a command name and the rest of the line, which is passed
--- to the handler as its arguments. Empty input shows help, and unknown commands say so.
---@param input string Everything typed after the slash command
local function handleSlashCommand(input)
    local name, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    name = name:lower()
    if name == "" then
        name = DEFAULT_COMMAND
    end

    local command = ns.commands[name]
    if command then
        command.handler(rest)
    else
        ns.Print("Unknown command: " .. name .. ". Type " .. SLASH_COMMAND .. " help.")
    end
end

SLASH_FOREVERGROUNDMARKERS1 = SLASH_COMMAND
SlashCmdList.FOREVERGROUNDMARKERS = handleSlashCommand
