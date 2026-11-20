# Forever Ground Markers

Target: World of Warcraft: Forever (interface 16001). Not compatible with Retail, Classic, or Midnight.

Save persistent markers at your location, in the spirit of RuneLite's Ground Markers. Markers are saved account-wide and stay until you remove them.

**Current status (0.2.0):** markers are saved with `/fgm mark`, and the nearest one in range is shown in the world as a white square, similar to a ping. Open world only: position isn't available to addons inside dungeons, raids, battlegrounds, or arenas.

## Slash commands
- `/fgm` or `/fgm help`: list commands
- `/fgm mark`: save a marker at your current position and print it
- `/fgm remove <id>`: delete a saved marker
- `/fgm debug`: toggle diagnostic output (off by default, saved between sessions)
- `/fgm config`: open the settings panel (Options > AddOns > Forever Ground Markers)
- `/fgm show` / `/fgm hide`: show or hide the marker, in Manual tracking mode only

Macro: create a macro with the single line `/fgm mark` and put it on an action bar.

Example output:

```
Ground Markers: Marker #3 saved: Elwynn Forest - Goldshire (42.15, 65.87)
```

## In-world display

The nearest saved marker within range (default 100 yards) is drawn as a white square over its spot in the world. When the spot is off-screen, the square sits at the screen edge pointing toward it (configurable).

**Only one marker is visible at a time.** The square is drawn on the game's navigation frame, which the engine keeps over the single tracked destination. Showing a marker therefore:
- places the game's map pin at the marker, so it also appears on the minimap and World Map,
- makes that pin the tracked destination, which replaces a tracked quest or your own pin.

The **tracking mode** setting decides how that's shared:

| Mode | Behavior |
|---|---|
| Only when nothing else is tracked (default) | Markers appear only while you aren't tracking a quest or your own map pin |
| Take over, then restore | Markers replace your tracked quest or pin while shown, which come back afterwards |
| Manual | Markers appear only after `/fgm show`, until `/fgm hide`. Your tracking is restored afterwards |

In every mode, if you track a quest or place a pin while a marker is shown, your choice wins. The addon backs off from that marker until a different marker becomes the nearest, or you leave range and come back.

## Settings panel

Options > AddOns > Forever Ground Markers, or `/fgm config`:
- **Tracking mode**: dropdown, see the table above
- **Maximum range**: 10–500 yards, default 100
- **Show at screen edge when off-screen**: default on

## Saved settings
- `ForeverGroundMarkersDB.markers`: saved markers, keyed by ID
- `ForeverGroundMarkersDB.nextMarkerId`: the ID the next marker will get
- `ForeverGroundMarkersDB.debug`: whether debug output is on
- `ForeverGroundMarkersDB.trackingMode`: `"yield"`, `"restore"` or `"manual"`
- `ForeverGroundMarkersDB.maxRange`: maximum display range in yards
- `ForeverGroundMarkersDB.showOffscreen`: keep the marker at the screen edge when off-screen
- `ForeverGroundMarkersDB.manualShown`: Manual mode only, whether `/fgm show` is active
- `ForeverGroundMarkersDB.waypoint`: present only while the addon owns the map pin. It records the shown marker, the pin the addon placed, and what you were tracking before, so that can be restored even after a relog

## Code overview

Review document for this addon. Update it in the same change as the code.

### Files (in .toc load order)

#### `ForeverGroundMarkers.lua`
Core: event frame, SavedVariables setup, and the `/fgm` command dispatcher. Loads first so the other files can use its `ns` functions.

| Function | Scope | Purpose |
|---|---|---|
| `applyDefaults(db, defaults)` | local | Recursively merges defaults into saved data without overwriting existing values |
| `ns.Print(msg)` | public | Prints a message to chat with the "Ground Markers:" prefix |
| `ns.Debug(msg)` | public | Prints a `[debug]`-tagged message only while debug mode is on |
| `dispatchEvent(_, event, ...)` | local | OnEvent script that calls every handler registered for the event, in registration order |
| `ns.RegisterEvent(event, handler)` | public | Adds a handler for an event. Several files can listen to the same event |
| `ns.UnregisterEvent(event, handler)` | public | Removes one specific handler. Stops listening when none remain |
| `onAddonLoaded(loadedName)` | local | Creates and fills `ForeverGroundMarkersDB`, exposes it as `ns.db`, then calls `ns.InitSettings` |
| `onPlayerLogin()` | local | Prints the loaded version from the `.toc` |
| `showHelp()` | local | Prints all `ns.commands` entries, sorted by name |
| `toggleDebug()` | local | `/fgm debug` handler, flips and saves `ns.db.debug` |
| `handleSlashCommand(input)` | local | Splits `/fgm <command> <args>` and calls the matching `ns.commands` handler |

Also exposes `ns.defaults`, `ns.commands`, `ns.SLASH_COMMAND`, and `ns.TRACKING_MODES` (`YIELD`, `RESTORE`, `MANUAL`).

#### `Position.lua`
Reads the player's location and returns plain data. It doesn't save or print anything, so it can be reused for distance and map features later.

| Function | Scope | Purpose |
|---|---|---|
| `getDistinctSubZone(zoneName)` | local | Returns the subzone name, or nil if it's empty or the same as the zone |
| `ns.GetDistance(x1, y1, x2, y2)` | public | Flat distance in yards between two world positions |
| `ns.GetPlayerPosition()` | public | Returns `position` (map + world coordinates, zone, subzone), or `nil, reason` |

Also exposes `ns.POSITION_UNAVAILABLE`, the reason codes. There is one per failure point, so debug output shows exactly which API came back empty:

| Code | Meaning |
|---|---|
| `instanced` | `IsInInstance()` is true, so position APIs are restricted |
| `no_map` | `C_Map.GetBestMapForUnit` returned nil |
| `no_map_position` | `C_Map.GetPlayerMapPosition` returned nil |
| `no_world_position` | `UnitPosition` returned nil |

#### `Markers.lua`
Marker storage and the `mark` / `remove` commands.

| Function | Scope | Purpose |
|---|---|---|
| `formatLocation(marker)` | local | Builds `Zone - Subzone (x, y)` text with coordinates as percentages to 2 decimal places |
| `describeMarkerForDebug(id, marker)` | local | One-line dump of a marker's raw values (4-decimal map coordinates, world coordinates, IDs) for debug output |
| `ns.AddMarker(position)` | public | Saves a new marker from a position and returns its ID and data |
| `ns.RemoveMarker(id)` | public | Deletes a marker and returns whether it existed |
| `ns.FindNearestMarker(position, maxRange)` | public | Returns the nearest marker on the same continent within range: `id, marker, distance` |
| `markCurrentPosition()` | local | `/fgm mark` handler. In debug mode it logs the failure reason code or the raw saved values |
| `removeMarkerCommand(args)` | local | `/fgm remove <id>` handler, validates the ID |

#### `Waypoint.lua`
Owns the addon's use of the game's single map pin and tracked destination: taking over, detecting when the player takes it back, and restoring.

| Function | Scope | Purpose |
|---|---|---|
| `readUserPin()` | local | Current map pin as a plain `{ mapId, x, y }` table, or nil |
| `pinsMatch(a, b)` | local | Whether two pins are on the same map within `PIN_MATCH_TOLERANCE` |
| `placePin(pin)` | local | Places the map pin if the map allows pins |
| `captureTracking()` | local | Records the player's pin, whether it was tracked, and their tracked quest |
| `ns.IsWaypointOwned()` | public | Whether the addon currently owns the pin |
| `ns.GetWaypointMarkerId()` | public | ID of the marker being shown, or nil |
| `ns.HasLostWaypoint()` | public | Whether the player moved or cleared the pin, or tracked something else |
| `ns.TakeOverWaypoint(markerId, marker)` | public | Points the pin and tracking at a marker, saving the player's state on first take-over |
| `ns.ReleaseWaypoint(restoreTracking)` | public | Removes the addon's pin, puts the player's pin back, and optionally restores their tracking |

#### `Display.lua`
Draws the white square on the game's navigation frame.

| Function | Scope | Purpose |
|---|---|---|
| `anchorToNavigationFrame()` | local | Anchors the square to `C_Navigation.GetFrame()`, if it exists |
| `updateVisibility()` | local | OnUpdate: sets the square's alpha based on screen position and the off-screen setting |
| `ns.ShowMarkerDisplay()` | public | Shows the square, anchoring it first |
| `ns.HideMarkerDisplay()` | public | Hides the square |
| `onNavigationFrameCreated()` | local | Re-anchors when the game creates a new navigation frame |
| `onNavigationFrameDestroyed()` | local | Detaches and hides when the navigation frame goes away |

#### `Beacon.lua`
Decides which marker is shown and when. Runs `update` every 0.5 seconds.

| Function | Scope | Purpose |
|---|---|---|
| `isDisplayAllowedByMode()` | local | False only in Manual mode without `/fgm show` |
| `stopShowing()` | local | Hides the square and releases tracking with restore |
| `handlePlayerTrackingChange()` | local | Backs off (release without restore) when the player took tracking back |
| `findNearestInRange()` | local | Nearest marker in range of the player, or nil (including in instances) |
| `update()` | local | The main loop: back-off, nearest marker, mode rules, take over, show |
| `onPlayerLogin()` | local | Restores tracking left over from the last session, then starts the loop |
| `setManualShown(shown)` | local | `/fgm show` and `/fgm hide` handler, Manual mode only |

#### `Config.lua`
The settings panel, built with Blizzard's `Settings` API. Each control is bound directly to a key in `ns.db`.

| Function | Scope | Purpose |
|---|---|---|
| `getTrackingModeOptions()` | local | Dropdown choices: value, label, tooltip |
| `formatYards(value)` | local | Slider label, e.g. "100 yd" |
| `addTrackingModeDropdown(category)` | local | Tracking mode dropdown, bound to `trackingMode` |
| `addRangeSlider(category)` | local | 10–500 yard slider, bound to `maxRange` |
| `addOffscreenCheckbox(category)` | local | Checkbox bound to `showOffscreen` |
| `ns.InitSettings()` | public | Registers the page and its controls; called from `ADDON_LOADED` |
| `openSettings()` | local | `/fgm config` handler |

### Saved marker format

```lua
ForeverGroundMarkersDB.markers[id] = {
    mapId = 37,              -- uiMapID of the most specific map at that spot
    mapX = 0.4215,           -- 0-1 across that map (displayed as 42.15)
    mapY = 0.6587,
    worldX = -9464.2,        -- yards, from UnitPosition
    worldY = 62.1,
    instanceId = 0,          -- continent/instance ID from UnitPosition
    zoneName = "Elwynn Forest",
    subZoneName = "Goldshire", -- nil when there is no distinct subzone
    createdAt = 1790000000,  -- time() when saved
}
```

The example values are illustrative, not real measurements.

Notes on world coordinates, confirmed in-game in Orgrimmar:

- **Axes.** The game's native X axis points north and its Y axis points west. `UnitPosition` returns the north value first, so the addon stores it as `worldY` and the west value as `worldX`. This matches the HereBeDragons convention (`local y, x = UnitPosition("player")`). As a result, `worldY` decreases when moving south and `worldX` decreases when moving east.
- **Precision.** Positions are accurate to about 0.1 yard. Saved values such as `1598.300048828125` are just 1598.3; the game stores positions at lower floating-point precision and Lua prints the full expansion. Round to one decimal for display.
- **Map and world agree.** Deriving Orgrimmar's size from four markers gave about 935 × 1395 yards, matching its known map size, so either coordinate system can be converted to the other.
- **Loop with `pairs`.** `markers` has gaps where markers were removed (the saved file shows them as `nil,`). Any code that walks the markers must use `pairs`, since `ipairs` stops at the first gap.

### Events
- `ADDON_LOADED`: initialize SavedVariables and the settings panel (unregistered after first use)
- `PLAYER_LOGIN`: print the loaded version (core), and restore leftover tracking then start the update loop (`Beacon.lua`)
- `NAVIGATION_FRAME_CREATED` / `NAVIGATION_FRAME_DESTROYED`: re-anchor or detach the square (`Display.lua`)

### SavedVariables
- `ForeverGroundMarkersDB` (account-wide): see Saved settings above

### Design decisions
- **Both coordinate systems are saved.** Map coordinates match what players see and share. World coordinates, in yards, allow real distance math later (e.g. "marker is 30 yards ahead") and don't depend on which map is active.
- **Position reading is separate from marker storage.** `Position.lua` only reads, and `Markers.lua` only stores. Future features (distance display, map pins, click-to-place) can reuse `ns.GetPlayerPosition` without saving anything.
- **`ns.AddMarker` copies fields explicitly** instead of saving the position table as-is. That keeps the saved format defined in one place and stops unrelated fields from ending up in SavedVariables.
- **IDs are never reused.** `nextMarkerId` only goes up, so `/fgm remove 3` can't delete a newer marker that happened to take a removed marker's number.
- **Instances are checked with `IsInInstance()` first.** The position APIs return nil there anyway, but checking up front gives a clear message instead of a generic failure.
- **Failure reasons are codes, not messages.** `Position.lua` returns a specific code and never prints. `Markers.lua` maps codes to player-facing text, and any code without its own text gets a generic fallback message. Debug mode shows the raw code. New failure points only need a new code, and a message only if players need a different explanation.
- **Debug output goes through `ns.Debug`**, which reuses `ns.Print` and is off by default. It checks `ns.db` first, so calling it before `ADDON_LOADED` is harmless.
- **No `pcall` wrappers.** WoW already reports Lua errors with file, line and stack trace (`/console scriptErrors 1` or BugSack). Catching errors would hide that.
- **Several handlers per event.** `ns.RegisterEvent` keeps a list per event, so each file registers what it needs without the core knowing about features. Lists are replaced rather than edited when a handler is removed, so a handler that unregisters itself mid-dispatch (like `onAddonLoaded`) can't make the loop skip the next one.
- **The square is drawn on the game's navigation frame.** Addons can't turn a world position into a screen position themselves. `C_Navigation.GetFrame()` is the one engine-positioned frame open to addons, and Blizzard's own waypoint marker (`SuperTrackedFrame`) anchors to it the same way. The cost is one visible marker at a time, and borrowing the map pin and tracking.
- **Forever reports the navigation state as Invalid (0)**, which is why Blizzard's own waypoint icon is invisible there. The frame is still positioned correctly (confirmed in-game in Durotar), so the square ignores the state and only checks `HasValidScreenPosition` and `WasClampedToScreen`.
- **Tracking changes are detected by polling, not events.** Each update, `ns.HasLostWaypoint` checks that our pin is still in place and tracked. Events would also fire for the addon's own calls and could arrive a frame later, making them easy to mistake for the player's.
- **Pins are compared with a tolerance** (`PIN_MATCH_TOLERANCE`, about 1.4 yards on a zone map), in case the game rounds a stored pin's position.
- **Ownership is saved in SavedVariables** (`ns.db.waypoint`). If the session ends while a marker is shown, the next login restores the player's pin and quest before anything else.
- **The player's own pin is restored even when backing off**, unless they've placed a new one. Only tracking is left alone, because they just chose something else to track.
- **Settings are read on each update** instead of through change callbacks, so there's one place that reacts to them (`update` in `Beacon.lua`).
- **Slash subcommands live in a table** (`ns.commands`), so each file registers its own commands and the dispatcher never changes.

## Future improvements

### Place markers at the cursor's location in the 3D world (blocked)

Goal: place a marker on the ground under the mouse cursor, the same way a ping is placed. It should be triggered by a macro command unless a click is required.

Status: not possible with the addon API as of Forever 1.60.1 / UI source 12.1.0.69933. Revisit whenever Blizzard patches the ping or map APIs.

What was found in Blizzard's ping code (`Blizzard_PingUI/Blizzard_PingManager.lua`):

1. `GetCursorPosition()` returns only the cursor's 2D screen position in pixels. Addons can call this.
2. `C_PingSecure.SetHitTestPingTarget(cursorX, cursorY)` makes the engine trace from the camera through that pixel to the ground. The hit point is stored inside the engine, and the function only returns a status code (`Enum.PingSetTargetState`), never coordinates.
3. `C_PingSecure.SendHitTestPing(type)` sends the stored point to the server, again without exposing it.
4. The engine then creates the on-screen ping icon and keeps it over that point. The UI code only receives the icon frame.

`C_PingSecure` is declared `Environment = "SecureOnly"` in the generated API docs, so it doesn't exist for addon code at all. A search of all the generated API docs found no function that converts screen to world, hit-tests, or returns a world position from the cursor. The other routes also fail:
- `UnitPosition("mouseover")` works only for you and your group members.
- There's no API for the camera's direction or terrain height, so the point can't be calculated.
- `/wm [@cursor]` world markers are placed and drawn by the engine: 8 at most, not saved, and addons can't read or restore their positions.

What to check when revisiting:
- `/dump C_PingSecure` in-game. It should be `nil`; anything else is worth investigating.
- Patch notes and API diffs (e.g. warcraft.wiki.gg "Patch X/API changes") for new `C_Ping`, `C_Map`, or world-cursor functions that return a position.
- Latest `Blizzard_PingUI` source in the [wow-ui-source mirror](https://github.com/Gethe/wow-ui-source).

Possible fallbacks that were considered and set aside for now: clicking the minimap, clicking the World Map, and marking at an offset from the player's position via the macro (e.g. `/fgm mark 5` for 5 yards ahead).

## Manual testing

### Step 1 checks (open world)

Status: steps 1–9, 11 and 13 passed in the Forever client (Orgrimmar). Steps 10 and 12 and the instance run of the API probe lines are **pending** until instance access is available.

1. Copy the `ForeverGroundMarkers` folder into the Forever `Interface/AddOns/` folder and restart the client.
2. Enable "Forever Ground Markers" in the AddOns list at character select.
3. `/console scriptErrors 1` to show Lua errors.
4. On login, expect `Ground Markers: v<version> loaded. Type /fgm help for commands.`
5. `/fgm`: expect the list of commands, sorted by name.
6. `/fgm mark` in an open-world zone: expect `Marker #1 saved: <Zone> - <Subzone> (x, y)`. Compare the coordinates with the world map.
7. Move and `/fgm mark` again: expect `Marker #2 ...`.
8. `/fgm remove 1`: expect `Marker #1 removed.`. `/fgm remove 1` again: expect `No marker #1.`. `/fgm remove abc`: expect the usage message.
9. `/reload`, then `/dump ForeverGroundMarkersDB`: marker #2 should still be there and `nextMarkerId` should be 3.
10. Enter any instance and `/fgm mark`: expect the "instanced area" message.
11. `/fgm debug`: expect `Debug mode on.`. Then `/fgm mark` in the open world: expect the normal saved line plus `Ground Markers: [debug] Marker #N: mapId=... mapX=... worldX=... instanceId=...`.
12. With debug on, `/fgm mark` inside an instance: expect the instanced message plus `[debug] GetPlayerPosition failed: instanced`.
13. `/reload`: debug should still be on. `/fgm debug`: expect `Debug mode off.`, and later marks show no `[debug]` lines.

### Step 2 checks (in-world display)

Status: first pass in the Forever client. Steps 1, 2, 9 and 10–19 passed. Step 3 **failed**: no marker appeared until a map pin was placed and removed. Open issues in Default mode: after tracking and then untracking a quest, the marker doesn't come back until `/reload`; placing a pin by hand while a marker is shown puts it in the wrong place until the pin is clicked. Steps 4–6 are **pending**.

Use an open area with a few markers about 30–80 yards apart. Turn on `/fgm debug` to see which marker is shown and why.

Setup
1. Login shows `v0.2.0 loaded`. No Lua errors (`/console scriptErrors 1`).
2. `/fgm config` opens the settings page with the tracking mode dropdown, range slider and off-screen checkbox. Each control shows its tooltip.

Default mode: only when nothing else is tracked
3. Untrack any quest and clear your pin (`/run C_Map.ClearUserWaypoint()`). Within 100 yards of a marker, a white square appears over it. `[debug] Showing marker #N`.
4. Walk toward a different marker until it's the nearest: the square moves to it.
5. Turn away: the square sits at the screen edge. Turn off the off-screen setting: it disappears while off-screen and returns when facing the spot.
6. Walk beyond 100 yards from all markers: the square and the pin disappear.
7. Track a quest (click it in the objective tracker): the square disappears. `[debug] Player changed tracking; backing off marker #N`. The quest stays tracked.
8. While a quest is tracked, walk into range of another marker: nothing appears.
9. Lower the range slider below your distance to the nearest marker: the square disappears on the next update.

Take over, then restore
10. Switch the mode. Track a quest, then walk into range: the square appears and the quest is no longer tracked.
11. Walk out of range: the square disappears and the quest is tracked again.
12. Place your own map pin (Ctrl-click the World Map) and track it, then walk into range: the square appears. Walk out: your pin is back where it was, and tracked.
13. In range with the square showing, click a quest to track it: the square disappears and the quest stays tracked (back-off). Walk out of range and back in: the square returns.

Manual
14. Switch the mode. In range, nothing appears. `/fgm show`: the square appears. `/fgm hide`: it disappears and your previous tracking is restored.
15. `/fgm show`, then `/reload`: the square is still shown after reload.
16. Switch to another mode and type `/fgm show`: expect the "only apply in Manual tracking mode" message.

Persistence and edge cases
17. With a quest tracked and a marker shown in Take-over mode, log out and back in: the quest is tracked again right after login, then the marker takes over again if in range.
18. `/fgm remove <id>` for the marker being shown: the square moves to the next nearest marker, or disappears.
19. `/fgm mark` while standing next to the shown marker: the new marker (distance 0) becomes the shown one.

### API probe lines (run inside and outside an instance)
Use these to confirm how the Forever client behaves. Paste the results back so we can plan instance support.

```
/dump select(4, GetBuildInfo())
/dump IsInInstance()
/dump C_Map.GetBestMapForUnit("player")
/dump C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player")
/dump UnitPosition("player")
/dump GetPlayerFacing()
```

Expected outside instances: all return values. Expected inside: `GetBestMapForUnit` returns a map ID, and the last three return nil. If `GetPlayerMapPosition` errors because the map ID is nil, that's also informative.
