--[[
    Utils.lua
    Small helpers used by more than one file. Loaded before the core file, so
    it must not depend on anything except ns.
]]

local _, ns = ...

local SECONDS_PER_MINUTE = 60

--- Formats a number of seconds as a countdown, e.g. 754 -> "12:34".
--- Rounds down to whole seconds. Used for the scan cooldown in chat (Scanner.lua)
--- and on the Scan button (ResultsWindow.lua).
---@param seconds number Time left, in seconds (0 or more)
---@return string countdown Minutes and zero-padded seconds, "m:ss"
function ns.FormatCountdown(seconds)
    seconds = math.floor(seconds)
    return ("%d:%02d"):format(math.floor(seconds / SECONDS_PER_MINUTE), seconds % SECONDS_PER_MINUTE)
end
