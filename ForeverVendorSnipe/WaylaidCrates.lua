--[[
    WaylaidCrates.lua
    Builds the "Waylaid Crates" results: for every crate in ns.CRATES (CrateData.lua),
    the cheapest crate on the AH and what each of its fill bundles costs.

    A bundle's cost is what buying its quantity from the cheapest listings would
    cost: 5 bars at 8s and 15 at 10s for a 20-bar bundle. Every fill item stacks, so
    the AH sells it by quantity and part of a listing can be bought. A bundle with
    too few units listed has no cost, only how many units it's short.

    Scanner.lua calls ns.AddCrateListing once per auction while reading, and
    ns.BuildCrateRows when the scan's results are saved. The window works out the
    cheapest bundle and the costs per Merchant's Favor with ns.GetCrateCosts. This
    file knows nothing about scans, saving or the window.
]]

local _, ns = ...

local compareUnitPrice = ns.CompareUnitPrice

-- Values per auction in listings[itemID]: count, buyout.
local LISTING_STRIDE = 2
-- Every crate stacks to 5, so the window shows it as a bulk item (light-blue name),
-- like other items bought by quantity.
local CRATE_IS_BULK = true

-- Item IDs whose auctions are kept during a scan: every crate and every fill item.
-- Built once from ns.CRATES at load; a crate and a fill item never share an ID.
local trackedItems = {}
-- ns.CRATES entries by crate item ID, for the turn-in rewards (ns.GetCrateCosts).
local cratesByID = {}
for _, crate in ipairs(ns.CRATES) do
    cratesByID[crate.itemID] = crate
    trackedItems[crate.itemID] = true
    for _, bundle in ipairs(crate.bundles) do
        trackedItems[bundle.itemID] = true
    end
end

--- Keeps one auction if it's for a crate or a fill item, and ignores everything else.
--- Auctions are stored flat, LISTING_STRIDE values each, so no table is built per
--- auction. Called for every auction with a buyout, before the item cache is checked:
--- only the item ID is needed, so these auctions are never held for item data.
---@param listings table Auctions being kept, listings[itemID] = { count, buyout, ... } (modified in place)
---@param itemID number
---@param count number Units in the auction (more than 0)
---@param buyout number Buyout for the whole auction, in copper (more than 0)
function ns.AddCrateListing(listings, itemID, count, buyout)
    if not trackedItems[itemID] then
        return
    end
    local kept = listings[itemID]
    if not kept then
        kept = {}
        listings[itemID] = kept
    end
    kept[#kept + 1] = count
    kept[#kept + 1] = buyout
end

--- table.sort comparator: whether listing a is cheaper per unit than listing b.
---@return boolean
local function isCheaper(a, b)
    return compareUnitPrice(a.buyout, a.count, b.buyout, b.count) < 0
end

--- Turns an item's flat auction list into { count, buyout } listings, cheapest per unit first.
--- Runs once per crate and bundle when results are saved, not per auction.
---@param flat table|nil The item's auctions from ns.AddCrateListing, nil if none were listed
---@return table listings Sorted, empty if none were listed
local function sortListings(flat)
    local listings = {}
    if flat then
        for i = 1, #flat, LISTING_STRIDE do
            listings[#listings + 1] = { count = flat[i], buyout = flat[i + 1] }
        end
        table.sort(listings, isCheaper)
    end
    return listings
end

--- Works out what buying `quantity` units from the cheapest listings costs.
--- Walks the listings cheapest first, taking whole listings and then part of the last
--- one at its unit price. The cost can have a fraction of a copper; the window rounds it.
---@param listings table From sortListings
---@param quantity number Units needed
---@return number|nil cost Copper, nil if fewer than `quantity` units are listed
---@return number short Units missing, 0 when there are enough
local function getFillCost(listings, quantity)
    local remaining, cost = quantity, 0
    for _, listing in ipairs(listings) do
        local take = math.min(listing.count, remaining)
        cost = cost + listing.buyout * take / listing.count
        remaining = remaining - take
        if remaining == 0 then
            return cost, 0
        end
    end
    return nil, remaining
end

--- Builds one crate's saved row: its cheapest listing and each bundle's cost.
---@param crate table An entry from ns.CRATES
---@param listings table All kept auctions, from ns.AddCrateListing
---@return table row See ns.BuildCrateRows
local function buildCrateRow(crate, listings)
    local cheapest = sortListings(listings[crate.itemID])[1]
    local bundles = {}
    for index, bundle in ipairs(crate.bundles) do
        local cost, short = getFillCost(sortListings(listings[bundle.itemID]), bundle.quantity)
        bundles[index] = {
            itemID = bundle.itemID,
            name = bundle.name,
            quantity = bundle.quantity,
            cost = cost,    -- copper for the whole bundle, nil if short
            short = short,  -- units missing on the AH, 0 if there are enough
        }
    end
    return {
        itemID = crate.itemID,
        name = crate.name,
        level = crate.level,
        quality = crate.quality,
        bulk = CRATE_IS_BULK,
        lowestBuyout = cheapest and cheapest.buyout, -- cheapest crate auction, both nil if
        lowestCount = cheapest and cheapest.count,   --   none are listed
        bundles = bundles,
    }
end

--- Builds a saved row for every crate in ns.CRATES, listed or not, in ns.CRATES order.
--- Called by Scanner.lua when it saves a scan's results.
---@param listings table All kept auctions, from ns.AddCrateListing
---@return table rows Array of { itemID, name, level, quality, bulk, lowestBuyout, lowestCount, bundles }
function ns.BuildCrateRows(listings)
    local rows = {}
    for index, crate in ipairs(ns.CRATES) do
        rows[index] = buildCrateRow(crate, listings)
    end
    return rows
end

--- Works out a crate row's crate price, cheapest bundle, and costs per Merchant's Favor.
--- Used by the window for its columns, tooltip and default sort, so they always agree.
--- The Favor and money come from ns.CRATES, not the saved row: they're fixed data, so a
--- corrected value shows without a new scan. Fill cost per Favor is the cheapest
--- bundle's cost / Favor. Total per Favor is (crate price + bundle cost - turn-in money)
--- / Favor, so the money only lowers the total. Values that can't be worked out (no
--- crate listed, no bundle with enough units, crate no longer in ns.CRATES) are nil.
---@param row table A saved crate row
---@return table costs { crateUnit, bestBundle, favor, money, fillPerFavor, totalPerFavor }, each possibly nil
function ns.GetCrateCosts(row)
    local crate = cratesByID[row.itemID]
    local favor, money = crate and crate.favor, crate and crate.money
    local crateUnit = row.lowestBuyout and row.lowestBuyout / row.lowestCount
    local bestBundle
    for _, bundle in ipairs(row.bundles) do
        if bundle.cost and (not bestBundle or bundle.cost < bestBundle.cost) then
            bestBundle = bundle
        end
    end

    local costs = { crateUnit = crateUnit, bestBundle = bestBundle, favor = favor, money = money }
    if favor and bestBundle then
        costs.fillPerFavor = bestBundle.cost / favor
        if crateUnit then
            costs.totalPerFavor = (crateUnit + bestBundle.cost - money) / favor
        end
    end
    return costs
end
