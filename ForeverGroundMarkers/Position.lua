--[[
    Position.lua
    Reads the player's current location from the game. Returns plain data only.
    Deciding what to do with it (saving, printing) is left to callers such as
    Markers.lua, so this can be reused later for distance and map features.
]]

local _, ns = ...

-- Reason codes returned when no position is available, one per failure point so
-- debug output shows exactly which API came back empty. Callers turn these into
-- user-facing messages.
ns.POSITION_UNAVAILABLE = {
    INSTANCED = "instanced",
    NO_MAP = "no_map",
    NO_MAP_POSITION = "no_map_position",
    NO_WORLD_POSITION = "no_world_position",
}

--- Returns the subzone name, or nil if there isn't a distinct one.
--- GetSubZoneText returns "" when the player isn't in a named subzone, and in some
--- places it repeats the zone name. Both cases become nil so callers can simply
--- check whether a subzone exists.
---@param zoneName string The zone name the subzone will be displayed with
---@return string|nil subZoneName
local function getDistinctSubZone(zoneName)
    local subZoneName = GetSubZoneText()
    if subZoneName == "" or subZoneName == zoneName then
        return nil
    end
    return subZoneName
end

--- Reads the player's position in both coordinate systems the addon stores.
--- Map coordinates come from C_Map on the most specific map for the player's
--- location (0-1 across that map). World coordinates come from UnitPosition in
--- yards, with the instance ID of the continent. Map coordinates are what players
--- see and share. World coordinates allow real distance math later.
--- Both APIs return nil inside instances (dungeons, raids, battlegrounds, arenas),
--- which Blizzard restricts on purpose, so that case is reported separately.
---@return table|nil position Fields: mapId, mapX, mapY, worldX, worldY, instanceId, zoneName, subZoneName
---@return string|nil reason One of ns.POSITION_UNAVAILABLE when position is nil
function ns.GetPlayerPosition()
    if IsInInstance() then
        return nil, ns.POSITION_UNAVAILABLE.INSTANCED
    end

    local mapId = C_Map.GetBestMapForUnit("player")
    if not mapId then
        return nil, ns.POSITION_UNAVAILABLE.NO_MAP
    end

    local mapPosition = C_Map.GetPlayerMapPosition(mapId, "player")
    if not mapPosition then
        return nil, ns.POSITION_UNAVAILABLE.NO_MAP_POSITION
    end

    -- UnitPosition returns Y before X, and its Z value is always 0 for addons.
    local worldY, worldX, _, instanceId = UnitPosition("player")
    if not worldX then
        return nil, ns.POSITION_UNAVAILABLE.NO_WORLD_POSITION
    end

    local mapX, mapY = mapPosition:GetXY()
    local mapInfo = C_Map.GetMapInfo(mapId)
    local zoneName = (mapInfo and mapInfo.name) or GetZoneText()

    return {
        mapId = mapId,
        mapX = mapX,
        mapY = mapY,
        worldX = worldX,
        worldY = worldY,
        instanceId = instanceId,
        zoneName = zoneName,
        subZoneName = getDistinctSubZone(zoneName),
    }
end
