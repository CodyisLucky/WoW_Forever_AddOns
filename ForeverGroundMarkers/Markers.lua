--[[
    Markers.lua
    Stores and removes saved markers, and provides the /fgm mark and
    /fgm remove commands. All persistence goes through ns.AddMarker and
    ns.RemoveMarker so the saved data format is defined in one place.
]]

local _, ns = ...

-- Map coordinates are stored as 0-1 and displayed as percentages, like the
-- default UI and most coordinate addons.
local MAP_COORD_DISPLAY_SCALE = 100
local MAP_COORD_FORMAT = "%.2f, %.2f"
local DEBUG_MARKER_FORMAT = "Marker #%d: mapId=%d mapX=%.4f mapY=%.4f worldX=%.2f worldY=%.2f instanceId=%d"

-- Player-facing text for position failures that need their own explanation.
-- Any reason code not listed here gets DEFAULT_UNAVAILABLE_MESSAGE, and the exact
-- code is still shown in debug mode.
local UNAVAILABLE_MESSAGES = {
    [ns.POSITION_UNAVAILABLE.INSTANCED] = "Position unavailable here (instanced area). Markers are open world only for now.",
}
local DEFAULT_UNAVAILABLE_MESSAGE = "Position unavailable here. Try again after moving."

--- Builds the readable location text for a marker, e.g. "Elwynn Forest - Goldshire (42.15, 65.87)".
--- Leaves the subzone out when the marker has none, and scales the stored 0-1 map
--- coordinates to percentages with two decimal places.
---@param marker table A saved marker (needs zoneName, subZoneName, mapX, mapY)
---@return string
local function formatLocation(marker)
    local place = marker.zoneName
    if marker.subZoneName then
        place = place .. " - " .. marker.subZoneName
    end
    local coords = MAP_COORD_FORMAT:format(
        marker.mapX * MAP_COORD_DISPLAY_SCALE,
        marker.mapY * MAP_COORD_DISPLAY_SCALE
    )
    return place .. " (" .. coords .. ")"
end

--- Builds a one-line dump of a marker's raw saved values for debug output.
--- Shows more precision than the chat message, plus the world coordinates and
--- IDs that players don't normally need to see.
---@param id number The marker ID
---@param marker table A saved marker
---@return string
local function describeMarkerForDebug(id, marker)
    return DEBUG_MARKER_FORMAT:format(
        id, marker.mapId, marker.mapX, marker.mapY,
        marker.worldX, marker.worldY, marker.instanceId
    )
end

--- Saves a new marker built from a position and returns its ID.
--- Copies each field explicitly, which makes this the single definition of the saved
--- marker format, and stamps the creation time. Takes the next ID from
--- ns.db.nextMarkerId and increments it, so IDs stay unique even after removals.
---@param position table A position from ns.GetPlayerPosition
---@return number id The new marker's ID
---@return table marker The saved marker
function ns.AddMarker(position)
    local id = ns.db.nextMarkerId
    ns.db.nextMarkerId = id + 1

    local marker = {
        mapId = position.mapId,
        mapX = position.mapX,
        mapY = position.mapY,
        worldX = position.worldX,
        worldY = position.worldY,
        instanceId = position.instanceId,
        zoneName = position.zoneName,
        subZoneName = position.subZoneName,
        createdAt = time(),
    }
    ns.db.markers[id] = marker
    return id, marker
end

--- Deletes a saved marker by ID.
---@param id number The marker ID
---@return boolean removed False if no marker had that ID
function ns.RemoveMarker(id)
    if not ns.db.markers[id] then
        return false
    end
    ns.db.markers[id] = nil
    return true
end

--- Handles /fgm mark: saves the player's current position as a new marker and
--- prints it. When position isn't available, prints why and saves nothing. In
--- debug mode it also logs the failure's reason code, or the raw saved values on success.
local function markCurrentPosition()
    local position, reason = ns.GetPlayerPosition()
    if not position then
        ns.Print(UNAVAILABLE_MESSAGES[reason] or DEFAULT_UNAVAILABLE_MESSAGE)
        ns.Debug("GetPlayerPosition failed: " .. tostring(reason))
        return
    end

    local id, marker = ns.AddMarker(position)
    ns.Print("Marker #" .. id .. " saved: " .. formatLocation(marker))
    ns.Debug(describeMarkerForDebug(id, marker))
end

--- Handles /fgm remove <id>: deletes one marker and confirms in chat.
--- Only accepts a whole positive number, since marker IDs are never anything else.
---@param args string The text after "remove", expected to be the marker ID
local function removeMarkerCommand(args)
    local id = tonumber(args)
    if not id or id < 1 or id % 1 ~= 0 then
        ns.Print("Usage: " .. ns.SLASH_COMMAND .. " remove <id>")
        return
    end

    if ns.RemoveMarker(id) then
        ns.Print("Marker #" .. id .. " removed.")
    else
        ns.Print("No marker #" .. id .. ".")
    end
end

ns.commands.mark = {
    description = "Save a marker at your current position",
    handler = markCurrentPosition,
}

ns.commands.remove = {
    arguments = "<id>",
    description = "Delete a saved marker",
    handler = removeMarkerCommand,
}
