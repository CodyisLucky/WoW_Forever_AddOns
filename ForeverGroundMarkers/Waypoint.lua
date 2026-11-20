--[[
    Waypoint.lua
    Owns the addon's use of the game's single map pin (the "user waypoint") and its
    single tracked destination ("super-tracking"). The in-world marker needs both,
    because the navigation frame it's drawn on only follows the tracked destination.

    Taking over saves what the player was tracking. Releasing puts it back. The
    ownership record lives in SavedVariables (ns.db.waypoint) so the player's own pin
    and quest can still be restored after a /reload or relog.
]]

local _, ns = ...

-- Two pin positions closer than this (0-1 map units) count as the same pin. About
-- 1.4 yards on a zone-sized map: loose enough to survive any rounding the game applies
-- to a stored pin, tight enough that a pin the player placed by hand won't match ours.
local PIN_MATCH_TOLERANCE = 0.001

-- Shape of ns.db.waypoint while the addon owns the pin (nil otherwise):
--   markerId   ID of the marker being shown
--   pin        { mapId, x, y } of the pin the addon placed
--   saved      what the player had before the addon took over:
--              { pin = { mapId, x, y } or nil, pinTracked = bool, questId = number or nil }

--- Reads the game's current map pin as a plain table, or nil if there is none.
--- A plain table (instead of the game's UiMapPoint object) can be compared and saved
--- to SavedVariables.
---@return table|nil pin { mapId, x, y }
local function readUserPin()
    if not C_Map.HasUserWaypoint() then
        return nil
    end
    local point = C_Map.GetUserWaypoint()
    return { mapId = point.uiMapID, x = point.position.x, y = point.position.y }
end

--- Returns whether two pins are on the same map at (nearly) the same spot.
---@param a table { mapId, x, y }
---@param b table { mapId, x, y }
---@return boolean
local function pinsMatch(a, b)
    return a.mapId == b.mapId
        and math.abs(a.x - b.x) < PIN_MATCH_TOLERANCE
        and math.abs(a.y - b.y) < PIN_MATCH_TOLERANCE
end

--- Places the game's map pin at a position. It shows on the minimap and World Map too.
---@param pin table { mapId, x, y }
---@return boolean wasSet False if the game refused (e.g. pins aren't allowed on that map)
local function placePin(pin)
    if not C_Map.CanSetUserWaypointOnMap(pin.mapId) then
        return false
    end
    return C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(pin.mapId, pin.x, pin.y))
end

--- Records what the player is tracking right now, so it can be restored later.
--- A quest ID of 0 means no quest, so it's stored as nil.
---@return table saved { pin, pinTracked, questId }
local function captureTracking()
    local questId = C_SuperTrack.GetSuperTrackedQuestID()
    return {
        pin = readUserPin(),
        pinTracked = C_SuperTrack.IsSuperTrackingUserWaypoint(),
        questId = (questId and questId > 0) and questId or nil,
    }
end

--- Returns whether the addon currently owns the map pin and tracked destination.
---@return boolean
function ns.IsWaypointOwned()
    return ns.db.waypoint ~= nil
end

--- Returns the ID of the marker the addon is showing, or nil if it owns nothing.
---@return number|nil
function ns.GetWaypointMarkerId()
    return ns.db.waypoint and ns.db.waypoint.markerId
end

--- Returns whether the player has taken tracking back since the addon took over.
--- True when the addon thinks it owns the pin, but the pin has moved or disappeared
--- (the player placed or cleared a pin), or something else is being tracked (the player
--- clicked a quest). Checked by polling from Beacon.lua, not events, so the addon's own
--- calls can never be mistaken for the player's.
---@return boolean
function ns.HasLostWaypoint()
    local state = ns.db.waypoint
    if not state then
        return false
    end
    local current = readUserPin()
    local ourPinInPlace = current ~= nil and pinsMatch(current, state.pin)
    return not (ourPinInPlace and C_SuperTrack.IsSuperTrackingUserWaypoint())
end

--- Points the map pin and tracked destination at a marker.
--- On the first take-over it saves what the player was tracking. Switching to another
--- marker keeps that saved state, so a release always restores the player's original
--- choice, not a previous marker.
---@param markerId number
---@param marker table A saved marker (needs mapId, mapX, mapY)
---@return boolean success False if the game wouldn't accept a pin at the marker's position
function ns.TakeOverWaypoint(markerId, marker)
    local state = ns.db.waypoint or { saved = captureTracking() }
    local pin = { mapId = marker.mapId, x = marker.mapX, y = marker.mapY }

    if not placePin(pin) then
        ns.Debug("Map pin refused on mapId " .. tostring(marker.mapId))
        return false
    end
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)

    state.markerId = markerId
    state.pin = pin
    ns.db.waypoint = state
    return true
end

--- Gives the map pin and tracked destination back to the player.
--- Always removes the addon's pin (if it's still there) and puts the player's own pin
--- back, unless they've placed a new one since. Tracking itself (their pin or quest) is
--- only restored when `restoreTracking` is true. When the player took tracking away on
--- purpose, their new choice is left alone.
---@param restoreTracking boolean
function ns.ReleaseWaypoint(restoreTracking)
    local state = ns.db.waypoint
    if not state then
        return
    end
    ns.db.waypoint = nil

    local current = readUserPin()
    if current and pinsMatch(current, state.pin) then
        C_Map.ClearUserWaypoint()
        current = nil
    end

    local saved = state.saved
    if saved.pin and not current then
        placePin(saved.pin)
    end

    if restoreTracking then
        -- Only one thing can be tracked, and the pin was the player's active choice if it was tracked.
        if saved.pin and saved.pinTracked then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        elseif saved.questId then
            C_SuperTrack.SetSuperTrackedQuestID(saved.questId)
        end
    end
end
