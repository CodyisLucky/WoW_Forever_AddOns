--[[
    Scanner.lua
    Reads full Auction House scans, groups the auctions into item variants, and
    feeds each auction to the result builders: BelowVendor.lua (lowest price
    below vendor), Undercuts.lua (cheapest vs second cheapest auction) and
    WaylaidCrates.lua (auctions of crates and their fill items).

    A variant is an item ID plus the name shown in the auction's item link, so
    "Axe of the Monkey" and "Axe of the Bear" are separate even though they share
    an item ID. Items that stack can't have a suffix, so their link isn't read.

    A full scan (C_AuctionHouse.ReplicateItems) can be started by any addon, and
    the server allows one every 15 minutes, shared by all of them. Gathercraft
    starts one when the Auction House opens, so this file mostly listens: whoever
    started the scan, the game fires REPLICATE_ITEM_LIST_UPDATE and this file reads
    the list. ns.StartScan is a fallback for when no other addon scans.

    Scan lifecycle (activeScan.state):
      reading  every auction is read in time-limited steps, one step per frame,
               while the Auction House is open (closing it loses the list)
      loading  reading is done and the results are saved, but some items weren't
               in the item cache yet. Their auctions wait until the item data
               arrives (or ITEM_LOAD_TIMEOUT passes), then join the results.
]]

local _, ns = ...

local L = ns.L

-- Hot-path locals: these are called once per auction, up to ~300,000 times per scan.
local C_AuctionHouse = C_AuctionHouse
local C_Item = C_Item
local debugprofilestop = debugprofilestop
local pcall = pcall
local addVendorListing = ns.AddVendorListing
local addUndercutListing = ns.AddUndercutListing
local addCrateListing = ns.AddCrateListing

local SCAN_COOLDOWN = 15 * 60 -- seconds the server waits between full scans
-- REPLICATE_ITEM_LIST_UPDATE fires 100+ times for a single scan. A new scan can't
-- come sooner than SCAN_COOLDOWN, so events this soon after the last scan seen
-- belong to that scan and are ignored.
local DUPLICATE_EVENT_WINDOW = 10 * 60
local READ_BUDGET_MS = 8 -- time spent reading per frame, so the game doesn't freeze
local SCAN_ANSWER_TIMEOUT = 30 -- seconds to wait for the server after ns.StartScan
local ITEM_LOAD_TIMEOUT = 60 -- seconds to wait for uncached items before giving up on them
-- Version of the saved results format. Saved results in any other format are discarded
-- by getRealmData. 1 (v0.1.0) summed every listing; 2 kept the lowest price per item ID;
-- 3 keys rows by variant (item ID + suffix) and adds the undercut list.
local RESULTS_FORMAT = 3
-- Captures the name between the brackets of an item link: "|h[Axe of the Monkey]|h".
local LINK_NAME_PATTERN = "|h%[(.-)%]|h"
-- Separates the item ID from the suffixed name in a variant key: "4567:Axe of the Monkey".
local VARIANT_KEY_SEPARATOR = ":"
-- Values per held auction in scan.held[itemID]: count, buyout, link (or false).
local HELD_STRIDE = 3

ns.SCAN_STATES = {
    IDLE = "idle",
    WAITING = "waiting", -- ns.StartScan asked the server, no answer yet
    READING = "reading",
    LOADING = "loading",
}
local STATES = ns.SCAN_STATES

-- Not part of the documented Mainline API on every client. Looked up once; if it's
-- missing, links aren't read and suffixed items are grouped by item ID only.
local getReplicateItemLink = C_AuctionHouse.GetReplicateItemLink

local ahOpen = false
-- The scan being read or loaded, or nil. Fields:
--   state         STATES.READING or STATES.LOADING
--   index, total  next auction to read (0-based) and how many there are
--   startedAt     time() when reading began, saved as the results' scan time
--   vendorRows    Below Vendor rows being built: vendorRows[variant.key] = row (BelowVendor.lua)
--   undercuts     undercut entries being built: undercuts[variant.key] = entry (Undercuts.lua)
--   crateListings auctions of crates and fill items: crateListings[itemID] = { count, buyout, ... } (WaylaidCrates.lua)
--   itemInfo      itemInfo[itemID] = { name, quality, vendorPrice, bulk } for items already looked up
--   variants      variants[itemID][name] = variant (see getVariant)
--   held          held[itemID] = { count, buyout, link, count, buyout, link, ... } for items not cached yet
--   heldCount     number of item IDs in held
--   readStartedMs, loadStartedMs  debugprofilestop() when reading / loading began, for the log
--   bidOnly, unreadable           auctions skipped for having no buyout / failing to read, for the log
--   emptyLinkNames                links with no name between the brackets, for the log
local activeScan
-- REPLICATE_ITEM_LIST_UPDATE events ignored since the Auction House opened. Logged on
-- close, to check the assumption that one scan sends many repeat events.
local ignoredEvents = 0
-- time() until which REPLICATE_ITEM_LIST_UPDATE is a repeat of the last scan seen. A copy
-- of lastScanSeenAt + DUPLICATE_EVENT_WINDOW, kept here so the ~96,000 repeat events per
-- scan (measured in game) are dropped without looking up the saved data each time.
local ignoreEventsUntil = 0

--- Returns this realm's saved scan data, creating it on first use.
--- Results are kept per realm because each realm has its own Auction House.
--- Results saved in an older format (resultsFormat ~= RESULTS_FORMAT) are discarded,
--- since the window can't read them; the scan timing is kept so the cooldown still works.
--- The crate rows (0.5.0) were added without a format change, so results saved by
--- 0.4.x keep their other lists and just get an empty crate list until the next scan.
---@return table realm { items, undercuts, crates, scannedAt, auctionCount, resultsFormat, lastScanSeenAt, lastRequestAt }
local function getRealmData()
    local realmName = GetRealmName()
    local realm = ns.db.realms[realmName]
    if not realm then
        realm = {
            lastScanSeenAt = 0,  -- time() this addon last saw a scan start, from any addon
            lastRequestAt = 0,   -- time() of this addon's last ns.StartScan
        }
        ns.db.realms[realmName] = realm
    end
    if realm.resultsFormat ~= RESULTS_FORMAT then
        realm.items = {}           -- Below Vendor rows, items[variant.key] = row (BelowVendor.lua)
        realm.undercuts = {}       -- Undercuts rows, largest gap first (Undercuts.lua)
        realm.scannedAt = 0        -- time() of the scan the results come from
        realm.auctionCount = 0     -- auctions in that scan
        realm.resultsFormat = RESULTS_FORMAT
    end
    if type(realm.crates) ~= "table" then
        realm.crates = {}          -- Waylaid Crates rows, in ns.CRATES order (WaylaidCrates.lua)
    end
    return realm
end

--- Counts the entries in a table keyed by something other than 1..n (# only counts those).
---@param t table
---@return number count
local function countKeys(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

--- Looks up an item's name, quality, vendor price and max stack size from the game's
--- item cache. Returns nils when the item isn't cached yet. Takes an item ID or an item
--- link; with a suffixed item's link, the name includes the suffix.
---@param item number|string Item ID or item link
---@return string|nil name
---@return number|nil quality Enum.ItemQuality value
---@return number|nil sellPrice Vendor price per unit in copper (0 = can't be sold)
---@return number|nil stackSize Most units that fit in one bag slot (1 = doesn't stack)
local function getItemDetails(item)
    local name, _, quality, _, _, _, _, stackSize, _, _, sellPrice = C_Item.GetItemInfo(item)
    return name, quality, sellPrice, stackSize
end

--- Whether an item is bought in bulk on the Auction House (by quantity, in one purchase)
--- rather than one listing at a time. The modern AH treats stackable items as bulk
--- (commodities). Blizzard's own check (C_AuctionHouse.GetItemCommodityStatus) needs an
--- item in the bags, so the max stack size is used instead.
---@param stackSize number|nil From getItemDetails
---@return boolean
local function isBulkItem(stackSize)
    return (stackSize or 1) > 1
end

--- Returns an item's cached details for this scan, looking them up the first time.
--- Name, quality, vendor price and bulk flag come from one C_Item.GetItemInfo call. The
--- name used to be looked up separately, later, and with 200,000+ auctions read in
--- between, the game could have dropped the item from its cache by then, leaving the
--- name empty. Only found items are cached, so an uncached item is looked up again
--- next time (callers hold its auctions in the meantime, see holdListing).
---@param scan table The active scan
---@param itemID number
---@return table|nil info { name, quality, vendorPrice, bulk }, nil if the item isn't cached yet
local function getItemInfo(scan, itemID)
    local info = scan.itemInfo[itemID]
    if not info then
        local name, quality, sellPrice, stackSize = getItemDetails(itemID)
        if sellPrice ~= nil then
            info = {
                name = name,
                quality = quality,
                vendorPrice = sellPrice,     -- copper per unit, 0 if it can't be sold
                bulk = isBulkItem(stackSize),
            }
            scan.itemInfo[itemID] = info
        end
    end
    return info
end

--- Reads the item link of one auction in the full scan list.
--- pcall-wrapped like readAuction, since single auctions can fail to read. Returns nil
--- when the API is missing on this client (see getReplicateItemLink) or the read fails.
---@param index number 0-based auction index
---@return string|nil link
local function readLink(index)
    if not getReplicateItemLink then
        return nil
    end
    local ok, link = pcall(getReplicateItemLink, index)
    return ok and link or nil
end

--- Returns the name shown in an item link, including any suffix ("Axe of the Monkey").
--- Reads it from between the link's brackets, which costs no API call. If the brackets
--- are empty (counted in scan.emptyLinkNames for the log), asks C_Item.GetItemInfo
--- for the link's name instead, which can still be nil.
---@param scan table The active scan
---@param link string An item link
---@return string|nil name
local function getLinkName(scan, link)
    local name = link:match(LINK_NAME_PATTERN)
    if name == nil or name == "" then
        scan.emptyLinkNames = scan.emptyLinkNames + 1
        name = C_Item.GetItemInfo(link)
    end
    return name
end

--- Returns the variant an auction belongs to: its item ID plus the name in its link.
--- Bulk items and auctions without a link use the item's plain name. A variant whose
--- name matches the plain name is keyed by the item ID; a suffixed one by
--- "itemID:name" and it keeps the link, so the window can show the suffix's stats.
--- Variants are cached per scan in a two-level table (item ID, then name), so the
--- common case costs two lookups and no string building.
---@param scan table The active scan
---@param itemID number
---@param info table The item's details from getItemInfo
---@param link string|nil The auction's item link, if it was read
---@return table variant { key, itemID, name, link, quality, bulk, vendorPrice }
local function getVariant(scan, itemID, info, link)
    local name = info.name
    if link and not info.bulk then
        name = getLinkName(scan, link) or info.name
    end

    local byName = scan.variants[itemID]
    if not byName then
        byName = {}
        scan.variants[itemID] = byName
    end
    local variant = byName[name]
    if not variant then
        local suffixed = name ~= info.name
        variant = {
            key = suffixed and (itemID .. VARIANT_KEY_SEPARATOR .. name) or itemID,
            itemID = itemID,
            name = name,
            link = suffixed and link or nil,
            quality = info.quality,
            bulk = info.bulk,
            vendorPrice = info.vendorPrice,
        }
        byName[name] = variant
    end
    return variant
end

--- Passes one auction of a cached item to both result builders (BelowVendor.lua and
--- Undercuts.lua), after working out its variant.
---@param scan table The active scan
---@param itemID number
---@param info table The item's details from getItemInfo
---@param count number Units in the auction
---@param buyout number Buyout for the whole auction, in copper
---@param link string|nil The auction's item link, if it was read
local function addAuction(scan, itemID, info, count, buyout, link)
    local variant = getVariant(scan, itemID, info, link)
    addVendorListing(scan.vendorRows, variant, count, buyout)
    addUndercutListing(scan.undercuts, variant, count, buyout)
end

--- Fills in a saved row's name, quality and bulk flag once its item data has loaded.
--- Suffixed rows look the name up by their link, so the suffix is kept.
--- The callback for fillMissingNames; tells the window to redraw.
---@param row table A saved result row (Below Vendor or Undercuts)
local function fillName(row)
    local _, quality, _, stackSize = getItemDetails(row.itemID)
    row.name = getItemDetails(row.link or row.itemID)
    row.quality = quality or row.quality
    row.bulk = isBulkItem(stackSize)
    ns.OnScanUpdated()
end

--- Safety net for rows saved without a name: requests each missing item's data and
--- fills the name in when it arrives (fillName). Logs how many were missing, which
--- should be 0 now that names are cached with the vendor price (see getItemInfo).
--- Works on both saved row sets, since they share itemID, link and name fields.
---@param rows table Saved rows (a map or an array)
local function fillMissingNames(rows)
    local missing = 0
    for _, row in pairs(rows) do
        if not row.name then
            missing = missing + 1
            Item:CreateFromItemID(row.itemID):ContinueOnItemLoad(function()
                ns.SafeCall(fillName, row)
            end)
        end
    end
    if missing > 0 then
        ns.Debug(("%d result rows had no item name; requested their item data."):format(missing))
    end
end

--- Saves the scan's results as this realm's current results.
--- The Below Vendor rows are saved as the live table, so held items that load later
--- show up straight away. The undercut list is a pick from all entries
--- (ns.PickTopUndercuts), so it's saved again when loading ends (finishLoading).
--- The crate rows are built from the kept crate and fill-item auctions
--- (ns.BuildCrateRows). Those never wait for item data, so rebuilding them when
--- loading ends gives the same rows.
---@param scan table The scan whose results to save
local function saveResults(scan)
    local realm = getRealmData()
    realm.items = scan.vendorRows
    realm.undercuts = ns.PickTopUndercuts(scan.undercuts)
    realm.crates = ns.BuildCrateRows(scan.crateListings)
    realm.scannedAt = scan.startedAt
    realm.auctionCount = scan.total
end

--- Marks the scan as finished: fills in any missing names and tells the window.
--- Called when reading ends with nothing held, or when loading ends.
---@param scan table The scan that just finished
local function endScan(scan)
    activeScan = nil
    fillMissingNames(scan.vendorRows)
    fillMissingNames(getRealmData().undercuts)
    ns.OnScanUpdated()
end

--- Ends the loading phase: the scan is done, and any items that never loaded are dropped.
--- Called when the last held item resolves, or by the ITEM_LOAD_TIMEOUT timer.
--- Saves the results again so the undercut pick includes the items that loaded, logs
--- how long loading took and how many items never arrived, then ends the scan.
---@param scan table The scan being finished
local function finishLoading(scan)
    saveResults(scan)
    ns.Debug(("Item data loading finished after %.1f s; %d items never loaded and were skipped."):format(
        (debugprofilestop() - scan.loadStartedMs) / 1000, scan.heldCount))
    endScan(scan)
end

--- Adds an item's held auctions to the results once its data has loaded, then forgets them.
--- Ignored if a newer scan has replaced this one. While loading, the window is told
--- to refresh, and the scan finishes when this was the last held item. During reading
--- the results aren't shown yet, so finishReading does that instead.
---@param scan table The scan that held the auctions
---@param itemID number
local function resolveHeldListings(scan, itemID)
    local held = scan.held[itemID]
    if activeScan ~= scan or not held then
        return
    end
    scan.held[itemID] = nil
    scan.heldCount = scan.heldCount - 1

    local info = getItemInfo(scan, itemID)
    if info then
        for i = 1, #held, HELD_STRIDE do
            -- A missing link is stored as false (nil would end the array); pass nil on.
            addAuction(scan, itemID, info, held[i], held[i + 1], held[i + 2] or nil)
        end
    end

    if scan.state == STATES.LOADING then
        ns.OnScanUpdated()
        if scan.heldCount == 0 then
            finishLoading(scan)
        end
    end
end

--- Keeps an auction for an item that isn't in the item cache yet, so it can be added later.
--- The first auction held for an item also asks the game to load it, using Blizzard's
--- Item mixin, which calls back when the data arrives. The auction is stored before
--- the request, in case the callback runs straight away. The callback runs through
--- ns.SafeCall so an error in it is logged.
---@param scan table The active scan
---@param itemID number
---@param count number
---@param buyout number
---@param link string|nil The auction's item link, kept so its suffix isn't lost
local function holdListing(scan, itemID, count, buyout, link)
    local held = scan.held[itemID]
    local isNew = not held
    if isNew then
        held = {}
        scan.held[itemID] = held
        scan.heldCount = scan.heldCount + 1
    end
    held[#held + 1] = count
    held[#held + 1] = buyout
    held[#held + 1] = link or false

    if isNew then
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
            ns.SafeCall(resolveHeldListings, scan, itemID)
        end)
    end
end

--- Sorts one auction: cached items go to the results, uncached items are held.
--- Every auction is first offered to the crate builder (ns.AddCrateListing), which
--- only needs the item ID, so crate and fill-item auctions count even when the item
--- isn't cached. The link is only read when the item might have a suffix: when it
--- isn't known to be a bulk (stacking) item. Items already being held skip the cache
--- lookup, so only one load is requested per item.
---@param scan table The active scan
---@param index number 0-based auction index, for reading the link
---@param itemID number
---@param count number
---@param buyout number
local function considerAuction(scan, index, itemID, count, buyout)
    addCrateListing(scan.crateListings, itemID, count, buyout)
    if scan.held[itemID] then
        holdListing(scan, itemID, count, buyout, readLink(index))
        return
    end
    local info = getItemInfo(scan, itemID)
    local link = not (info and info.bulk) and readLink(index) or nil
    if info then
        addAuction(scan, itemID, info, count, buyout, link)
    else
        holdListing(scan, itemID, count, buyout, link)
    end
end

--- Picks the fields this addon needs from GetReplicateItemInfo's return values.
--- Takes pcall's results directly so no table is built per auction.
---@param ok boolean Whether the call succeeded
---@return number|nil itemID
---@return number|nil count
---@return number|nil buyout Buyout for the whole auction (0 if bid only)
local function pickAuctionFields(ok, ...)
    if not ok then
        return nil
    end
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = ...
    return itemID, count, buyout
end

--- Reads one auction from the full scan list.
--- Wrapped in pcall because the call can fail for single auctions. Gathercraft
--- counts these failures, and a failed auction is simply skipped here.
---@param index number 0-based auction index
local function readAuction(index)
    return pickAuctionFields(pcall(C_AuctionHouse.GetReplicateItemInfo, index))
end

--- Saves the results once every auction is read, then waits for held items if there are any.
--- Replaces this realm's saved results with the new scan (saveResults) and logs a summary
--- (time taken, skipped auctions, variants and items found). The scan stays active in the
--- loading state while items are held, and the window is told to refresh either way.
---@param scan table The scan that just finished reading
local function finishReading(scan)
    saveResults(scan)
    ns.Debug(("Read %d auctions in %.1f s: %d bid-only skipped, %d unreadable, %d variants, %d below vendor, %d items waiting for item data, %d links without a name."):format(
        scan.total, (debugprofilestop() - scan.readStartedMs) / 1000, scan.bidOnly, scan.unreadable,
        countKeys(scan.undercuts), countKeys(scan.vendorRows), scan.heldCount, scan.emptyLinkNames))

    if scan.heldCount > 0 then
        scan.state = STATES.LOADING
        scan.loadStartedMs = debugprofilestop()
        C_Timer.After(ITEM_LOAD_TIMEOUT, function()
            if activeScan == scan then
                ns.SafeCall(finishLoading, scan)
            end
        end)
        ns.OnScanUpdated()
    else
        endScan(scan)
    end
end

--- Reads as many auctions as fit in READ_BUDGET_MS, then continues next frame.
--- Stops quietly if the scan was cancelled (Auction House closed) or replaced.
--- Auctions that can't be read or have no buyout (bid only) are skipped and counted for
--- the log. The next step runs through ns.SafeCall so an error in it is logged.
---@param scan table The scan being read
local function readStep(scan)
    if activeScan ~= scan or scan.state ~= STATES.READING then
        return
    end
    local stepStart = debugprofilestop()
    local index, total = scan.index, scan.total
    while index < total and debugprofilestop() - stepStart < READ_BUDGET_MS do
        local itemID, count, buyout = readAuction(index)
        if not itemID then
            scan.unreadable = scan.unreadable + 1
        elseif not (buyout and buyout > 0) then
            scan.bidOnly = scan.bidOnly + 1
        elseif count and count > 0 then
            considerAuction(scan, index, itemID, count, buyout)
        end
        index = index + 1
    end
    scan.index = index

    if index >= total then
        finishReading(scan)
    else
        C_Timer.After(0, function()
            ns.SafeCall(readStep, scan)
        end)
    end
end

--- Starts reading a full scan list that the server has just sent.
--- Replaces any scan still in the loading state; its pending callbacks are then ignored.
--- Logs once per scan if the item-link API is missing (suffixes can't be told apart).
---@param total number Auctions in the list, from GetNumReplicateItems
local function startReading(total)
    local scan = {
        state = STATES.READING,
        index = 0,
        total = total,
        startedAt = time(),
        vendorRows = {},
        undercuts = {},
        crateListings = {},
        itemInfo = {},
        variants = {},
        held = {},
        heldCount = 0,
        readStartedMs = debugprofilestop(),
        bidOnly = 0,
        unreadable = 0,
        emptyLinkNames = 0,
    }
    activeScan = scan
    ns.Debug(("Reading full scan: %d auctions."):format(total))
    if not getReplicateItemLink then
        ns.Debug("C_AuctionHouse.GetReplicateItemLink is missing; suffixed items are grouped by item ID.")
    end
    ns.OnScanUpdated()
    readStep(scan)
end

--- Starts reading when the game sends a full scan, from this addon or any other.
--- Ignored while the Auction House is closed (the list can't be read), while a scan
--- is being read, and for the repeat events of a scan already seen (see
--- DUPLICATE_EVENT_WINDOW). Ignored events are counted for the log (ignoredEvents).
--- Repeats are dropped by comparing time() with ignoreEventsUntil, before any saved
--- data is touched. Only an event past that point reads the saved lastScanSeenAt, which
--- also covers the first event after a /reload, when ignoreEventsUntil starts at 0.
--- An empty list is ignored without marking the scan as seen, so a later event with
--- the real list still gets through.
local function onReplicateListUpdate()
    if not ahOpen then
        return
    end
    local now = time()
    if now < ignoreEventsUntil or (activeScan and activeScan.state == STATES.READING) then
        ignoredEvents = ignoredEvents + 1
        return
    end
    local realm = getRealmData()
    ignoreEventsUntil = realm.lastScanSeenAt + DUPLICATE_EVENT_WINDOW
    if now < ignoreEventsUntil then
        ignoredEvents = ignoredEvents + 1
        return
    end

    local total = C_AuctionHouse.GetNumReplicateItems() or 0
    if total == 0 then
        ns.Debug("Full scan event with no auctions, ignored.")
        return
    end
    realm.lastScanSeenAt = now
    ignoreEventsUntil = now + DUPLICATE_EVENT_WINDOW
    startReading(total)
end

--- Remembers that the Auction House is open, so scans can be read and started, and logs it.
--- Registered before ResultsWindow.lua's handler, so the window sees ahOpen = true.
local function onAuctionHouseShow()
    ahOpen = true
    ignoredEvents = 0
    ns.Debug("Auction House opened.")
end

--- Remembers that the Auction House closed, and cancels a scan that is still being read.
--- The rest of the scan list is gone once the Auction House closes, so a half-read scan
--- is dropped and the previous results stay. A scan in the loading state doesn't need
--- the Auction House any more and carries on. Logs the close with the number of
--- full-scan events ignored during this visit.
local function onAuctionHouseClosed()
    ahOpen = false
    ns.Debug(("Auction House closed; %d full-scan events ignored as repeats or while reading."):format(ignoredEvents))
    if activeScan and activeScan.state == STATES.READING then
        activeScan = nil
        ns.Print(L.SCAN_CANCELLED)
        ns.OnScanUpdated()
    end
end

--- Whether the server is still expected to answer this addon's last scan request.
---@param realm table This realm's data from getRealmData
---@return boolean
local function isAwaitingAnswer(realm)
    return realm.lastRequestAt > realm.lastScanSeenAt
        and time() - realm.lastRequestAt < SCAN_ANSWER_TIMEOUT
end

--- Returns the saved Below Vendor rows for this realm.
---@return table rows rows[variant.key] = { itemID, name, link, quality, bulk, vendorPrice, lowestBuyout, lowestCount, quantity }
function ns.GetVendorRows()
    return getRealmData().items
end

--- Returns the saved Undercuts rows for this realm.
---@return table rows Array, largest gap first: { itemID, name, link, quality, bulk, lowestBuyout, lowestCount, secondBuyout, secondCount }
function ns.GetUndercutRows()
    return getRealmData().undercuts
end

--- Returns the saved Waylaid Crates rows for this realm.
---@return table rows Array in ns.CRATES order: { itemID, name, level, quality, bulk, lowestBuyout, lowestCount, bundles }
function ns.GetCrateRows()
    return getRealmData().crates
end

--- Returns when the saved results were scanned and how many auctions the scan had.
---@return number scannedAt time() of the scan, 0 if there has been none
---@return number auctionCount Auctions in that scan
function ns.GetScanInfo()
    local realm = getRealmData()
    return realm.scannedAt, realm.auctionCount
end

--- Returns what the scanner is doing right now, for the window's status line.
---@return string state One of ns.SCAN_STATES
---@return number progress Fraction read (0-1) while reading, otherwise 0
---@return number loadingCount Items still loading while in the loading state, otherwise 0
function ns.GetScanStatus()
    if activeScan then
        if activeScan.state == STATES.READING then
            return STATES.READING, activeScan.index / activeScan.total, 0
        end
        return STATES.LOADING, 0, activeScan.heldCount
    end
    if ahOpen and isAwaitingAnswer(getRealmData()) then
        return STATES.WAITING, 0, 0
    end
    return STATES.IDLE, 0, 0
end

--- Seconds until this addon expects the server to allow another full scan.
--- Counts from the later of the last scan seen (any addon) and this addon's last request.
--- Scans this addon never saw (e.g. started while it was disabled) aren't counted,
--- and neither is Gathercraft's own request time, so the server may still refuse.
---@return number seconds 0 when a scan should be allowed
function ns.GetScanCooldown()
    local realm = getRealmData()
    local last = math.max(realm.lastScanSeenAt, realm.lastRequestAt)
    return math.max(0, SCAN_COOLDOWN - (time() - last))
end

---@return boolean open Whether the Auction House window is open
function ns.IsAuctionHouseOpen()
    return ahOpen
end

--- Tells the player if the server never answered a scan request. Runs SCAN_ANSWER_TIMEOUT
--- after ns.StartScan; does nothing if a scan has been seen since the request.
---@param realm table This realm's data from getRealmData
---@param requestedAt number time() of the request
local function reportIfUnanswered(realm, requestedAt)
    if realm.lastScanSeenAt < requestedAt then
        ns.Print(L.SCAN_NO_ANSWER)
        ns.OnScanUpdated()
    end
end

--- Asks the server for a full scan, the fallback for when no other addon scans.
--- Checks that the Auction House is open, no scan is busy and the cooldown has passed,
--- telling the player in chat if not. The answer arrives as REPLICATE_ITEM_LIST_UPDATE,
--- read like any other scan. If nothing arrives within SCAN_ANSWER_TIMEOUT,
--- reportIfUnanswered says so in chat.
--- Saves lastRequestAt so the cooldown survives /reload.
function ns.StartScan()
    local state = ns.GetScanStatus()
    local left = ns.GetScanCooldown()
    if not ahOpen then
        ns.Print(L.SCAN_NEED_AH)
        return
    elseif state == STATES.READING or state == STATES.WAITING then
        ns.Print(L.SCAN_BUSY)
        return
    elseif left > 0 then
        ns.Print(L.SCAN_COOLDOWN:format(ns.FormatCountdown(left)))
        return
    end

    local ok, err = pcall(C_AuctionHouse.ReplicateItems)
    if not ok then
        ns.Print(L.SCAN_FAILED:format(tostring(err)))
        return
    end
    local realm = getRealmData()
    local requestedAt = time()
    realm.lastRequestAt = requestedAt
    ns.Print(L.SCAN_STARTED)
    ns.OnScanUpdated()

    C_Timer.After(SCAN_ANSWER_TIMEOUT, function()
        ns.SafeCall(reportIfUnanswered, realm, requestedAt)
    end)
end

ns.commands.scan = { description = L.CMD_SCAN, handler = ns.StartScan }

ns.RegisterEvent("AUCTION_HOUSE_SHOW", onAuctionHouseShow)
ns.RegisterEvent("AUCTION_HOUSE_CLOSED", onAuctionHouseClosed)
ns.RegisterEvent("REPLICATE_ITEM_LIST_UPDATE", onReplicateListUpdate)
