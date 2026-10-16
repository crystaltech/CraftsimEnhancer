# CraftSim 27.0.5 compatibility

Source review and automated checks completed September 17, 2026 against the official release:
https://github.com/derfloh205/CraftSim/releases/tag/27.0.5

Asset: `CraftSim-27.0.5.zip`
SHA-256: `451f3963fa0ab2408ee0fd11b04acc2a22bc0dc394eea56c64119a288f560c89`

## Result

No Enhancer code changes are required based on source review and automated testing. CraftSim Enhancer 1.6.1 passes its release integration test against the actual 27.0.5 modules.

Compared with the previously tested 27.0.3 release, functional changes are confined to inventory counting and craft-list restocking. Restock now includes bound copies of inherently untradeable items, the reagent bag and warbank, and multiple output qualities. The price API file changes only a comment. Enhancer's shopping module, queue helpers, public API, price-override and saved-cost repositories, reagent classes, constants, and module refresh handler are unchanged.

## Automated validation

From the repository root, with the official release extracted separately:

```bash
CRAFTSIM_SOURCE_DIR=/path/to/CraftSim lua Tests/test_craftsim_release.lua
for test in Tests/test_*.lua; do lua "$test" || exit 1; done
find CraftSimEnhancer -name '*.lua' -exec luac -p {} +
```

The release integration test passed, covering adapter initialization, feature capabilities, global and ranked price overrides, estimated override removal, ranked saved costs, tooltip lookup, UI refresh, vendor queue quantities, deferred and automatic shopping-list publication, recursion prevention, and quick-buy cache reset.

All six standalone Lua suites passed: auction scanner, break-even tooltip, configuration, compatibility adapter, slash commands, and vendor purchasing. All addon Lua files passed syntax checks. The release integration test intentionally skips in the standalone loop when its source environment variable is unset; it was run separately with that variable set.

## In-game validation still pending

These checks mock WoW and Auctionator services; they do not establish live UI or server behavior. Version 27.0.5 remains outside the runtime tested-version list until in-game validation is reported. An untested-version notice alone does not disable compatible features.

With CraftSim 27.0.5 and Enhancer 1.6.1 enabled:

1. Run `/cse status` and check for unavailable features or Lua errors.
2. Run a small CSE Recon scan, push overrides, and confirm CraftSim updates its prices.
3. Check a break-even tooltip for an item with a saved CraftSim crafting cost.
4. Create a queue shopping list with vendor reagents, including immediately after login when item data may be uncached. Confirm vendor items remain separated after loading finishes.
5. Buy a small vendor quantity and confirm the plan decreases after delivery to bags.

The full regression checklist is in [MANUAL_CRAFTSIM_27.md](MANUAL_CRAFTSIM_27.md).
