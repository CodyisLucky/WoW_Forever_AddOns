--[[
    Log.lua
    A capped, timestamped log saved in the ForeverVendorSnipeLog SavedVariable, so
    players can send it back when something goes wrong. Addons can't write files,
    so the game writes the log to
    WTF/Account/<ACCOUNT>/SavedVariables/ForeverVendorSnipe.lua on /reload or logout.

    Loaded before the core file so ns.Print and ns.Debug can write to it. Lines
    logged before ADDON_LOADED (when the SavedVariable exists) are buffered and
    flushed by ns.InitLog.
]]

local addonName, ns = ...

local LOG_MAX_LINES = 500
local TIMESTAMP_FORMAT = "%Y-%m-%d %H:%M:%S"
local ERROR_PREFIX = "ERROR: "
local STACK_INDENT = "    "
-- debugstack levels to skip inside the error handler: 1 is reportError itself,
-- so 2 starts at the function that raised the error.
local STACK_START_LEVEL = 2
local STACK_MAX_LINES = 8

local logLines -- ForeverVendorSnipeLog.lines once ns.InitLog has run
local bufferedLines = {}
-- How many times each error message has been raised this session (see reportError).
local errorCounts = {}

--- Adds one finished line to the log and drops the oldest lines past LOG_MAX_LINES.
--- Before ns.InitLog, lines go to a buffer instead.
---@param line string A timestamped log line
local function appendLine(line)
    if not logLines then
        bufferedLines[#bufferedLines + 1] = line
        return
    end
    logLines[#logLines + 1] = line
    while #logLines > LOG_MAX_LINES do
        table.remove(logLines, 1)
    end
end

--- Writes a timestamped line to the saved log. Never prints to chat.
--- ns.Print and ns.Debug call this, so everything shown in chat is logged too.
---@param msg any The message; converted with tostring
function ns.Log(msg)
    appendLine(date(TIMESTAMP_FORMAT) .. " " .. tostring(msg))
end

--- Deletes every saved log line. /vsnipe clearlog runs this, so a player can start
--- a clean log before reproducing a problem.
function ns.ClearLog()
    if logLines then
        for i = #logLines, 1, -1 do
            logLines[i] = nil
        end
    end
end

--- Connects the log to its SavedVariable, flushes buffered lines, and writes a session
--- header (addon version, realm, client version and build) so each session's lines
--- are easy to find. Called once from the core file's ADDON_LOADED handler.
function ns.InitLog()
    ForeverVendorSnipeLog = ForeverVendorSnipeLog or {}
    if type(ForeverVendorSnipeLog.lines) ~= "table" then
        ForeverVendorSnipeLog.lines = {}
    end
    logLines = ForeverVendorSnipeLog.lines

    for _, line in ipairs(bufferedLines) do
        appendLine(line)
    end
    bufferedLines = {}

    local clientVersion, clientBuild = GetBuildInfo()
    ns.Log(("Session start: %s v%s, realm %s, client %s (%s)"):format(
        addonName, tostring(C_AddOns.GetAddOnMetadata(addonName, "Version")),
        tostring(GetRealmName()), tostring(clientVersion), tostring(clientBuild)))
end

--- Whether a number is a power of two (1, 2, 4, 8, ...).
---@param n number A positive whole number
---@return boolean
local function isPowerOfTwo(n)
    while n > 1 and n % 2 == 0 do
        n = n / 2
    end
    return n == 1
end

--- xpcall error handler: logs the error, then hands it to the game's normal error
--- handler, so BugSack or the default error popup still shows it.
--- The first time a message is seen this session it's logged with a short stack trace,
--- one line per stack frame so the saved file stays readable. Repeats (e.g. an error in
--- the once-a-second status ticker) are logged as one short line on the 2nd, 4th, 8th...
--- occurrence, so they can't push everything else out of the capped log.
---@param err any The error raised
---@return any err The same error
local function reportError(err)
    local message = tostring(err)
    local count = (errorCounts[message] or 0) + 1
    errorCounts[message] = count
    if count == 1 then
        ns.Log(ERROR_PREFIX .. message)
        local stack = debugstack(STACK_START_LEVEL, STACK_MAX_LINES, 0) or ""
        for line in stack:gmatch("[^\n]+") do
            ns.Log(STACK_INDENT .. line)
        end
    elseif isPowerOfTwo(count) then
        ns.Log(("%s(seen %d times) %s"):format(ERROR_PREFIX, count, message))
    end
    geterrorhandler()(err)
    return err
end

--- Calls a function and logs any error it raises (see reportError) instead of letting
--- it escape. Used for event handlers (core dispatcher), timer and item-load callbacks
--- (Scanner.lua), and the window's timers, OnShow and click/typing handlers
--- (ResultsWindow.lua). Arguments are packed into a closure because Lua 5.1's
--- xpcall can't pass them through.
---@param fn function The function to call
---@param ... any Arguments for fn
---@return boolean ok False if fn raised an error
function ns.SafeCall(fn, ...)
    local count, args = select("#", ...), { ... }
    return xpcall(function()
        return fn(unpack(args, 1, count))
    end, reportError)
end
