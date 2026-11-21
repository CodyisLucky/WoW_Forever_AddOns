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

--- Compares the unit prices of two auctions exactly, without dividing.
--- Cross-multiplies: (buyoutA / countA) - (buyoutB / countB) has the same sign as
--- buyoutA * countB - buyoutB * countA, because counts are positive. Stacks priced in
--- fractions of a copper per unit (7 for 1s) therefore compare exactly. Used once per
--- auction by BelowVendor.lua and Undercuts.lua, so both cache it as a local.
---@param buyoutA number Buyout of auction A, in copper
---@param countA number Units in auction A (more than 0)
---@param buyoutB number Buyout of auction B, in copper
---@param countB number Units in auction B (more than 0)
---@return number sign Negative if A is cheaper per unit, 0 if equal, positive if dearer
function ns.CompareUnitPrice(buyoutA, countA, buyoutB, countB)
    return buyoutA * countB - buyoutB * countA
end
