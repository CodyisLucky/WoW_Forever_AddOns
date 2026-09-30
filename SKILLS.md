# SKILLS.md — WoW Forever AddOn Workflows

Step-by-step procedures for creating and maintaining addons in this repo.
Repo-wide rules (target version, API restrictions, conventions) live in [AGENTS.md](AGENTS.md). Follow them in every skill below.

All templates use `MyAddon` as the placeholder. Replace it everywhere (folder, `.toc` filename, SavedVariables, slash command, frame names) with the real addon name.

| Skill | Use when |
|---|---|
| 1. Create a new addon | Starting a new addon folder |
| 2. Add a feature | Adding events, slash commands, UI, or saved settings |
| 3. Add a settings panel | Exposing options in Game Menu > Options > AddOns |
| 4. Patch update | Forever interface number or APIs change |
| 5. Lint and verify | Before finishing any change |
| 6. Install locally for testing | Trying the addon in the Forever client |
| 7. Release | Cutting a version for distribution |
| 8. Debug an in-game error | A user reports a Lua error or broken behavior |

---

## 1. Create a new addon

Checklist:

```
- [ ] Ask Cody clarifying questions (see "Questions to ask before a new addon" below) and wait for answers
- [ ] Pick a unique PascalCase name (no spaces). Confirm no folder with that name exists.
- [ ] Create MyAddon/ at the repo root
- [ ] Create MyAddon/MyAddon.toc from the template
- [ ] Create MyAddon/MyAddon.lua from the template
- [ ] Create MyAddon/README.md (including Code overview) and MyAddon/CHANGELOG.md
- [ ] Add the addon to the root README.md list
- [ ] Run skill 5 (lint and verify)
- [ ] Leave everything uncommitted and post the review summary in chat
```

### Questions to ask before a new addon

Ask any of these that the request doesn't already answer, plus anything else that's unclear:

- **Purpose:** what problem does it solve? What does "done" look like for the first version?
- **Name:** addon name and slash command(s).
- **UI:** new frames, changes to existing Blizzard frames, or chat output only? Where on screen? Should it work with Edit Mode?
- **Settings:** which options are user-configurable? Account-wide or per-character? Default values?
- **Triggers:** which game events or user actions drive the behavior?
- **Combat:** does anything need to happen in combat? (That affects protected frames and secret values.)
- **Dependencies:** embedded libraries (Ace3, LibStub, LibDataBroker) or none? Any optional integration with other addons?
- **Scope:** anything explicitly out of scope for v0.1.0?

### `MyAddon.toc` template

```
## Interface: 16001
## Title: MyAddon
## Notes: One-line description shown in the AddOns list.
## Author: Cody
## Version: 0.1.0
## Category: Miscellaneous
## IconTexture: Interface\Icons\INV_Misc_QuestionMark
## SavedVariables: MyAddonDB
## SavedVariablesPerCharacter: MyAddonCharDB

MyAddon.lua
```

Rules:

- `## Interface:` is exactly `16001`. Never a comma list, never a Retail/Classic number.
- The filename is `MyAddon.toc`, not `MyAddon_Mainline.toc` or similar. (The client also recognizes a `MyAddon_Camelot.toc` Forever suffix; only use it if a plain `.toc` stops being picked up.)
- Files load top to bottom: `Libs/`, then `Locales/`, then `Utils.lua`, then `MyAddon.lua` (core: event frame, SavedVariables, commands), then feature files such as `Config.lua`.
- Remove `SavedVariables*` lines the addon doesn't use.
- Use a real in-game icon path for `IconTexture` or remove the line.

### `MyAddon.lua` template

Every function carries a summary block (what, how, when) per the documentation standard in AGENTS.md. Keep that when adapting the template.

```lua
--[[
    MyAddon.lua
    Main entry point. Owns the addon's single event frame, initializes
    SavedVariables, and registers slash commands. Other files add behavior
    by attaching handlers through ns.RegisterEvent and ns.commands.
]]

local addonName, ns = ...

local CHAT_PREFIX_COLOR = "|cff33ff99"

-- Account-wide defaults, merged into MyAddonDB on load.
ns.defaults = {
    enabled = true,
}

-- Per-character defaults, merged into MyAddonCharDB on load.
ns.charDefaults = {}

--- Merges default values into a SavedVariables table without overwriting user choices.
--- Walks `defaults` recursively. Missing keys are copied in, nested tables are created
--- and filled the same way, and existing user values are left untouched.
--- Called from ADDON_LOADED before anything reads the settings.
---@param db table The SavedVariables table to fill (modified in place)
---@param defaults table The default values to merge in
local function applyDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            -- Replace non-table values too, so a corrupted entry can't break nested lookups.
            if type(db[key]) ~= "table" then
                db[key] = {}
            end
            applyDefaults(db[key], value)
        elseif db[key] == nil then
            db[key] = value
        end
    end
end

--- Prints a message to the default chat frame, prefixed with the colored addon name.
--- Converts non-string values with tostring so callers can pass numbers or booleans.
---@param msg any The message to print
function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX_COLOR .. addonName .. "|r: " .. tostring(msg))
end

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

--- Routes a game event to the handler registered for it.
--- Installed as the event frame's OnEvent script. Events with no handler are ignored.
---@param event string The game event name
---@param ... any The event's payload, passed straight through to the handler
local function dispatchEvent(_, event, ...)
    local handler = eventHandlers[event]
    if handler then
        handler(...)
    end
end
eventFrame:SetScript("OnEvent", dispatchEvent)

--- Registers a handler for a game event on the addon's shared event frame.
--- One handler per event. Registering again replaces the previous handler.
---@param event string The game event name, e.g. "PLAYER_LOGIN"
---@param handler fun(...) Called with the event's payload
function ns.RegisterEvent(event, handler)
    eventHandlers[event] = handler
    eventFrame:RegisterEvent(event)
end

--- Stops listening for a game event and removes its handler.
---@param event string The game event name
function ns.UnregisterEvent(event)
    eventHandlers[event] = nil
    eventFrame:UnregisterEvent(event)
end

--- Initializes SavedVariables once this addon has loaded.
--- ADDON_LOADED fires for every addon, so this ignores the others, then unregisters
--- itself. Creates the saved tables on first run, merges defaults, exposes them as
--- ns.db / ns.charDb, and builds the settings panel if Config.lua is loaded.
---@param loadedName string Name of the addon that just loaded
local function onAddonLoaded(loadedName)
    if loadedName ~= addonName then
        return
    end
    ns.UnregisterEvent("ADDON_LOADED")

    MyAddonDB = MyAddonDB or {}
    MyAddonCharDB = MyAddonCharDB or {}
    applyDefaults(MyAddonDB, ns.defaults)
    applyDefaults(MyAddonCharDB, ns.charDefaults)
    ns.db = MyAddonDB
    ns.charDb = MyAddonCharDB

    if ns.InitSettings then
        ns.InitSettings()
    end
end

--- Announces the loaded version in chat once the player is in the world.
--- Reads the version from the .toc so it never drifts from the packaged version.
local function onPlayerLogin()
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
    ns.Print("v" .. tostring(version) .. " loaded. Type /myaddon help for commands.")
end

ns.RegisterEvent("ADDON_LOADED", onAddonLoaded)
ns.RegisterEvent("PLAYER_LOGIN", onPlayerLogin)

-- Slash subcommands. Each entry is { description, handler }; add new ones here
-- or from other files via ns.commands.name = { ... }.
ns.commands = {}

--- Prints every registered subcommand with its description.
--- Sorts by name first, because pairs() order is unpredictable and the list
--- should read the same every time.
local function showHelp()
    local names = {}
    for name in pairs(ns.commands) do
        names[#names + 1] = name
    end
    table.sort(names)

    ns.Print("Commands:")
    for _, name in ipairs(names) do
        ns.Print("  /myaddon " .. name .. " - " .. ns.commands[name].description)
    end
end

ns.commands.help = { description = "Show this list", handler = showHelp }

ns.commands.toggle = {
    description = "Enable or disable the addon",
    --- Flips the account-wide enabled setting and reports the new state.
    handler = function()
        ns.db.enabled = not ns.db.enabled
        ns.Print("Enabled: " .. tostring(ns.db.enabled))
    end,
}

ns.commands.config = {
    description = "Open the settings panel",
    --- Opens this addon's page in the Options panel, if Config.lua registered one.
    handler = function()
        if ns.settingsCategory then
            Settings.OpenToCategory(ns.settingsCategory:GetID())
        end
    end,
}

--- Handles /myaddon input by looking up the first word in ns.commands.
--- Splits the input into a command name and the rest of the line, which is passed
--- to the handler as arguments. Empty input shows help, and unknown commands say so.
---@param input string Everything typed after the slash command
local function handleSlashCommand(input)
    local name, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    name = name:lower()
    if name == "" then
        name = "help"
    end

    local command = ns.commands[name]
    if command then
        command.handler(rest)
    else
        ns.Print("Unknown command: " .. name .. ". Type /myaddon help.")
    end
end

SLASH_MYADDON1 = "/myaddon"
SlashCmdList.MYADDON = handleSlashCommand
```

When a second file needs `applyDefaults` or any other local helper, move it to `Utils.lua` (listed first in the `.toc`), expose it on `ns`, and update the README Code overview. Ask Cody first if it's unclear whether a helper belongs there.

### Per-addon `README.md` template

```markdown
# MyAddon

Target: World of Warcraft: Forever (interface 16001). Not compatible with Retail, Classic, or Midnight.

## What it does
- ...

## Slash commands
- `/myaddon` — help
- `/myaddon toggle` — enable/disable
- `/myaddon config` — open settings

## Saved settings
- `MyAddonDB.enabled` — ...

## Code overview

Review document for this addon. Update it in the same change as the code.

### Files (in .toc load order)

#### `MyAddon.lua`
Main entry point: event frame, SavedVariables setup, slash commands.

| Function | Scope | Purpose |
|---|---|---|
| `applyDefaults(db, defaults)` | local | Recursively merges defaults into saved settings without overwriting user values |
| `ns.Print(msg)` | public | Prints a prefixed message to chat |
| `ns.RegisterEvent(event, handler)` | public | Registers one handler per event on the shared event frame |
| `ns.UnregisterEvent(event)` | public | Removes an event handler |
| `handleSlashCommand(input)` | local | Dispatches `/myaddon <command>` to `ns.commands` |

### Events
- `ADDON_LOADED` — initialize SavedVariables (unregistered after first use)
- `PLAYER_LOGIN` — print the loaded version

### SavedVariables
- `MyAddonDB` (account) — see Saved settings above
- `MyAddonCharDB` (character) — ...

### Design decisions
- One event frame with a handler table, so every file registers events the same way.
- Slash subcommands live in a table (`ns.commands`), so new commands don't require editing a growing if/else chain.
```

### Per-addon `CHANGELOG.md` template

```markdown
# Changelog

## 0.1.0
- Initial release.
```

---

## 2. Add a feature

1. Ask Cody clarifying questions about behavior, UI, settings, and edge cases. Wait for answers.
2. Read the addon's `.toc`, every `.lua` file, `README.md` (Code overview), and `CHANGELOG.md`.
3. **Reuse check.** List the existing functions (`ns.*`, `Utils.lua`, Blizzard `C_*` APIs) that could do part of the job. For each piece of new logic, decide whether to:
   - use an existing function as-is,
   - extend an existing function (only if its current callers stay correct), or
   - write a new function.

   If the choice isn't obvious, present the options to Cody with trade-offs and let him decide.
4. Decide where the code goes. If it's more than ~150 lines or a distinct concern, put it in a new file (e.g. `Tooltip.lua`) and add it to the `.toc` **after** `MyAddon.lua`, since that file defines `ns.RegisterEvent`, `ns.Print`, and `ns.commands`.
5. New files start with a header comment and `local addonName, ns = ...`, and attach public functions to `ns`.
6. Events: register through `ns.RegisterEvent("EVENT_NAME", handler)`. Unregister when no longer needed.
7. New persisted setting: add it to `ns.defaults` (account) or `ns.charDefaults` (character). Never read a setting before `ADDON_LOADED`.
8. New slash subcommand: add an entry to `ns.commands` instead of editing `handleSlashCommand`.
9. Anything touching secure/protected frames (action bars, unit frames, `SetPoint` on secure frames, `Show`/`Hide` of protected frames) must wait for combat to end:

    ```lua
    local pendingLayout = false

    --- Applies the addon's frame layout, or defers it if the player is in combat.
    --- Protected frames can't be changed during combat lockdown, so this sets a flag
    --- instead. The PLAYER_REGEN_ENABLED handler below retries once combat ends.
    local function applyLayout()
        if InCombatLockdown() then
            pendingLayout = true
            return
        end
        pendingLayout = false
        -- protected work here
    end

    --- Runs a layout that was deferred during combat, now that lockdown has lifted.
    local function onCombatEnded()
        if pendingLayout then
            applyLayout()
        end
    end

    ns.RegisterEvent("PLAYER_REGEN_ENABLED", onCombatEnded)
    ```

    If more than one feature needs this, move it into a shared `ns.RunOutOfCombat(fn)` helper in `Utils.lua` rather than repeating the flag pattern.
10. Do not base logic on combat values that may be secret (see AGENTS.md). If a value might be secret, only pass it through to display widgets; don't compare or do math on it.
11. Write the summary comment block for every new or changed function (AGENTS.md "Documentation standard").
12. Update `README.md`: commands, settings, and the Code overview (files, functions, events, SavedVariables, design decisions). Bump `## Version` and add a `CHANGELOG.md` entry.
13. Run skill 5, then post the review summary in chat and leave the changes uncommitted.

---

## 3. Add a settings panel

Put this in `Config.lua`, listed in the `.toc` after `MyAddon.lua`. `MyAddon.lua` calls `ns.InitSettings()` from `ADDON_LOADED`, which fires after every file has loaded and SavedVariables exist.

```lua
--[[
    Config.lua
    Builds the addon's page in Game Menu > Options > AddOns using the Settings API.
]]

local addonName, ns = ...

--- Registers the settings category and one control per user-configurable option.
--- Each setting is bound directly to a key in ns.db, so changes in the panel save
--- automatically. Stores the category on ns so /myaddon config can open it.
--- Called once from ADDON_LOADED, after SavedVariables and defaults are in place.
function ns.InitSettings()
    local category = Settings.RegisterVerticalLayoutCategory(addonName)

    local enabledSetting = Settings.RegisterAddOnSetting(
        category,
        addonName .. "_enabled",
        "enabled",
        ns.db,
        Settings.VarType.Boolean,
        "Enable " .. addonName,
        ns.defaults.enabled
    )
    Settings.CreateCheckbox(category, enabledSetting, "Turns the addon on or off.")

    Settings.RegisterAddOnCategory(category)
    ns.settingsCategory = category
end
```

Rules:

- Use the modern `Settings` API only. No `InterfaceOptions_AddCategory` or `InterfaceOptionsFrame_OpenToCategory`.
- Setting variable names (`addonName .. "_key"`) must be globally unique.
- If a Settings call errors in the client, check the current Mainline 12.x signature on warcraft.wiki.gg and update this template in SKILLS.md too.

---

## 4. Patch update

Run when Blizzard ships a Forever patch that changes the interface number or APIs.

```
- [ ] Confirm the new interface number in-game: /dump select(4, GetBuildInfo())
- [ ] Update the "Target game version" table in AGENTS.md
- [ ] Update the TOC template in SKILLS.md
- [ ] Update ## Interface: in every addon's .toc (search: rg -n "^## Interface:" -g "*.toc")
- [ ] Check patch notes / API diffs for removed or changed functions used in this repo
- [ ] rg for each changed API across all addons and fix call sites
- [ ] Bump ## Version and add a CHANGELOG entry in every touched addon
- [ ] Run skill 5 on every addon
```

---

## 5. Lint and verify

### Static checks

`luacheck` is installed as a standalone binary at `~/.local/bin/luacheck` (from the lunarmodules/luacheck GitHub releases, no sudo needed). Settings live in the repo-root `.luacheckrc`. Run from the repo root:

```bash
luacheck MyAddon
```

- When an addon starts using a new WoW global, add it to `read_globals` in `.luacheckrc`, since the list is shared by every addon.
- Each addon gets a `files["MyAddon/"]` entry listing the globals it writes (SavedVariables, `SLASH_*`, `SlashCmdList`).
- A warning about setting an undeclared global almost always means a missing `local`.
- The binary uses threads, which the agent sandbox blocks (`pthread_create() failed, EPERM`). Agents must run it outside the sandbox.

### Structural checks

```
- [ ] Folder name == .toc filename (without extension) == addonName
- [ ] ## Interface: 16001 and nothing else
- [ ] Every .lua/.xml in the folder is listed in the .toc, and every .toc entry exists (case-sensitive)
- [ ] Every SavedVariable in the .toc is initialized in ADDON_LOADED
- [ ] No globals besides SavedVariables and slash-command registrations
- [ ] No references to other game flavors (rg -n "WOW_PROJECT|_Mainline|_Vanilla|_Classic" MyAddon)
- [ ] Every file has a header comment; every function has a summary block (what / how / when)
- [ ] No duplicated logic: repeated code is pulled into a helper, and cross-file helpers live in Utils.lua
- [ ] No magic numbers or strings outside named constants or ns.defaults
- [ ] README.md Code overview matches the code (files, functions, events, SavedVariables, design decisions)
- [ ] README.md and CHANGELOG.md updated; ## Version bumped
```

### Review summary (post in chat, don't commit)

```
Files changed: ...
New functions: name — one-line purpose
Modified functions: name — what changed and why
Reuse decisions: what was reused, extended, or newly written, and why
Open questions / assumptions: ...
In-game test steps: ...
```

### In-game verification (hand to Cody)

Agents can't run the client. End every change with explicit test steps, for example:

1. Copy the folder to the AddOns directory (skill 6) and `/reload`.
2. `/console scriptErrors 1` to show Lua errors.
3. Run `/myaddon toggle` and expect the chat message `Enabled: false`.
4. Relog and confirm the setting persisted.

---

## 6. Install locally for testing

The client reads from the Forever AddOns folder (beta: `World of Warcraft/_classic_beta_/Interface/AddOns/`; confirm the folder name after the Nov 4 launch). From WSL, copy rather than symlink, since the Windows client doesn't follow WSL symlinks reliably:

```bash
WOW_ADDONS="/mnt/c/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns"
rsync -a --delete --exclude '.git' MyAddon/ "$WOW_ADDONS/MyAddon/"
```

Adjust `WOW_ADDONS` to the actual install path. Then `/reload` in game (new files or `.toc` changes need a full client restart, not just `/reload`).

---

## 7. Release

```
- [ ] Skill 5 passes
- [ ] ## Version bumped (semver: MAJOR.MINOR.PATCH)
- [ ] CHANGELOG.md has an entry for this version
- [ ] Package: the zip must contain the MyAddon/ folder at its root
- [ ] Tag: git tag MyAddon-vX.Y.Z
```

```bash
mkdir -p .release
VERSION=$(awk -F': ' '/^## Version:/ {print $2}' MyAddon/MyAddon.toc | tr -d '\r')
zip -r ".release/MyAddon-$VERSION.zip" MyAddon -x '*.git*'
```

When uploading to CurseForge or Wago, select game version **Forever 1.60.1** only.

---

## 8. Debug an in-game error

1. Get the full error text including file and line number (`/console scriptErrors 1`, or BugSack if installed).
2. Map it to the source file and line. Errors in `Interface/AddOns/MyAddon/...` point directly at repo files.
3. Common causes:
   - `attempt to index a nil value` on a `C_*` namespace or function: the API differs on Forever. Check `/dump C_Namespace` in game.
   - `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN`: protected call during combat or from tainted code. Use the combat-queue pattern in skill 2.
   - Errors about secret values: the code compared or did math on a restricted combat value. Remove that logic.
   - Settings nil on login: code read `ns.db` before `ADDON_LOADED`.
   - Addon missing from the AddOns list: folder/`.toc` name mismatch, nested folder, wrong `## Interface:`, or "Load out of date AddOns" needed after a patch.
4. Useful in-game tools: `/fstack` (frame under cursor), `/etrace` (event trace), `/dump <expr>`, `/tinspect <table>`.
5. Fix, then run skill 5 and add a `CHANGELOG.md` entry.
