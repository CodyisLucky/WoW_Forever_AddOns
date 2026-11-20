# Changelog

## 0.1.0
- Initial version: reads full Auction House scans started by any addon (e.g. Gathercraft) and lists items whose buyout is below their vendor price.
- Movable results window that opens and closes with the Auction House. One row per item, with total quantity, buyout, vendor value and profit. Sortable columns (default: highest profit, ties to lowest buyout) and name search.
- Last scan's results are saved per realm, with a "scanned X min ago" status line.
- Fallback Scan button and `/vsnipe scan`, with a 15-minute cooldown countdown.
- `/vsnipe` toggles the window. `/vsnipe help` and `/vsnipe debug` are also available.
- Saved log (last 500 lines, in `ForeverVendorSnipeLog`): scans, timings, chat messages and Lua errors with stack traces, for sending back when something goes wrong. `/vsnipe clearlog` empties it.
