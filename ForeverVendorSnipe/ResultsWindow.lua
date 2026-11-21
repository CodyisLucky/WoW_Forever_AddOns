--[[
    ResultsWindow.lua
    The movable results window: a search box, a status line, the fallback Scan
    button, sortable column headers and a scrolling list with one row per item.
    Prices are per unit: the item's lowest below-vendor buyout, its vendor price,
    and the profit on each unit bought at that price.
    Opens when the Auction House opens, closes when it closes, and /vsnipe toggles
    it at any time to show the last saved scan.

    The window is created the first time it's shown (after ADDON_LOADED, so ns.db
    exists). It reads everything from Scanner.lua (ns.GetResults, ns.GetScanStatus,
    ns.GetScanCooldown) and never changes scan data.
]]

local _, ns = ...

local L = ns.L

local WINDOW_NAME = "ForeverVendorSnipeFrame"
local WINDOW_TEMPLATE = "BasicFrameTemplateWithInset"
local WINDOW_STRATA = "HIGH"
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
local STATUS_UPDATE_INTERVAL = 1 -- seconds, keeps "X min ago" and the cooldown current
local REFRESH_DELAY = 0.2 -- seconds, batches many scan updates into one redraw
local DEFAULT_QUALITY = Enum.ItemQuality.Common
local SECONDS_PER_MINUTE = 60
local SECONDS_PER_HOUR = 60 * 60
local SECONDS_PER_DAY = 24 * 60 * 60

-- Columns, left to right. key is the field on a list element (see buildElements).
-- ascendingFirst: the first click sorts A-Z / low-high instead of high-low.
local COLUMNS = {
    { key = "name", label = L.COL_ITEM, width = 250, justify = "LEFT", ascendingFirst = true },
    { key = "quantity", label = L.COL_QUANTITY, width = 70, justify = "RIGHT" },
    { key = "unitBuyout", label = L.COL_BUYOUT, width = 100, justify = "RIGHT" },
    { key = "vendorPrice", label = L.COL_VENDOR, width = 100, justify = "RIGHT" },
    { key = "profit", label = L.COL_PROFIT, width = 100, justify = "RIGHT" },
}

-- Default sort: highest profit per unit first (ties: lowest buyout, see compareDefault).
local DEFAULT_SORT_KEY = "profit"
local sortKey = DEFAULT_SORT_KEY
local sortAscending = false

local window -- created by getWindow on first show
local refreshPending = false

--- Gives each column its x position inside a row, from the column widths and CELL_GAP.
--- Called once at load. Headers and row cells both use column.offset, so they line up.
local function computeColumnOffsets()
    local x = 0
    for _, column in ipairs(COLUMNS) do
        column.offset = x
        x = x + column.width + CELL_GAP
    end
end
computeColumnOffsets()

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

--- The default ordering: highest profit per unit, then lowest unit buyout ("what costs
--- the least"), then name and item ID so the order is always the same.
---@return boolean aFirst Whether element a sorts before element b
local function compareDefault(a, b)
    if a.profit ~= b.profit then
        return a.profit > b.profit
    elseif a.unitBuyout ~= b.unitBuyout then
        return a.unitBuyout < b.unitBuyout
    elseif a.sortName ~= b.sortName then
        return a.sortName < b.sortName
    end
    return a.itemID < b.itemID
end

--- Orders two list elements by the clicked column, falling back to compareDefault on ties.
--- The Item column compares lowercase names, so sorting ignores case.
---@return boolean aFirst Whether element a sorts before element b
local function compareElements(a, b)
    local key = sortKey == "name" and "sortName" or sortKey
    local valueA, valueB = a[key], b[key]
    if valueA ~= valueB then
        if sortAscending then
            return valueA < valueB
        end
        return valueA > valueB
    end
    return compareDefault(a, b)
end

--- Builds the sorted list shown in the window from the saved results and the search text.
--- Copies each saved row into a new element with its derived fields (unit buyout,
--- profit per unit, lowercase name), so nothing derived ends up in SavedVariables.
--- The search is a plain, case-insensitive substring match on the item name.
---@return table elements Sorted list elements
---@return boolean hasResults Whether the last scan found anything, before the search filter
local function buildElements()
    local items = ns.GetResults()
    local query = strtrim(window.searchBox:GetText()):lower()
    local elements = {}
    for itemID, row in pairs(items) do
        local sortName = (row.name or ""):lower()
        if query == "" or sortName:find(query, 1, true) then
            local unitBuyout = row.lowestBuyout / row.lowestCount
            elements[#elements + 1] = {
                itemID = itemID,
                name = row.name,
                sortName = sortName,
                quality = row.quality,
                quantity = row.quantity,
                unitBuyout = unitBuyout,
                vendorPrice = row.vendorPrice,
                profit = row.vendorPrice - unitBuyout,
            }
        end
    end
    table.sort(elements, compareElements)
    return elements, next(items) ~= nil
end

--- Rebuilds the list from the current results, search and sort, keeping the scroll position.
--- Shows a message over the empty list: "no matches" when the search hid everything,
--- "nothing below vendor" after a scan that found nothing. With no scan at all, the
--- status line already says so.
local function refreshList()
    local elements, hasResults = buildElements()
    window.scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)

    local _, scannedAt = ns.GetResults()
    if #elements > 0 or (not hasResults and scannedAt == 0) then
        window.emptyText:Hide()
    else
        window.emptyText:SetText(hasResults and L.EMPTY_SEARCH or L.EMPTY_LIST)
        window.emptyText:Show()
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
    local _, scannedAt, auctionCount = ns.GetResults()
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

--- Shows the item's tooltip while the mouse is over a row.
---@param row Button The list row
local function onRowEnter(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.itemID)
    GameTooltip:Show()
end

--- Hides the tooltip when the mouse leaves a row or the Scan button.
local function hideTooltip()
    GameTooltip:Hide()
end

--- Creates a row's icon and one text cell per column. Runs once per row frame;
--- the scroll box reuses row frames, so initRow only fills them in afterwards.
---@param row Button A row frame created by the scroll box
local function createRowRegions(row)
    row:SetHighlightTexture(ROW_HIGHLIGHT_TEXTURE, "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.cells = {}
    for _, column in ipairs(COLUMNS) do
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

--- Fills a row with one list element: icon, name in its quality color, units at the
--- lowest price, and the three per-unit money columns.
--- The scroll box calls this whenever a row frame is shown for an element.
---@param row Button The row frame
---@param element table A list element from buildElements
local function initRow(row, element)
    if not row.cells then
        createRowRegions(row)
    end
    row.itemID = element.itemID
    row.icon:SetTexture(C_Item.GetItemIconByID(element.itemID))

    local r, g, b = C_Item.GetItemQualityColor(element.quality or DEFAULT_QUALITY)
    row.cells.name:SetText(element.name)
    row.cells.name:SetTextColor(r, g, b)

    row.cells.quantity:SetText(BreakUpLargeNumbers(element.quantity))
    row.cells.unitBuyout:SetText(formatMoney(element.unitBuyout))
    row.cells.vendorPrice:SetText(formatMoney(element.vendorPrice))
    row.cells.profit:SetText(formatMoney(element.profit))
end

--- Shows the sort arrow on the sorted column only, pointing up for ascending.
--- The arrow sits just past the label text: right of it for left-aligned columns,
--- left of it for right-aligned ones.
local function updateHeaders()
    for _, header in ipairs(window.headers) do
        local arrow = header.arrow
        if header.column.key == sortKey then
            local textOffset = header.label:GetStringWidth() + SORT_ARROW_GAP
            arrow:ClearAllPoints()
            if header.column.justify == "LEFT" then
                arrow:SetPoint("LEFT", header, "LEFT", textOffset, 0)
            else
                arrow:SetPoint("RIGHT", header, "RIGHT", -textOffset, 0)
            end
            if sortAscending then
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

--- Sorts by a column when its header is clicked. Clicking the sorted column again
--- reverses the order; a new column starts in its natural direction (ascendingFirst).
---@param column table The clicked entry from COLUMNS
local function onHeaderClick(column)
    if sortKey == column.key then
        sortAscending = not sortAscending
    else
        sortKey = column.key
        sortAscending = column.ascendingFirst == true
    end
    updateHeaders()
    refreshList()
end

--- Creates one clickable column header with its label and (hidden) sort arrow.
--- Clicks run through ns.SafeCall, so errors are logged.
---@param parent Frame The window
---@param column table An entry from COLUMNS
---@return Button header
local function createHeader(parent, column)
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
        ns.SafeCall(onHeaderClick, column)
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
--- Typing in the search box refreshes the list (through ns.SafeCall, so errors are
--- logged). HookScript keeps the template's own OnTextChanged, which shows and hides
--- the "Search" placeholder.
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

--- Creates the column headers, the scrolling list and the empty-list message.
--- Uses Blizzard's ScrollBox with a linear view: only visible rows have frames, which
--- are reused as the list scrolls (initRow fills them in).
---@param frame Frame The window
local function createList(frame)
    frame.headers = {}
    for _, column in ipairs(COLUMNS) do
        frame.headers[#frame.headers + 1] = createHeader(frame, column)
    end

    frame.scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
    frame.scrollBox:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, HEADER_OFFSET_Y - HEADER_HEIGHT)
    frame.scrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(PADDING + SCROLLBAR_GAP), PADDING)

    local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", frame.scrollBox, "TOPRIGHT", SCROLLBAR_OFFSET_X, 0)
    scrollBar:SetPoint("BOTTOMLEFT", frame.scrollBox, "BOTTOMRIGHT", SCROLLBAR_OFFSET_X, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", initRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(frame.scrollBox, scrollBar, view)

    frame.emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.emptyText:SetPoint("CENTER", frame.scrollBox, "CENTER")
    frame.emptyText:Hide()
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
--- Runs through ns.SafeCall (see getWindow), and so does each tick.
---@param frame Frame The window
local function onWindowShow(frame)
    updateStatus()
    updateHeaders()
    refreshList()
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
        createList(window)
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
