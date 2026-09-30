# AGENTS.md — WoW Forever AddOns

Guidance for AI agents (and humans) creating and maintaining addons in this repo.
For step-by-step workflows and file templates, read [SKILLS.md](SKILLS.md) before starting any addon task.

## Working with Cody (read first)

Cody is a software developer and reviews every line before it is committed. These rules override default agent behavior:

1. **Ask before you build.** Before writing or changing any code, ask every clarifying question you have, as many as needed, using the AskQuestion tool where possible. Do not assume requirements, names, UI placement, defaults, or behavior. It is cheaper to ask now than to fix it later. Only start work once the open questions are answered.
2. **Code must be reviewable.** Every function gets a summary comment block explaining what it does and how it does it (see "Documentation standard" below). Each addon's `README.md` is the review document. Keep its "Code overview" section accurate with every change.
3. **Reuse over duplication.** Before writing a new function, look for an existing one in the addon (`ns.*`, `Utils.lua`) or in Blizzard's API that already does the job. If it's unclear whether to extend an existing function or write a new one, or where a shared helper should live, ask Cody instead of deciding alone.
4. **Don't commit.** Leave changes uncommitted so Cody can review them. Only commit when explicitly asked.

## Target game version (non-negotiable)

Every addon in this repo targets **World of Warcraft: Forever only**.

| Property | Value |
|---|---|
| Game version | 1.60.1 |
| TOC `## Interface:` | `16001` |
| Client UI engine | Modern Mainline (12.x-era) API, same addon rules as Midnight |
| Beta AddOns folder | `World of Warcraft/_classic_beta_/Interface/AddOns/` (launch folder not yet confirmed) |

Do **not** add support for, or code paths targeting, any other flavor:

- Retail / Mainline / The War Within
- Midnight
- Classic Era, Anniversary, Hardcore, Season of Discovery
- Any progression Classic (TBC, Wrath, Cata, MoP Classic)

Concretely, that means:

- No `_Mainline.toc`, `_Vanilla.toc`, `_Classic.toc`, `_Mists.toc`, etc. Use a single `AddonName.toc`.
- No comma-separated multi-version `## Interface:` lines. Only `16001` (or the current Forever interface number).
- No `WOW_PROJECT_ID` / `WOW_PROJECT_MAINLINE` / `WOW_PROJECT_CLASSIC` branching.
- No compatibility shims for old global APIs (e.g. `GetAddOnMetadata`, `UnitAura`, `GetSpellInfo`) that exist only on other clients. Use the `C_*` namespaced APIs.
- Do not copy code from Classic Era addons without rewriting it for the modern API.

If Blizzard patches Forever and the interface number changes, update it everywhere in one pass (see "Patch update" in SKILLS.md) and update the table above.

## Repository layout

One top-level directory per addon. The directory name, the `.toc` filename, and the addon name must match exactly (case-sensitive):

```
WoW_Forever_AddOns/
├── AGENTS.md
├── SKILLS.md
├── README.md
└── MyAddon/
    ├── MyAddon.toc        # required: table of contents / metadata
    ├── MyAddon.lua        # required: main entry point
    ├── Utils.lua          # optional: shared helpers used by more than one file
    ├── Config.lua         # optional: settings panel, defaults
    ├── Locales/           # optional: enUS.lua etc.
    ├── Libs/              # optional: embedded third-party libs
    ├── Media/             # optional: textures (.tga/.blp), sounds
    ├── README.md          # required: what it does, slash commands, settings
    └── CHANGELOG.md       # required: one entry per version
```

A folder that is dropped into `Interface/AddOns/` must work as-is. No nested `MyAddon/MyAddon/` folders.

## Required files per addon

1. **`AddonName.toc`** — metadata and load order. Must include `## Interface: 16001`, `## Title`, `## Notes`, `## Author`, `## Version`, and list every `.lua`/`.xml` file in load order.
2. **`AddonName.lua`** — main entry point. Owns the event frame, initialization, and slash commands.
3. **`README.md`** (user docs plus the Code overview for review) and **`CHANGELOG.md`** inside the addon folder.

## API rules for Forever

Forever runs the modern client, so it inherits Midnight's addon restrictions:

- **Allowed:** UI changes, layouts, frames, bags, maps, quest helpers, tooltips, nameplate styling, quality-of-life automation outside of combat logic.
- **Not allowed / will not work:** computing decisions from live combat data. Combat-sensitive values can be returned as *secret values* that may be displayed but not compared, used in arithmetic, or used as table keys. Do not build features on `COMBAT_LOG_EVENT_UNFILTERED` parsing, damage/threat math, or rotation logic.
- Built-in systems already exist: Edit Mode, damage meter, Cooldown Manager, swing timer. Integrate with them rather than duplicating them.
- Use `C_AddOns`, `C_Container`, `C_Item`, `C_Spell`, `C_UnitAuras`, `C_Timer`, `C_QuestLog`, `C_Map`, etc.
- Use the modern `Settings` API for options panels, not `InterfaceOptions_AddCategory`.
- Protected frames/actions: never call protected functions or modify secure frames while `InCombatLockdown()` is true. Queue the work and apply it on `PLAYER_REGEN_ENABLED`.

When unsure whether an API exists on Forever, say so and check the in-game API (`/api` in the client, or `/dump C_Something`) or [warcraft.wiki.gg](https://warcraft.wiki.gg/) for the Mainline 12.x signature. Never guess a signature silently.

## Lua coding conventions

- Target Lua 5.1 (WoW's embedded Lua). No `goto`, no integer division `//`, no `<const>`, no `utf8` library.
- Every file starts with `local addonName, ns = ...` and shares state through `ns`. No accidental globals.
- Allowed globals: SavedVariables declared in the `.toc`, `SLASH_*` entries, and `SlashCmdList` registrations. Nothing else.
- Cache frequently used globals as locals at the top of the file when in hot paths (`OnUpdate`, frequent events).
- One event frame per addon, dispatching via a handler table (`ns.events[event](...)`).
- Initialize SavedVariables on `ADDON_LOADED` for this addon only, merging in defaults without overwriting user values.
- Throttle `OnUpdate` handlers; prefer events or `C_Timer` over polling.
- 4-space indentation, `camelCase` for locals/functions, `PascalCase` for frame names and the addon table, `UPPER_SNAKE` for constants.
- User-facing strings go through a locale table (`ns.L`) once an addon has more than a handful of strings.
- Functions do one thing. If logic appears twice, pull it out into a helper. Helpers used by more than one file in an addon go in `Utils.lua` (loaded first in the `.toc`) and are exposed on `ns`.
- Keep functions small enough to review at a glance (roughly under 40 lines). Split larger ones into named steps.
- No magic numbers or strings. Put them in named constants at the top of the file or in `ns.defaults`.

## Documentation standard

Every file begins with a header comment saying what the file is responsible for.

Every function, including local helpers and event handlers, gets a summary comment block directly above it. The block says:

- **What** the function does, in one or two sentences.
- **How** it does it: the approach, any non-obvious steps, and side effects (events registered, SavedVariables written, frames created or shown).
- **When** it's called, if that isn't obvious (e.g. "Called once from ADDON_LOADED").

Add LuaLS annotations (`---@param`, `---@return`) to the block wherever parameters or return values aren't self-evident. Add inline comments inside the function body for tricky logic: combat-lockdown handling, secret-value handling, ordering constraints, or workarounds for API quirks.

```lua
--- Merges default values into a SavedVariables table without overwriting user choices.
--- Walks `defaults` recursively. Missing keys are copied in, nested tables are created
--- and filled the same way, and existing user values are left untouched.
--- Called from ADDON_LOADED before anything reads the settings.
---@param db table The SavedVariables table to fill (modified in place)
---@param defaults table The default values to merge in
local function applyDefaults(db, defaults)
```

Each addon's `README.md` must contain a **Code overview** section for review. It covers:

- A file-by-file breakdown: each file's responsibility and its public `ns.*` functions, with a one-line description of each.
- Key design decisions and why they were made (e.g. why a helper was shared, why work is queued until after combat).
- Events registered and SavedVariables used.

Update this section in the same change as the code.

## Workflow expectations for agents

- Before any work: ask clarifying questions (see "Working with Cody").
- Before editing an addon, read its `.toc`, all `.lua` files, `README.md` (especially the Code overview), and `CHANGELOG.md`, so you know which helpers already exist.
- Every change updates the function comment blocks it touches and the README Code overview.
- End each change with a short chat summary: files changed, new or modified functions, reuse decisions, and in-game test steps.
- When you add a new `.lua` file, add it to the `.toc` in the correct load order in the same change.
- When you add a SavedVariable, declare it in the `.toc` and add a default in the defaults table.
- Bump `## Version` in the `.toc` and add a `CHANGELOG.md` entry for any user-visible change.
- Run `luacheck` on the addon folder if it is installed (see SKILLS.md). Fix warnings, don't silence them globally.
- You cannot run the game. State clearly which behavior still needs in-game verification and give the exact steps (`/reload`, slash commands to try, what should happen).
- Never commit `WTF/`, `SavedVariables/`, or packaged `.zip` files (already in `.gitignore`).
