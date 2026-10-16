# CraftSim recheck — October 16, 2026

The official GitHub latest-release API and CurseForge file list still identify
**27.0.7**, released September 28, 2026, as the latest published release:

- https://github.com/derfloh205/CraftSim/releases/tag/27.0.7
- https://www.curseforge.com/wow/addons/craftsim/files/8997314

GitHub's current release asset digest remains
`c2b93d7b14e59bac9cd009ccb52a233ec400fdbbd74383f10f64c7e591205d6e`, matching
the previously tested CraftSim-27.0.7.zip. No newer published release was found.

## Unreleased development changes

Compared 27.0.7 with main at **042d8887f88b1830755d9f5702a20b8423ba0fc4**:
https://github.com/derfloh205/CraftSim/compare/27.0.7...042d8887f88b1830755d9f5702a20b8423ba0fc4

Three commits are ahead of the release:

1. October 4, b48b0e0b20ad: inventory/restock fixes and queue limits for
   unpurchaseable/currency reagents. Bank caches work with the bank closed;
   TSM inventory/AH queries preserve gear-rank distinctions where links allow.
   A shared required-reagent pool prevents multiple recipes from overcommitting
   owned bound materials/currencies, including decor lumber.
2. October 4, 32ef852aeee7: Stabilized Derivate (242651) is exempt from the new
   owned-stock queue limit, while still excluded from shopping.
3. October 14, 042d8887f88b: updates DevTools/DataMining/LAST_BUILD to
   12.1.5.70391. The comparison changes this build marker; it does not contain
   new generated recipe tables or a new release version.

Nine files differ: Classes/ReagentData.lua, Classes/RecipeData.lua,
DataSource/InventorySource.lua, DevTools/DataMining/LAST_BUILD,
Modules/CraftQueue/CraftLists.lua, Modules/CraftQueue/CraftQueue.lua,
Modules/RecipeScan/RecipeScan.lua, Modules/Shopping/Shopping.lua and Util/Const.lua.

Shopping now calls INVENTORY_SOURCE:IsItemUnpurchaseable for BoP, quest-bound and
hard account/warbound items. CSE's existing compatibility helper still uses its
legacy soulbound mapping for its own vendor queue traversal; this semantic
boundary deserves another check when the new CraftSim version ships. The current
released version requires no CSE runtime change. CSE's AH bound-item exclusions
remain independent of this new upstream helper.

## Validation and limits

Downloaded and extracted the pinned development snapshot separately from both
stock and modified references. Source archive:
`zip/CraftSim-main-042d8887f88b-source.zip`, SHA-256:
`a301daafa7c468dfed13cb118372809a8a70513be7824b88a44f42528bc26e2c`.
Raw API responses are cached in tmp/craftsim-latest-2026-10-16.json and
tmp/craftsim-compare-2026-10-16.json.

Updated the source-integration harness to load the actual InventorySource module,
which the new Shopping code requires. Both source trees pass:

```bash
CRAFTSIM_SOURCE_DIR=tmp/patch-12.1.5/CraftSim-27.0.7/CraftSim lua Tests/test_craftsim_release.lua
CRAFTSIM_SOURCE_DIR=tmp/craftsim-review-2026-10-16/CraftSim-042d8887f88b lua Tests/test_craftsim_release.lua
```

These tests exercise CSE price overrides, saved crafting costs, tooltip cost
lookup, UI refresh, vendor queue quantity calculation, deferred shopping-list
publication and automatic shopping-list options with real upstream modules and
mocked game APIs. They do not simulate all new inventory/restock/queue algorithms
or establish in-game compatibility of unreleased CraftSim.

The user reports that current in-game usage looks working. Exact installed
versions and individual checklist coverage were not provided, so this is recorded
as a positive user report without advancing the complete tested-version markers.
No runtime addon files or candidate packages changed during this recheck.
