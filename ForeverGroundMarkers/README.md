# Forever Ground Markers

Target: World of Warcraft: Forever (interface 16001). Not compatible with Retail, Classic, or Midnight.

Save persistent markers at your location, in the spirit of RuneLite's Ground Markers. Markers are saved account-wide and stay until you remove them.

**Current status (0.1.0):** position capture only. Markers are saved and can be removed, but aren't drawn anywhere yet. Open world only: position isn't available to addons inside dungeons, raids, battlegrounds, or arenas.

## Slash commands
- `/fgm` or `/fgm help`: list commands
- `/fgm mark`: save a marker at your current position and print it
- `/fgm remove <id>`: delete a saved marker
- `/fgm debug`: toggle diagnostic output (off by default, saved between sessions)

Macro: create a macro with the single line `/fgm mark` and put it on an action bar.

Example output:

```
Ground Markers: Marker #3 saved: Elwynn Forest - Goldshire (42.15, 65.87)
```

## Saved settings
- `ForeverGroundMarkersDB.markers`: saved markers, keyed by ID
- `ForeverGroundMarkersDB.nextMarkerId`: the ID the next marker will get
- `ForeverGroundMarkersDB.debug`: whether debug output is on

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
| `dispatchEvent(_, event, ...)` | local | OnEvent script that routes each event to its registered handler |
| `ns.RegisterEvent(event, handler)` | public | Registers one handler per event on the shared event frame |
| `ns.UnregisterEvent(event)` | public | Removes an event handler |
| `onAddonLoaded(loadedName)` | local | Creates and fills `ForeverGroundMarkersDB`, exposes it as `ns.db` |
| `onPlayerLogin()` | local | Prints the loaded version from the `.toc` |
| `showHelp()` | local | Prints all `ns.commands` entries, sorted by name |
| `toggleDebug()` | local | `/fgm debug` handler, flips and saves `ns.db.debug` |
| `handleSlashCommand(input)` | local | Splits `/fgm <command> <args>` and calls the matching `ns.commands` handler |

Also exposes `ns.defaults`, `ns.commands`, and `ns.SLASH_COMMAND`.

#### `Position.lua`
Reads the player's location and returns plain data. It doesn't save or print anything, so it can be reused for distance and map features later.

| Function | Scope | Purpose |
|---|---|---|
| `getDistinctSubZone(zoneName)` | local | Returns the subzone name, or nil if it's empty or the same as the zone |
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
| `markCurrentPosition()` | local | `/fgm mark` handler. In debug mode it logs the failure reason code or the raw saved values |
| `removeMarkerCommand(args)` | local | `/fgm remove <id>` handler, validates the ID |

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

### Events
- `ADDON_LOADED`: initialize SavedVariables (unregistered after first use)
- `PLAYER_LOGIN`: print the loaded version

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
- **Slash subcommands live in a table** (`ns.commands`), so each file registers its own commands and the dispatcher never changes.

## Manual testing

### Step 1 checks (open world)
1. Copy the `ForeverGroundMarkers` folder into the Forever `Interface/AddOns/` folder and restart the client.
2. Enable "Forever Ground Markers" in the AddOns list at character select.
3. `/console scriptErrors 1` to show Lua errors.
4. On login, expect `Ground Markers: v0.1.0 loaded. Type /fgm help for commands.`
5. `/fgm`: expect the list of `debug`, `help`, `mark`, `remove <id>`.
6. `/fgm mark` in an open-world zone: expect `Marker #1 saved: <Zone> - <Subzone> (x, y)`. Compare the coordinates with the world map.
7. Move and `/fgm mark` again: expect `Marker #2 ...`.
8. `/fgm remove 1`: expect `Marker #1 removed.`. `/fgm remove 1` again: expect `No marker #1.`. `/fgm remove abc`: expect the usage message.
9. `/reload`, then `/dump ForeverGroundMarkersDB`: marker #2 should still be there and `nextMarkerId` should be 3.
10. Enter any instance and `/fgm mark`: expect the "instanced area" message.
11. `/fgm debug`: expect `Debug mode on.`. Then `/fgm mark` in the open world: expect the normal saved line plus `Ground Markers: [debug] Marker #N: mapId=... mapX=... worldX=... instanceId=...`.
12. With debug on, `/fgm mark` inside an instance: expect the instanced message plus `[debug] GetPlayerPosition failed: instanced`.
13. `/reload`: debug should still be on. `/fgm debug`: expect `Debug mode off.`, and later marks show no `[debug]` lines.

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
