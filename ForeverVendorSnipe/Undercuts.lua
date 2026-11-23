--[[
    Undercuts.lua
    Builds the "Undercuts" results: for each item variant, the cheapest and the
    second cheapest auction by unit price, then keeps the MAX_SAVED_UNDERCUTS
    variants where the gap between the two is largest. Each variant also counts
    every unit listed across all its auctions (totalQuantity).

    "Second cheapest" means the second auction, not the next higher price: three
    axes at 60s and one at 1g10s have a gap of 0, because the second auction is
    also 60s. Only a single cheap auction on its own counts as an undercut.

    Scanner.lua calls ns.AddUndercutListing once per auction while reading, and
    ns.PickTopUndercuts when the scan's results are saved. This file knows nothing
    about scans, saving or the window.
]]

local _, ns = ...

-- Hot path: called once per auction, up to ~300,000 times per scan.
local compareUnitPrice = ns.CompareUnitPrice

local MAX_SAVED_UNDERCUTS = 200 -- variants kept after a scan, largest gap first

--- Adds one auction to its variant's cheapest-two record and its total units listed.
--- The first auction of a variant creates its entry. After that, every auction adds
--- its units to totalQuantity, and an auction cheaper
--- per unit than the lowest becomes the lowest and pushes the old lowest down to
--- second. Otherwise it becomes the second if there is none yet or it's cheaper than
--- the current second. An auction priced the same as the lowest goes to second, which
--- gives a gap of 0 ("second auction" rule, see the file header).
---@param entries table Entries being built, entries[variant.key] = entry (modified in place)
---@param variant table From Scanner.lua's getVariant: key, itemID, name, link, quality, bulk
---@param count number Units in the auction (more than 0)
---@param buyout number Buyout for the whole auction, in copper (more than 0)
function ns.AddUndercutListing(entries, variant, count, buyout)
    local entry = entries[variant.key]
    if not entry then
        entries[variant.key] = {
            itemID = variant.itemID,
            name = variant.name,
            link = variant.link,    -- only for suffixed variants ("of the Monkey")
            quality = variant.quality,
            bulk = variant.bulk,
            lowestBuyout = buyout,  -- cheapest auction per unit: lowestBuyout / lowestCount
            lowestCount = count,
            totalQuantity = count,  -- units listed across every auction of this variant
            -- secondBuyout, secondCount: second cheapest auction, set once there is one
        }
        return
    end

    entry.totalQuantity = entry.totalQuantity + count
    if compareUnitPrice(buyout, count, entry.lowestBuyout, entry.lowestCount) < 0 then
        entry.secondBuyout, entry.secondCount = entry.lowestBuyout, entry.lowestCount
        entry.lowestBuyout, entry.lowestCount = buyout, count
    elseif not entry.secondBuyout
        or compareUnitPrice(buyout, count, entry.secondBuyout, entry.secondCount) < 0 then
        entry.secondBuyout, entry.secondCount = buyout, count
    end
end

--- Works out an undercut entry's per-unit prices and the gap between them.
--- Used to rank entries here (ns.PickTopUndercuts) and to fill the window's columns
--- (ResultsWindow.lua), so both always agree. Unit prices can have fractions of a
--- copper; the window rounds them for display.
---@param entry table An undercut entry or saved row
---@return number unitLowest Cheapest auction's price per unit, in copper
---@return number|nil unitSecond Second cheapest auction's price per unit, nil if there is only one auction
---@return number|nil difference unitSecond - unitLowest, nil if there is only one auction
function ns.GetUndercutPrices(entry)
    local unitLowest = entry.lowestBuyout / entry.lowestCount
    if not entry.secondBuyout then
        return unitLowest, nil, nil
    end
    local unitSecond = entry.secondBuyout / entry.secondCount
    return unitLowest, unitSecond, unitSecond - unitLowest
end

--- Inserts an entry into a list kept sorted by gap, largest first, capped at
--- MAX_SAVED_UNDERCUTS. Shifts smaller gaps down one place until the right spot is
--- found, then drops whatever falls off the end.
---@param ranked table Entries, largest gap first (modified in place)
---@param gaps table gaps[i] is ranked[i]'s gap (modified in place)
---@param entry table The entry to insert
---@param gap number Its gap per unit, in copper
local function insertRanked(ranked, gaps, entry, gap)
    local position = #ranked + 1
    while position > 1 and gaps[position - 1] < gap do
        ranked[position], gaps[position] = ranked[position - 1], gaps[position - 1]
        position = position - 1
    end
    ranked[position], gaps[position] = entry, gap
    ranked[MAX_SAVED_UNDERCUTS + 1], gaps[MAX_SAVED_UNDERCUTS + 1] = nil, nil
end

--- Picks the MAX_SAVED_UNDERCUTS entries with the largest gap per unit.
--- Skips entries with only one auction or a gap of 0. One pass over all entries: an
--- entry is only inserted when the list isn't full yet or its gap beats the smallest
--- one kept, so most entries cost a single comparison. Ties keep whichever came first.
--- Called by Scanner.lua when it saves a scan's results.
---@param entries table All entries from the scan, entries[key] = entry
---@return table rows The picked entries as an array, largest gap first (these are saved)
function ns.PickTopUndercuts(entries)
    local ranked, gaps = {}, {}
    for _, entry in pairs(entries) do
        local _, _, gap = ns.GetUndercutPrices(entry)
        if gap and gap > 0 and (#ranked < MAX_SAVED_UNDERCUTS or gap > gaps[#ranked]) then
            insertRanked(ranked, gaps, entry, gap)
        end
    end
    return ranked
end
