--[[
    Scanner.lua
    Reads full Auction House scans and keeps, per item, the lowest unit price
    below what a vendor pays and how many units are listed at that price.

    A full scan (C_AuctionHouse.ReplicateItems) can be started by any addon, and
    the server allows one every 15 minutes, shared by all of them. Gathercraft
    starts one when the Auction House opens, so this file mostly listens: whoever
    started the scan, the game fires REPLICATE_ITEM_LIST_UPDATE and this file reads
    the list. ns.StartScan is a fallback for when no other addon scans.

    Scan lifecycle (activeScan.state):
      reading  every auction is read in time-limited steps, one step per frame,
               while the Auction House is open (closing it loses the list)
      loading  reading is done and the results are saved, but some items weren't
               in the item cache yet. Their listings wait until the item data
               arrives (or ITEM_LOAD_TIMEOUT passes), then join the results.
]]

local _, ns = ...

local L = ns.L

-- Hot-path locals: these are called once per auction, up to ~300,000 times per scan.
local C_AuctionHouse = C_AuctionHouse
local C_Item = C_Item
local debugprofilestop = debugprofilestop
local pcall = pcall

local SCAN_COOLDOWN = 15 * 60 -- seconds the server waits between full scans
-- REPLICATE_ITEM_LIST_UPDATE fires 100+ times for a single scan. A new scan can't
-- come sooner than SCAN_COOLDOWN, so events this soon after the last scan seen
-- belong to that scan and are ignored.
local DUPLICATE_EVENT_WINDOW = 10 * 60
local READ_BUDGET_MS = 8 -- time spent reading per frame, so the game doesn't freeze
local SCAN_ANSWER_TIMEOUT = 30 -- seconds to wait for the server after ns.StartScan
local ITEM_LOAD_TIMEOUT = 60 -- seconds to wait for uncached items before giving up on them
-- Version of the saved row format (see addListing). Saved results in any other format
-- are discarded by getRealmData. 1 (v0.1.0) summed every listing; 2 keeps the lowest price.
local RESULTS_FORMAT = 2

ns.SCAN_STATES = {
    IDLE = "idle",
    WAITING = "waiting", -- ns.StartScan asked the server, no answer yet
    READING = "reading",
    LOADING = "loading",
}
local STATES = ns.SCAN_STATES

local ahOpen = false
-- The scan being read or loaded, or nil. Fields:
--   state         STATES.READING or STATES.LOADING
--   index, total  next auction to read (0-based) and how many there are
--   startedAt     time() when reading began, saved as the results' scan time
--   items         results being built: items[itemID] = row (see addListing)
--   vendorPrices  vendorPrices[itemID] = vendor price per unit, for items already looked up
--   names, qualities, stackSizes  the item's name, quality and max stack size, cached in
--                                 the same lookup as its price
--   held          held[itemID] = { count, buyout, count, buyout, ... } for items not cached yet
--   heldCount     number of item IDs in held
--   readStartedMs, loadStartedMs  debugprofilestop() when reading / loading began, for the log
--   bidOnly, unreadable           auctions skipped for having no buyout / failing to read, for the log
local activeScan
-- REPLICATE_ITEM_LIST_UPDATE events ignored since the Auction House opened. Logged on
-- close, to check the assumption that one scan sends many repeat events.
local ignoredEvents = 0

--- Returns this realm's saved scan data, creating it on first use.
--- Results are kept per realm because each realm has its own Auction House.
--- Results saved in an older row format (resultsFormat ~= RESULTS_FORMAT) are discarded,
--- since the window can't read them; the scan timing is kept so the cooldown still works.
---@return table realm { items, scannedAt, auctionCount, resultsFormat, lastScanSeenAt, lastRequestAt }
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
        realm.items = {}           -- items[itemID] = row, see addListing
        realm.scannedAt = 0        -- time() of the scan the results come from
        realm.auctionCount = 0     -- auctions in that scan
        realm.resultsFormat = RESULTS_FORMAT
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
--- item cache. Returns nils when the item isn't cached yet.
---@param itemID number
---@return string|nil name
---@return number|nil quality Enum.ItemQuality value
---@return number|nil sellPrice Vendor price per unit in copper (0 = can't be sold)
---@return number|nil stackSize Most units that fit in one bag slot (1 = doesn't stack)
local function getItemDetails(itemID)
    local name, _, quality, _, _, _, _, stackSize, _, _, sellPrice = C_Item.GetItemInfo(itemID)
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

--- Returns an item's vendor price per unit, using the scan's cache when possible.
--- The name, quality and stack size are cached from the same lookup. The name used to be
--- looked up again
--- when the item's first row was made, and with 200,000+ auctions read in between, the
--- game could have dropped the item from its cache by then, leaving the name empty.
--- Only known prices are cached, so an uncached item is looked up again next time.
---@param scan table The active scan
---@param itemID number
---@return number|nil price Copper per unit, 0 if it can't be sold, nil if not cached yet
local function getVendorPrice(scan, itemID)
    local price = scan.vendorPrices[itemID]
    if price == nil then
        local name, quality, stackSize
        name, quality, price, stackSize = getItemDetails(itemID)
        if price ~= nil then
            scan.vendorPrices[itemID] = price
            scan.names[itemID] = name
            scan.qualities[itemID] = quality
            scan.stackSizes[itemID] = stackSize
        end
    end
    return price
end

--- Adds one auction to its item's row if its buyout is below the vendor value.
--- Each item keeps only its lowest unit price and the units listed at exactly that price:
--- a cheaper auction replaces the price and quantity, one at the same price adds its
--- units, and a dearer one is ignored. The price is kept as one auction's (buyout, count)
--- pair, and unit prices are compared by cross-multiplying, so stacks priced in
--- fractions of a copper per unit (e.g. 7 for 1s) compare exactly.
---@param scan table The active scan
---@param itemID number
---@param count number Units in the auction
---@param buyout number Buyout for the whole auction, in copper
---@param unitVendorPrice number Vendor price per unit, in copper (more than 0)
local function addListing(scan, itemID, count, buyout, unitVendorPrice)
    if unitVendorPrice * count <= buyout then
        return
    end

    local row = scan.items[itemID]
    if not row then
        scan.items[itemID] = {
            name = scan.names[itemID],
            quality = scan.qualities[itemID],
            bulk = isBulkItem(scan.stackSizes[itemID]), -- bought by quantity, not per listing
            vendorPrice = unitVendorPrice,  -- copper per unit
            lowestBuyout = buyout,          -- an auction at the lowest unit price:
            lowestCount = count,            --   unit price = lowestBuyout / lowestCount
            quantity = count,               -- units listed at that unit price
        }
        return
    end

    -- Sign of (buyout / count) - (lowestBuyout / lowestCount), without dividing.
    local difference = buyout * row.lowestCount - row.lowestBuyout * count
    if difference < 0 then
        row.lowestBuyout, row.lowestCount, row.quantity = buyout, count, count
    elseif difference == 0 then
        row.quantity = row.quantity + count
    end
end

--- Fills in a row's name, quality and bulk flag once its item data has loaded.
--- The callback for fillMissingNames; tells the window to redraw.
---@param row table A saved result row
---@param itemID number
local function fillName(row, itemID)
    local name, quality, _, stackSize = getItemDetails(itemID)
    row.name, row.quality = name, quality or row.quality
    row.bulk = isBulkItem(stackSize)
    ns.OnScanUpdated()
end

--- Safety net for rows saved without a name: requests each missing item's data and
--- fills the name in when it arrives (fillName). Logs how many were missing, which
--- should be 0 now that names are cached with the vendor price (see getVendorPrice).
---@param items table A realm's saved rows, items[itemID] = row
local function fillMissingNames(items)
    local missing = 0
    for itemID, row in pairs(items) do
        if not row.name then
            missing = missing + 1
            Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
                ns.SafeCall(fillName, row, itemID)
            end)
        end
    end
    if missing > 0 then
        ns.Debug(("%d result rows had no item name; requested their item data."):format(missing))
    end
end

--- Marks the scan as finished: fills in any missing names and tells the window.
--- Called when reading ends with nothing held, or when loading ends.
---@param scan table The scan that just finished
local function endScan(scan)
    activeScan = nil
    fillMissingNames(scan.items)
    ns.OnScanUpdated()
end

--- Ends the loading phase: the scan is done, and any items that never loaded are dropped.
--- Called when the last held item resolves, or by the ITEM_LOAD_TIMEOUT timer.
--- Logs how long loading took and how many items never arrived, then ends the scan.
---@param scan table The scan being finished
local function finishLoading(scan)
    ns.Debug(("Item data loading finished after %.1f s; %d items never loaded and were skipped."):format(
        (debugprofilestop() - scan.loadStartedMs) / 1000, scan.heldCount))
    endScan(scan)
end

--- Checks an item's held listings once its data has loaded, then forgets them.
--- Ignored if a newer scan has replaced this one. While loading, the window is told
--- to refresh, and the scan finishes when this was the last held item. During reading
--- the results aren't shown yet, so finishReading does that instead.
---@param scan table The scan that held the listings
---@param itemID number
local function resolveHeldListings(scan, itemID)
    local held = scan.held[itemID]
    if activeScan ~= scan or not held then
        return
    end
    scan.held[itemID] = nil
    scan.heldCount = scan.heldCount - 1

    local unitPrice = getVendorPrice(scan, itemID)
    if unitPrice and unitPrice > 0 then
        for i = 1, #held, 2 do
            addListing(scan, itemID, held[i], held[i + 1], unitPrice)
        end
    end

    if scan.state == STATES.LOADING then
        ns.OnScanUpdated()
        if scan.heldCount == 0 then
            finishLoading(scan)
        end
    end
end

--- Keeps an auction for an item that isn't in the item cache yet, so it can be checked later.
--- The first auction held for an item also asks the game to load it, using Blizzard's
--- Item mixin, which calls back when the data arrives. The auction is stored before
--- the request, in case the callback runs straight away. The callback runs through
--- ns.SafeCall so an error in it is logged.
---@param scan table The active scan
---@param itemID number
---@param count number
---@param buyout number
local function holdListing(scan, itemID, count, buyout)
    local held = scan.held[itemID]
    local isNew = not held
    if isNew then
        held = {}
        scan.held[itemID] = held
        scan.heldCount = scan.heldCount + 1
    end
    held[#held + 1] = count
    held[#held + 1] = buyout

    if isNew then
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
            ns.SafeCall(resolveHeldListings, scan, itemID)
        end)
    end
end

--- Sorts one auction: below-vendor listings join the results, uncached items are held.
--- Items already being held skip the lookup, so only one load is requested per item.
---@param scan table The active scan
---@param itemID number
---@param count number
---@param buyout number
local function considerAuction(scan, itemID, count, buyout)
    if scan.held[itemID] then
        holdListing(scan, itemID, count, buyout)
        return
    end
    local unitPrice = getVendorPrice(scan, itemID)
    if unitPrice == nil then
        holdListing(scan, itemID, count, buyout)
    elseif unitPrice > 0 then
        addListing(scan, itemID, count, buyout, unitPrice)
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
--- Replaces this realm's saved results with the new scan and logs a summary (time taken,
--- skipped auctions, items found). The scan stays active in the loading state while
--- items are held, and the window is told to refresh either way.
---@param scan table The scan that just finished reading
local function finishReading(scan)
    local realm = getRealmData()
    realm.items = scan.items
    realm.scannedAt = scan.startedAt
    realm.auctionCount = scan.total
    ns.Debug(("Read %d auctions in %.1f s: %d bid-only skipped, %d unreadable, %d items below vendor so far, %d items waiting for item data."):format(
        scan.total, (debugprofilestop() - scan.readStartedMs) / 1000, scan.bidOnly, scan.unreadable,
        countKeys(scan.items), scan.heldCount))

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
            considerAuction(scan, itemID, count, buyout)
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
---@param total number Auctions in the list, from GetNumReplicateItems
local function startReading(total)
    local scan = {
        state = STATES.READING,
        index = 0,
        total = total,
        startedAt = time(),
        items = {},
        vendorPrices = {},
        names = {},
        qualities = {},
        stackSizes = {},
        held = {},
        heldCount = 0,
        readStartedMs = debugprofilestop(),
        bidOnly = 0,
        unreadable = 0,
    }
    activeScan = scan
    ns.Debug(("Reading full scan: %d auctions."):format(total))
    ns.OnScanUpdated()
    readStep(scan)
end

--- Starts reading when the game sends a full scan, from this addon or any other.
--- Ignored while the Auction House is closed (the list can't be read), while a scan
--- is being read, and for the repeat events of a scan already seen (see
--- DUPLICATE_EVENT_WINDOW). Ignored events are counted for the log (ignoredEvents).
--- An empty list is ignored without marking the scan as seen, so a later event with
--- the real list still gets through.
local function onReplicateListUpdate()
    if not ahOpen then
        return
    end
    local realm = getRealmData()
    local now = time()
    if (activeScan and activeScan.state == STATES.READING) or now - realm.lastScanSeenAt < DUPLICATE_EVENT_WINDOW then
        ignoredEvents = ignoredEvents + 1
        return
    end

    local total = C_AuctionHouse.GetNumReplicateItems() or 0
    if total == 0 then
        ns.Debug("Full scan event with no auctions, ignored.")
        return
    end
    realm.lastScanSeenAt = now
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

--- Returns the current saved results for this realm.
---@return table items items[itemID] = { name, quality, bulk, vendorPrice, lowestBuyout, lowestCount, quantity }
---@return number scannedAt time() of the scan, 0 if there has been none
---@return number auctionCount Auctions in that scan
function ns.GetResults()
    local realm = getRealmData()
    return realm.items, realm.scannedAt, realm.auctionCount
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
