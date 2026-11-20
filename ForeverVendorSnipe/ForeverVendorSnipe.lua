--[[
    ForeverVendorSnipe.lua
    Core of the addon. Owns the single event frame, initializes SavedVariables,
    and dispatches /vsnipe subcommands. Loaded after the locale, Utils and Log
    files, so every later file can use ns.Print, ns.Debug, ns.RegisterEvent,
    ns.commands and (after ADDON_LOADED) ns.db.
]]

local addonName, ns = ...

local L = ns.L

local CHAT_PREFIX_COLOR = "|cff33ff99"
local SLASH_COMMAND = "/vsnipe"
-- Typing /vsnipe on its own runs this subcommand (registered in ResultsWindow.lua).
local DEFAULT_COMMAND = "toggle"

-- Account-wide defaults, merged into ForeverVendorSnipeDB on load.
ns.defaults = {
    debug = false,
    -- Results window position, saved when the player drags it (ResultsWindow.lua).
    window = {
        point = "TOPRIGHT",
        relativePoint = "TOPRIGHT",
        x = -40,
        y = -120,
    },
    -- Scan results and scan timing per realm, keyed by realm name (Scanner.lua).
    realms = {},
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

--- Shows a message in the default chat frame, prefixed with the colored addon name.
--- Chat only: callers decide whether the message is also logged.
---@param msg string The message to show
local function printToChat(msg)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX_COLOR .. L.CHAT_PREFIX .. "|r: " .. msg)
end

--- Prints a message to chat and writes it to the saved log (ns.Log).
--- Converts non-string values with tostring so callers can pass numbers or booleans.
---@param msg any The message to print
function ns.Print(msg)
    msg = tostring(msg)
    ns.Log(msg)
    printToChat(msg)
end

--- Records a diagnostic message. It always goes to the saved log, and is also shown
--- in chat with a "[debug]" tag while debug mode is on (/vsnipe debug). Before
--- ADDON_LOADED the debug setting isn't known yet, so it's only logged.
---@param msg any The message to record
function ns.Debug(msg)
    msg = tostring(msg)
    ns.Log(msg)
    if ns.db and ns.db.debug then
        printToChat("[debug] " .. msg)
    end
end

local eventFrame = CreateFrame("Frame")

-- Handlers per event, in registration order: eventHandlers[event] = { handler1, handler2 }.
-- Lists are never modified in place. ns.UnregisterEvent builds a new list, so a
-- handler that unregisters itself mid-dispatch can't make the loop skip the next one.
local eventHandlers = {}

--- Routes a game event to every handler registered for it, in registration order.
--- Installed as the event frame's OnEvent script. Events with no handlers are ignored.
--- Each handler runs through ns.SafeCall, so an error is logged and shown, and the
--- remaining handlers for the event still run.
---@param event string The game event name
---@param ... any The event's payload, passed straight through to each handler
local function dispatchEvent(_, event, ...)
    local handlers = eventHandlers[event]
    if not handlers then
        return
    end
    for _, handler in ipairs(handlers) do
        ns.SafeCall(handler, ...)
    end
end
eventFrame:SetScript("OnEvent", dispatchEvent)

--- Adds a handler for a game event on the addon's shared event frame.
--- Several files can listen to the same event, and each handler runs in the order it
--- was registered. The game is only asked to send the event once, on the first registration.
---@param event string The game event name, e.g. "PLAYER_LOGIN"
---@param handler fun(...) Called with the event's payload
function ns.RegisterEvent(event, handler)
    local handlers = eventHandlers[event]
    if not handlers then
        handlers = {}
        eventHandlers[event] = handlers
        eventFrame:RegisterEvent(event)
    end
    handlers[#handlers + 1] = handler
end

--- Removes one handler from a game event, leaving any other handlers in place.
--- Builds a new list without the handler instead of editing the old one (see eventHandlers).
--- When no handlers remain, the game stops sending the event.
---@param event string The game event name
---@param handler fun(...) The same function that was passed to ns.RegisterEvent
function ns.UnregisterEvent(event, handler)
    local handlers = eventHandlers[event]
    if not handlers then
        return
    end

    local remaining = {}
    for _, existing in ipairs(handlers) do
        if existing ~= handler then
            remaining[#remaining + 1] = existing
        end
    end

    if #remaining == 0 then
        eventHandlers[event] = nil
        eventFrame:UnregisterEvent(event)
    else
        eventHandlers[event] = remaining
    end
end

--- Initializes SavedVariables once this addon has loaded.
--- ADDON_LOADED fires for every addon, so this ignores the others, then unregisters
--- itself. Connects the saved log first (ns.InitLog), so everything after is logged,
--- then creates the settings table on first run, merges defaults, and exposes it as
--- ns.db for the other files.
---@param loadedName string Name of the addon that just loaded
local function onAddonLoaded(loadedName)
    if loadedName ~= addonName then
        return
    end
    ns.UnregisterEvent("ADDON_LOADED", onAddonLoaded)
    ns.InitLog()

    ForeverVendorSnipeDB = ForeverVendorSnipeDB or {}
    applyDefaults(ForeverVendorSnipeDB, ns.defaults)
    ns.db = ForeverVendorSnipeDB
end

--- Announces the loaded version in chat once the player is in the world.
--- Reads the version from the .toc so it never drifts from the packaged version.
local function onPlayerLogin()
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
    ns.Print(L.LOADED:format(tostring(version), SLASH_COMMAND))
end

ns.RegisterEvent("ADDON_LOADED", onAddonLoaded)
ns.RegisterEvent("PLAYER_LOGIN", onPlayerLogin)

-- Slash subcommands, keyed by the word typed after /vsnipe. Each entry is:
--   description  shown by /vsnipe help
--   handler      called with the rest of the input line as a string
-- Other files add their own entries (Scanner.lua: scan, ResultsWindow.lua: toggle).
ns.commands = {}

--- Prints every registered subcommand with its description.
--- Sorts by name first, because pairs() order is unpredictable and the list
--- should read the same every time.
local function showHelp()
    local names = {}
    for name in pairs(ns.commands) do
        names[#names + 1] = name
    end
    table.sort(names)

    ns.Print(L.COMMANDS_HEADER)
    for _, name in ipairs(names) do
        ns.Print("  " .. SLASH_COMMAND .. " " .. name .. " - " .. ns.commands[name].description)
    end
end

ns.commands.help = { description = L.CMD_HELP, handler = showHelp }

--- Handles /vsnipe debug: turns debug output on or off and confirms the new state.
--- The setting is saved, so debug mode survives /reload and relogging.
local function toggleDebug()
    ns.db.debug = not ns.db.debug
    ns.Print(L.DEBUG_STATE:format(ns.db.debug and L.ON or L.OFF))
end

ns.commands.debug = { description = L.CMD_DEBUG, handler = toggleDebug }

--- Handles /vsnipe clearlog: empties the saved log and confirms in chat.
--- Clears first, so the confirmation becomes the new log's first line.
local function clearLog()
    ns.ClearLog()
    ns.Print(L.LOG_CLEARED)
end

ns.commands.clearlog = { description = L.CMD_CLEARLOG, handler = clearLog }

--- Handles /vsnipe input by looking up the first word in ns.commands.
--- Splits the input into a command name and the rest of the line, which is passed
--- to the handler as its arguments. Empty input runs DEFAULT_COMMAND (toggle the
--- window), and unknown commands say so.
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
        ns.Print(L.UNKNOWN_COMMAND:format(name, SLASH_COMMAND))
    end
end

SLASH_FOREVERVENDORSNIPE1 = SLASH_COMMAND
SlashCmdList.FOREVERVENDORSNIPE = handleSlashCommand
