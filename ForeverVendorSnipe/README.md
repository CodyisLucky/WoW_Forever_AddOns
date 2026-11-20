# Forever Vendor Snipe

Target: World of Warcraft: Forever (interface 16001). Not compatible with Retail, Classic, or Midnight.

Lists Auction House items whose buyout is below what a vendor pays for them, ranked by the profit you'd make buying them and selling them to a vendor.

**Current status (0.1.0):** reads full Auction House scans (from Gathercraft, any other addon, or its own Scan button) and shows the below-vendor items in a movable window. List only: it doesn't buy anything.

## How it works

1. Open the Auction House. The results window opens with it, showing the last saved scan.
2. Gathercraft starts a full scan when the Auction House opens. This addon reads that same scan, so it never uses up the shared cooldown itself.
3. Every auction with a buyout is compared with the item's vendor price. When `vendor price × stack size` is more than the buyout, the auction counts.
4. Each item gets one row that adds up all of its below-vendor auctions.

The server allows **one full scan every 15 minutes, shared by every addon**. If Gathercraft is disabled or its auto-scan is off, use the window's **Scan** button. It's greyed out with a countdown until 15 minutes have passed since the last scan this addon saw. It can't see Gathercraft's own timer, so the server may still refuse a click, and the window says so after 30 seconds.

Scan data is a snapshot, so some listings will have sold by the time you look. The status line shows how old the results are.

## The results window

| Column | Meaning |
|---|---|
| Item | Icon and name in quality color. Hover for the item tooltip |
| Qty | Total units across the item's below-vendor auctions, with the auction count in brackets when there's more than one, e.g. `45 (3)` |
| Buyout | Sum of those auctions' buyouts |
| Vendor | What a vendor pays for all those units |
| Profit | Vendor minus Buyout |

- **Default sort:** highest profit first. Ties go to the lowest buyout.
- **Sorting:** click a header to sort by it, and click again to reverse.
- **Search:** filters by item name, ignoring case.
- **Moving:** drag the window. Its position is saved.
- **Opening and closing:** opens and closes with the Auction House. Escape closes it, and `/vsnipe` toggles it at any time.

## Slash commands
- `/vsnipe`: show or hide the results window
- `/vsnipe help`: list commands
- `/vsnipe scan`: start a full scan (same as the Scan button)
- `/vsnipe debug`: toggle diagnostic output in chat (off by default, saved between sessions). Diagnostics are always written to the log either way
- `/vsnipe clearlog`: empty the saved log

## Sending a log

The addon keeps a log of its last 500 lines: scans, timings, chat messages, and any Lua errors it hits, with a short stack trace. To send it:

1. Optional: `/vsnipe clearlog`, then reproduce the problem.
2. `/reload` or log out. The game only writes the log to disk then.
3. Send `World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\ForeverVendorSnipe.lua`.

That file holds the log (`ForeverVendorSnipeLog`) and the saved settings and results (`ForeverVendorSnipeDB`). It contains realm names and item data, but no character names.

## Saved settings
- `ForeverVendorSnipeDB.debug`: whether debug output is on
- `ForeverVendorSnipeDB.window`: window position (`point`, `relativePoint`, `x`, `y`)
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

#### `Scanner.lua`
Reads full scans and builds the results. It owns all scan state, and the window only reads from it.

| Function | Scope | Purpose |
|---|---|---|
| `getRealmData()` | local | This realm's saved results and timing, created on first use |
| `countKeys(t)` | local | Counts the entries in a non-array table, for the log summary |
| `getItemDetails(itemID)` | local | Name, quality and vendor price from `C_Item.GetItemInfo`, nil if not cached |
| `getVendorPrice(scan, itemID)` | local | Vendor price per unit, cached per scan |
| `addListing(scan, itemID, count, buyout, unitVendorPrice)` | local | Adds an auction to its item's row if it's below vendor value |
| `finishLoading(scan)` | local | Ends the scan once held items have loaded or timed out, and logs how long loading took |
| `resolveHeldListings(scan, itemID)` | local | Checks an item's held auctions once its data arrives |
| `holdListing(scan, itemID, count, buyout)` | local | Keeps an auction for an uncached item and requests the item's data |
| `considerAuction(scan, itemID, count, buyout)` | local | Routes one auction to `addListing` or `holdListing` |
| `pickAuctionFields(ok, ...)` | local | Picks itemID, count and buyout from `GetReplicateItemInfo`'s 18 return values |
| `readAuction(index)` | local | Reads one auction, pcall-wrapped |
| `finishReading(scan)` | local | Saves the results, logs a summary, then waits for held items if any |
| `readStep(scan)` | local | Reads auctions for up to 8 ms, counting bid-only and unreadable ones, then continues next frame |
| `startReading(total)` | local | Creates the scan state and starts reading |
| `onReplicateListUpdate()` | local | `REPLICATE_ITEM_LIST_UPDATE`: starts reading a scan from any addon, ignoring (and counting) repeat events |
| `onAuctionHouseShow()` / `onAuctionHouseClosed()` | local | Track and log whether the AH is open. Closing logs the ignored-event count and cancels a scan still being read |
| `isAwaitingAnswer(realm)` | local | Whether this addon's scan request is still waiting for the server |
| `ns.GetResults()` | public | `items, scannedAt, auctionCount` for this realm |
| `ns.GetScanStatus()` | public | `state, progress, loadingCount` for the status line |
| `ns.GetScanCooldown()` | public | Seconds until a scan should be allowed |
| `ns.IsAuctionHouseOpen()` | public | Whether the AH window is open |
| `reportIfUnanswered(realm, requestedAt)` | local | Says so in chat if a scan request got no answer within 30 s |
| `ns.StartScan()` | public | Fallback scan request: checks, `C_AuctionHouse.ReplicateItems()`, answer timeout. Also `/vsnipe scan` |

Also exposes `ns.SCAN_STATES` (`IDLE`, `WAITING`, `READING`, `LOADING`).

#### `ResultsWindow.lua`
The results window. It's created on first show and reads from Scanner.lua through the `ns.*` functions above.

| Function | Scope | Purpose |
|---|---|---|
| `computeColumnOffsets()` | local | Gives each column its x position, shared by headers and rows |
| `formatAge(seconds)` | local | `"just now"`, `"12 min ago"`, `"3 h ago"`, `"2 days ago"` |
| `compareDefault(a, b)` | local | Profit high to low, then buyout low to high, then name, then item ID |
| `compareElements(a, b)` | local | Sorts by the clicked column, falling back to `compareDefault` |
| `buildElements()` | local | Copies saved rows into list elements with profit added, filtered by search, sorted |
| `refreshList()` | local | Sends the elements to the scroll box and shows the empty-list message if needed |
| `updateScanButton(state)` | local | Scan button label and enabled state (busy, countdown, ready) |
| `updateStatus()` | local | Status line plus Scan button. Runs every second while shown |
| `onRowEnter(row)` / `hideTooltip()` | local | Item tooltip on hover. `hideTooltip` is shared with the Scan button |
| `createRowRegions(row)` | local | Creates a row's icon and text cells once per row frame |
| `initRow(row, element)` | local | Fills a (reused) row frame with one element |
| `updateHeaders()` | local | Shows the sort arrow on the sorted column |
| `onHeaderClick(column)` | local | Changes or reverses the sort |
| `createHeader(parent, column)` | local | Creates one clickable column header |
| `onScanButtonEnter(button)` / `onScanButtonClick()` | local | Scan button tooltip and click |
| `createToolbar(frame)` | local | Title, search box, Scan button, status line |
| `createList(frame)` | local | Headers, ScrollBox list with scroll bar, empty-list message |
| `savePosition(frame)` | local | Saves the dragged position to `ns.db.window` |
| `onDragStart(frame)` / `onDragStop(frame)` | local | Moves the window and saves where it's dropped |
| `onWindowShow(frame)` / `onWindowHide(frame)` | local | Refresh on open and start the status ticker, then stop the ticker on close |
| `createWindowFrame()` | local | The frame itself: size, position, dragging, Escape to close |
| `getWindow()` | local | Creates the window on first use |
| `ns.ShowResultsWindow()` / `ns.HideResultsWindow()` / `ns.ToggleResultsWindow()` | public | Show, hide, toggle. Toggle is also `/vsnipe` |
| `runPendingRefresh()` | local | Runs the batched redraw |
| `ns.OnScanUpdated()` | public | Called by Scanner.lua when data or state changes. Batches redraws to one per 0.2 s |

### Saved results format

```lua
ForeverVendorSnipeDB.realms["Realm Name"] = {
    items = {
        [2589] = {               -- itemID (Linen Cloth)
            name = "Linen Cloth",
            quality = 1,         -- Enum.ItemQuality
            quantity = 45,       -- units across below-vendor auctions
            listings = 3,        -- number of those auctions
            buyout = 120,        -- copper, summed
            vendorValue = 135,   -- copper, vendor price × quantity
        },
    },
    scannedAt = 1795000000,      -- time() of the scan the items come from
    auctionCount = 152345,       -- auctions in that scan
    lastScanSeenAt = 1795000000, -- last time this addon saw a scan start (any addon)
    lastRequestAt = 1794990000,  -- last time this addon's Scan button asked for one
}
```

The example values are illustrative. Profit isn't saved. The window works it out as `vendorValue - buyout`.

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
- **Repeat events are ignored by time.** The game fires `REPLICATE_ITEM_LIST_UPDATE` 100+ times for one scan. Gathercraft's code shows the full list can be read on the first one. A real new scan can't arrive within 15 minutes, so events within 10 minutes of the last scan seen are treated as repeats. The timestamp is saved, so a `/reload` mid-scan doesn't read the same scan twice.
- **Reading in timed steps.** A scan can hold ~300,000 auctions (per Gathercraft's notes). Reading stops after 8 ms each frame and continues next frame, so the game doesn't freeze. Only below-vendor items are kept, which is a small set.
- **Must read while the AH is open.** The scan list is gone once the AH closes, so closing mid-read cancels the scan and keeps the previous results. Item-data loading carries on after closing, since it doesn't need the AH.
- **Uncached items are held, not dropped.** The vendor price comes from the item cache. Auctions for uncached items are held as `(count, buyout)` pairs. The item data is requested through Blizzard's `Item` mixin, and the auctions are checked when it arrives. Results are saved as soon as reading finishes, and held items join them as they load, for up to 60 seconds.
- **Results are saved per realm**, because each realm has its own Auction House. Only the grouped below-vendor rows are saved, not raw auctions, which keeps SavedVariables small.
- **Derived values aren't saved.** Profit and lowercase names are added to fresh list elements in `buildElements`, so SavedVariables only hold scan data.
- **The log lives in SavedVariables.** Addons can't write files, so the log is a capped list of lines in its own SavedVariable, written to disk on `/reload` or logout. It's always on, because problems are usually noticed after the fact. `/vsnipe debug` only controls chat output.
- **Error capture.** Event handlers, timer and item-load callbacks, and the window's handlers run through `ns.SafeCall`, which logs an error and then passes it to the game's error handler, so nothing that BugSack or the default popup would show is hidden. A repeating error is logged in full once, then only on the 2nd, 4th, 8th… time, so it can't push everything else out of the 500-line log. Row hover tooltips aren't wrapped, since they only call Blizzard's tooltip.
- **Gathercraft is a reference, not a dependency.** Its scan code (GPL-3) was read to confirm which APIs work on Forever. No code was copied, and the addon has no dependency on Gathercraft.
