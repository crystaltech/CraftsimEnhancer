# CraftSim 27.0.3 compatibility

Source and automated checks completed September 11, 2026 against the GitHub release asset:
https://github.com/derfloh205/CraftSim/releases/tag/27.0.3

Asset: `CraftSim-27.0.3.zip`
SHA-256: `84595de33d686843e6abba62af5bdc2748bb36a58d0cdfc89252c5123ce13d75`

## Compatibility change

CraftSim 27.0.3 creates the Auctionator queue list asynchronously after item data loads. Hooking the return from `SHOPPING:CreateShoppingListFromCraftQueue` runs before publication when items are uncached. Enhancer now hooks Auctionator's completed `CreateShoppingList` call for the CraftSim caller and queue-list name. Enhancer's own replacement calls are ignored to prevent recursion. The CraftSim 26 hook remains unchanged.

The price-override repository, saved crafting-cost repository, module refresh handler, craft queue, public API, reagent classes, and price APIs are unchanged from the installed 27.0.2 source.

## Automated validation

From the repository root, with the release extracted outside the addon:

```bash
CRAFTSIM_SOURCE_DIR=/path/to/CraftSim lua Tests/test_craftsim_release.lua
```

This loads actual release modules with mocked WoW, item loading, and Auctionator services. It verifies adapter initialization, capabilities, global and ranked result overrides, estimated override removal, ranked saved costs, tooltip lookup, UI refresh dispatch, vendor queue quantities, deferred shopping-list publication, recursion prevention, automatic queue publication, and quick-buy cache reset.

All six existing Lua suites and addon Lua syntax checks also pass. The release integration test skips when `CRAFTSIM_SOURCE_DIR` is unset.

## In-game validation

Use the scenarios in [the CraftSim 27 smoke checklist](MANUAL_CRAFTSIM_27.md), substituting version 27.0.3. Test vendor separation both immediately after login with uncached items and on a repeated list creation. Confirm vendor materials remain removed after item data finishes loading. Also confirm the delayed vendor purchase fix with a small purchase.

After testing the pushed fixes on another PC, the user reported that CSE was working and authorized release 1.6.1. Version 27.0.3 is now marked tested. Individual checklist results were not recorded; the scenarios above remain useful regression checks. The separate WoW-interface warning is unchanged.
