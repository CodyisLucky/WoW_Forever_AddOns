--[[
    Beacon.lua
    Decides which marker is shown in the world, and when. Every UPDATE_INTERVAL seconds
    it finds the nearest marker in range, applies the tracking mode from the settings,
    and tells Waypoint.lua (map pin and tracking) and Display.lua (the square) what to do.
    Also provides /fgm show and /fgm hide for manual mode.
]]

local _, ns = ...

local UPDATE_INTERVAL = 0.5 -- seconds

-- Marker the player took tracking away from (by clicking a quest or placing their own
-- pin). It isn't shown again until a different marker becomes the nearest, or the
-- player leaves range and comes back.
local backedOffMarkerId

--- Returns whether the current tracking mode allows a marker to be shown at all.
--- Only manual mode can say no here, when /fgm show isn't active. Yield mode's "only
--- when nothing else is tracked" rule is checked separately in update.
---@return boolean
local function isDisplayAllowedByMode()
    if ns.db.trackingMode == ns.TRACKING_MODES.MANUAL then
        return ns.db.manualShown
    end
    return true
end

--- Stops showing any marker and gives tracking back to the player, restoring what
--- they were tracking before.
local function stopShowing()
    ns.HideMarkerDisplay()
    if ns.IsWaypointOwned() then
        ns.ReleaseWaypoint(true)
    end
end

--- Backs off if the player took tracking away since the last update.
--- Releases without restoring, so the player's new choice stands, and remembers the
--- marker so update doesn't immediately take it back.
local function handlePlayerTrackingChange()
    if not ns.HasLostWaypoint() then
        return
    end
    backedOffMarkerId = ns.GetWaypointMarkerId()
    ns.Debug("Player changed tracking; backing off marker #" .. tostring(backedOffMarkerId))
    ns.ReleaseWaypoint(false)
    ns.HideMarkerDisplay()
end

--- Finds the nearest marker in range of the player, or nil (including in instances,
--- where the player's position isn't available).
---@return number|nil id
---@return table|nil marker
local function findNearestInRange()
    local position = ns.GetPlayerPosition()
    if not position then
        return nil
    end
    local id, marker = ns.FindNearestMarker(position, ns.db.maxRange)
    return id, marker
end

--- Runs every UPDATE_INTERVAL seconds: picks the marker to show and applies the rules.
--- Order: respect a player tracking change, find the nearest marker, clear the back-off
--- once the nearest marker changes, check the mode, then point tracking at the marker
--- (only when it changed) and show the square.
local function update()
    handlePlayerTrackingChange()

    local nearestId, nearest = findNearestInRange()
    if nearestId ~= backedOffMarkerId then
        backedOffMarkerId = nil
    end

    if not nearestId or nearestId == backedOffMarkerId or not isDisplayAllowedByMode() then
        stopShowing()
        return
    end

    local isYield = ns.db.trackingMode == ns.TRACKING_MODES.YIELD
    if isYield and not ns.IsWaypointOwned() and C_SuperTrack.IsSuperTrackingAnything() then
        ns.HideMarkerDisplay()
        return
    end

    if ns.GetWaypointMarkerId() ~= nearestId then
        if not ns.TakeOverWaypoint(nearestId, nearest) then
            stopShowing()
            return
        end
        ns.Debug("Showing marker #" .. nearestId)
    end
    ns.ShowMarkerDisplay()
end

--- Starts the update loop once the player is in the world.
--- If the addon still owned the pin when the last session ended, it first restores the
--- player's own pin and quest from SavedVariables. The next update then takes over again
--- if the current mode and position call for it.
local function onPlayerLogin()
    if ns.IsWaypointOwned() then
        ns.Debug("Restoring tracking saved from the last session")
        ns.ReleaseWaypoint(true)
    end
    C_Timer.NewTicker(UPDATE_INTERVAL, update)
    update()
end

ns.RegisterEvent("PLAYER_LOGIN", onPlayerLogin)

--- Handles /fgm show and /fgm hide: turns the marker on or off in manual mode.
--- The choice is saved, so it survives /reload and relogging. In the other modes it
--- explains that the commands don't apply, instead of silently doing nothing.
---@param shown boolean
local function setManualShown(shown)
    if ns.db.trackingMode ~= ns.TRACKING_MODES.MANUAL then
        ns.Print(ns.SLASH_COMMAND .. " show and hide only apply in Manual tracking mode. Change it with " .. ns.SLASH_COMMAND .. " config.")
        return
    end
    ns.db.manualShown = shown
    ns.Print(shown and "Showing the nearest marker in range." or "Marker hidden.")
    update()
end

ns.commands.show = {
    description = "Manual mode: show the nearest marker",
    handler = function() setManualShown(true) end,
}

ns.commands.hide = {
    description = "Manual mode: hide the marker",
    handler = function() setManualShown(false) end,
}
