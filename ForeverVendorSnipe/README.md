# Forever Vendor Snipe

Target: World of Warcraft: Forever (interface 16001). Not compatible with Retail, Classic, or Midnight.

Three lists from each full Auction House scan:

- **Below Vendor:** items whose buyout is below what a vendor pays for them, ranked by the profit you'd make buying them and selling them to a vendor.
- **Undercuts:** the 200 items whose cheapest auction is furthest below the second cheapest, per unit. For example, an axe listed at 60s3c with the next axe at 1g10s3c is a 50s gap.
- **Waylaid Crates:** every Waylaid Crate with its required level, the Merchant's Favor it gives when turned in, the cheapest crate on the AH, the cheapest bundle to fill it, and what filling it and buying and filling it cost per Favor.

**Current status (0.5.0):** reads full Auction House scans (from Gathercraft, any other addon, or its own Scan button) and shows the three lists on three tabs of a movable window. List only: it doesn't buy anything.

## How it works

1. Open the Auction House. The results window opens with it, showing the last saved scan.
2. Gathercraft starts a full scan when the Auction House opens. This addon reads that same scan, so it never uses up the shared cooldown itself.
3. Auctions are grouped by item **and suffix**: "Axe of the Monkey" and "Axe of the Bear" are separate rows, even though they're the same item underneath.
4. **Below Vendor:** every auction with a buyout is compared with the item's vendor price. When `vendor price × stack size` is more than the buyout, the auction counts. Each item gets one row with its lowest below-vendor price per unit, and how many units are listed at exactly that price.
5. **Undercuts:** for each item, the cheapest and the second cheapest auction (by price per unit) are kept. The 200 items with the biggest gap between the two are saved. The second cheapest is the second *auction*, not the next higher price: if three axes are listed at 60s, the second cheapest is 60s and the gap is 0. Only a single cheap auction on its own counts.
6. **Waylaid Crates:** every auction of a Waylaid Crate or of an item that fills one is kept. A crate is filled with any one of the bundles in its tooltip (Apprentice Textiles: 40 Linen Cloth or 20 Light Leather). Each bundle's cost is what buying that many units from the cheapest listings costs, e.g. 5 bars at 8s plus 15 at 10s. The cheapest bundle is the crate's fill cost. Filled crates are turned in for Merchant's Favor and a little money, so the costs are shown per Favor: fill cost ÷ Favor, and (crate price + fill cost − turn-in money) ÷ Favor. The crate list and rewards are built into the addon (see `/vsnipe crates` and `CrateData.lua`).

The server allows **one full scan every 15 minutes, shared by every addon**. If Gathercraft is disabled or its auto-scan is off, use the window's **Scan** button. It's greyed out with a countdown until 15 minutes have passed since the last scan this addon saw. It can't see Gathercraft's own timer, so the server may still refuse a click, and the window says so after 30 seconds.

Scan data is a snapshot, so some listings will have sold by the time you look. The status line shows how old the results are.

## The results window

Three tabs along the bottom edge switch the list. The search box, Scan button and status line at the top are shared by all of them. The window reopens on the last tab you used.

### Below Vendor tab

| Column | Meaning |
|---|---|
| Item | Icon and name, with its suffix. The name is light blue for items bought in bulk (stackable items, bought by quantity), otherwise its quality color. Hover for the item tooltip |
| Qty | Units listed at the lowest price |
| Buyout | Lowest buyout per unit. Stacks priced in fractions of a copper per unit are rounded to the nearest copper |
| Vendor | What a vendor pays per unit |
| Profit | Vendor minus Buyout, per unit |

Default sort: highest profit per unit first. Ties go to the lowest buyout.

### Undercuts tab

| Column | Meaning |
|---|---|
| Item | As above |
| Lowest | Cheapest auction's buyout per unit |
| 2nd lowest | Second cheapest auction's buyout per unit |
| Difference | 2nd lowest minus Lowest, per unit |

Default sort: biggest difference first. Ties go to the lowest price. Only the 200 biggest differences from the last scan are kept, and items with a difference of 0 aren't listed.

### Waylaid Crates tab

| Column | Meaning |
|---|---|
| Crate | Icon and crate name, without the "Waylaid Crate:" prefix. Light blue, since crates are bought in bulk. Hover for the crate's tooltip, the turn-in reward (Favor and money), and every bundle's whole cost: the cheapest in green, and bundles the AH can't fill in grey with how many units are short |
| Lvl | Level required to use the crate |
| Favor | Merchant's Favor for turning in the filled crate |
| Price | Cheapest crate's buyout |
| Fill with | The cheapest bundle, e.g. "20 Light Leather" |
| Fill / Favor | What that bundle costs from the cheapest listings, divided by Favor |
| Total / Favor | (Price + bundle cost − turn-in money) ÷ Favor |

Every crate is listed, even when none are for sale. A price that can't be worked out shows "—": Price when no crate is listed, Fill with and Fill / Favor when no bundle has enough units listed, and Total / Favor when either is missing. Default sort: lowest Total / Favor first, with "—" rows last (first if you reverse the sort). Ties go to the lowest level. Search matches the crate name and its bundles' item names, so "linen" finds Apprentice Textiles and Apprentice Fabrics.

### All tabs

- **Sorting:** click a header to sort by it, and click again to reverse. Each tab keeps its own sort until you `/reload`.
- **Search:** filters by item name (including the suffix), ignoring case.
- **Tooltips:** items with a suffix show the suffix's stats.
- **Moving:** drag the window. Its position is saved.
- **Layering:** the window shares a layer with your bags and the Auction House, so whichever you clicked last is on top. Click your bags to bring them in front of it.
- **Opening and closing:** opens and closes with the Auction House. Escape closes it, and `/vsnipe` toggles it at any time.

## Slash commands
- `/vsnipe`: show or hide the results window
- `/vsnipe help`: list commands
- `/vsnipe scan`: start a full scan (same as the Scan button)
- `/vsnipe debug`: toggle diagnostic output in chat (off by default, saved between sessions). Diagnostics are always written to the log either way
- `/vsnipe clearlog`: empty the saved log
- `/vsnipe crates`: with the Auction House open, search for "Waylaid Crate", then run this. It writes every Waylaid Crate in the search results to the log: item ID, name, required level, how many are listed, the cheapest price, and the tooltip text with its fill bundles. `/reload` afterwards so the log is written to disk. Used to collect and update the crate list in `CrateData.lua`

## Sending a log

The addon keeps a log of its last 500 lines: scans, timings, chat messages, and any Lua errors it hits, with a short stack trace. To send it:

1. Optional: `/vsnipe clearlog`, then reproduce the problem.
2. `/reload` or log out. The game only writes the log to disk then.
3. Send `World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\ForeverVendorSnipe.lua`.

That file holds the log (`ForeverVendorSnipeLog`) and the saved settings and results (`ForeverVendorSnipeDB`). It contains realm names and item data, but no character names.

## Saved settings
- `ForeverVendorSnipeDB.debug`: whether debug output is on
- `ForeverVendorSnipeDB.window`: window position (`point`, `relativePoint`, `x`, `y`)
- `ForeverVendorSnipeDB.selectedTab`: tab the window opens on, `"vendor"` (default), `"undercuts"` or `"crates"`
- `ForeverVendorSnipeDB.realms[realmName]`: last scan results and scan timing for each realm (see "Saved results format")
- `ForeverVendorSnipeLog.lines`: the log, oldest line first, capped at 500

## Code overview

Review document for this addon. Update it in the same change as the code.

### Files (in .toc load order)

#### `Locales/enUS.lua`
Every user-facing string, as `ns.L`. Format patterns have a comment saying what fills them.

#### `Utils.lua`
Helpers used by more than one file.

| Function | Scope | Purpose |
|---|---|---|
| `ns.FormatCountdown(seconds)` | public | `754` → `"12:34"`. Used for the cooldown in chat (Scanner) and on the Scan button (window) |
| `ns.CompareUnitPrice(buyoutA, countA, buyoutB, countB)` | public | Sign of the difference between two auctions' unit prices, by cross-multiplying, so fractional unit prices compare exactly. Used by BelowVendor.lua and Undercuts.lua |

#### `Log.lua`
The saved log, plus error capture. It loads before the core file, so `ns.Print` and `ns.Debug` can write to it.

| Function | Scope | Purpose |
|---|---|---|
| `appendLine(line)` | local | Adds a line, dropping the oldest past 500. Buffers lines until `ns.InitLog` |
| `ns.Log(msg)` | public | Writes a timestamped line to the log (never to chat) |
| `ns.ClearLog()` | public | Empties the log (`/vsnipe clearlog`) |
| `ns.InitLog()` | public | Connects to `ForeverVendorSnipeLog`, flushes the buffer, writes the session header. Called from `ADDON_LOADED` |
| `isPowerOfTwo(n)` | local | Used to log repeated errors only on the 2nd, 4th, 8th… time |
| `reportError(err)` | local | xpcall handler: logs the error (with a stack the first time), then calls the game's error handler |
| `ns.SafeCall(fn, ...)` | public | Runs `fn` under xpcall with `reportError` |

#### `ForeverVendorSnipe.lua`
Core: event frame, SavedVariables setup, and the `/vsnipe` command dispatcher. Same structure as ForeverGroundMarkers' core file.

| Function | Scope | Purpose |
|---|---|---|
| `applyDefaults(db, defaults)` | local | Recursively merges defaults into saved data without overwriting existing values |
| `printToChat(msg)` | local | Shows a message in chat with the "Vendor Snipe:" prefix |
| `ns.Print(msg)` | public | Logs a message and prints it to chat |
| `ns.Debug(msg)` | public | Always logs a message. Also prints it to chat, `[debug]`-tagged, while debug mode is on |
| `dispatchEvent(_, event, ...)` | local | OnEvent script that calls every handler registered for the event, in registration order, each through `ns.SafeCall` |
| `ns.RegisterEvent(event, handler)` | public | Adds a handler for an event. Several files can listen to the same event |
| `ns.UnregisterEvent(event, handler)` | public | Removes one specific handler. Stops listening when none remain |
| `onAddonLoaded(loadedName)` | local | Calls `ns.InitLog`, then creates and fills `ForeverVendorSnipeDB` and exposes it as `ns.db` |
| `onPlayerLogin()` | local | Prints the loaded version from the `.toc` |
| `showHelp()` | local | Prints all `ns.commands` entries, sorted by name |
| `toggleDebug()` | local | `/vsnipe debug` handler, flips and saves `ns.db.debug` |
| `clearLog()` | local | `/vsnipe clearlog` handler |
| `handleSlashCommand(input)` | local | Splits `/vsnipe <command> <args>` and calls the matching `ns.commands` handler. No command runs `toggle` |

Also exposes `ns.defaults`, `ns.commands`, and `ns.SLASH_COMMAND`.

#### `BelowVendor.lua`
Builds the Below Vendor rows. Knows nothing about scans, saving or the window: Scanner.lua hands it each auction's variant.

| Function | Scope | Purpose |
|---|---|---|
| `ns.AddVendorListing(rows, variant, count, buyout)` | public | If below vendor, updates the variant's row: a lower unit price replaces it, an equal one adds units |

#### `Undercuts.lua`
Builds the Undercuts rows. Like BelowVendor.lua, it only sees variants and auctions.

| Function | Scope | Purpose |
|---|---|---|
| `ns.AddUndercutListing(entries, variant, count, buyout)` | public | Keeps each variant's cheapest and second cheapest auction by unit price. An auction tied with the cheapest becomes the second (gap 0) |
| `ns.GetUndercutPrices(entry)` | public | `unitLowest, unitSecond, difference` for an entry. Used for ranking here and for the window's columns |
| `insertRanked(ranked, gaps, entry, gap)` | local | Inserts into a list sorted by gap, largest first, capped at 200 |
| `ns.PickTopUndercuts(entries)` | public | The 200 entries with the largest gap above 0, as an array, largest first. Called when results are saved |

#### `CrateData.lua`
Data only: `ns.CRATES`, every Waylaid Crate with its item ID, display name (no prefix), required level, quality, turn-in reward (`favor`, `money` in copper) and bundles `{ itemID, name, quantity }`. Collected with `/vsnipe crates` on 2026-11-21. Four crates whose in-game tooltip hadn't loaded its fill list were taken from Wowhead's Forever tooltips. Every item ID was checked against its name on Wowhead Forever.

The rewards come from community guides (wow-professions.com, maxloot.pro, urgametips.com): white crates pay 5 / 10 / 15 Favor for Apprentice / Journeyman / Expert, green crates (Fabrics, Ingots, Parts) double that, and the money is 50 copper per Favor. **Artisan is assumed** (20 white, 40 green, 50 copper per Favor) because no guide lists it yet. Quality was checked on Wowhead.

#### `WaylaidCrates.lua`
Builds the Waylaid Crates rows. Like the other builders, it knows nothing about scans, saving or the window.

| Function | Scope | Purpose |
|---|---|---|
| `ns.AddCrateListing(listings, itemID, count, buyout)` | public | Keeps an auction (flat `count, buyout` pairs per item ID) if it's a crate or fill item. One table lookup for everything else |
| `isCheaper(a, b)` | local | `table.sort` comparator by unit price, via `ns.CompareUnitPrice` |
| `sortListings(flat)` | local | An item's kept auctions as `{ count, buyout }` listings, cheapest per unit first |
| `getFillCost(listings, quantity)` | local | Cost of the cheapest `quantity` units (part of the last listing counts), or nil plus how many units are short |
| `buildCrateRow(crate, listings)` | local | One crate's saved row: cheapest crate auction and each bundle's cost or shortfall |
| `ns.BuildCrateRows(listings)` | public | A row for every crate in `ns.CRATES`, listed or not. Called when results are saved |
| `ns.GetCrateCosts(row)` | public | `{ crateUnit, bestBundle, favor, money, fillPerFavor, totalPerFavor }` for a row, nil where missing. Favor and money come from `ns.CRATES`, not the saved row. Used for the window's columns, tooltip and default sort |

#### `Scanner.lua`
Reads full scans, groups auctions into variants, and feeds the three builders. It owns all scan state, and the window only reads from it.

| Function | Scope | Purpose |
|---|---|---|
| `getRealmData()` | local | This realm's saved results and timing, created on first use. Discards results in an older format. Adds an empty `crates` list to results saved before 0.5.0 |
| `countKeys(t)` | local | Counts the entries in a non-array table, for the log summary |
| `getItemDetails(item)` | local | Name, quality, vendor price and max stack size from `C_Item.GetItemInfo` (item ID or link), nil if not cached |
| `isBulkItem(stackSize)` | local | Whether an item is bought in bulk (stacks to more than 1) |
| `getItemInfo(scan, itemID)` | local | `{ name, quality, vendorPrice, bulk }` for an item, cached per scan. Replaces 0.3's `getVendorPrice` |
| `readLink(index)` | local | One auction's item link via `C_AuctionHouse.GetReplicateItemLink`, pcall-wrapped. nil if the API is missing |
| `getLinkName(scan, link)` | local | The name between a link's brackets, with suffix. Falls back to `C_Item.GetItemInfo(link)` and counts empty names for the log |
| `getVariant(scan, itemID, info, link)` | local | The auction's variant `{ key, itemID, name, link, quality, bulk, vendorPrice }`, cached per item and name |
| `addAuction(scan, itemID, info, count, buyout, link)` | local | Works out the variant and passes the auction to `ns.AddVendorListing` and `ns.AddUndercutListing` |
| `fillName(row)` | local | Fills a saved row's name (by link for suffixed rows), quality and bulk flag once its item data loads |
| `fillMissingNames(rows)` | local | Safety net: requests data for rows without a name and logs how many there were. Used for the Below Vendor and Undercuts rows (crate rows take their names from `CrateData.lua`) |
| `saveResults(scan)` | local | Saves the Below Vendor rows, the top-200 undercut pick, the crate rows (`ns.BuildCrateRows`), scan time and auction count |
| `endScan(scan)` | local | Clears the active scan, fills missing names, refreshes the window |
| `finishLoading(scan)` | local | Saves again (so the undercut pick includes loaded items), logs loading time, ends the scan |
| `resolveHeldListings(scan, itemID)` | local | Adds an item's held auctions once its data arrives |
| `holdListing(scan, itemID, count, buyout, link)` | local | Keeps an auction (with its link) for an uncached item and requests the item's data |
| `considerAuction(scan, index, itemID, count, buyout)` | local | Offers the auction to `ns.AddCrateListing` (needs only the item ID), then reads the link unless the item is known to stack and routes to `addAuction` or `holdListing` |
| `pickAuctionFields(ok, ...)` | local | Picks itemID, count and buyout from `GetReplicateItemInfo`'s 18 return values |
| `readAuction(index)` | local | Reads one auction, pcall-wrapped |
| `finishReading(scan)` | local | Saves the results, logs a summary, then waits for held items if any |
| `readStep(scan)` | local | Reads auctions for up to 8 ms, counting bid-only and unreadable ones, then continues next frame |
| `startReading(total)` | local | Creates the scan state and starts reading |
| `onReplicateListUpdate()` | local | `REPLICATE_ITEM_LIST_UPDATE`: starts reading a scan from any addon, ignoring (and counting) repeat events with a cheap time check first |
| `onAuctionHouseShow()` / `onAuctionHouseClosed()` | local | Track and log whether the AH is open. Closing logs the ignored-event count and cancels a scan still being read |
| `isAwaitingAnswer(realm)` | local | Whether this addon's scan request is still waiting for the server |
| `ns.GetVendorRows()` | public | Saved Below Vendor rows for this realm |
| `ns.GetUndercutRows()` | public | Saved Undercuts rows for this realm (array, largest gap first) |
| `ns.GetCrateRows()` | public | Saved Waylaid Crates rows for this realm (array, `ns.CRATES` order) |
| `ns.GetScanInfo()` | public | `scannedAt, auctionCount` for the saved results. With the two above, replaces 0.3's `ns.GetResults` |
| `ns.GetScanStatus()` | public | `state, progress, loadingCount` for the status line |
| `ns.GetScanCooldown()` | public | Seconds until a scan should be allowed |
| `ns.IsAuctionHouseOpen()` | public | Whether the AH window is open |
| `reportIfUnanswered(realm, requestedAt)` | local | Says so in chat if a scan request got no answer within 30 s |
| `ns.StartScan()` | public | Fallback scan request: checks, `C_AuctionHouse.ReplicateItems()`, answer timeout. Also `/vsnipe scan` |

Also exposes `ns.SCAN_STATES` (`IDLE`, `WAITING`, `READING`, `LOADING`).

#### `CrateDump.lua`
`/vsnipe crates`: a data-gathering tool that writes the Waylaid Crates in the AH's current search results to the log. It reads `C_AuctionHouse.GetBrowseResults`, not the full scan, so it doesn't use the scan cooldown. It never changes scan data.

| Function | Scope | Purpose |
|---|---|---|
| `isCrateName(name)` | local | Whether a name starts with `"Waylaid Crate:"` |
| `getTooltipText(itemID)` | local | The item's whole tooltip (`C_TooltipInfo.GetItemByID`) as one line, with line breaks turned into `" \| "` |
| `logCrate(itemID, name, minLevel, result)` | local | Logs one crate's summary line and its tooltip line |
| `reportDump(resultCount, found, notLoaded)` | local | Logs a summary and tells the player in chat: no search, items not loaded yet, results cut short, crates logged |
| `dumpCrates()` | local | `/vsnipe crates` handler: walks the browse results, logs the crates, requests data for uncached items |

#### `ResultsWindow.lua`
The results window. It's created on first show and reads from Scanner.lua through the `ns.*` functions above. Each tab is described by an entry in `TABS` (columns, default sort and direction, row source, element builder, optional search text and tooltip lines, default comparator, empty text) and gets its own page frame with headers and a scroll box.

| Function | Scope | Purpose |
|---|---|---|
| `formatAge(seconds)` | local | `"just now"`, `"12 min ago"`, `"3 h ago"`, `"2 days ago"` |
| `formatMoney(copper)` | local | `GetMoneyString` after rounding to the nearest copper |
| `formatQuantity(count)` | local | Thousands separators, for the Qty column |
| `formatMoneyOrNone(copper)` | local | `formatMoney`, or "—" for a missing price (`NO_PRICE`). Waylaid Crates columns |
| `formatBundle(bundle)` | local | `"20 Light Leather"` |
| `computeColumnOffsets(columns)` | local | Gives each column its x position, shared by headers and rows. Run once per tab's column set |
| `compareByName(a, b)` | local | Shared last tie-breakers: name, then item ID |
| `compareVendorDefault(a, b)` | local | Profit high to low, then unit buyout low to high, then `compareByName` |
| `compareUndercutDefault(a, b)` | local | Difference high to low, then lowest price low to high, then `compareByName` |
| `compareCrateDefault(a, b)` | local | Total / Favor low to high ("—" last), then level low to high, then `compareByName` |
| `makeVendorElement(row)` | local | Qty, unit buyout, vendor price and profit for a Below Vendor row |
| `makeUndercutElement(row)` | local | Lowest, 2nd lowest and difference for an Undercuts row, via `ns.GetUndercutPrices` |
| `makeCrateElement(row)` | local | Level, Favor, price, cheapest bundle, Fill / Favor and Total / Favor for a crate row, via `ns.GetCrateCosts`. Missing prices become `NO_PRICE` |
| `getCrateSearchText(row)` | local | Crate name plus bundle item names, lowercase, for the search box |
| `addCrateTooltipLines(tooltip, element)` | local | Adds the turn-in reward and each bundle's whole cost (cheapest green, short ones grey) below the crate's tooltip |
| `compareElements(a, b)` | local | Sorts by the tab's clicked column, falling back to the tab's default comparator |
| `buildElements(tab)` | local | Tab-specific fields plus shared ones (name, link, quality…) for each saved row, filtered by search (the name, or the tab's `getSearchText`), sorted |
| `refreshList()` | local | Sends the showing tab's elements to its scroll box and shows the empty-list message if needed |
| `updateScanButton(state)` | local | Scan button label and enabled state (busy, countdown, ready) |
| `updateStatus()` | local | Status line plus Scan button. Runs every second while shown |
| `onRowEnter(row)` / `hideTooltip()` | local | Tooltip on hover: by link for suffixed rows (shows the suffix's stats), otherwise by item ID, plus the tab's `addTooltipLines` if it has one. `hideTooltip` is shared with the Scan button |
| `createRowRegions(row, tab)` | local | Creates a row's icon and text cells once per row frame, and remembers its tab |
| `setNameCell(row, element)` | local | Icon and colored name. Bulk items get a light-blue name |
| `initRow(row, element, tab)` | local | Fills a (reused) row frame: name cell, then every other column through its `format`. Remembers the element for the tooltip |
| `updateHeaders(tab)` | local | Shows the sort arrow on the tab's sorted column |
| `onHeaderClick(tab, column)` | local | Changes or reverses the tab's sort |
| `createHeader(parent, tab, column)` | local | Creates one clickable column header |
| `onScanButtonEnter(button)` / `onScanButtonClick()` | local | Scan button tooltip and click |
| `createToolbar(frame)` | local | Title, search box, Scan button, status line (shared by every tab) |
| `createPage(frame, tab)` | local | A tab's page: headers, ScrollBox list with scroll bar, empty-list message, starting sort and direction |
| `selectTab(index)` | local | Shows one page, highlights its tab, saves `ns.db.selectedTab`, refreshes |
| `findTabIndex(id)` | local | Position of a saved tab id in `TABS`, 1 if unknown |
| `onTabClick(button)` | local | Plays the tab sound and selects the clicked tab |
| `createTabs(frame)` | local | Blizzard `PanelTabButtonTemplate` tabs along the bottom edge, registered with `PanelTemplates` |
| `savePosition(frame)` | local | Saves the dragged position to `ns.db.window` |
| `onDragStart(frame)` / `onDragStop(frame)` | local | Moves the window and saves where it's dropped |
| `onWindowShow(frame)` / `onWindowHide(frame)` | local | Status, saved tab and status ticker on open, then stop the ticker on close |
| `createWindowFrame()` | local | The frame itself: size, position, dragging, Escape to close |
| `getWindow()` | local | Creates the window, every page and the tabs on first use |
| `ns.ShowResultsWindow()` / `ns.HideResultsWindow()` / `ns.ToggleResultsWindow()` | public | Show, hide, toggle. Toggle is also `/vsnipe` |
| `runPendingRefresh()` | local | Runs the batched redraw |
| `ns.OnScanUpdated()` | public | Called by Scanner.lua when data or state changes. Batches redraws to one per 0.2 s |

### Saved results format

```lua
ForeverVendorSnipeDB.realms["Realm Name"] = {
    items = {                    -- Below Vendor rows, keyed by variant key
        [2589] = {               -- plain item: key is the item ID (Linen Cloth)
            itemID = 2589,
            name = "Linen Cloth",
            quality = 1,         -- Enum.ItemQuality
            bulk = true,         -- bought by quantity (stacks), not one listing at a time
            vendorPrice = 13,    -- copper per unit
            lowestBuyout = 120,  -- one auction at the lowest unit price:
            lowestCount = 10,    --   unit price = 120 / 10 = 12c
            quantity = 45,       -- units listed at that unit price
        },
        ["15210:Raider Shortsword of the Monkey"] = {  -- suffixed: "itemID:name"
            itemID = 15210,
            name = "Raider Shortsword of the Monkey",
            link = "|cff1eff00|Hitem:15210:...|h[Raider Shortsword of the Monkey]|h|r",
            -- ...same price fields as above
        },
    },
    undercuts = {                -- Undercuts rows, array, largest gap first (at most 200)
        {
            itemID = 15210,
            name = "Raider Shortsword of the Monkey",
            link = "...",        -- only on suffixed rows
            quality = 2,
            bulk = false,
            lowestBuyout = 6003,  lowestCount = 1,   -- cheapest auction (60s 3c each)
            secondBuyout = 11003, secondCount = 1,   -- second cheapest (1g 10s 3c each)
        },
    },
    crates = {                   -- Waylaid Crates rows, array in ns.CRATES order (one per crate)
        {
            itemID = 248684,
            name = "Apprentice Textiles",  -- without the "Waylaid Crate: " prefix
            level = 10,
            quality = 1,         -- from ns.CRATES (green crates are 2)
            bulk = true,
            lowestBuyout = 750, lowestCount = 1,  -- cheapest crate auction; both nil if none listed
            bundles = {
                { itemID = 2589, name = "Linen Cloth", quantity = 40, cost = 3900, short = 0 },
                { itemID = 2318, name = "Light Leather", quantity = 20, short = 6 },  -- no cost: 6 short
            },
        },
    },
    scannedAt = 1795000000,      -- time() of the scan the results come from
    auctionCount = 152345,       -- auctions in that scan
    resultsFormat = 3,           -- saved results format version
    lastScanSeenAt = 1795000000, -- last time this addon saw a scan start (any addon)
    lastRequestAt = 1794990000,  -- last time this addon's Scan button asked for one
}
```

The example values are illustrative. Unit prices, profit and difference aren't saved. The window works them out from the buyout and count pairs. `resultsFormat` is the format version, and results in an older format are discarded on load (0.4.0 bumped it to 3). 0.5.0 added `crates` without a bump: results saved by 0.4.x keep their other lists and get an empty crate list until the next scan.

### Events
- `ADDON_LOADED`: initialize SavedVariables (unregistered after first use)
- `PLAYER_LOGIN`: print the loaded version
- `AUCTION_HOUSE_SHOW`: mark the AH open (Scanner), then show the window (ResultsWindow). The Scanner registers first, so the window sees the AH as open
- `AUCTION_HOUSE_CLOSED`: mark the AH closed and cancel a half-read scan (Scanner), hide the window (ResultsWindow)
- `REPLICATE_ITEM_LIST_UPDATE`: a full scan's list is ready (Scanner)
- Item data loading uses Blizzard's `Item:ContinueOnItemLoad` (which listens for `ITEM_DATA_LOAD_RESULT` itself)

### SavedVariables
- `ForeverVendorSnipeDB` (account-wide): see Saved settings above
- `ForeverVendorSnipeLog` (account-wide): `{ lines = { "2026-11-20 14:03:22 message", ... } }`, capped at 500 lines

### Design decisions
- **Listen instead of scan.** The 15-minute full-scan cooldown is shared by every addon, and Gathercraft already scans when the AH opens. `REPLICATE_ITEM_LIST_UPDATE` fires no matter which addon asked, so reading that scan costs nothing. The Scan button is only a fallback.
- **Repeat events are ignored by time.** The game fires `REPLICATE_ITEM_LIST_UPDATE` many times for one scan. Gathercraft's code shows the full list can be read on the first one. A real new scan can't arrive within 15 minutes, so events within 10 minutes of the last scan seen are treated as repeats. The timestamp is saved, so a `/reload` mid-scan doesn't read the same scan twice. The log showed about 96,000 repeats per scan (roughly one per 2.5 auctions), so repeats are dropped by comparing `time()` with a local `ignoreEventsUntil` before any saved data is read.
- **Reading in timed steps.** A scan can hold ~300,000 auctions (per Gathercraft's notes). Reading stops after 8 ms each frame and continues next frame, so the game doesn't freeze. 0.3 read ~240,000 auctions in about 11.5 s.
- **Must read while the AH is open.** The scan list is gone once the AH closes, so closing mid-read cancels the scan and keeps the previous results. Item-data loading carries on after closing, since it doesn't need the AH.
- **One reader, three builders.** Scanner.lua reads each auction once and hands it to BelowVendor.lua, Undercuts.lua and WaylaidCrates.lua. The builders only see the auction and the table they fill, so none of them knows about scans, saving or the window. The crate builder gets `(itemID, count, buyout)` in `considerAuction`, before the item-cache check, since the crate list already names every item it needs. Its auctions are never held for item data.
- **Variants by link name.** Random-suffix items ("of the Monkey") share an item ID. Forever's links follow the modern layout, and Gathercraft's notes describe suffixes as *bonuses*, so the suffix may not sit in the classic suffix field. Grouping by the name between the link's brackets works whichever way the suffix is encoded, and it groups exactly what the player sees. Plain items keep the item ID as their key. Suffixed ones use `"itemID:name"` and keep the link for the tooltip. If the brackets are ever empty, the name comes from `C_Item.GetItemInfo(link)`, and the log counts how often that happened (expected 0).
- **Links are only read when needed.** Items that stack can't have a suffix, so their link isn't read. Only non-stacking items (and items not cached yet, whose stack size is unknown) cost the extra `GetReplicateItemLink` call. If that API is missing on the client, suffixed items fall back to grouping by item ID and the log says so.
- **Vendor price per item, not per suffix.** The vendor price comes from the base item (`C_Item.GetItemInfo(itemID)`), cached once per item per scan. Suffixed variants of an item share it.
- **"Second cheapest" is the second auction.** Three axes at 60s give a gap of 0, so the list only shows a single cheap auction standing alone below the rest. Auctions are compared per unit with `ns.CompareUnitPrice`, so stacks of different sizes compare fairly.
- **Only the top 200 undercuts are saved.** Every variant on the AH (tens of thousands) is tracked during the scan, then `ns.PickTopUndercuts` keeps the 200 biggest gaps above 0 in a single pass. That keeps SavedVariables small. The pick runs when reading finishes and again when held items finish loading.
- **No "last sold" column.** The modern `C_AuctionHouse` API has no sale history for other players' auctions (no last sold price or date). The only sold data is for the player's own auctions (`GetOwnedAuctionInfo`, the "auction sold" notification). Showing an earlier scan's lowest listing or your own last sale was considered and left out for now.
- **Uncached items are held, not dropped.** The vendor price and name come from the item cache. Auctions for uncached items are held as `(count, buyout, link)`. The item data is requested through Blizzard's `Item` mixin, and the auctions join both lists when it arrives. Results are saved as soon as reading finishes, and held items join them as they load, for up to 60 seconds.
- **Results are saved per realm**, because each realm has its own Auction House. Only the grouped rows are saved, not raw auctions.
- **Lowest price per item, compared exactly.** Each row keeps one auction's `(buyout, count)` at the lowest unit price, plus the units at that price. Unit prices are compared by cross-multiplying, so stack prices that work out to fractions of a copper compare exactly. Rounding only happens for display.
- **Names are read with the vendor price.** In 0.1.0 the name was looked up later, when the item's row was created. With 200,000+ auctions read in between, the game could drop the item from its cache, so some rows had no name. Now both come from one `C_Item.GetItemInfo` call. `fillMissingNames` is a safety net that logs a count, which should stay 0.
- **Bulk is decided by stack size.** The modern AH sells stackable items as commodities, bought by quantity in one purchase. Blizzard's `C_AuctionHouse.GetItemCommodityStatus` would say so directly, but it takes an item in the bags, not an item ID. So an item that stacks to more than 1 counts as bulk. The stack size comes from the `C_Item.GetItemInfo` call the scanner already makes.
- **Tabs as pages.** Each tab has its own page frame with its own headers and scroll box, rather than one list that swaps columns. Row frames never need re-laying out, and each tab keeps its scroll position. Columns carry a `format` function, so `initRow` fills any tab's cells with one loop. Search, Scan and the status line are about the scan, not the list, so they're shared.
- **Derived values aren't saved.** Unit prices, profit, difference and lowercase names are added to fresh list elements in `buildElements`, so SavedVariables only hold scan data. The undercut columns use the same `ns.GetUndercutPrices` that ranked the rows.
- **Same layer as the bags.** The window used the HIGH frame strata, which drew it over the bags (MEDIUM, per Blizzard's `ContainerFrame.xml`) no matter what. It now uses MEDIUM, like the bags and `AuctionHouseFrame`, and keeps `SetToplevel(true)`, so clicking raises whichever frame was clicked. Showing a frame doesn't raise it, so opening the bags while the window is on top may leave them behind it until they're clicked.
- **The log lives in SavedVariables.** Addons can't write files, so the log is a capped list of lines in its own SavedVariable, written to disk on `/reload` or logout. It's always on, because problems are usually noticed after the fact. `/vsnipe debug` only controls chat output.
- **Error capture.** Event handlers, timer and item-load callbacks, and the window's handlers run through `ns.SafeCall`, which logs an error and then passes it to the game's error handler, so nothing that BugSack or the default popup would show is hidden. A repeating error is logged in full once, then only on the 2nd, 4th, 8th… time, so it can't push everything else out of the 500-line log. Row hover tooltips aren't wrapped, since they only call Blizzard's tooltip.
- **Fill cost walks the cheapest listings.** Taking the cheapest unit price times the quantity would undercount when only a few units sit at that price. Every fill item stacks, and the AH sells stackable items by quantity, so part of a listing can be bought. The builder sorts each fill item's auctions by unit price once, when results are saved, and adds them up until the bundle is complete. Only the ~100 crate and fill items' auctions are kept during the scan, as flat `count, buyout` pairs.
- **Bundle costs are saved, the choice isn't.** Each saved crate row has every bundle's cost (or shortfall), because the auctions behind them aren't saved. The cheapest bundle and the costs per Favor are worked out by `ns.GetCrateCosts` when the window draws, like the other tabs' derived values.
- **Rewards are read from the data, not saved.** Favor and money are fixed per crate, so `ns.GetCrateCosts` looks them up in `ns.CRATES` by item ID. Correcting a value (e.g. once the Artisan rewards are confirmed) shows straight away, without a new scan.
- **Turn-in money lowers only the total.** Fill / Favor is the cost of the bundle alone. Total / Favor is what a Favor really costs when buying the crate too, so it subtracts the money the turn-in pays back.
- **"—" sorts as infinity.** Missing prices are stored on list elements as `math.huge` (`NO_PRICE`), so the shared `compareElements` can sort them without nil checks and they land last in a low-to-high sort. `formatMoneyOrNone` shows them as "—".
- **Tab hooks instead of special cases.** The crates tab needed search over its fill items, extra tooltip lines and a low-to-high default sort. These are optional `TABS` fields (`getSearchText`, `addTooltipLines`, `defaultSortAscending`), so `buildElements`, `onRowEnter` and `createPage` stay generic.
- **Crate list from a dump, not live detection.** Waylaid Crates are filled with any one of several bundles listed in their tooltip ("40 Linen Cloth or 20 Light Leather"). Wowhead's Forever pages load their data with JavaScript, so the list couldn't be collected from there. `/vsnipe crates` logs what the AH search shows, and `CrateData.lua` is a hardcoded, reviewable table built from that log. Reading tooltips on every scan would break silently if the wording changed, and crates with no listing would disappear. The dump reads the AH's search results because the player can search for crates directly, so no full scan is needed. Item names can't be turned into item IDs here (`C_Item.GetItemInfoInstant` only resolves names of items that have been in the bags), so the bundle item IDs are looked up separately.
- **Gathercraft is a reference, not a dependency.** Its scan code (GPL-3) was read to confirm which APIs work on Forever. No code was copied, and the addon has no dependency on Gathercraft.
