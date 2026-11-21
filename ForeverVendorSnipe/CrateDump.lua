--[[
    CrateDump.lua
    /vsnipe crates: writes every Waylaid Crate in the Auction House's current
    search results to the saved log (item ID, name, required level, how many are
    listed, cheapest price, and the full tooltip text with its fill bundles).

    It's a data-gathering tool for maintaining the crate list: search the AH for
    "Waylaid Crate", run the command, /reload, and the crates are in
    ForeverVendorSnipeLog. It reads the AH's own search results
    (C_AuctionHouse.GetBrowseResults), so it needs no full scan and doesn't touch
    the scan cooldown. It never changes scan data or the window.
]]

local _, ns = ...

local L = ns.L

-- Every Waylaid Crate's name starts with this ("Waylaid Crate: Apprentice Textiles").
local CRATE_NAME_PREFIX = "Waylaid Crate:"
-- Tooltip lines can hold line breaks ("...list:\n- 40 Linen Cloth"); the log keeps one line per crate.
local LINE_BREAK_PATTERN = "[\r\n]+"
local TOOLTIP_SEPARATOR = " | "

--- Whether an item name is a Waylaid Crate's, by its CRATE_NAME_PREFIX.
---@param name string An item name
---@return boolean
local function isCrateName(name)
    return name:sub(1, #CRATE_NAME_PREFIX) == CRATE_NAME_PREFIX
end

--- Returns an item's whole tooltip as one line of text, for the log.
--- Reads the left text of every tooltip line (C_TooltipInfo.GetItemByID), turns the
--- line breaks inside a line into TOOLTIP_SEPARATOR, and joins the lines with it too.
--- The item must be cached, or the tooltip only says it's still loading.
---@param itemID number
---@return string text The tooltip text, "" if the game returned no tooltip
local function getTooltipText(itemID)
    local data = C_TooltipInfo.GetItemByID(itemID)
    if not (data and data.lines) then
        return ""
    end
    local parts = {}
    for _, line in ipairs(data.lines) do
        if line.leftText and line.leftText ~= "" then
            -- Parentheses keep only gsub's first return value (the text, not the count).
            parts[#parts + 1] = (line.leftText:gsub(LINE_BREAK_PATTERN, TOOLTIP_SEPARATOR))
        end
    end
    return table.concat(parts, TOOLTIP_SEPARATOR)
end

--- Writes one crate to the saved log: a summary line, then its tooltip on the next line.
--- Log only, not chat: one crate's tooltip is too long to read in chat.
---@param itemID number
---@param name string The crate's name
---@param minLevel number Required level, 0 if none
---@param result table The crate's BrowseResultInfo (totalQuantity, minPrice)
local function logCrate(itemID, name, minLevel, result)
    ns.Log(("Crate %d \"%s\": level %d, %d listed, cheapest %d copper"):format(
        itemID, name, minLevel, result.totalQuantity, result.minPrice))
    ns.Log("    Tooltip: " .. getTooltipText(itemID))
end

--- Tells the player in chat how the dump went, and writes a one-line summary to the log.
--- Separate messages for: no search results at all, items that weren't loaded yet (run
--- again), results cut short (more than one group of 500), and how many crates were logged.
---@param resultCount number Search results read
---@param found number Crates logged
---@param notLoaded number Results skipped because their item data wasn't cached yet
local function reportDump(resultCount, found, notLoaded)
    local full = C_AuctionHouse.HasFullBrowseResults()
    ns.Log(("Crate dump: %d search results, %d crates logged, %d not loaded, full results: %s."):format(
        resultCount, found, notLoaded, tostring(full)))

    if resultCount == 0 then
        ns.Print(L.CRATES_NO_SEARCH:format(ns.SLASH_COMMAND))
        return
    end
    if notLoaded > 0 then
        ns.Print(L.CRATES_NOT_LOADED:format(notLoaded, ns.SLASH_COMMAND))
    end
    if not full then
        ns.Print(L.CRATES_PARTIAL)
    end
    ns.Print(found > 0 and L.CRATES_LOGGED:format(found) or L.CRATES_NONE)
end

--- Handles /vsnipe crates: logs every Waylaid Crate in the AH's current search results.
--- Reads C_AuctionHouse.GetBrowseResults, looks each result's item up in the item cache,
--- and logs the ones named like a crate (logCrate). Results the AH is showing are
--- normally cached already. Any that aren't are counted, their data is requested
--- (C_Item.RequestLoadItemDataByID), and the player is asked to run the command again.
local function dumpCrates()
    if not ns.IsAuctionHouseOpen() then
        ns.Print(L.SCAN_NEED_AH)
        return
    end

    local results = C_AuctionHouse.GetBrowseResults() or {}
    local found, notLoaded = 0, 0
    for _, result in ipairs(results) do
        local itemID = result.itemKey.itemID
        local name, _, _, _, minLevel = C_Item.GetItemInfo(itemID)
        if not name then
            notLoaded = notLoaded + 1
            C_Item.RequestLoadItemDataByID(itemID)
        elseif isCrateName(name) then
            logCrate(itemID, name, minLevel, result)
            found = found + 1
        end
    end
    reportDump(#results, found, notLoaded)
end

ns.commands.crates = { description = L.CMD_CRATES, handler = dumpCrates }
