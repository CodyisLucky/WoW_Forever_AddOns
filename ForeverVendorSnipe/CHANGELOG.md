# Changelog

## 0.6.1
- Fixed random-suffix items sometimes showing without their suffix ("Opulent Gloves" instead of "Opulent Gloves of Spirit"). The full scan doesn't always have an auction's link straight away, and those auctions were all merged into one plain-name row, so Undercuts compared different suffixes. They now wait up to 60 seconds after reading for their link.
- An auction that still has no link after that is shown on Below Vendor under the plain name and left out of Undercuts.
- Closing the Auction House while item data is still loading now finishes the scan straight away.

## 0.6.0
- New **Listed** column on the Undercuts tab: how many units of the item are listed in total, across all its auctions.
- The results window is 20 pixels wider to fit Listed. This also fixes the right edge of Below Vendor's Profit column being cut off.
- Undercuts results saved by 0.5.0 are kept and show "—" in Listed until the next scan.

## 0.5.0
- New **Waylaid Crates** tab: all 30 Waylaid Crates with their required level, the Merchant's Favor each gives when turned in, the cheapest crate's price, and the cheapest bundle to fill one. **Fill / Favor** is that bundle's cost per Favor, and **Total / Favor** is (crate price + bundle cost − turn-in money) per Favor. Fill costs add up the cheapest listings until the bundle is complete. Hover a crate for its reward and every bundle's whole cost. Prices that can't be worked out show "—". Default sort is lowest Total / Favor first.
- Artisan crate rewards (20 / 40 Favor) are assumed from the other tiers until confirmed in game.
- Search on the Waylaid Crates tab also matches the items that fill a crate.
- New `/vsnipe crates`: with "Waylaid Crate" searched in the Auction House, writes every crate in the results to the log (ID, required level, listings, cheapest price, and the tooltip's fill bundles), for keeping the crate list up to date.
- The results window no longer always covers your bags. It shares their layer now, so whichever you clicked last is on top.
- Saved results from 0.4.x are kept. The Waylaid Crates tab fills in with the next scan.

## 0.4.0
- New **Undercuts** tab: the 200 items whose cheapest auction is furthest below the second cheapest auction, per unit, sorted by the difference. Columns: Item, Lowest, 2nd lowest, Difference.
- The window now has two tabs along the bottom, **Below Vendor** and **Undercuts**. Search, Scan and the status line are shared, and the window reopens on the last tab used.
- Random-suffix items ("of the Monkey", "of the Tiger") are now listed separately on both tabs, with the suffix in the name and its stats in the tooltip. Before, all suffixes of an item were merged into one row without the suffix.
- Search matches the suffix too.
- Results saved by 0.3.x are discarded once, because the saved format changed. The next scan fills both tabs.

## 0.3.1
- Cheaper handling of repeat scan events. The game sends about 96,000 of them per full scan, and each is now dropped with one time comparison instead of a saved-data lookup.

## 0.3.0
- Items bought in bulk on the Auction House (stackable items, bought by quantity) have their name shown in light blue. Items bought one listing at a time keep their quality color.
- Results saved by 0.2.0 have no bulk information and show quality colors until the next scan.

## 0.2.0
- Buyout, Vendor and Profit are now per item. Each row shows the item's lowest below-vendor unit price, and Qty is the number of units listed at that price.
- Default sort is highest profit per item, with ties going to the lowest buyout.
- Qty shows units only, without the listing count in brackets.
- Fixed item names sometimes missing. The name is now read together with the vendor price, and any row saved without a name gets it filled in.
- Results saved by 0.1.0 are discarded once, because the saved format changed. The next scan fills the window again.

## 0.1.0
- Initial version: reads full Auction House scans started by any addon (e.g. Gathercraft) and lists items whose buyout is below their vendor price.
- Movable results window that opens and closes with the Auction House. One row per item, with total quantity, buyout, vendor value and profit. Sortable columns (default: highest profit, ties to lowest buyout) and name search.
- Last scan's results are saved per realm, with a "scanned X min ago" status line.
- Fallback Scan button and `/vsnipe scan`, with a 15-minute cooldown countdown.
- `/vsnipe` toggles the window. `/vsnipe help` and `/vsnipe debug` are also available.
- Saved log (last 500 lines, in `ForeverVendorSnipeLog`): scans, timings, chat messages and Lua errors with stack traces, for sending back when something goes wrong. `/vsnipe clearlog` empties it.
