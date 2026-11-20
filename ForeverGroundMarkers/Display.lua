--[[
    Display.lua
    Draws the in-world marker: a white square anchored to the game's navigation frame.
    The engine keeps that frame over the tracked destination every frame, and pins it to
    the screen edge when the spot is off-screen. Only one marker can be drawn, because
    there is only one navigation frame. Which marker that is comes from Beacon.lua.
]]

local _, ns = ...

local MARKER_SIZE = 24 -- pixels, before UI scale

local markerFrame = CreateFrame("Frame", nil, UIParent)
markerFrame:SetSize(MARKER_SIZE, MARKER_SIZE)
-- BACKGROUND keeps the rest of the UI (action bars, chat, tooltips) drawn above the marker.
markerFrame:SetFrameStrata("BACKGROUND")
markerFrame:Hide()

local markerTexture = markerFrame:CreateTexture(nil, "ARTWORK")
markerTexture:SetAllPoints()
markerTexture:SetColorTexture(1, 1, 1, 1)

--- Anchors the marker to the center of the game's navigation frame.
--- The navigation frame only exists while something is being tracked.
---@return boolean anchored False if there's no navigation frame to anchor to
local function anchorToNavigationFrame()
    local navigationFrame = C_Navigation.GetFrame()
    if not navigationFrame then
        return false
    end
    markerFrame:ClearAllPoints()
    markerFrame:SetPoint("CENTER", navigationFrame, "CENTER")
    return true
end

--- Shows or hides the marker every frame while it's active, without stopping updates.
--- Uses alpha instead of Hide, because a hidden frame stops receiving OnUpdate. The
--- marker is invisible when the engine has no screen position for the spot, or when it's
--- pinned to the screen edge and the "show off-screen" setting is off.
local function updateVisibility()
    local visible = C_Navigation.HasValidScreenPosition()
    if visible and not ns.db.showOffscreen and C_Navigation.WasClampedToScreen() then
        visible = false
    end
    markerFrame:SetAlpha(visible and 1 or 0)
end
markerFrame:SetScript("OnUpdate", updateVisibility)

--- Shows the marker on the navigation frame. Does nothing if it's already showing.
--- Stays hidden if there's no navigation frame yet. Beacon.lua calls this again on its
--- next update, and onNavigationFrameCreated re-anchors when the frame appears.
function ns.ShowMarkerDisplay()
    if markerFrame:IsShown() then
        return
    end
    if anchorToNavigationFrame() then
        markerFrame:Show()
    end
end

--- Hides the marker.
function ns.HideMarkerDisplay()
    markerFrame:Hide()
end

--- Re-anchors the marker when the game creates a new navigation frame, since the
--- old anchor pointed at the previous frame.
local function onNavigationFrameCreated()
    if markerFrame:IsShown() then
        anchorToNavigationFrame()
    end
end

--- Detaches and hides the marker when the navigation frame goes away, so it isn't left
--- anchored to a frame that no longer moves. ns.ShowMarkerDisplay re-anchors later.
local function onNavigationFrameDestroyed()
    markerFrame:ClearAllPoints()
    markerFrame:Hide()
end

ns.RegisterEvent("NAVIGATION_FRAME_CREATED", onNavigationFrameCreated)
ns.RegisterEvent("NAVIGATION_FRAME_DESTROYED", onNavigationFrameDestroyed)
