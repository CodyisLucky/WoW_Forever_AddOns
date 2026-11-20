# Changelog

## 0.2.0
- The nearest saved marker within range is shown in the world as a white square, drawn on the game's navigation frame. It stays over the marker's spot and sits at the screen edge when off-screen.
- Settings panel (Options > AddOns, or `/fgm config`): tracking mode (only when nothing else is tracked, take over and restore, or manual), maximum range (10–500 yards, default 100), and show at screen edge when off-screen.
- `/fgm show` and `/fgm hide` for Manual tracking mode.
- The player's own map pin and tracked quest are saved while a marker is shown and restored afterwards, including across relogs.
- `ns.RegisterEvent` supports several handlers per event, and `ns.UnregisterEvent(event, handler)` removes one specific handler.

## 0.1.0
- Initial version: `/fgm mark` saves the player's open-world position (map and world coordinates) as a persistent, account-wide marker and prints it.
- `/fgm remove <id>` deletes a marker.
- `/fgm debug` toggles diagnostic output. It logs which position API failed, or the raw saved values of a new marker.
