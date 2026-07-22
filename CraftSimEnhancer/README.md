# CraftSim Enhancer

CraftSim Enhancer is a standalone companion addon for CraftSim. It keeps the custom Auction House scanner, merchant reagent buying, and vendor-shopping-list notice outside the CraftSim directory so a CurseForge update can safely replace stock CraftSim.

The addon was developed against CraftSim 26.1.10 and World of Warcraft interface 120007 (12.0.7).

## Extracted features

- Auction House scanner backed by the supplied generated Midnight recipe/item data, with profession filters, presets, missing-result reporting, fill/outlier pricing, lowest-output pricing, vendor fixed prices, TSM fallback, and CraftSim price-override export. Outputs with no auctions use CraftSim's saved average cost for a 5%-AH-cut break-even estimate, with lower ranks capped below real higher-rank listings; outputs without a saved cost are skipped.
- `Buy Reagents` merchant button for outstanding vendor-sold CraftSim queue reagents, including inventory subtraction, stock/gold checks, and optional Auctionator shopping-list deduction.
- A deduplicated notice when a CraftSim Auctionator shopping list contains vendor-sold reagents.
- Independent compatibility checks, debug/status reporting, module enable flags, and one-time legacy settings migration.

The custom RecipeScan smart-restock rewrite was also reviewed. Stock CraftSim 26.1.10 already produces the same result from the same target and owned values, so the Enhancer does not install a fragile function replacement for it.

## Installation

1. Install or restore an unmodified CraftSim release.
2. Copy the complete `CraftSimEnhancer` folder beside CraftSim, not inside it.
3. Confirm the final folders are `Interface/AddOns/CraftSim/` and `Interface/AddOns/CraftSimEnhancer/`.
4. Enable both addons and log in or reload.
5. Run `/cse status`.

CraftSim is a required dependency. If CraftSim is disabled, WoW will not load CraftSim Enhancer; this is expected and prevents partial initialization.

## Settings and migration

All Enhancer settings are stored in `CraftSimEnhancerDB`. The database has schema and migration versions, global settings, and a reserved profile root. It stores only Enhancer debug/module settings and scanner configuration; transient scan results are not saved.

On first load, the Enhancer checks `CraftSimDB.auctionHouseScanDB.data`. If present, it copies fill quantity, per-crafter profession choices, target exclusions, and the configuration profession into new tables in `CraftSimEnhancerDB`. The old CraftSim value is not changed or deleted, and the migration does not repeat. CraftSim price overrides remain in CraftSim's normal `priceOverrideDB` because they are an upstream CraftSim feature.

Missing-output estimates read CraftSim's Last Crafting Cost database. Enable **Update Last Crafting Cost DB** in CraftSim's Recipe Scan or Craft Lists and run it once to seed those costs. The scanner records these overrides as `Estimated — no auctions`; real AH results always replace estimates on a later push.

`/cse reset confirm` resets only Enhancer settings. It deliberately does not re-import the retained legacy settings and does not reset CraftSim.

## Commands

- `/cse` or `/cse help` — list commands.
- `/cse status` — show Enhancer/CraftSim/interface versions, module states, compatibility failures, debug state, and migration status.
- `/cse debug` — toggle concise debug output; it is off by default.
- `/cse reset` — show the required confirmation command.
- `/cse reset confirm` — reset only CraftSim Enhancer settings.
- `/cse scan` — open the scanner when the Auction House is open.
- `/cse vendor` — refresh Vendor Buy when a merchant is open.
- `/cse module <scan|vendor|notice> <on|off>` — persist a module state for the next reload.

## Compatibility and debugging

Each module validates its required objects before initialization. A failed check disables only that module and emits one warning; `/cse status` retains the reason. Genuine Lua programming errors are not broadly suppressed, so normal error tools can capture them.

The principal update-sensitive file is `Compat/CraftSim.lua`. It centralizes all CraftSim internal table paths used by feature modules and states the tested CraftSim version. Auction House and Merchant API wrappers that add practical version isolation are in `Compat/WoW.lua`.

Known risks:

- Vendor Buy depends on CraftSim's internal queue/recipe/reagent object layout and cached inventory helpers.
- Scanner export depends on CraftSim's internal price-override repository and UI refresh method.
- The shopping-list notice securely hooks an internal CraftSim method.
- Auctionator list/vendor APIs are optional but version-sensitive.
- The Auction House launcher's tab integration follows the current Blizzard frame implementation.
- Generated recipes, item metadata, vendor prices, PTR exclusions, and binding assumptions age as game data changes.

Use `/console scriptErrors 1` and BugSack/BugGrabber while testing. The full checklist is in `Docs/TESTING.md`.

## Restoring stock CraftSim

The simplest restoration is to replace the live CraftSim directory with the matching CurseForge package, leaving `CraftSimEnhancer` untouched. A precise file restoration/removal list is in `Docs/RESTORE_STOCK.md`. Legacy `CraftSimDB.auctionHouseScanDB` may remain for migration compatibility.

No custom Lua, XML, TOC entry, or generated data file is required inside stock CraftSim after extraction.

## Maintenance after a CraftSim update

1. Keep a copy of the previously supported stock CraftSim release and recursively compare it with the new release, ignoring packaging metadata and line endings before classifying functional changes.
2. Review each implementation named in `Compat/CraftSim.lua`: queue storage/helpers, shopping-list creation, price-override saves, profession metadata/localization, UI refresh, and optional TSM fallback.
3. Update only the adapter when a table path or compatible signature changes. Update a feature module only when the behavior contract itself changed.
4. Re-evaluate the RecipeScan smart-restock equivalence if upstream modifies either the restock expression or smart-restock branch.
5. Update generated data for the current game patch and review manual item overrides.
6. Increment `## Version` in `CraftSimEnhancer.toc`, `ns.version` in `Core.lua`, and the version mentioned here when publishing a change.
7. Log in with script errors enabled, run `/cse status`, and complete `Docs/TESTING.md`, especially scanner push, vendor purchase, migration, reset, and repeated frame opening.

CurseForge should manage only `Interface/AddOns/CraftSim/`. CraftSim Enhancer must remain in its own sibling folder, so updating CraftSim cannot overwrite Enhancer-owned files.
