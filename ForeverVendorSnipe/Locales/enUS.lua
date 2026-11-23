--[[
    Locales/enUS.lua
    Every user-facing string in the addon, exposed as ns.L. Loaded first so all
    other files can read it at load time. Strings with %s / %d are format
    patterns; the comment above each says what fills them in.
]]

local _, ns = ...

ns.L = {
    -- Chat
    CHAT_PREFIX = "Vendor Snipe",
    -- %s = version, %s = slash command
    LOADED = "v%s loaded. Type %s help for commands.",
    COMMANDS_HEADER = "Commands:",
    -- %s = command name, %s = slash command
    UNKNOWN_COMMAND = "Unknown command: %s. Type %s help.",
    -- %s = "on" or "off"
    DEBUG_STATE = "Debug mode %s.",
    ON = "on",
    OFF = "off",
    LOG_CLEARED = "Log cleared.",

    -- Slash command descriptions
    CMD_HELP = "Show this list",
    CMD_DEBUG = "Toggle diagnostic output in chat (it's always saved to the log)",
    CMD_CLEARLOG = "Clear the saved log",
    CMD_TOGGLE = "Show or hide the results window",
    CMD_SCAN = "Start a full Auction House scan (shares the 15-minute cooldown with other addons)",
    CMD_CRATES = "Write the Waylaid Crates in the current Auction House search to the log",

    -- Crate dump (CrateDump.lua)
    -- %s = slash command
    CRATES_NO_SEARCH = "No search results. Search the Auction House for \"Waylaid Crate\", then run %s crates again.",
    -- %d = items not loaded, %s = slash command
    CRATES_NOT_LOADED = "%d results weren't loaded yet. Run %s crates again in a few seconds.",
    CRATES_PARTIAL = "Not all search results are loaded. Scroll to the bottom of the Auction House list and run it again.",
    -- %d = crates logged
    CRATES_LOGGED = "Logged %d Waylaid Crates. /reload to write the log to disk.",
    CRATES_NONE = "No Waylaid Crates in the current search results.",

    -- Scanner messages
    SCAN_NEED_AH = "Open the Auction House first.",
    SCAN_BUSY = "A scan is already being read.",
    -- %s = time left as m:ss
    SCAN_COOLDOWN = "The server allows one full scan every 15 minutes. Try again in %s.",
    SCAN_STARTED = "Scanning the Auction House...",
    -- %s = error text from the game
    SCAN_FAILED = "Scan failed: %s",
    SCAN_NO_ANSWER = "The Auction House didn't answer. Another addon may have used the shared scan. Try again later.",
    SCAN_CANCELLED = "Auction House closed before the scan was read. The previous results are kept.",

    -- Results window
    WINDOW_TITLE = "Forever Vendor Snipe",
    SCAN_BUTTON = "Scan",
    -- %s = time left as m:ss
    SCAN_BUTTON_WAIT = "Scan (%s)",
    SCAN_BUTTON_BUSY = "Scanning...",
    SCAN_TOOLTIP_TITLE = "Full Auction House scan",
    SCAN_TOOLTIP_TEXT = "All addons share one full scan every 15 minutes. The timer only counts scans this addon has seen, so the server may still refuse.",
    COL_ITEM = "Item",
    COL_QUANTITY = "Qty",
    COL_BUYOUT = "Buyout",
    COL_VENDOR = "Vendor",
    COL_PROFIT = "Profit",
    COL_LOWEST = "Lowest",
    COL_SECOND = "2nd lowest",
    COL_DIFFERENCE = "Difference",
    COL_LISTED = "Listed",
    TAB_VENDOR = "Below Vendor",
    TAB_UNDERCUTS = "Undercuts",
    TAB_CRATES = "Waylaid Crates",
    COL_CRATE = "Crate",
    COL_LEVEL = "Lvl",
    COL_CRATE_PRICE = "Price",
    COL_FILL = "Fill with",
    COL_FAVOR = "Favor",
    COL_FILL_PER_FAVOR = "Fill / Favor",
    COL_TOTAL_PER_FAVOR = "Total / Favor",
    -- Shown for a price that can't be worked out (no crate listed, not enough to fill one)
    NO_VALUE = "—",
    -- %d = quantity, %s = item name
    BUNDLE = "%d %s",
    -- %s = Merchant's Favor, %s = money paid (formatted)
    TOOLTIP_REWARD = "Turn-in: %s Merchant's Favor and %s",
    TOOLTIP_BUNDLES = "Fill with any one of (whole bundle):",
    -- %d = units missing on the Auction House
    TOOLTIP_SHORT = "%d short",
    STATUS_NONE = "No scan yet. Gathercraft scans when you open the Auction House, or press Scan.",
    STATUS_WAITING = "Waiting for the Auction House to answer...",
    -- %d = percent read
    STATUS_READING = "Reading scan... %d%%",
    -- %s = age (e.g. "12 min ago"), %s = auction count
    STATUS_SCANNED = "Scanned %s, %s auctions",
    -- %d = items still loading
    STATUS_LOADING = "  (loading %d items)",
    EMPTY_LIST = "No items below vendor price in the last scan.",
    EMPTY_UNDERCUTS = "No item had a second auction priced higher than its cheapest in the last scan.",
    EMPTY_CRATES = "Waylaid Crate prices appear after the next scan.",
    EMPTY_SEARCH = "No items match your search.",
    AGE_NOW = "just now",
    -- %d = minutes / hours / days
    AGE_MINUTES = "%d min ago",
    AGE_HOURS = "%d h ago",
    AGE_DAYS = "%d days ago",
}
