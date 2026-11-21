--[[
    BelowVendor.lua
    Builds the "Below Vendor" results: for each item variant, the lowest unit price
    that is below what a vendor pays, and how many units are listed at that price.

    Scanner.lua reads the auctions and calls ns.AddVendorListing once per auction
    (with the auction's variant, see Scanner.lua's getVariant). This file only
    decides what goes into a row. It knows nothing about scans, saving or the window.
]]

local _, ns = ...

-- Hot path: called once per auction, up to ~300,000 times per scan.
local compareUnitPrice = ns.CompareUnitPrice

--- Adds one auction to its variant's row if its buyout is below the vendor value.
--- Each variant keeps only its lowest unit price and the units listed at exactly that
--- price: a cheaper auction replaces the price and quantity, one at the same price adds
--- its units, and a dearer one is ignored. The price is kept as one auction's
--- (buyout, count) pair and compared with ns.CompareUnitPrice, so fractional unit
--- prices compare exactly. Variants that can't be sold to a vendor (price 0) never
--- pass the first check.
---@param rows table Rows being built, rows[variant.key] = row (modified in place)
---@param variant table From Scanner.lua's getVariant: key, itemID, name, link, quality, bulk, vendorPrice
---@param count number Units in the auction (more than 0)
---@param buyout number Buyout for the whole auction, in copper (more than 0)
function ns.AddVendorListing(rows, variant, count, buyout)
    local unitVendorPrice = variant.vendorPrice
    if unitVendorPrice * count <= buyout then
        return
    end

    local row = rows[variant.key]
    if not row then
        rows[variant.key] = {
            itemID = variant.itemID,
            name = variant.name,
            link = variant.link,            -- only for suffixed variants ("of the Monkey")
            quality = variant.quality,
            bulk = variant.bulk,            -- bought by quantity, not per listing
            vendorPrice = unitVendorPrice,  -- copper per unit
            lowestBuyout = buyout,          -- an auction at the lowest unit price:
            lowestCount = count,            --   unit price = lowestBuyout / lowestCount
            quantity = count,               -- units listed at that unit price
        }
        return
    end

    local difference = compareUnitPrice(buyout, count, row.lowestBuyout, row.lowestCount)
    if difference < 0 then
        row.lowestBuyout, row.lowestCount, row.quantity = buyout, count, count
    elseif difference == 0 then
        row.quantity = row.quantity + count
    end
end
