--[[
    ResultsWindow.lua
    The movable results window: a search box, a status line and the fallback Scan
    button at the top, and three tabs at the bottom, each with its own page of
    sortable column headers and a scrolling list.
      Below Vendor    each variant's lowest below-vendor price, its vendor price, and
                      the profit on each unit bought at that price
      Undercuts       the variants whose cheapest auction is furthest below the
                      second cheapest, per unit
      Waylaid Crates  every crate's cheapest price, its cheapest fill bundle, and
                      the total to buy and fill one
    Search, Scan and the status line are shared by all tabs. The selected tab is
    saved (ns.db.selectedTab); each tab keeps its own sort while the game runs.
    Opens when the Auction House opens, closes when it closes, and /vsnipe toggles
    it at any time to show the last saved scan.

    The window is created the first time it's shown (after ADDON_LOADED, so ns.db
    exists). It reads everything from Scanner.lua (ns.GetVendorRows,
    ns.GetUndercutRows, ns.GetCrateRows, ns.GetScanInfo, ns.GetScanStatus,
    ns.GetScanCooldown) and never changes scan data.
]]

local _, ns = ...

local L = ns.L

local WINDOW_NAME = "ForeverVendorSnipeFrame"
local WINDOW_TEMPLATE = "BasicFrameTemplateWithInset"
-- Same layer as Blizzard's bags and Auction House frame (both MEDIUM), so with
-- SetToplevel whichever was clicked last is drawn on top. HIGH covered the bags.
local WINDOW_STRATA = "MEDIUM"
local WINDOW_WIDTH = 680
local WINDOW_HEIGHT = 460
local PADDING = 12
local TITLE_OFFSET_Y = -5
local TOOLBAR_OFFSET_Y = -32
local SEARCH_INSET_X = 6 -- SearchBoxTemplate draws its border outside the frame
local SEARCH_WIDTH = 200
local SEARCH_HEIGHT = 20
local SCAN_BUTTON_WIDTH = 120
local SCAN_BUTTON_HEIGHT = 22
local STATUS_OFFSET_Y = -60
local HEADER_OFFSET_Y = -80
local HEADER_HEIGHT = 20
local ROW_HEIGHT = 20
local ICON_SIZE = 16
local ICON_GAP = 4
local CELL_GAP = 6
local SCROLLBAR_GAP = 24 -- room right of the list for the scroll bar
local SCROLLBAR_OFFSET_X = 6
local SORT_ARROW_WIDTH = 9
local SORT_ARROW_HEIGHT = 8
local SORT_ARROW_GAP = 2
local SORT_ARROW_TEXTURE = "Interface\\Buttons\\UI-SortArrow"
local ROW_HIGHLIGHT_TEXTURE = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
-- Tabs hang off the window's bottom edge, like Blizzard's Character and AH frames.
local TAB_TEMPLATE = "PanelTabButtonTemplate"
local TAB_OFFSET_X = 11 -- first tab, from the window's bottom-left corner
local TAB_OFFSET_Y = 2  -- tabs overlap the window border slightly
local TAB_GAP = 3       -- between neighboring tabs
local TAB_TEXT_PADDING = 0 -- extra width passed to PanelTemplates_TabResize
local STATUS_UPDATE_INTERVAL = 1 -- seconds, keeps "X min ago" and the cooldown current
local REFRESH_DELAY = 0.2 -- seconds, batches many scan updates into one redraw
local DEFAULT_QUALITY = Enum.ItemQuality.Common
-- Name color for items bought in bulk (by quantity) instead of one listing at a time.
local BULK_NAME_COLOR = { r = 0.4, g = 0.8, b = 1.0 } -- light blue, #66CCFF
-- Waylaid Crates tooltip: the cheapest bundle, other bundles, and bundles the AH can't fill.
local BEST_BUNDLE_COLOR = { r = 0.1, g = 1.0, b = 0.1 }  -- green
local BUNDLE_COLOR = { r = 1.0, g = 1.0, b = 1.0 }       -- white
local SHORT_BUNDLE_COLOR = { r = 0.5, g = 0.5, b = 0.5 } -- grey
-- Sort value for a price that can't be worked out (shown as L.NO_VALUE). Bigger than
-- any price, so those rows sort last when sorting low to high.
local NO_PRICE = math.huge
local SECONDS_PER_MINUTE = 60
local SECONDS_PER_HOUR = 60 * 60
local SECONDS_PER_DAY = 24 * 60 * 60

local window -- created by getWindow on first show
local activeTab -- the entry from TABS whose page is showing, set by selectTab
local sortingTab -- the tab whose list table.sort is ordering, read by compareElements
local refreshPending = false

--- Formats how long ago something happened, e.g. "12 min ago".
---@param seconds number Elapsed time in seconds
---@return string
local function formatAge(seconds)
    if seconds < SECONDS_PER_MINUTE then
        return L.AGE_NOW
    elseif seconds < SECONDS_PER_HOUR then
        return L.AGE_MINUTES:format(math.floor(seconds / SECONDS_PER_MINUTE))
    elseif seconds < SECONDS_PER_DAY then
        return L.AGE_HOURS:format(math.floor(seconds / SECONDS_PER_HOUR))
    end
    return L.AGE_DAYS:format(math.floor(seconds / SECONDS_PER_DAY))
end

--- Formats a copper amount as gold/silver/copper with coin icons.
--- Rounds to the nearest copper first: unit prices from stacks can have fractions
--- (7 for 1s is 14.29c each), and GetMoneyString expects whole copper.
---@param copper number
---@return string
local function formatMoney(copper)
    return GetMoneyString(math.floor(copper + 0.5), true)
end

--- Formats a unit count with thousands separators, e.g. 12345 -> "12,345".
---@param count number
---@return string
local function formatQuantity(count)
    return BreakUpLargeNumbers(count)
end

--- Formats a price like formatMoney, or L.NO_VALUE ("—") for NO_PRICE.
--- Used by the Waylaid Crates columns, whose prices can be missing.
---@param copper number A price, or NO_PRICE
---@return string
local function formatMoneyOrNone(copper)
    if copper == NO_PRICE then
        return L.NO_VALUE
    end
    return formatMoney(copper)
end

--- Formats a fill bundle as its quantity and item name, e.g. "20 Light Leather".
---@param bundle table A bundle from a saved crate row
---@return string
local function formatBundle(bundle)
    return L.BUNDLE:format(bundle.quantity, bundle.name)
end

-- Columns per tab, left to right. key is the field on a list element (see the tab's
-- makeElement), format turns that field into the cell's text (the Item column is
-- filled by setNameCell instead). ascendingFirst: the first click sorts A-Z / low-high
-- instead of high-low.
local VENDOR_COLUMNS = {
    { key = "name", label = L.COL_ITEM, width = 250, justify = "LEFT", ascendingFirst = true },
    { key = "quantity", label = L.COL_QUANTITY, width = 70, justify = "RIGHT", format = formatQuantity },
    { key = "unitBuyout", label = L.COL_BUYOUT, width = 100, justify = "RIGHT", format = formatMoney },
    { key = "vendorPrice", label = L.COL_VENDOR, width = 100, justify = "RIGHT", format = formatMoney },
    { key = "profit", label = L.COL_PROFIT, width = 100, justify = "RIGHT", format = formatMoney },
}

local UNDERCUT_COLUMNS = {
    { key = "name", label = L.COL_ITEM, width = 290, justify = "LEFT", ascendingFirst = true },
    { key = "unitLowest", label = L.COL_LOWEST, width = 100, justify = "RIGHT", format = formatMoney },
    { key = "unitSecond", label = L.COL_SECOND, width = 100, justify = "RIGHT", format = formatMoney },
    { key = "difference", label = L.COL_DIFFERENCE, width = 100, justify = "RIGHT", format = formatMoney },
}

-- Level, Favor and Fill with are already plain values, so tostring is their format.
-- Fill / Favor and Total / Favor are per Merchant's Favor (see ns.GetCrateCosts).
local CRATE_COLUMNS = {
    { key = "name", label = L.COL_CRATE, width = 150, justify = "LEFT", ascendingFirst = true },
    { key = "level", label = L.COL_LEVEL, width = 30, justify = "RIGHT", format = tostring, ascendingFirst = true },
    { key = "favor", label = L.COL_FAVOR, width = 40, justify = "RIGHT", format = tostring },
    { key = "crateUnit", label = L.COL_CRATE_PRICE, width = 80, justify = "RIGHT", format = formatMoneyOrNone, ascendingFirst = true },
    { key = "fill", label = L.COL_FILL, width = 125, justify = "LEFT", format = tostring, ascendingFirst = true },
    { key = "fillPerFavor", label = L.COL_FILL_PER_FAVOR, width = 80, justify = "RIGHT", format = formatMoneyOrNone, ascendingFirst = true },
    { key = "totalPerFavor", label = L.COL_TOTAL_PER_FAVOR, width = 80, justify = "RIGHT", format = formatMoneyOrNone, ascendingFirst = true },
}

--- Gives each column its x position inside a row, from the column widths and CELL_GAP.
--- Called once per column set at load. Headers and row cells both use column.offset,
--- so they line up.
---@param columns table VENDOR_COLUMNS, UNDERCUT_COLUMNS or CRATE_COLUMNS
local function computeColumnOffsets(columns)
    local x = 0
    for _, column in ipairs(columns) do
        column.offset = x
        x = x + column.width + CELL_GAP
    end
end
computeColumnOffsets(VENDOR_COLUMNS)
computeColumnOffsets(UNDERCUT_COLUMNS)
computeColumnOffsets(CRATE_COLUMNS)

--- The last tie-breakers for every tab: name (case-insensitive), then item ID, so the
--- order is always the same. Two variants of one item differ by name, so they never
--- reach the item ID check.
---@return boolean aFirst Whether element a sorts before element b
local function compareByName(a, b)
    if a.sortName ~= b.sortName then
        return a.sortName < b.sortName
    end
    return a.itemID < b.itemID
end

--- Below Vendor's default order: highest profit per unit, then lowest unit buyout
--- ("what costs the least"), then compareByName.
---@return boolean aFirst Whether element a sorts before element b
local function compareVendorDefault(a, b)
    if a.profit ~= b.profit then
        return a.profit > b.profit
    elseif a.unitBuyout ~= b.unitBuyout then
        return a.unitBuyout < b.unitBuyout
    end
    return compareByName(a, b)
end

--- Undercuts' default order: largest gap per unit, then lowest unit price, then
--- compareByName.
---@return boolean aFirst Whether element a sorts before element b
local function compareUndercutDefault(a, b)
    if a.difference ~= b.difference then
        return a.difference > b.difference
    elseif a.unitLowest ~= b.unitLowest then
        return a.unitLowest < b.unitLowest
    end
    return compareByName(a, b)
end

--- Waylaid Crates' default order: lowest total per Merchant's Favor first (crates without
--- one last, see NO_PRICE), then lowest level, then compareByName.
---@return boolean aFirst Whether element a sorts before element b
local function compareCrateDefault(a, b)
    if a.totalPerFavor ~= b.totalPerFavor then
        return a.totalPerFavor < b.totalPerFavor
    elseif a.level ~= b.level then
        return a.level < b.level
    end
    return compareByName(a, b)
end

--- Builds a Below Vendor list element's columns from a saved row: units at the lowest
--- price, unit buyout, vendor price and profit per unit. Derived values are worked out
--- here so they never end up in SavedVariables.
---@param row table A saved Below Vendor row
---@return table element The tab-specific fields (buildElements adds the shared ones)
local function makeVendorElement(row)
    local unitBuyout = row.lowestBuyout / row.lowestCount
    return {
        quantity = row.quantity,
        unitBuyout = unitBuyout,
        vendorPrice = row.vendorPrice,
        profit = row.vendorPrice - unitBuyout,
    }
end

--- Builds an Undercuts list element's columns from a saved row, using the same
--- ns.GetUndercutPrices that ranked the rows, so the numbers always agree.
---@param row table A saved Undercuts row (always has a second auction)
---@return table element The tab-specific fields (buildElements adds the shared ones)
local function makeUndercutElement(row)
    local unitLowest, unitSecond, difference = ns.GetUndercutPrices(row)
    return {
        unitLowest = unitLowest,
        unitSecond = unitSecond,
        difference = difference,
    }
end

--- Builds a Waylaid Crates list element's columns from a saved row, using
--- ns.GetCrateCosts for the crate price, cheapest bundle, Favor, and costs per Favor.
--- Missing prices become NO_PRICE, so they sort and display consistently ("—").
--- The bundles and turn-in money are kept for the row tooltip (addCrateTooltipLines).
---@param row table A saved crate row
---@return table element The tab-specific fields (buildElements adds the shared ones)
local function makeCrateElement(row)
    local costs = ns.GetCrateCosts(row)
    return {
        level = row.level,
        -- A number either way, so the column can sort. 0 only for a saved row whose crate
        -- was removed from ns.CRATES, until the next scan drops it.
        favor = costs.favor or 0,
        crateUnit = costs.crateUnit or NO_PRICE,
        fill = costs.bestBundle and formatBundle(costs.bestBundle) or L.NO_VALUE,
        fillPerFavor = costs.fillPerFavor or NO_PRICE,
        totalPerFavor = costs.totalPerFavor or NO_PRICE,
        bundles = row.bundles,
        bestBundle = costs.bestBundle,
        money = costs.money,
    }
end

--- The text the search box matches for a crate row: its name and every bundle's item
--- name, lowercase, one per line (so a search can't match across two names).
---@param row table A saved crate row
---@return string text
local function getCrateSearchText(row)
    local names = { row.name or "" }
    for _, bundle in ipairs(row.bundles) do
        names[#names + 1] = bundle.name
    end
    return table.concat(names, "\n"):lower()
end

--- Adds the turn-in reward and every fill bundle's whole cost below a crate's item
--- tooltip. The reward line shows the Favor and the money that Total / Favor subtracts.
--- The cheapest bundle (the one in the Fill with column) is green, and bundles the AH
--- can't fill show how many units are short, in grey.
---@param tooltip GameTooltip The tooltip, already showing the crate
---@param element table The row's list element (makeCrateElement)
local function addCrateTooltipLines(tooltip, element)
    tooltip:AddLine(" ")
    if element.money then
        tooltip:AddLine(L.TOOLTIP_REWARD:format(tostring(element.favor), formatMoney(element.money)))
    end
    tooltip:AddLine(L.TOOLTIP_BUNDLES)
    for _, bundle in ipairs(element.bundles) do
        local color, right
        if not bundle.cost then
            color, right = SHORT_BUNDLE_COLOR, L.TOOLTIP_SHORT:format(bundle.short)
        elseif bundle == element.bestBundle then
            color, right = BEST_BUNDLE_COLOR, formatMoney(bundle.cost)
        else
            color, right = BUNDLE_COLOR, formatMoney(bundle.cost)
        end
        tooltip:AddDoubleLine(formatBundle(bundle), right,
            color.r, color.g, color.b, color.r, color.g, color.b)
    end
end

-- The tabs, in display order. Fields:
--   id                   saved in ns.db.selectedTab
--   label                tab button text
--   columns              the page's columns (see VENDOR_COLUMNS)
--   defaultSortKey       column sorted by when the game starts
--   defaultSortAscending optional: true to start that sort low to high (default high to low)
--   getRows              returns the saved rows to show (from Scanner.lua)
--   makeElement          builds a row's tab-specific element fields
--   getSearchText        optional: a row's lowercase text for the search box (default its name)
--   addTooltipLines      optional: adds lines below a row's item tooltip
--   compareDefault       the default order, also the tie-breaker for every column
--   emptyText            shown when the last scan found nothing for this tab
-- createPage adds the runtime fields: sortKey, sortAscending, page, headers,
-- scrollBox, emptyTextFrame.
local TABS = {
    {
        id = "vendor",
        label = L.TAB_VENDOR,
        columns = VENDOR_COLUMNS,
        defaultSortKey = "profit",
        getRows = ns.GetVendorRows,
        makeElement = makeVendorElement,
        compareDefault = compareVendorDefault,
        emptyText = L.EMPTY_LIST,
    },
    {
        id = "undercuts",
        label = L.TAB_UNDERCUTS,
        columns = UNDERCUT_COLUMNS,
        defaultSortKey = "difference",
        getRows = ns.GetUndercutRows,
        makeElement = makeUndercutElement,
        compareDefault = compareUndercutDefault,
        emptyText = L.EMPTY_UNDERCUTS,
    },
    {
        id = "crates",
        label = L.TAB_CRATES,
        columns = CRATE_COLUMNS,
        defaultSortKey = "totalPerFavor",
        defaultSortAscending = true,
        getRows = ns.GetCrateRows,
        makeElement = makeCrateElement,
        getSearchText = getCrateSearchText,
        addTooltipLines = addCrateTooltipLines,
        compareDefault = compareCrateDefault,
        emptyText = L.EMPTY_CRATES,
    },
}

--- Orders two list elements by sortingTab's clicked column, falling back to the tab's
--- default order on ties. The Item column compares lowercase names, so sorting ignores
--- case. table.sort can't pass the tab, so buildElements sets sortingTab first.
---@return boolean aFirst Whether element a sorts before element b
local function compareElements(a, b)
    local tab = sortingTab
    local key = tab.sortKey == "name" and "sortName" or tab.sortKey
    local valueA, valueB = a[key], b[key]
    if valueA ~= valueB then
        if tab.sortAscending then
            return valueA < valueB
        end
        return valueA > valueB
    end
    return tab.compareDefault(a, b)
end

--- Builds the sorted list for a tab from its saved rows and the search text.
--- Each row becomes a new element: the tab's own columns (makeElement) plus the fields
--- every tab shares (item ID, name, lowercase name, link, quality, bulk flag), so
--- nothing derived ends up in SavedVariables. The search is a plain, case-insensitive
--- substring match on the item name, which includes any suffix, or on the tab's own
--- search text when it has a getSearchText (Waylaid Crates adds the fill items).
---@param tab table An entry from TABS
---@return table elements Sorted list elements
---@return boolean hasResults Whether the last scan found anything for this tab, before the search filter
local function buildElements(tab)
    local rows = tab.getRows()
    local query = strtrim(window.searchBox:GetText()):lower()
    local elements = {}
    for _, row in pairs(rows) do
        local sortName = (row.name or ""):lower()
        local searchText = tab.getSearchText and tab.getSearchText(row) or sortName
        if query == "" or searchText:find(query, 1, true) then
            local element = tab.makeElement(row)
            element.itemID = row.itemID
            element.name = row.name
            element.sortName = sortName
            element.link = row.link
            element.quality = row.quality
            element.bulk = row.bulk
            elements[#elements + 1] = element
        end
    end
    sortingTab = tab
    table.sort(elements, compareElements)
    return elements, next(rows) ~= nil
end

--- Rebuilds the showing tab's list from the current results, search and sort, keeping
--- the scroll position. Shows a message over the empty list: "no matches" when the
--- search hid everything, the tab's emptyText after a scan that found nothing. With no
--- scan at all, the status line already says so. Does nothing before the first tab is
--- selected (the search box can report a change while the window is being built).
local function refreshList()
    local tab = activeTab
    if not tab then
        return
    end
    local elements, hasResults = buildElements(tab)
    tab.scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)

    local scannedAt = ns.GetScanInfo()
    if #elements > 0 or (not hasResults and scannedAt == 0) then
        tab.emptyTextFrame:Hide()
    else
        tab.emptyTextFrame:SetText(hasResults and L.EMPTY_SEARCH or tab.emptyText)
        tab.emptyTextFrame:Show()
    end
end

--- Sets the Scan button's label and whether it can be clicked.
--- Busy while a scan is being read or the server hasn't answered, a countdown while
--- the cooldown runs, otherwise "Scan", enabled only while the Auction House is open.
---@param state string The scanner state from ns.GetScanStatus
local function updateScanButton(state)
    local button = window.scanButton
    local left = ns.GetScanCooldown()
    if state == ns.SCAN_STATES.READING or state == ns.SCAN_STATES.WAITING then
        button:SetText(L.SCAN_BUTTON_BUSY)
        button:Disable()
    elseif left > 0 then
        button:SetText(L.SCAN_BUTTON_WAIT:format(ns.FormatCountdown(left)))
        button:Disable()
    else
        button:SetText(L.SCAN_BUTTON)
        button:SetEnabled(ns.IsAuctionHouseOpen())
    end
end

--- Updates the status line and the Scan button from the scanner's current state.
--- Runs every STATUS_UPDATE_INTERVAL while the window is shown, and after scan updates.
local function updateStatus()
    local state, progress, loadingCount = ns.GetScanStatus()
    local scannedAt, auctionCount = ns.GetScanInfo()
    local text
    if state == ns.SCAN_STATES.READING then
        text = L.STATUS_READING:format(math.floor(progress * 100))
    elseif state == ns.SCAN_STATES.WAITING then
        text = L.STATUS_WAITING
    elseif scannedAt > 0 then
        text = L.STATUS_SCANNED:format(formatAge(time() - scannedAt), BreakUpLargeNumbers(auctionCount))
        if state == ns.SCAN_STATES.LOADING then
            text = text .. L.STATUS_LOADING:format(loadingCount)
        end
    else
        text = L.STATUS_NONE
    end
    window.statusText:SetText(text)
    updateScanButton(state)
end

--- Shows the item's tooltip while the mouse is over a row. Suffixed variants have a
--- link, which shows the suffix's stats; other rows show the item by ID. Tabs with an
--- addTooltipLines (Waylaid Crates) add their own lines below the item.
---@param row Button The list row
local function onRowEnter(row)
    local element = row.element
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if element.link then
        GameTooltip:SetHyperlink(element.link)
    else
        GameTooltip:SetItemByID(element.itemID)
    end
    if row.tab.addTooltipLines then
        row.tab.addTooltipLines(GameTooltip, element)
    end
    GameTooltip:Show()
end

--- Hides the tooltip when the mouse leaves a row or the Scan button.
local function hideTooltip()
    GameTooltip:Hide()
end

--- Creates a row's icon and one text cell per column. Runs once per row frame;
--- the scroll box reuses row frames, so initRow only fills them in afterwards.
--- Remembers the row's tab (row.tab), which never changes, for the tooltip.
---@param row Button A row frame created by the scroll box
---@param tab table The entry from TABS whose page the row is on
local function createRowRegions(row, tab)
    local columns = tab.columns
    row.tab = tab
    row:SetHighlightTexture(ROW_HIGHLIGHT_TEXTURE, "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.cells = {}
    for _, column in ipairs(columns) do
        local left, width = column.offset, column.width
        -- The Item column starts with the icon, so its text begins after it.
        if column.key == "name" then
            left = left + ICON_SIZE + ICON_GAP
            width = width - ICON_SIZE - ICON_GAP
        end
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell:SetPoint("LEFT", row, "LEFT", left, 0)
        cell:SetWidth(width)
        cell:SetJustifyH(column.justify)
        cell:SetWordWrap(false)
        row.cells[column.key] = cell
    end
    row:SetScript("OnEnter", onRowEnter)
    row:SetScript("OnLeave", hideTooltip)
end

--- Fills a row's icon and Item cell. The name is light blue (BULK_NAME_COLOR) for items
--- bought in bulk, otherwise its quality color.
---@param row Button The row frame
---@param element table A list element from buildElements
local function setNameCell(row, element)
    row.icon:SetTexture(C_Item.GetItemIconByID(element.itemID))
    local r, g, b
    if element.bulk then
        r, g, b = BULK_NAME_COLOR.r, BULK_NAME_COLOR.g, BULK_NAME_COLOR.b
    else
        r, g, b = C_Item.GetItemQualityColor(element.quality or DEFAULT_QUALITY)
    end
    row.cells.name:SetText(element.name)
    row.cells.name:SetTextColor(r, g, b)
end

--- Fills a row with one list element: icon and name (setNameCell), then every other
--- column through its format function. Remembers the element for the tooltip.
--- The scroll box calls this (through createPage's initializer) whenever a row frame
--- is shown for an element.
---@param row Button The row frame
---@param element table A list element from buildElements
---@param tab table The entry from TABS whose page the row is on
local function initRow(row, element, tab)
    if not row.cells then
        createRowRegions(row, tab)
    end
    row.element = element
    setNameCell(row, element)
    for _, column in ipairs(tab.columns) do
        if column.format then
            row.cells[column.key]:SetText(column.format(element[column.key]))
        end
    end
end

--- Shows the sort arrow on a tab's sorted column only, pointing up for ascending.
--- The arrow sits just past the label text: right of it for left-aligned columns,
--- left of it for right-aligned ones.
---@param tab table An entry from TABS
local function updateHeaders(tab)
    for _, header in ipairs(tab.headers) do
        local arrow = header.arrow
        if header.column.key == tab.sortKey then
            local textOffset = header.label:GetStringWidth() + SORT_ARROW_GAP
            arrow:ClearAllPoints()
            if header.column.justify == "LEFT" then
                arrow:SetPoint("LEFT", header, "LEFT", textOffset, 0)
            else
                arrow:SetPoint("RIGHT", header, "RIGHT", -textOffset, 0)
            end
            if tab.sortAscending then
                arrow:SetTexCoord(0, 0.5625, 0, 1)
            else
                arrow:SetTexCoord(0, 0.5625, 1, 0)
            end
            arrow:Show()
        else
            arrow:Hide()
        end
    end
end

--- Sorts a tab by a column when its header is clicked. Clicking the sorted column again
--- reverses the order; a new column starts in its natural direction (ascendingFirst).
---@param tab table The entry from TABS the header belongs to
---@param column table The clicked column
local function onHeaderClick(tab, column)
    if tab.sortKey == column.key then
        tab.sortAscending = not tab.sortAscending
    else
        tab.sortKey = column.key
        tab.sortAscending = column.ascendingFirst == true
    end
    updateHeaders(tab)
    refreshList()
end

--- Creates one clickable column header with its label and (hidden) sort arrow.
--- Clicks run through ns.SafeCall, so errors are logged.
---@param parent Frame The tab's page
---@param tab table The entry from TABS
---@param column table One of the tab's columns
---@return Button header
local function createHeader(parent, tab, column)
    local header = CreateFrame("Button", nil, parent)
    header:SetSize(column.width, HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING + column.offset, HEADER_OFFSET_Y)
    header.column = column

    header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header.label:SetAllPoints()
    header.label:SetJustifyH(column.justify)
    header.label:SetText(column.label)

    header.arrow = header:CreateTexture(nil, "OVERLAY")
    header.arrow:SetTexture(SORT_ARROW_TEXTURE)
    header.arrow:SetSize(SORT_ARROW_WIDTH, SORT_ARROW_HEIGHT)
    header.arrow:Hide()

    header:SetScript("OnClick", function()
        ns.SafeCall(onHeaderClick, tab, column)
    end)
    return header
end

--- Explains the shared 15-minute scan cooldown when hovering the Scan button.
---@param button Button The Scan button
local function onScanButtonEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:AddLine(L.SCAN_TOOLTIP_TITLE)
    GameTooltip:AddLine(L.SCAN_TOOLTIP_TEXT, 1, 1, 1, true)
    GameTooltip:Show()
end

--- Starts a fallback scan through ns.SafeCall, so errors are logged. Wrapped so the
--- button's click arguments aren't passed on.
local function onScanButtonClick()
    ns.SafeCall(ns.StartScan)
end

--- Creates the title, search box, Scan button and status line at the top of the window.
--- These are shared by every tab. Typing in the search box refreshes the showing tab's
--- list (through ns.SafeCall, so errors are logged). HookScript keeps the template's
--- own OnTextChanged, which shows and hides the "Search" placeholder.
---@param frame Frame The window
local function createToolbar(frame)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", frame, "TOP", 0, TITLE_OFFSET_Y)
    title:SetText(L.WINDOW_TITLE)

    frame.searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    frame.searchBox:SetSize(SEARCH_WIDTH, SEARCH_HEIGHT)
    frame.searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + SEARCH_INSET_X, TOOLBAR_OFFSET_Y)
    frame.searchBox:SetAutoFocus(false)
    frame.searchBox:HookScript("OnTextChanged", function()
        ns.SafeCall(refreshList)
    end)

    frame.scanButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.scanButton:SetSize(SCAN_BUTTON_WIDTH, SCAN_BUTTON_HEIGHT)
    frame.scanButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, TOOLBAR_OFFSET_Y)
    frame.scanButton:SetScript("OnClick", onScanButtonClick)
    frame.scanButton:SetScript("OnEnter", onScanButtonEnter)
    frame.scanButton:SetScript("OnLeave", hideTooltip)

    frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.statusText:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, STATUS_OFFSET_Y)
    frame.statusText:SetPoint("RIGHT", frame, "RIGHT", -PADDING, 0)
    frame.statusText:SetJustifyH("LEFT")
end

--- Creates a tab's page: a frame covering the window that holds the tab's column
--- headers, scrolling list and empty-list message, hidden until the tab is selected.
--- Uses Blizzard's ScrollBox with a linear view: only visible rows have frames, which
--- are reused as the list scrolls (initRow fills them in). Each page has its own
--- scroll box, so each tab keeps its own rows and scroll position. Also sets the tab's
--- starting sort (high to low unless the tab sets defaultSortAscending).
---@param frame Frame The window
---@param tab table An entry from TABS (runtime fields are added to it)
local function createPage(frame, tab)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints(frame)
    page:Hide()
    tab.page = page
    tab.sortKey = tab.defaultSortKey
    tab.sortAscending = tab.defaultSortAscending == true

    tab.headers = {}
    for _, column in ipairs(tab.columns) do
        tab.headers[#tab.headers + 1] = createHeader(page, tab, column)
    end

    tab.scrollBox = CreateFrame("Frame", nil, page, "WowScrollBoxList")
    tab.scrollBox:SetPoint("TOPLEFT", page, "TOPLEFT", PADDING, HEADER_OFFSET_Y - HEADER_HEIGHT)
    tab.scrollBox:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -(PADDING + SCROLLBAR_GAP), PADDING)

    local scrollBar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", tab.scrollBox, "TOPRIGHT", SCROLLBAR_OFFSET_X, 0)
    scrollBar:SetPoint("BOTTOMLEFT", tab.scrollBox, "BOTTOMRIGHT", SCROLLBAR_OFFSET_X, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    -- The initializer only gets (row, element), so this closure supplies the page's tab.
    view:SetElementInitializer("Button", function(row, element)
        initRow(row, element, tab)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(tab.scrollBox, scrollBar, view)

    tab.emptyTextFrame = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    tab.emptyTextFrame:SetPoint("CENTER", tab.scrollBox, "CENTER")
    tab.emptyTextFrame:Hide()
end

--- Shows one tab's page and hides the others, then fills it.
--- Highlights the tab button (PanelTemplates_SetTab), saves the choice in
--- ns.db.selectedTab so the window reopens on it, and refreshes the list, since the
--- results or search may have changed while the page was hidden.
---@param index number Position of the tab in TABS
local function selectTab(index)
    activeTab = TABS[index]
    ns.db.selectedTab = activeTab.id
    PanelTemplates_SetTab(window, index)
    for _, tab in ipairs(TABS) do
        tab.page:SetShown(tab == activeTab)
    end
    updateHeaders(activeTab)
    refreshList()
end

--- Finds a tab's position in TABS by its id, for restoring the saved tab.
--- Falls back to the first tab if the id is unknown (e.g. a tab removed in a later version).
---@param id string|nil A tab id, e.g. ns.db.selectedTab
---@return number index
local function findTabIndex(id)
    for index, tab in ipairs(TABS) do
        if tab.id == id then
            return index
        end
    end
    return 1
end

--- Switches to the clicked tab with Blizzard's tab sound, through ns.SafeCall so errors
--- are logged. The tab's position in TABS is stored as the button's ID (createTabs).
---@param button Button The clicked tab button
local function onTabClick(button)
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    ns.SafeCall(selectTab, button:GetID())
end

--- Creates one Blizzard-style tab button per entry in TABS along the window's bottom
--- edge, left to right, and registers them with PanelTemplates so the selected one is
--- drawn raised. The buttons are named WINDOW_NAME .. "Tab" .. index and also stored
--- in frame.Tabs, since PanelTemplates looks tabs up either way.
---@param frame Frame The window
local function createTabs(frame)
    frame.Tabs = {}
    for index, tab in ipairs(TABS) do
        local button = CreateFrame("Button", WINDOW_NAME .. "Tab" .. index, frame, TAB_TEMPLATE)
        button:SetID(index)
        button:SetText(tab.label)
        if index == 1 then
            button:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", TAB_OFFSET_X, TAB_OFFSET_Y)
        else
            button:SetPoint("TOPLEFT", frame.Tabs[index - 1], "TOPRIGHT", TAB_GAP, 0)
        end
        button:SetScript("OnClick", onTabClick)
        PanelTemplates_TabResize(button, TAB_TEXT_PADDING)
        frame.Tabs[index] = button
    end
    PanelTemplates_SetNumTabs(frame, #TABS)
end

--- Saves the window's position after the player drags it.
---@param frame Frame The window
local function savePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    local saved = ns.db.window
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

--- Starts dragging the window. Wrapped because OnDragStart passes the mouse button,
--- which StartMoving would take as its own optional argument.
---@param frame Frame The window
local function onDragStart(frame)
    frame:StartMoving()
end

--- Ends a drag and saves where the window was dropped.
---@param frame Frame The window
local function onDragStop(frame)
    frame:StopMovingOrSizing()
    savePosition(frame)
end

--- Brings the window up to date when it opens, and starts the once-a-second status ticker.
--- Opens on the saved tab (selectTab also fills its list). Runs through ns.SafeCall
--- (see getWindow), and so does each tick.
---@param frame Frame The window
local function onWindowShow(frame)
    updateStatus()
    selectTab(findTabIndex(ns.db.selectedTab))
    frame.ticker = C_Timer.NewTicker(STATUS_UPDATE_INTERVAL, function()
        ns.SafeCall(updateStatus)
    end)
end

--- Stops the status ticker when the window closes.
---@param frame Frame The window
local function onWindowHide(frame)
    if frame.ticker then
        frame.ticker:Cancel()
        frame.ticker = nil
    end
end

--- Creates the window frame: size, saved position, dragging and show/hide scripts.
--- Adds it to UISpecialFrames so Escape closes it like Blizzard windows.
---@return Frame frame
local function createWindowFrame()
    local frame = CreateFrame("Frame", WINDOW_NAME, UIParent, WINDOW_TEMPLATE)
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetFrameStrata(WINDOW_STRATA)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", onDragStart)
    frame:SetScript("OnDragStop", onDragStop)

    local saved = ns.db.window
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    table.insert(UISpecialFrames, WINDOW_NAME)
    return frame
end

--- Returns the window, creating it and its contents on first use.
--- The show/hide scripts are set last, once every part they use exists. OnShow runs
--- through ns.SafeCall, so errors while filling the window are logged.
---@return Frame window
local function getWindow()
    if not window then
        window = createWindowFrame()
        createToolbar(window)
        for _, tab in ipairs(TABS) do
            createPage(window, tab)
        end
        createTabs(window)
        window:SetScript("OnShow", function(frame)
            ns.SafeCall(onWindowShow, frame)
        end)
        window:SetScript("OnHide", onWindowHide)
        window:Hide()
    end
    return window
end

--- Shows the results window, creating it on first use.
function ns.ShowResultsWindow()
    getWindow():Show()
end

--- Hides the results window, if it has been created.
function ns.HideResultsWindow()
    if window then
        window:Hide()
    end
end

--- Shows the window if hidden, hides it if shown. /vsnipe (no arguments) runs this.
function ns.ToggleResultsWindow()
    local frame = getWindow()
    frame:SetShown(not frame:IsShown())
end

--- Runs the redraw that ns.OnScanUpdated scheduled, if the window is still open.
local function runPendingRefresh()
    refreshPending = false
    if window and window:IsShown() then
        updateStatus()
        refreshList()
    end
end

--- Tells the window that scan data or scan state changed. Called by Scanner.lua.
--- Waits REFRESH_DELAY before redrawing, so a burst of updates (many items loading
--- at once) causes one redraw, run through ns.SafeCall. Does nothing while the window
--- is closed; it refreshes itself when it opens.
function ns.OnScanUpdated()
    if refreshPending or not (window and window:IsShown()) then
        return
    end
    refreshPending = true
    C_Timer.After(REFRESH_DELAY, function()
        ns.SafeCall(runPendingRefresh)
    end)
end

ns.commands.toggle = { description = L.CMD_TOGGLE, handler = ns.ToggleResultsWindow }

ns.RegisterEvent("AUCTION_HOUSE_SHOW", ns.ShowResultsWindow)
ns.RegisterEvent("AUCTION_HOUSE_CLOSED", ns.HideResultsWindow)
