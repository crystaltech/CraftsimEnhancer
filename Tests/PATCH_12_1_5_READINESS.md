# 12.1.5 / CraftSim 27.0.7 release readiness

Original API review: October 6, 2026, candidate **1.6.2-rc1**. Current candidate: **1.6.2-rc4**.

The [October 15 live decor update](PATCH_12_1_5_DECOR.md) adds older-expansion and new 12.1.5 decor coverage. Its 1,030-recipe dataset supersedes the original data-only statement below; in-game validation remains pending.

The requested `ptr2` branch was checked again on October 7, 2026; see the detailed verification below.

## Sources and result

- Latest official CraftSim release: [27.0.7](https://github.com/derfloh205/CraftSim/releases/tag/27.0.7), published September 28, 2026. Latest-release metadata was fetched directly from the GitHub API.
- Official asset: `CraftSim-27.0.7.zip`. SHA-256: `c2b93d7b14e59bac9cd009ccb52a233ec400fdbbd74383f10f64c7e591205d6e`.
- Blizzard UI-source mirror: [pinned 12.1.5 snapshot](https://github.com/Gethe/wow-ui-source/tree/07ac548d7185832674fbd886ed243146b096c4fd), whose `version.txt` reports **12.1.5.70077**.
- Comparison baseline: local `References/wow-ui-source-live`, whose `version.txt` reports 12.0.7.68453, and official CraftSim 27.0.5.

No runtime adapter changes were required by source review and automated integration testing. The TOC now supports both 120100 and 120105. This is a candidate for in-game validation, not a claim of completed live testing.

## WoW source review

Auction House, merchant, addon metadata/loading, and profession API function entries have unchanged signatures. The item API adds `DoesItemMatchSpellItemCondition`, which Enhancer does not use; its existing item functions are unchanged. Tooltip documentation changes concern unit auras and LFG rewards, outside the crafted-item tooltip path.

The Auction House frame and tab Lua implementations are unchanged. MenuUtil adds a highlight-button helper; the context-menu entry point used by Enhancer is unchanged. No API migration was identified for scanning, price export, merchant purchasing, or bag-count confirmation.

At the October 6 review, generated data contained the validated 12.1.0 **763 recipes and 1,102 metadata rows**. Reproducibility passed. This check does not establish new or changed 12.1.5 recipe coverage; refresh from confirmed profession/item data before claiming that coverage.

### October 7 ptr2 double-check

The [ptr2 branch](https://github.com/Gethe/wow-ui-source/tree/ptr2) was resolved through the GitHub branch API to commit `07ac548d7185832674fbd886ed243146b096c4fd`, build **12.1.5.70077**, dated September 29, 2026. It is the same pinned snapshot used in the initial review.

The second audit inventories actual addon API references and loads the generated documentation as Lua tables, comparing complete entries against the local 12.0.7.68453 baseline, including arguments, returns, and secret-argument annotations:

- All **25 namespaced APIs** referenced by runtime Lua have unchanged entries, including timer callbacks, merchant info, item counts, item lookup, profession lookup, addon loading, and Auction House queries/results.
- All **11 scanner events** have unchanged entries and payloads.
- Existing auction, merchant, profession, and item data structures are unchanged, including the result and merchant-info fields the addon reads.
- Profession, auction sort, item-binding, and tooltip-type enum definitions are unchanged.
- The Auction House frame/tab Lua and XML, item-loading mixin, and tooltip post-processing implementation are identical. `MenuUtil.CreateContextMenu` is unchanged.
- Blizzard's current merchant and profession UI still use the legacy globals required by Enhancer (`GetMerchantNumItems`, `GetMerchantItemLink`, `BuyMerchantItem`, `GetProfessions`, and `GetProfessionInfo`). This verifies continued source usage, not undocumented engine guarantees.

MerchantFrame adds registration with the player interaction manager and replaces repair-icon desaturation calls. Enhancer uses merchant events and does not hook those repair or interaction functions. Shared panel templates add narration and side-tab helpers and remove legacy `ScrollingEdit_*` helpers; Enhancer does not reference the removed helpers, and its `PanelTemplates_*` tab functions are unchanged.

No runtime change is indicated by this audit. Merchant opening/closing, combat/taint behavior, and actual server responses remain part of the in-game release gate. The tested-version markers remain unchanged.

## CraftSim source review

The public namespace API, global/result price-override repository, saved crafting-cost repository, and module refresh handler are identical to 27.0.5. Queue changes add patron knowledge-point cost handling and improve visible-recipe selection; the inventory helper used by Vendor Buy is unchanged. Constant changes add unrelated options and profession lists.

The shopping module now checks `CRAFTQUEUE_AUTO_SHOPPING_LIST` before publishing on queue completion. The integration harness now supplies that option and verifies both states. Manual creation still publishes when the automatic option is disabled, and Enhancer vendor separation runs only after publication. No change to the runtime publication hook is needed.

CraftSim 27.0.7 currently declares interfaces 120005, 120007, and 120100, not 120105. Install it separately and enable **Load out of date AddOns** if needed for 12.1.5 testing; leave its files unmodified.

## Automated checks

From the repository root:

```bash
CRAFTSIM_SOURCE_DIR=/path/to/CraftSim-27.0.7/CraftSim lua Tests/test_craftsim_release.lua
for test in Tests/test_*.lua; do lua "$test" || exit 1; done
find CraftSimEnhancer -name '*.lua' -exec luac -p {} +
python3 -m unittest tools/test_generate_generated_recipes.py
python3 tools/generate_generated_recipes.py --verify-only \
  --input-dir legacy/CraftSim/Data/GeneratedRecipes \
  --check-output CraftSimEnhancer/Data/GeneratedRecipes
```

Passed: actual-release integration, six standalone Lua suites, all addon Lua syntax checks, six data-generator tests, and generated-data reproducibility. The standalone loop intentionally skips release integration when its environment variable is unset; the release test was run separately with it set. Developer data tools and source inputs are workspace-only and are not included in the addon ZIP.

The integration test covers initialization, feature capabilities, global and ranked price overrides, estimated override removal, saved ranked costs, tooltip lookup, UI refresh, vendor queue quantities, deferred publication, recursion prevention, automatic publication enabled/disabled, manual publication with automation disabled, and quick-buy cache reset. WoW and Auctionator services are mocked.

## In-game release gate

Install the candidate beside stock CraftSim 27.0.7 and Auctionator on a 12.1.5 client, and enable `/console scriptErrors 1`.

1. Run `/cse status`: confirm version 1.6.2-rc4, interface 120105, CraftSim 27.0.7, and all enabled modules initialized. Untested-version warnings are expected.
2. Open/close the Auction House and professions, run a small Recon scan, cancel a scan, export its missing-item report, and push overrides. Confirm CraftSim immediately refreshes reagent and exact-rank result prices.
3. Check ordinary and ranked crafted-item break-even tooltips with saved CraftSim costs.
4. Immediately after login, create a mixed vendor/AH shopping list with uncached item data. Confirm vendor separation survives deferred publication and repeats without duplicate notices.
5. Enable CraftSim's automatic-shopping-list option and finish a queue operation: confirm one publication and vendor split. Disable the option and repeat: confirm no automatic publication or split. Confirm manual creation still works.
6. Buy a small planned vendor quantity: confirm the plan decreases only after delivery to bags; verify partial purchases or full bags leave unreceived quantities outstanding.
7. Reload and confirm settings, unfinished vendor plans, and UI state persist without duplicate controls. Check opening the Auction House and merchant around combat for blocked actions.

Record client build, CraftSim/Auctionator versions, `/cse status`, and any first Lua error. Only after these checks pass should `WoW.testedInterface` and the CraftSim tested-version list advance and a final release replace the candidate.
